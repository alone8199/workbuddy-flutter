/// SSE 分帧事件。数据源：cli SSEDecoder/SSEUtil。
class SseEvent {
  final String? event;
  final String data;
  final List<String> raw;

  SseEvent({this.event, required this.data, List<String>? raw})
      : raw = raw ?? const [];

  bool get isDone => data.trim() == '[DONE]';
}
