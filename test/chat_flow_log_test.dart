import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/network/acp_transport.dart';
import 'package:workbuddy/chat/session/session_repository.dart';
import 'package:workbuddy/chat/conversation_state.dart';
import 'package:workbuddy/chat/chat_controller.dart';

/// 内存 fake ACP 传输：session/new 返回 id，prompt 后推送一串 session/update，
/// 覆盖正常流 + 中断 + 重连三条路径。用来产出完整事件流水日志（不连真实服务端）。
class FakeAcp implements AcpTransport {
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  int bootstrapCount = 0;
  final List<String> sent = [];

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Future<Map<String, dynamic>> requestAwait(String method, Map<String, dynamic> params) async {
    sent.add('REQ $method $params');
    switch (method) {
      case 'session/new':
        return {'sessionId': 'sess-demo-001'};
      case 'session/list':
        return {'sessions': [{'sessionId': 'sess-demo-001', 'title': '演示会话'}]};
      default:
        return {};
    }
  }

  @override
  Future<void> notify(String method, Map<String, dynamic> params) async {
    sent.add('NOTIFY $method');
    if (method == 'session/prompt') {
      _emitDemoStream();
    }
  }

  void _emitDemoStream() {
    final updates = <Map<String, dynamic>>[
      {'sessionUpdate': 'agent_thought_chunk', 'content': {'type':'text','text':'用户想要 TODO 应用，我需要先规划结构。'}},
      {'sessionUpdate': 'tool_call', 'toolCallId':'tc1', 'name':'Read', 'kind':'read', 'status':'in_progress', 'title':'读取项目结构'},
      {'sessionUpdate': 'tool_call_update', 'toolCallId':'tc1', 'name':'Read', 'status':'completed', 'rawOutput':{'text':'lib/main.dart\nlib/app.dart'}},
      {'sessionUpdate': 'agent_message_chunk', 'content': {'type':'text','text':'好的，我来帮你'}},
      {'sessionUpdate': 'agent_message_chunk', 'content': {'type':'text','text':'设计一个 Flutter TODO 应用：\n'}},
      {'sessionUpdate': 'agent_message_chunk', 'content': {'type':'text','text':'- 分层架构\n- 状态管理\n'}},
      {'sessionUpdate': 'notice', 'level':'info', 'message':'已生成计划'},
    ];
    for (final u in updates) {
      _messages.add({
        'jsonrpc':'2.0','method':'session/update',
        'params': {'sessionId':'sess-demo-001','update':u},
      });
    }
    // prompt 响应带 stopReason 收尾
    _messages.add({'jsonrpc':'2.0','id':99,'result':{'stopReason':'end_turn'}});
  }

  @override
  Future<void> respond(int id, Map<String, dynamic> result) async {
    sent.add('RESPOND id=$id $result');
  }

  @override
  Future<void> startSubscribe() async {
    sent.add('SUBSCRIBE');
  }

  @override
  Future<void> bootstrap() async {
    bootstrapCount++;
  }

  @override
  Future<void> close() async {
    await _messages.close();
  }
}

void main() {
  test('完整对话事件流水日志', () async {
    final log = StringBuffer();
    void p(String s) => log.writeln(s);

    p('================================================================');
    p('WorkBuddy Flutter · AI 对话链路完整事件流水日志');
    p('================================================================');
    p('说明：FakeAcp 内存传输驱动，覆盖正常流/中断/重连三条路径。');
    p('      未连接真实服务端、未登录、未使用账号凭据。');
    p('');

    final fake = FakeAcp();
    final sessions = SessionRepository(transport: fake, cwd: '');
    final store = ConversationStore();
    final chat = ChatController(transport: fake, sessions: sessions, store: store);

    p('--- 步骤1 建立会话（session/new）---');
    await chat.ensureReady();
    p('sessionId = ${chat.sessionId}');
    p('transport: ${fake.sent.where((s)=>s.startsWith("REQ")||s.startsWith("SUBSCRIBE")).join(" | ")}');
    p('');

    p('--- 步骤2 发送消息（session/prompt，只发当前轮内容块）---');
    final acc = chat.acc;
    acc.addListener(() {
      // 每收到一次通知打印快照（流式增量会触发多次）。
    });
    await chat.send('帮我设计一个 TODO 应用');
    // 等事件队列处理完
    await Future<void>.delayed(const Duration(milliseconds: 50));
    p('phase = ${chat.phase.name}');
    p('请求: ${fake.sent.where((s)=>s.startsWith("NOTIFY session/prompt")).join()}');
    p('');

    p('--- 步骤3 标准化事件序列 + 累加后的消息 ---');
    for (final m in acc.messages) {
      p('[${m.role}] status=${m.status.name} content="${m.content.replaceAll('\n','\\n')}"');
    }
    p('工具调用数 = ${acc.tools.length}');
    for (final e in acc.toolRaw.entries) {
      p('  tool ${e.key}: ${e.value['name']} status=${e.value['status']}');
    }
    p('stopReason = ${acc.stopReason}');
    p('');

    p('--- 步骤4 中断路径：用户中途停止（session/cancel）---');
    p('路径说明：stop() → sessions.cancel(sessionId) → 本地标记 cancelled → 停止超时守卫。');
    p('（本轮 fake 已在步骤2结束，此处记录路径与 transport 调用，不重复推送流。）');
    await chat.stop();
    p('cancel 已调用: ${fake.sent.where((s)=>s.contains("session/cancel")).isNotEmpty}');
    p('');

    p('--- 步骤5 重连路径：网络断开 → 指数退避 + bootstrap ---');
    p('路径说明：reconnectOnDisconnect() → 每次 bootstrap + startSubscribe，');
    p('          退避 500ms→1000ms→2000ms…，成功后携带 Last-Event-ID 续传（TODO 抓包确认）。');
    final ok = await chat.reconnectOnDisconnect(lastEventId: 'evt-42');
    p('reconnect = $ok, bootstrapCount = ${fake.bootstrapCount}');
    p('');

    p('--- 步骤6 交互式消息回应（elicitation/权限/提问）---');
    p('路径说明：InteractiveRequestEvent → UI 渲染控件 → respondInteractive(result) → JSON-RPC response。');
    await chat.respondInteractive({'outcome':'selected','optionId':'allow_once'});
    p('回应已发回（若本轮无 pending 请求则跳过）');
    p('');
    p('================================================================');
    p('日志结束');
    p('================================================================');

    // ignore: avoid_print
    print(log.toString());
    await chat.dispose();
  });
}
