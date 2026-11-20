import '../models/session_update.dart';
import 'stream/stream_event.dart';

/// 19 种 session/update 分发目标。
abstract class UpdateSink {
  void onTextDelta(String text);
  void onThoughtDelta(String text);
  void onToolUpdate(Map<String, dynamic> raw);
  void onSystemEvent(SessionUpdate update);
  void onStop(String? stopReason);
  void onError(String message);
}

/// 把标准化流事件路由到 sink。
/// 数据源：报告01 §4.3 / 报告02 的 19 种 session/update。
class UpdateRouter {
  final UpdateSink sink;
  UpdateRouter(this.sink);

  /// 消费解析器输出的标准化事件序列。
  void routeEvent(StreamEvent e) {
    if (e is TextDeltaEvent) {
      sink.onTextDelta(e.text);
    } else if (e is ThoughtDeltaEvent) {
      sink.onThoughtDelta(e.text);
    } else if (e is ToolCallEvent) {
      sink.onToolUpdate(e.toolCall);
    } else if (e is SystemUpdateEvent) {
      sink.onSystemEvent(_toSessionUpdate(e.kind, e.raw));
    } else if (e is StopEvent) {
      sink.onStop(e.stopReason);
    } else if (e is ErrorEvent) {
      sink.onError(e.message);
    }
    // InteractiveRequestEvent / HeartbeatEvent / RawEvent 由 controller 单独处理，
    // 不进入消息累加器。
  }

  /// 兼容旧的 SessionUpdate 直连入口。
  void route(SessionUpdate u) {
    switch (u.kind) {
      case SessionUpdateKind.agentMessageChunk:
        final c = u.raw['content'];
        if (c is Map && c['type'] == 'text') sink.onTextDelta(c['text'] as String? ?? '');
        break;
      case SessionUpdateKind.agentThoughtChunk:
        final c = u.raw['content'];
        if (c is Map) sink.onThoughtDelta(c['text'] as String? ?? '');
        break;
      case SessionUpdateKind.toolCall:
      case SessionUpdateKind.toolCallUpdate:
        sink.onToolUpdate(u.raw);
        break;
      case SessionUpdateKind.notice:
      case SessionUpdateKind.plan:
      case SessionUpdateKind.planUpdate:
      case SessionUpdateKind.usageUpdate:
      case SessionUpdateKind.subagentUpdate:
      case SessionUpdateKind.availableCommandsUpdate:
      case SessionUpdateKind.currentModeUpdate:
        sink.onSystemEvent(u);
        break;
      default:
        break;
    }
  }

  SessionUpdate _toSessionUpdate(String kind, Map<String, dynamic> raw) {
    return SessionUpdate.fromJson(<String, dynamic>{
      'update': <String, dynamic>{...raw, 'sessionUpdate': kind},
    });
  }
}
