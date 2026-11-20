import 'content_block.dart';

/// 前端消息状态。数据源：renderer 消息状态 error/complete/failed/pending + 流式 streaming。
enum MessageStatus { pending, streaming, complete, failed, retrying }

/// 一条展示消息。role: user | assistant | thought | tool | system。
class ChatMessage {
  final String id;
  final String role;
  final String content;
  final MessageStatus status;
  final DateTime createdAt;

  /// 结构化内容块（图片/文件/资源等），text 块内容与 content 同步。
  final List<ContentBlock> blocks;

  /// 关联的工具调用 id（tool 角色或 assistant 消息内的工具）。
  final List<String> toolCallIds;

  /// notice/system 事件的级别（info/warning/error）。
  final String? level;

  /// 失败原因。
  final String? error;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.status = MessageStatus.pending,
    DateTime? createdAt,
    List<ContentBlock>? blocks,
    List<String>? toolCallIds,
    this.level,
    this.error,
  })  : createdAt = createdAt ?? DateTime.now(),
        blocks = blocks ?? const [],
        toolCallIds = toolCallIds ?? const [];

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    List<ContentBlock>? blocks,
    List<String>? toolCallIds,
    String? level,
    String? error,
    bool clearError = false,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        status: status ?? this.status,
        createdAt: createdAt,
        blocks: blocks ?? this.blocks,
        toolCallIds: toolCallIds ?? this.toolCallIds,
        level: level ?? this.level,
        error: clearError ? null : (error ?? this.error),
      );
}
