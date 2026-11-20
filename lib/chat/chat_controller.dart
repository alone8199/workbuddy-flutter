import 'dart:async';
import 'dart:convert';

import '../models/content_block.dart';
import '../network/acp_transport.dart';
import 'session/session_repository.dart';
import 'stream/stream_parser.dart';
import 'stream/stream_event.dart';
import 'message_accumulator.dart';
import 'update_router.dart';
import 'conversation_state.dart';

/// 单条消息发送状态（对外暴露的状态机，配合 MessageStatus）。
enum SendPhase { idle, sending, streaming, done, failed, cancelled }

/// 对话控制器：发送逻辑 + 状态流转 + 会话级并发保护 + 中断/重连。
/// 数据源：报告01（发送链路/流式）、报告05（cancel/上下文）、分析报告上下文携带规则。
class ChatController {
  final AcpTransport transport;
  final SessionRepository sessions;
  final ConversationStore store;
  final StreamParser parser = StreamParser();

  String? _sessionId;
  bool _busy = false; // 会话级并发保护：同一会话同时只允许一条 prompt 在途
  SendPhase _phase = SendPhase.idle;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Future<void>? _subscribeTask;

  /// 中断/重连配置（报告06 #3 心跳/超时参数静态未坐实，这里给可配置默认值）。
  final Duration streamTimeout; // 流超时：两次有效事件间隔超过此值视为超时
  final int maxReconnect; // 网络断开最大重连次数
  final Duration reconnectBaseDelay; // 指数退避基数

  ChatController({
    required this.transport,
    required this.sessions,
    required this.store,
    this.streamTimeout = const Duration(seconds: 30),
    this.maxReconnect = 5,
    this.reconnectBaseDelay = const Duration(milliseconds: 500),
  });

  SendPhase get phase => _phase;
  String? get sessionId => _sessionId;
  bool get isBusy => _busy;

  MessageAccumulator get acc =>
      _sessionId != null ? store.accumulator(_sessionId!) : MessageAccumulator();

  /// 初始化：确保有会话，启动 SSE 订阅并把消息路由到当前会话累加器。
  Future<void> ensureReady() async {
    if (_sessionId != null && _sub != null && _subscribeTask != null) return;
    final info = await sessions.create();
    _sessionId = info.sessionId;
    store.activate(info.sessionId);
    _attachSubscription();
    _subscribeTask = transport.startSubscribe();
  }

  void _attachSubscription() {
    _sub?.cancel();
    _sub = transport.messages.listen(_onTransportMessage);
  }

  /// 收到一条 JSON-RPC 消息：先编码成 SSE data 帧喂给解析器，再路由标准化事件。
  void _onTransportMessage(Map<String, dynamic> msg) {
    final events = parser.feedAndDrain('data: ${_jsonEncode(msg)}\n\n');
    for (final e in events) {
      _route(e);
    }
  }

  /// 喂入任意 SSE 文本分片（供真实 SSE 字节流或测试使用）。
  void feedSse(String chunk) {
    for (final e in parser.feedAndDrain(chunk)) {
      _route(e);
    }
  }

  void _route(StreamEvent e) {
    final router = UpdateRouter(acc);
    router.routeEvent(e);
    if (e is StopEvent) {
      _finish();
    } else if (e is ErrorEvent) {
      _phase = SendPhase.failed;
      _busy = false;
    } else if (e is InteractiveRequestEvent) {
      // 交互式请求（权限确认/elicitation/提问）：交由上层 UI 处理并回发响应。
      _pendingInteractiveId = e.id;
      onInteractiveRequest?.call(e);
    }
  }

  /// 交互式请求回调（UI 层注册，渲染对应控件并回发响应）。
  void Function(InteractiveRequestEvent)? onInteractiveRequest;
  int? _pendingInteractiveId;

