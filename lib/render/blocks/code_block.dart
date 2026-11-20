import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 代码块：语言标注 + 语法高亮（轻量自研）+ 复制按钮 + 横向滚动 + 长代码折叠。
/// 选型说明见交付文档：因 Flutter 3.7/Dart2.19 依赖锁定，未引入 highlighter 包，
/// 用正则关键字着色覆盖主流语言；视觉样式对齐放下一轮。
class CodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  const CodeBlock(this.code, {this.language, super.key});

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _expanded = false;
  static const int _foldLines = 20;

  static const Set<String> _keywords = {
    'class','def','return','if','else','for','while','import','from','const','final','var',
    'function','let','await','async','new','public','private','void','int','String','bool',
    'try','catch','throw','switch','case','break','continue','this','super','extends','in',
    'export','default','interface','type','enum','struct','fn','impl','use','match','null',
  };

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.split('\n');
    final needFold = lines.length > _foldLines;
    final shown = (!_expanded && needFold) ? lines.sublist(0, _foldLines).join('\n') : widget.code;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.language != null && widget.language!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 6),
                  child: Text(widget.language!,
                      style: const TextStyle(color: Color(0xFF9CDCFE), fontSize: 11)),
                ),
              const Spacer(),
              IconButton(
                tooltip: '复制',
                icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text.rich(
                TextSpan(children: _highlight(shown, theme)),
                style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: Color(0xFFD4D4D4), height: 1.4),
              ),
            ),
          ),
          if (needFold)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起代码' : '展开全部 ${lines.length} 行',
                  style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _highlight(String code, ThemeData theme) {
    final spans = <InlineSpan>[];
    // 拆成两段原始字符串拼接，避开 Dart 原始字符串不支持单引号内转义的限制。
    final regex = RegExp("(\"[^\"]*\"|'[^']*'|//[^\\n]*|\\b\\w+\\b)");
    for (final m in regex.allMatches(code)) {
      final token = m.group(0) ?? '';
      Color? color;
      if (token.startsWith('"') || token.startsWith("'")) {
        color = const Color(0xFFCE9178); // 字符串
      } else if (token.startsWith('//')) {
        color = const Color(0xFF6A9955); // 注释
      } else if (_keywords.contains(token)) {
        color = const Color(0xFF569CD6); // 关键字
      }
      spans.add(TextSpan(text: token, style: TextStyle(color: color)));
    }
    return spans;
  }
}
