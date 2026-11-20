import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/session_update.dart';
import 'markdown_view.dart';
import 'blocks/image_attachment.dart';
import 'blocks/error_message.dart';
import 'blocks/special_tool_view.dart';
import 'interactive/interactive_card.dart';

/// 消息类型 → widget 分发器。
/// 未知类型走兜底展示原始数据，绝不崩溃（用户要求）。
class RenderDispatcher extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<InteractiveResponse>? onInteractiveRespond;
  final VoidCallback? onRetry;
  const RenderDispatcher(
    this.message, {
    super.key,
    this.onInteractiveRespond,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return _build(context);
    } catch (e) {
      // 兜底：任何渲染异常都不让整条消息崩溃。
      return RawFallback(text: message.content, error: e.toString());
    }
  }

  Widget _build(BuildContext context) {
    // 失败态优先：统一错误样式 + 重试入口。
    if (message.status == MessageStatus.failed) {
      return ErrorMessage(
        content: message.content,
        error: message.error ?? '生成失败',
        onRetry: onRetry,
      );
    }

    switch (message.role) {
      case 'user':
        return _bubble(context, message.content, isUser: true);
      case 'thought':
        return _thought(context, message.content, message.status);
      case 'tool':
        return _tool(context, message.content);
      case 'system':
        return _system(context, message);
      case 'assistant':
      default:
        return _bubble(context, message.content, isUser: false, status: message.status);
    }
  }

  Widget _bubble(BuildContext context, String text,
      {required bool isUser, MessageStatus status = MessageStatus.complete}) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (message.blocks.isNotEmpty) ...[
              for (final b in message.blocks)
                if (b.type.name == 'image')
                  ImageAttachment(data: b.data, uri: b.uri, mimeType: b.mimeType)
                else if (b.type.name == 'resourceLink')
                  ImageAttachment(uri: b.uri, name: b.name, mimeType: b.mimeType),
            ],
            if (text.isNotEmpty)
              isUser ? Text(text) : MarkdownView(text),
            if (!isUser && status == MessageStatus.streaming)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _thought(BuildContext context, String text, MessageStatus status) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: ExpansionTile(
        // thinking 折叠面板，默认收起（用户要求）。
        initiallyExpanded: false,
        leading: const Icon(Icons.psychology, size: 18),
        title: const Text('思考过程', style: TextStyle(fontSize: 12)),
        trailing: status == MessageStatus.streaming
            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        children: [Padding(padding: const EdgeInsets.all(8), child: MarkdownView(text))],
      ),
    );
  }

  Widget _tool(BuildContext context, String content) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return RawFallback(text: content);
    }
    // 交互式工具（askuserquestion / elicitation / permission）→ 专门控件。
    final name = (data['name'] ?? '').toString().toLowerCase();
    if (name.contains('askuserquestion')) {
      final questions = data['rawInput']?['questions'];
      final choices = questions is List
          ? questions.expand((q) => (q is Map ? (q['options'] ?? []) : [])).toList()
          : <dynamic>[];
      return InteractiveCard(
        method: 'askuserquestion',
        message: data['title']?.toString() ?? '请选择：',
        mode: 'choice',
        choices: choices.map((o) => (o is Map ? (o['label'] ?? o['name']) : o).toString()).toList(),
        multiSelect: false,
        onRespond: onInteractiveRespond ?? (_) {},
      );
    }
    return SpecialToolView(data);
  }

  Widget _system(BuildContext context, ChatMessage m) {
    final isError = m.level == 'error';
    final color = isError ? Theme.of(context).colorScheme.error : Theme.of(context).hintColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.info_outline, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(m.content, style: TextStyle(fontSize: 12, color: color))),
      ]),
    );
  }
}

/// 未知类型兜底：展示原始 JSON，不崩溃。
class RawFallback extends StatelessWidget {
  final String text;
  final String? error;
  const RawFallback({super.key, required this.text, this.error});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.amber.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.amber.withOpacity(0.4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('[未识别的消息类型 · 原始数据]',
          style: TextStyle(fontSize: 11, color: Colors.amber)),
      if (error != null)
        Text('渲染异常: $error', style: const TextStyle(fontSize: 10, color: Colors.red)),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
    ]),
  );
}

/// session update 类型到是否需要独立组件的判断（供扩展/文档）。
bool requiresIndependentWidget(SessionUpdateKind kind) {
  switch (kind) {
    case SessionUpdateKind.toolCall:
    case SessionUpdateKind.toolCallUpdate:
    case SessionUpdateKind.plan:
    case SessionUpdateKind.planUpdate:
    case SessionUpdateKind.notice:
    case SessionUpdateKind.subagentUpdate:
    case SessionUpdateKind.usageUpdate:
      return true;
    default:
      return false;
  }
}
