/// ACP 工具调用状态与类别。数据源：acp-DdDO41dd.js ue/de 枚举。
enum ToolKind { read, edit, delete, move, search, execute, think, fetch, switchMode, other }
enum ToolStatus { pending, inProgress, completed, failed }

ToolKind _kind(String? s) {
  switch (s) {
    case 'read': return ToolKind.read;
    case 'edit': return ToolKind.edit;
    case 'delete': return ToolKind.delete;
    case 'move': return ToolKind.move;
    case 'search': return ToolKind.search;
    case 'execute': return ToolKind.execute;
    case 'think': return ToolKind.think;
    case 'fetch': return ToolKind.fetch;
    case 'switch_mode': return ToolKind.switchMode;
    default: return ToolKind.other;
  }
}

ToolStatus _status(String? s) {
  switch (s) {
    case 'pending': return ToolStatus.pending;
    case 'in_progress': return ToolStatus.inProgress;
    case 'completed': return ToolStatus.completed;
    case 'failed': return ToolStatus.failed;
    default: return ToolStatus.pending;
  }
}

class ToolCall {
  final String toolCallId;
  final ToolKind kind;
  final ToolStatus status;
  final String? title;
  final String? name;
  final Map<String, dynamic>? rawOutput;

  ToolCall({
    required this.toolCallId,
    required this.kind,
    required this.status,
    this.title,
    this.name,
    this.rawOutput,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        toolCallId: json['toolCallId'] as String? ?? '',
        kind: _kind(json['kind'] as String?),
        status: _status(json['status'] as String?),
        title: json['title'] as String?,
        name: json['name'] as String?,
        rawOutput: json['rawOutput'] is Map ? json['rawOutput'] as Map<String, dynamic> : null,
      );
}
