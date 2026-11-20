import 'dart:convert';
import 'package:flutter/material.dart';

import '../../render/tool_cards/webview_renderer.dart';

/// 按工具名/kind 选择专门渲染组件。
/// 结论标注：✅纯Flutter / 🟡自研中等 / 🔴WebView 或深度自研（报告03 §三、报告04）。
class SpecialToolView extends StatelessWidget {
  final Map<String, dynamic> data;
  const SpecialToolView(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? data['title'] ?? '').toString().toLowerCase();
    final kind = (data['kind'] ?? '').toString().toLowerCase();
    final status = (data['status'] ?? 'pending').toString();

    // 有 diff 内容块 → diff 视图（Write/Edit/NotebookEdit）
    final content = data['content'];
    if (content is List) {
      for (final c in content) {
        if (c is Map && c['type'] == 'diff') {
          return _DiffView(
            path: c['path']?.toString() ?? '',
            oldText: c['oldText']?.toString() ?? '',
            newText: c['newText']?.toString() ?? '',
          );
        }
      }
    }

    if (name.contains('bash') || name.contains('powershell') ||
        name.contains('shell') || kind == 'execute') {
      return _TerminalView(output: _extractText(data['rawOutput']));
    }
    if (name.contains('imagegen') || name.contains('viewimage') ||
        name.contains('imageedit') || kind == 'read' && _looksLikeImage(data)) {
      return _ImageView(data: data);
    }
    if (name.contains('plantask') || name.contains('enterplan') || kind == 'plan') {
      return _PlanView(data: data);
    }
    if (name.contains('artifact') || name.contains('drawio') ||
        name.contains('excalidraw') || name.contains('doc')) {
      final uri = _extractUri();
      return WebViewRenderer(uri.isEmpty ? '[artifact/document]' : uri);
    }
    // 其余（Read/Grep/Glob/WebFetch/WebSearch/...）→ 通用折叠卡片
    return _GenericTool(data: data, status: status);
  }

  bool _looksLikeImage(Map<String, dynamic> d) {
    final out = jsonEncode(d['rawOutput'] ?? '').toLowerCase();
    return out.contains('mime') && (out.contains('image') || out.contains('png') || out.contains('jpeg'));
  }

  String _extractText(dynamic out) {
    if (out == null) return '';
    if (out is String) return out;
    if (out is Map) {
      for (final k in ['stdout', 'output', 'text', 'content', 'result']) {
        if (out[k] != null) return out[k].toString();
      }
    }
    try { return jsonEncode(out); } catch (_) { return out.toString(); }
  }

  String _extractUri() {
    final raw = jsonEncode(data);
    final m = RegExp(r'https?://[^"\s]+').firstMatch(raw);
    return m?.group(0) ?? '';
  }
}

class _GenericTool extends StatelessWidget {
  final Map<String, dynamic> data;
  final String status;
  const _GenericTool({required this.data, required this.status});

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text((data['name'] ?? data['title'] ?? '工具').toString(),
          style: const TextStyle(fontSize: 13)),
      subtitle: Text('${data['kind'] ?? 'tool'} · $status', style: const TextStyle(fontSize: 11)),
      children: [Padding(
        padding: const EdgeInsets.all(8),
        child: Text(jsonEncode(data), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      )],
    ),
  );
}

class _DiffView extends StatelessWidget {
  final String path, oldText, newText;
  const _DiffView({required this.path, required this.oldText, required this.newText});
  @override
  Widget build(BuildContext context) => Card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.all(8),
        child: Text(path, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold))),
      Container(color: const Color(0xFF300000),
        padding: const EdgeInsets.all(8),
        child: Text(oldText.isEmpty ? '(无原文)' : '- $oldText',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFFF8888)))),
      Container(color: const Color(0xFF003000),
        padding: const EdgeInsets.all(8),
        child: Text('+ $newText',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF88FF88)))),
    ]),
  );
}

class _TerminalView extends StatelessWidget {
  final String output;
  const _TerminalView({required this.output});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    color: Colors.black87,
    padding: const EdgeInsets.all(10),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent)),
    ),
  );
}

class _ImageView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ImageView({required this.data});
  @override
  Widget build(BuildContext context) {
    // 尽力从 rawOutput 提取 url/base64；无则不崩溃，展示占位。
    final raw = jsonEncode(data['rawOutput'] ?? data);
    final urlMatch = RegExp(r'https?://[^"\s]+').firstMatch(raw);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          if (urlMatch != null)
            Image.network(urlMatch.group(0)!, errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image), height: 160)
          else
            const Icon(Icons.image, size: 48, color: Colors.grey),
          const SizedBox(height: 4),
          const Text('[图片附件]', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PlanView({required this.data});
  @override
  Widget build(BuildContext context) {
    final plan = data['plan'];
    final entries = (plan is Map ? plan['entries'] : null) is List
        ? (plan['entries'] as List).whereType<Map>().toList()
        : <Map>[];
    return Card(child: Column(children: [
      const Padding(padding: EdgeInsets.all(8),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('执行计划', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
      for (final e in entries)
        ListTile(
          leading: Icon(e['status'] == 'completed' ? Icons.check_box
              : e['status'] == 'in_progress' ? Icons.indeterminate_check_box
              : Icons.check_box_outline_blank, size: 18),
          title: Text(e['content']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
        ),
    ]));
  }
}
