import 'dart:convert';
import 'sse_event.dart';

/// SSE 逐行解码器：处理 event:/data:/空行/注释/裸 JSON 行/粘包残留。
/// 数据源：cli SSEDecoder（codebuddy-lite-wb.mjs @23869）。
class SseParser {
  String _event = '';
  final List<String> _data = <String>[];
  final List<String> _chunks = <String>[];
  final StringBuffer _buffer = StringBuffer();

  /// 喂入字节片段（UTF-8 解码后）。按 \n 切行，残留缓存处理半包。
  void feed(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final lines = text.split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      _decodeLine(lines[i]);
    }
    _buffer.clear();
    _buffer.write(lines.last); // 残留半行
  }

  SseEvent? _decodeLine(String line) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.isEmpty) return _buildEvent();
    _chunks.add(line);
    if (line.startsWith(':')) return null; // 心跳/注释
    if (line.startsWith('{') && line.endsWith('}')) {
      _data.add(line);
      return _buildEvent(); // 裸 JSON 行
    }
    final idx = line.indexOf(':');
    if (idx < 0) return null;
    final field = line.substring(0, idx);
    var value = line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      _data.add(value);
    }
    return null;
  }

  SseEvent? _buildEvent() {
    if (_event.isEmpty && _data.isEmpty) return null;
    final ev = SseEvent(
      event: _event.isEmpty ? null : _event,
      data: _data.join('\n'),
      raw: List.unmodifiable(_chunks),
    );
    _decoded.add(ev);
    _event = '';
    _data.clear();
    _chunks.clear();
    return ev;
  }

  /// 喂入并立即取出已完成的帧（便捷方法）。
  List<SseEvent> feedAndDrain(String chunk) {
    feed(chunk);
    return drain();
  }

  /// 取出并清空已解析出的帧。
  List<SseEvent> drain() {
    final result = List<SseEvent>.unmodifiable(_decoded);
    _decoded.clear();
    return result;
  }

  final List<SseEvent> _decoded = <SseEvent>[];

  /// 解析 data 为 JSON。失败返回 null（调用方按错误处理）。
  Map<String, dynamic>? parseJson(SseEvent ev) {
    try {
      final decoded = jsonDecode(ev.data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
