import 'dart:convert';

import 'stream_event.dart';

/// SSE 解析器（独立于网络层，纯 Dart、可单测）。
///
/// 职责：输入一条 SSE 流（分段喂入），输出标准化事件序列 [StreamEvent]。
/// 还原自分析报告 01 第四节：
///   - 4.1 SSEDecoder 分帧：event:/data:/空行分隔/注释心跳/裸 JSON 行/TCP 粘包半包
///   - 4.2 SSEUtil.handleSSE：[DONE] / done:true / msg.error / event:error 判定
///   - 4.3 ACP 消费：JSON-RPC session/update 通知 + kind:stop 收尾
///
/// 用法：
/// ```dart
/// final p = StreamParser();
/// p.feed('data: {"jsonrpc":"2.0",...}\n\n'); // 可多次喂入任意切片
/// final events = p.drain();                    // 取出已解析出的事件
/// ```
class StreamParser {
  final StringBuffer _buffer = StringBuffer(); // 半行残留
  String _eventName = '';
  final List<String> _dataLines = <String>[];
  final List<String> _rawLines = <String>[];
  final List<StreamEvent> _out = <StreamEvent>[];

  /// 喂入一段文本（字节已 UTF-8 解码）。任意切片边界都安全。
  void feed(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final lines = text.split('\n');
    // 最后一段可能是不完整的半行，留存到下次。
    for (var i = 0; i < lines.length - 1; i++) {
      _decodeLine(lines[i]);
    }
    _buffer
      ..clear()
      ..write(lines.last);
  }

  /// 取出并清空已解析出的事件。
  List<StreamEvent> drain() {
    final result = List<StreamEvent>.unmodifiable(_out);
    _out.clear();
    return result;
  }

  /// 喂入并立即取出（便捷方法）。
  List<StreamEvent> feedAndDrain(String chunk) {
    feed(chunk);
    return drain();
  }

  /// 流结束时调用：冲刷残留 buffer（把没有以空行结尾的最后一帧也解析出来）。
  List<StreamEvent> close() {
    if (_buffer.isNotEmpty) {
      _decodeLine(_buffer.toString());
      _buffer.clear();
    }
    _flushFrame();
    return drain();
  }

