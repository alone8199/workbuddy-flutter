import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/chat/stream/stream_parser.dart';
import 'package:workbuddy/chat/stream/stream_event.dart';

String rpc(Map<String, dynamic> m) => 'data: ${jsonEncode(m)}\n\n';

/// 用构造样例分片对拍解析器（用户要求：样例输入输出对拍）。
/// 样例依据报告01 §4 的分帧/结束/错误规则手工构造，非真实抓包。
void main() {
  group('StreamParser 分帧', () {
    test('单帧增量文本 → TextDeltaEvent', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': '你好'},
          }
        }
      }));
      expect(ev.length, 1);
      expect(ev.first, isA<TextDeltaEvent>());
      expect((ev.first as TextDeltaEvent).text, '你好');
    });

    test('thinking 增量 → ThoughtDeltaEvent', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'update': {
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': '让我思考'},
        }}
      }));
      expect(ev.single, isA<ThoughtDeltaEvent>());
      expect((ev.single as ThoughtDeltaEvent).text, '让我思考');
    });

    test('心跳注释行 : ping → HeartbeatEvent，不污染数据帧', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(': ping\n\n');
      expect(ev.single, isA<HeartbeatEvent>());
    });

    test('裸 JSON 行也当一帧', () {
      final p = StreamParser();
      final ev = p.feedAndDrain('{"jsonrpc":"2.0","result":{"stopReason":"end_turn"},"id":1}\n');
      expect(ev.single, isA<StopEvent>());
      expect((ev.single as StopEvent).stopReason, 'end_turn');
    });

    test('粘包半包：拆成多段喂入仍正确解析一帧', () {
      final p = StreamParser();
      final full = rpc({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': '流式拼接'},
        }}
      });
      final all = <dynamic>[];
      for (var i = 0; i < full.length; i += 7) {
        final end = (i + 7 < full.length) ? i + 7 : full.length;
        all.addAll(p.feedAndDrain(full.substring(i, end)));
      }
      all.addAll(p.close());
      expect(all.whereType<TextDeltaEvent>().length, 1);
      expect(all.whereType<TextDeltaEvent>().first.text, '流式拼接');
    });
  });

  group('结束标记', () {
    test('[DONE] → StopEvent(marker=[DONE])', () {
      final p = StreamParser();
      final ev = p.feedAndDrain('data: [DONE]\n\n');
      expect(ev.single, isA<StopEvent>());
      expect((ev.single as StopEvent).marker, '[DONE]');
    });

    test('done:true → StopEvent(marker=done:true)', () {
      final p = StreamParser();
      final ev = p.feedAndDrain('data: {"done":true}\n\n');
      expect((ev.single as StopEvent).marker, 'done:true');
    });

    test('kind:stop（prompt 响应带 stopReason）→ StopEvent', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({
        'jsonrpc': '2.0',
        'id': 3,
        'result': {'stopReason': 'cancelled'}
      }));
      expect((ev.single as StopEvent).stopReason, 'cancelled');
    });
  });

  group('错误帧', () {
    test('event:error → ErrorEvent', () {
      final p = StreamParser();
      final ev = p.feedAndDrain('event: error\ndata: stream broke\n\n');
      expect(ev.single, isA<ErrorEvent>());
      expect((ev.single as ErrorEvent).message, contains('stream broke'));
    });

    test('msg.error 对象 → ErrorEvent 带 code', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({'jsonrpc': '2.0', 'error': {
        'code': -32000, 'message': 'rate limited'
      }}));
      expect(ev.single, isA<ErrorEvent>());
      expect((ev.single as ErrorEvent).rawCode, '-32000');
    });

    test('非法 JSON → ErrorEvent（不崩溃）', () {
      final p = StreamParser();
      final ev = p.feedAndDrain('data: {not json}\n\n');
      expect(ev.single, isA<ErrorEvent>());
    });
  });

  group('工具与交互', () {
    test('tool_call → ToolCallEvent', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tc1', 'name': 'Read', 'status': 'in_progress',
        }}
      }));
      expect(ev.single, isA<ToolCallEvent>());
    });

    test('elicitation/create → InteractiveRequestEvent（带 id）', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({
        'jsonrpc': '2.0', 'id': 9, 'method': 'elicitation/create',
        'params': {'mode': 'form', 'message': '请填写'}
      }));
      expect(ev.single, isA<InteractiveRequestEvent>());
      expect((ev.single as InteractiveRequestEvent).id, 9);
    });

    test('多字段并行增量：一次流内连续文本+思考+工具+系统事件全部产出', () {
      final p = StreamParser();
      final buf = StringBuffer()
        ..write(rpc({'jsonrpc':'2.0','method':'session/update','params':{'update':{
          'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':'正文'}
        }}}))
        ..write(rpc({'jsonrpc':'2.0','method':'session/update','params':{'update':{
          'sessionUpdate':'agent_thought_chunk','content':{'type':'text','text':'推理'}
        }}}))
        ..write(rpc({'jsonrpc':'2.0','method':'session/update','params':{'update':{
          'sessionUpdate':'tool_call','toolCallId':'x','name':'Grep','status':'completed'
        }}}))
        ..write(rpc({'jsonrpc':'2.0','method':'session/update','params':{'update':{
          'sessionUpdate':'notice','level':'warning','message':'注意'
        }}}))
        ..write('data: [DONE]\n\n');
      final ev = p.feedAndDrain(buf.toString());
      expect(ev.whereType<TextDeltaEvent>().length, 1);
      expect(ev.whereType<ThoughtDeltaEvent>().length, 1);
      expect(ev.whereType<ToolCallEvent>().length, 1);
      expect(ev.whereType<SystemUpdateEvent>().length, 1);
      expect(ev.whereType<StopEvent>().length, 1);
    });
  });

  group('OpenAI delta 兼容', () {
    test('choices[0].delta.content → TextDeltaEvent', () {
      final p = StreamParser();
      final ev = p.feedAndDrain(rpc({
        'choices': [{'delta': {'content': '模型输出'}}]
      }));
      expect(ev.single, isA<TextDeltaEvent>());
      expect((ev.single as TextDeltaEvent).text, '模型输出');
    });
  });
}