  /// 把用户回应经 JSON-RPC 响应发回服务端（报告02 §5）。
  Future<void> respondInteractive(Map<String, dynamic> result) async {
    final id = _pendingInteractiveId;
    if (id == null) return;
    await transport.respond(id, result);
    _pendingInteractiveId = null;
  }

  /// 发送消息。历史拼接/上下文规则在 SessionRepository.prompt 内按报告实现。
  Future<void> send(String text) async {
    if (_busy) {
      // 会话级并发保护：拒绝并发发送，避免流串线。
      throw StateError('该会话已有消息在生成中，请等待完成或先停止');
    }
    await ensureReady();
    _busy = true;
    _phase = SendPhase.sending;
    acc.addUserMessage(text);
    acc.addPendingAssistant();

    // 捕获当前会话引用：发送期间即使用户切走会话，事件也落到发起时的会话。
    final targetSession = _sessionId!;
    try {
      await sessions.prompt(
        targetSession,
        <ContentBlock>[ContentBlock.text(text)],
      );
      _phase = SendPhase.streaming;
      acc.markStreaming();
      _armTimeoutGuard(targetSession);
    } catch (e) {
      _failCurrent(e.toString());
    }
  }

  /// 重试失败消息：状态重置后重新走发送。
  Future<void> retry(String failedMessageId, String text) async {
    acc.markRetry(failedMessageId);
    _busy = false;
    await send(text);
  }

  /// 中断路径 1：用户中途停止 → session/cancel notification + 本地转 cancelled。
  Future<void> stop() async {
    if (_sessionId == null) return;
    await sessions.cancel(_sessionId!);
    _cancelWatch?.call();
    if (_busy) {
      _phase = SendPhase.cancelled;
      acc.onStop('cancelled');
      _finish();
    }
  }

  /// 中断路径 2：流式超时 → 本地判定 + session/cancel。
  Timer? _watchTimer;
  void Function()? _cancelWatch;
  void _armTimeoutGuard(String sessionId) {
    _watchTimer?.cancel();
    _cancelWatch?.call();
    _watchTimer = Timer.periodic(streamTimeout, (_) {
      // 超时路径：停止生成，标记 failed 并提供重试入口。
      sessions.cancel(sessionId);
      _failCurrent('流式响应超时（${streamTimeout.inSeconds}s 无新数据）');
    });
    _cancelWatch = () {
      _watchTimer?.cancel();
      _watchTimer = null;
    };
  }

  /// 收到任意事件时刷新超时计时（由 feedSse/_onTransportMessage 调用点外部按需触发）。
  void touch() => _armTimeoutGuard(_sessionId ?? '');

  /// 中断路径 3：网络断开 → 指数退避重连 + Last-Event-ID 续传。
  /// 由 UI/传输层在检测到 SSE 断开时调用。
  Future<bool> reconnectOnDisconnect({String? lastEventId}) async {
    for (var attempt = 0; attempt < maxReconnect; attempt++) {
      final delay = reconnectBaseDelay * (1 << attempt);
      await Future<void>.delayed(delay);
      try {
        await transport.bootstrap();
        _subscribeTask = transport.startSubscribe();
        _attachSubscription();
        // TODO(dynamic-capture): 把 lastEventId 作为 Last-Event-ID 头带上（端点/续传行为需抓包确认）。
        return true;
      } catch (_) {
        // 继续下一次退避重试。
      }
    }
    _failCurrent('网络断开且重连 $maxReconnect 次失败');
    return false;
  }

  void _finish() {
    _cancelWatch?.call();
    _phase = SendPhase.done;
    _busy = false;
  }

  void _failCurrent(String reason) {
    _cancelWatch?.call();
    acc.onError(reason);
    _phase = SendPhase.failed;
    _busy = false;
  }

  String _jsonEncode(Map<String, dynamic> m) => jsonEncode(m);

  Future<void> dispose() async {
    _cancelWatch?.call();
    await _sub?.cancel();
    await transport.close();
  }
}