  void _decodeLine(String rawLine) {
    var line = rawLine;
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line.isEmpty) {
      _flushFrame(); // 空行 = 一个事件结束（SSE 标准）
      return;
    }
    _rawLines.add(line);
    // 注释/心跳：': ping' 之类，忽略为帧内容但产出心跳事件。
    if (line.startsWith(':')) {
      _out.add(HeartbeatEvent(line));
      return;
    }
    // 裸 JSON 行也当一个完整事件（SSEDecoder 行为）。
    if (line.startsWith('{') && line.endsWith('}')) {
      _dataLines.add(line);
      _flushFrame();
      return;
    }
    final idx = line.indexOf(':');
    if (idx < 0) {
      // 无冒号的字段行：按 data 处理（容错）。
      _dataLines.add(line);
      return;
    }
    final field = line.substring(0, idx);
    var value = line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _eventName = value;
        break;
      case 'data':
        _dataLines.add(value);
        break;
      case 'id':
      case 'retry':
        // Last-Event-ID / 重连时间：传输层关注，解析层仅记录不产出事件。
        break;
    }
  }

  void _flushFrame() {
    if (_eventName.isEmpty && _dataLines.isEmpty) {
      _rawLines.clear();
      return;
    }
    final data = _dataLines.join('\n');
    final event = _eventName.isEmpty ? null : _eventName;
    final raw = List<String>.unmodifiable(_rawLines);
    _eventName = '';
    _dataLines.clear();
    _rawLines.clear();

    _parseFrame(event, data, raw);
  }

  void _parseFrame(String? event, String data, List<String> raw) {
    // 结束标志 1：[DONE]（OpenAI 标准）
    if (data.trim() == '[DONE]') {
      _out.add(const StopEvent(marker: '[DONE]'));
      return;
    }
    // 错误帧：event:error（即使 data 不是 JSON）
    if (event == 'error') {
      _out.add(ErrorEvent(data.isNotEmpty ? data : 'stream error event',
          raw: <String, dynamic>{'event': event, 'data': data, 'raw': raw}));
      return;
    }

    Map<String, dynamic>? msg;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (_) {
      // JSON 解析失败：报告 4.2 observer.error 路径。
      _out.add(ErrorEvent('Could not parse message into JSON: $data',
          raw: <String, dynamic>{'event': event, 'data': data, 'raw': raw}));
      return;
    }
    if (msg == null) {
      _out.add(RawEvent(event, data));
      return;
    }

    // 错误帧：msg.error 非空（字符串或对象）
    final err = msg['error'];
    if (err != null) {
      final code = err is Map ? err['code']?.toString() : null;
      final text = err is Map ? (err['message']?.toString() ?? err.toString()) : err.toString();
      _out.add(ErrorEvent(text, rawCode: code, raw: msg));
      return;
    }

    // 结束标志 2：done:true
    if (msg['done'] == true) {
      _out.add(StopEvent(marker: 'done:true', stopReason: msg['stop_reason']?.toString() ??
          msg['stopReason']?.toString()));
      return;
    }

    // ACP / JSON-RPC 消息
    if (msg.containsKey('jsonrpc')) {
      _parseJsonRpc(msg);
      return;
    }

    // OpenAI delta 格式（第二层模型流的兼容解析）
    if (msg.containsKey('choices')) {
      _parseOpenAiDelta(msg);
      return;
    }

    // 无法归类：兜底原始事件，不崩溃。
    _out.add(RawEvent(event, data));
  }

  void _parseJsonRpc(Map<String, dynamic> msg) {
    final method = msg['method']?.toString();
    final id = msg['id'] is int ? msg['id'] as int : null;

    if (method == 'session/update') {
      final params = (msg['params'] is Map) ? msg['params'] as Map<String, dynamic> : <String, dynamic>{};
      final update = (params['update'] is Map)
          ? params['update'] as Map<String, dynamic>
          : params;
      _parseSessionUpdate(update);
      return;
    }

    // 服务端主动请求用户交互：权限确认 / elicitation / 提问。
    if (method == 'session/request_permission' ||
        method == 'elicitation/create' ||
        method == 'askuserquestion' ||
        (method != null && method.contains('request'))) {
      final params = (msg['params'] is Map) ? msg['params'] as Map<String, dynamic> : <String, dynamic>{};
      _out.add(InteractiveRequestEvent(method ?? '', params, id: id));
      return;
    }

    // JSON-RPC 响应里带 stopReason（prompt 的返回）→ 收尾。
    final result = msg['result'];
    if (result is Map && result.containsKey('stopReason')) {
      _out.add(StopEvent(marker: 'kind:stop', stopReason: result['stopReason']?.toString()));
      return;
    }

    _out.add(RawEvent('jsonrpc:$method', jsonEncode(msg)));
  }

  void _parseSessionUpdate(Map<String, dynamic> update) {
    final kind = update['sessionUpdate']?.toString() ?? '';
    switch (kind) {
      case 'agent_message_chunk':
        final c = update['content'];
        if (c is Map && c['type'] == 'text') {
          _out.add(TextDeltaEvent(c['text']?.toString() ?? ''));
        }
        break;
      case 'agent_thought_chunk':
        final c = update['content'];
        if (c is Map) {
          _out.add(ThoughtDeltaEvent(c['text']?.toString() ?? ''));
        }
        break;
      case 'tool_call':
      case 'tool_call_update':
        _out.add(ToolCallEvent(Map<String, dynamic>.from(update)));
        break;
      case 'stop':
        // ACP updates 队列的 stop（ActiveSession.prompt().then 里的 kind:'stop'）
        _out.add(StopEvent(
            marker: 'kind:stop', stopReason: update['stopReason']?.toString()));
        break;
      default:
        // 其余 15 种（plan/notice/usage/compaction/subagent/session_info ...）
        _out.add(SystemUpdateEvent(kind, update));
        break;
    }
  }

  void _parseOpenAiDelta(Map<String, dynamic> msg) {
    final choices = msg['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final delta = first['delta'];
        if (delta is Map) {
          final content = delta['content']?.toString();
          if (content != null && content.isNotEmpty) {
            _out.add(TextDeltaEvent(content));
          }
          final reasoning = delta['reasoning_content']?.toString();
          if (reasoning != null && reasoning.isNotEmpty) {
            _out.add(ThoughtDeltaEvent(reasoning));
          }
        }
      }
    }
    if (msg['done'] == true) {
      _out.add(const StopEvent(marker: 'done:true'));
    }
  }
}
