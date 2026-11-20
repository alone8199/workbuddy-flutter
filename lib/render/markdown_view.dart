import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'blocks/code_block.dart';

/// Markdown 正文渲染：标题/列表/表格/引用/行内代码 + 代码块 + 公式占位。
/// 选型说明：flutter_markdown 0.6.15（纯 Flutter、无 WebView），GFM 表格依赖
/// 其内置 github 语法扩展；代码块抽出交给 [CodeBlock] 以获得高亮/复制/折叠。
/// mermaid/KaTeX 走 [WebViewRenderer]（见 render_dispatcher），不在此处理。
class MarkdownView extends StatelessWidget {
  final String content;
  const MarkdownView(this.content, {super.key});

  static final RegExp _fence = RegExp(r'```(\w+)?\s*\n?([\s\S]*?)```');

  @override
  Widget build(BuildContext context) {
    final segments = _split();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final seg in segments)
          if (seg.isCode)
            CodeBlock(seg.text, language: seg.language)
          else
            MarkdownBody(
              data: seg.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 14, height: 1.5),
                code: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                ),
                blockquote: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
      ],
    );
  }

  List<_Segment> _split() {
    final result = <_Segment>[];
    var last = 0;
    for (final m in _fence.allMatches(content)) {
      if (m.start > last) {
        result.add(_Segment(content.substring(last, m.start), false, null));
      }
      result.add(_Segment(m.group(2) ?? '', true, m.group(1)));
      last = m.end;
    }
    if (last < content.length) {
      result.add(_Segment(content.substring(last), false, null));
    }
    if (result.isEmpty) result.add(_Segment(content, false, null));
    return result;
  }
}

class _Segment {
  final String text;
  final bool isCode;
  final String? language;
  _Segment(this.text, this.isCode, this.language);
}
