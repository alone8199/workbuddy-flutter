/// 标准化对话流式事件（纯 Dart，无 Flutter 依赖，可单测）。
/// 解析器输入 SSE 分片，输出本文件定义的事件序列。
/// 数据源：报告01《对话链路与传输分析》4.1 SSEDecoder / 4.2 SSEUtil.handleSSE / 4.3 ACP 消费。
///
/// 设计意图：把「SSE 分帧 → JSON 解析 → session/update 语义」三层收敛为
/// 一条标准化事件流，UI/状态层只消费本文件，不接触原始 SSE 细节。

abstract class StreamEvent {
  const StreamEvent();
}

/// 增量正文：agent_message_chunk（content.type=='text'）或 OpenAI delta.content。
class TextDeltaEvent extends StreamEvent {
  final String text;
  final String? messageId;
  const TextDeltaEvent(this.text, {this.messageId});
  @override
  String toString() => 'TextDelta(+${text.length}chars)';
}

/// 增量思考：agent_thought_chunk（thinking/reasoning）。
class ThoughtDeltaEvent extends StreamEvent {
  final String text;
  const ThoughtDeltaEvent(this.text);
  @override
  String toString() => 'ThoughtDelta(+${text.length}chars)';
}

/// 工具调用开始/进展/结果：tool_call / tool_call_update。
class ToolCallEvent extends StreamEvent {
  final Map<String, dynamic> toolCall;
  const ToolCallEvent(this.toolCall);
  @override
  String toString() => 'ToolCall(${toolCall['name'] ?? toolCall['title'] ?? '?'},'
      'status=${toolCall['status'] ?? '?'})';
}

/// 其他 session/update（plan/notice/usage/compaction/subagent/session_info 等）。
/// 保留 kind + 原始 payload 交给渲染层按类型处理。
class SystemUpdateEvent extends StreamEvent {
  final String kind; // 原始 sessionUpdate 字符串
  final Map<String, dynamic> raw;
  const SystemUpdateEvent(this.kind, this.raw);
  @override
  String toString() => 'SystemUpdate($kind)';
}

/// 服务端主动发起的交互式请求（JSON-RPC request，需用户回应并回发响应）：
/// session/request_permission、elicitation/create、askuserquestion 等。
class InteractiveRequestEvent extends StreamEvent {
  final String method;
  final int? id;
  final Map<String, dynamic> params;
  const InteractiveRequestEvent(this.method, this.params, {this.id});
  @override
  String toString() => 'InteractiveRequest($method, id=$id)';
}

/// 流结束。marker 区分三种结束标记：[DONE] / done:true / kind:stop。
class StopEvent extends StreamEvent {
  final String? stopReason;
  final String marker; // '[DONE]' | 'done:true' | 'kind:stop'
  const StopEvent({this.stopReason, this.marker = 'kind:stop'});
  @override
  String toString() => 'Stop(marker=$marker, reason=$stopReason)';
}

/// 错误帧：event:error 或 msg.error 非空，或 JSON 解析失败。
class ErrorEvent extends StreamEvent {
  final String message;
  final String? rawCode;
  final Map<String, dynamic>? raw;
  const ErrorEvent(this.message, {this.rawCode, this.raw});
  @override
  String toString() => 'Error($message, code=$rawCode)';
}

/// 心跳/注释行（以 ':' 开头）或 SSE 注释，保序产出但通常被上层忽略。
class HeartbeatEvent extends StreamEvent {
  final String raw;
  const HeartbeatEvent(this.raw);
  @override
  String toString() => 'Heartbeat';
}

/// 兜底：无法归类但合法的帧，保留原始 event/data，保证不丢数据、不崩溃。
class RawEvent extends StreamEvent {
  final String? event;
  final String data;
  const RawEvent(this.event, this.data);
  @override
  String toString() => 'Raw(event=$event, ${data.length}chars)';
}
