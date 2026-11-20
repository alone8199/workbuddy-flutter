/// ACP session/update 的 19 种类型。
/// 数据源：acp-DdDO41dd.js Rn union。
enum SessionUpdateKind {
  userMessageChunk,
  agentMessageChunk,
  agentThoughtChunk,
  toolCall,
  toolCallUpdate,
  plan,
  planUpdate,
  planRemoved,
  availableCommandsUpdate,
  currentModeUpdate,
  configOptionUpdate,
  sessionInfoUpdate,
  usageUpdate,
  notice,
  compactionUpdate,
  compactionSummaryChunk,
  subagentUpdate,
  sessionMessage,
  sessionMessageChunk,
  unknown,
}

SessionUpdateKind _parseUpdate(String s) {
  switch (s) {
    case 'user_message_chunk': return SessionUpdateKind.userMessageChunk;
    case 'agent_message_chunk': return SessionUpdateKind.agentMessageChunk;
    case 'agent_thought_chunk': return SessionUpdateKind.agentThoughtChunk;
    case 'tool_call': return SessionUpdateKind.toolCall;
    case 'tool_call_update': return SessionUpdateKind.toolCallUpdate;
    case 'plan': return SessionUpdateKind.plan;
    case 'plan_update': return SessionUpdateKind.planUpdate;
    case 'plan_removed': return SessionUpdateKind.planRemoved;
    case 'available_commands_update': return SessionUpdateKind.availableCommandsUpdate;
    case 'current_mode_update': return SessionUpdateKind.currentModeUpdate;
    case 'config_option_update': return SessionUpdateKind.configOptionUpdate;
    case 'session_info_update': return SessionUpdateKind.sessionInfoUpdate;
    case 'usage_update': return SessionUpdateKind.usageUpdate;
    case 'notice': return SessionUpdateKind.notice;
    case 'compaction_update': return SessionUpdateKind.compactionUpdate;
    case 'compaction_summary_chunk': return SessionUpdateKind.compactionSummaryChunk;
    case 'subagent_update': return SessionUpdateKind.subagentUpdate;
    case 'session_message': return SessionUpdateKind.sessionMessage;
    case 'session_message_chunk': return SessionUpdateKind.sessionMessageChunk;
    default: return SessionUpdateKind.unknown;
  }
}

/// 一次 session/update 通知的强类型封装。
class SessionUpdate {
  final SessionUpdateKind kind;
  final Map<String, dynamic> raw;
  final String? noticeLevel;
  final String? noticeMessage;
  final String? stopReason;

  SessionUpdate({
    required this.kind,
    required this.raw,
    this.noticeLevel,
    this.noticeMessage,
    this.stopReason,
  });

  factory SessionUpdate.fromJson(Map<String, dynamic> json) {
    final u = (json['update'] is Map) ? json['update'] as Map<String, dynamic> : json;
    return SessionUpdate(
      kind: _parseUpdate(u['sessionUpdate'] as String? ?? ''),
      raw: u,
      noticeLevel: u['level'] as String?,
      noticeMessage: u['message'] as String?,
      stopReason: u['stopReason'] as String?,
    );
  }
}
