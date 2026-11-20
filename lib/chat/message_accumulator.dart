import 'dart:convert';

import '../models/message.dart';
import '../models/tool_call.dart';
import '../models/session_update.dart';
import 'update_router.dart';

/// 增量累加器：把流式事件累加成完整消息；按 toolCallId 归并工具更新。
/// 一个实例对应一个会话（多会话切换不串消息：每个 sessionId 持有独立 accumulator）。
class MessageAccumulator implements UpdateSink {
  final Map<String, ChatMessage> _messages = {};
  final Map<String, ToolCall> _tools = {};
  final List<void Function()> _listeners = [];

  String? _currentAssistantId;
  String? _currentThoughtId;
  String? _stopReason;

  List<ChatMessage> get messages {
    final list = _messages.values.toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(list);
  }

  Map<String, ToolCall> get tools => Map.unmodifiable(_tools);
  String? get stopReason => _stopReason;

  void addListener(void Function() cb) => _listeners.add(cb);
  void removeListener(void Function() cb) => _listeners.remove(cb);
  void _notify() {
    for (final cb in List<void Function()>.from(_listeners)) {
      cb();
    }
  }

  /// 用户消息：状态 complete。
  String addUserMessage(String text) {
    final id = 'u_${DateTime.now().microsecondsSinceEpoch}';
    _messages[id] = ChatMessage(
      id: id,
      role: 'user',
      content: text,
      status: MessageStatus.complete,
    );
    _notify();
    return id;
  }

  /// 建一条 pending 的 assistant 占位（对应 createPendingMessage）。
  String addPendingAssistant() {
    final id = 'a_${DateTime.now().microsecondsSinceEpoch}';
    _messages[id] = ChatMessage(
      id: id,
      role: 'assistant',
      content: '',
      status: MessageStatus.pending,
    );
    _currentAssistantId = id;
    _notify();
    return id;
  }

  /// 流式中：pending → streaming。
  void markStreaming() {
    final id = _currentAssistantId;
    if (id == null) return;
    final m = _messages[id];
    if (m != null && m.status == MessageStatus.pending) {
      _messages[id] = m.copyWith(status: MessageStatus.streaming);
      _notify();
    }
  }

  @override
  void onTextDelta(String text) {
    markStreaming();
    _currentAssistantId ??= addPendingAssistant();
    final id = _currentAssistantId!;
    final prev = _messages[id]!;
    _messages[id] = prev.copyWith(
      content: prev.content + text,
      status: MessageStatus.streaming,
      clearError: true,
    );
    _notify();
  }

  @override
  void onThoughtDelta(String text) {
    _currentThoughtId ??= 't_${DateTime.now().microsecondsSinceEpoch}';
    final id = _currentThoughtId!;
    final prev = _messages[id];
    _messages[id] = ChatMessage(
      id: id,
      role: 'thought',
      content: (prev?.content ?? '') + text,
      status: MessageStatus.streaming,
    );
    _notify();
  }

  @override
  void onToolUpdate(Map<String, dynamic> raw) {
    // 保留完整原始字段（rawInput/rawOutput/content/locations/_meta），
    // 供渲染层逐工具展示。
    final tc = ToolCall.fromJson(raw);
    final merged = <String, dynamic>{...raw};
    if (_tools.containsKey(tc.toolCallId)) {
      final prev = _tools[tc.toolCallId]!;
      final effective = tc.rawOutput ?? prev.rawOutput;
      merged.putIfAbsent('rawInput', () => {
        'name': prev.name,
        'title': prev.title,
        'kind': _kindName(prev.kind),
      });
      if (effective != null) merged['rawOutput'] = effective;
    }
    _tools[tc.toolCallId] = ToolCall.fromJson(merged);
    _toolsMapRaw[tc.toolCallId] = merged;

    // 同步落一条 role='tool' 消息，携带完整原始数据，渲染层按工具名分派专门组件。
    final msgId = 'tc_${tc.toolCallId}';
    final toolMsg = ChatMessage(
      id: msgId,
      role: 'tool',
      content: jsonEncode(merged),
      status: _toolStatus(tc.status),
      blocks: const [],
    );
    _messages[msgId] = toolMsg;
    _notify();
  }

  MessageStatus _toolStatus(ToolStatus s) {
    switch (s) {
      case ToolStatus.completed: return MessageStatus.complete;
      case ToolStatus.failed: return MessageStatus.failed;
      case ToolStatus.inProgress: return MessageStatus.streaming;
      default: return MessageStatus.pending;
    }
  }

  /// 供渲染层读取工具的完整原始数据。
  final Map<String, Map<String, dynamic>> _toolsMapRaw = {};
  Map<String, Map<String, dynamic>> get toolRaw => Map.unmodifiable(_toolsMapRaw);

  @override
  void onSystemEvent(SessionUpdate update) {
    // notice / plan / usage / compaction / subagent 等：作为一条 system 消息落库，
    // 渲染层按 level/kind 决定样式（详见 RenderDispatcher）。
    if (update.kind == SessionUpdateKind.notice ||
        update.kind == SessionUpdateKind.usageUpdate ||
        update.kind == SessionUpdateKind.subagentUpdate ||
        update.kind == SessionUpdateKind.compactionUpdate ||
        update.kind == SessionUpdateKind.plan) {
      final id = 's_${DateTime.now().microsecondsSinceEpoch}_${_messages.length}';
      final text = update.noticeMessage ?? jsonEncode(update.raw);
      _messages[id] = ChatMessage(
        id: id,
        role: 'system',
        content: text,
        status: MessageStatus.complete,
        level: update.noticeLevel,
      );
      _notify();
    }
  }

  @override
  void onStop(String? stopReason) {
    _stopReason = stopReason;
    if (_currentAssistantId != null) {
      final m = _messages[_currentAssistantId!];
      if (m != null) {
        _messages[_currentAssistantId!] =
            m.copyWith(status: MessageStatus.complete, clearError: true);
      }
    }
    if (_currentThoughtId != null) {
      final t = _messages[_currentThoughtId!];
      if (t != null) {
        _messages[_currentThoughtId!] = t.copyWith(status: MessageStatus.complete);
      }
    }
    _currentAssistantId = null;
    _currentThoughtId = null;
    _notify();
  }

  /// 错误：当前 assistant 消息转 failed，携带原因。
  @override
  void onError(String message) {
    if (_currentAssistantId != null) {
      final m = _messages[_currentAssistantId!];
      if (m != null) {
        _messages[_currentAssistantId!] =
            m.copyWith(status: MessageStatus.failed, error: message);
      }
    }
    _currentAssistantId = null;
    _currentThoughtId = null;
    _notify();
  }

  /// 重试：把失败消息置回 retrying（由 controller 重新发送）。
  void markRetry(String messageId) {
    final m = _messages[messageId];
    if (m != null && m.status == MessageStatus.failed) {
      _messages[messageId] = m.copyWith(status: MessageStatus.retrying, clearError: true);
      _notify();
    }
  }

  static String _kindName(ToolKind k) {
    switch (k) {
      case ToolKind.read: return 'read';
      case ToolKind.edit: return 'edit';
      case ToolKind.delete: return 'delete';
      case ToolKind.move: return 'move';
      case ToolKind.search: return 'search';
      case ToolKind.execute: return 'execute';
      case ToolKind.think: return 'think';
      case ToolKind.fetch: return 'fetch';
      case ToolKind.switchMode: return 'switch_mode';
      default: return 'other';
    }
  }
}
