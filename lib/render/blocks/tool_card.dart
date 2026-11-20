import 'dart:convert';
import 'package:flutter/material.dart';

/// 通用工具调用折叠卡片：工具名 + 参数 + 状态 + 结果。
/// 特殊工具（terminal/diff/image/plan/permission/elicitation/webview）由
/// RenderDispatcher 路由到专门组件（见 tool_cards/）。
class ToolCard extends StatefulWidget {
  final String toolCallId;
  final String? name;
  final String? title;
  final String? kind;
  final String status;
  final Map<String, dynamic>? rawInput;
  final dynamic rawOutput;
  const ToolCard({
    super.key,
    required this.toolCallId,
    this.name,
    this.title,
    this.kind,
    required this.status,
    this.rawInput,
    this.rawOutput,
  });

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(widget.status);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(_statusIcon(widget.status), size: 18, color: color),
        title: Text(
          widget.title ?? widget.name ?? widget.kind ?? '工具调用',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Text('${widget.kind ?? 'tool'} · ${widget.status}',
            style: const TextStyle(fontSize: 11)),
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('参数', style: TextStyle(fontSize: 11, color: Colors.grey)),
                _json(widget.rawInput),
                const SizedBox(height: 6),
                const Text('结果', style: TextStyle(fontSize: 11, color: Colors.grey)),
                _json(widget.rawOutput),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _json(dynamic v) {
    if (v == null) return const Text('—', style: TextStyle(fontSize: 12, color: Colors.grey));
    String text;
    try {
      text = jsonEncode(v);
    } catch (_) {
      text = v.toString();
    }
    return Container(
      padding: const EdgeInsets.all(6),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'completed': return Colors.green;
      case 'failed': return Colors.red;
      case 'in_progress': return Colors.blue;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'completed': return Icons.check_circle;
      case 'failed': return Icons.error;
      case 'in_progress': return Icons.hourglass_top;
      default: return Icons.radio_button_unchecked;
    }
  }
}
