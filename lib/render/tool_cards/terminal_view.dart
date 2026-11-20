import 'package:flutter/material.dart';
/// 终端输出：🔴需 WebView（xterm.js）或自研 PTY 桥。骨架占位。
class TerminalView extends StatelessWidget {
  final String output;
  const TerminalView(this.output, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black, padding: const EdgeInsets.all(8),
    child: Text(output, style: const TextStyle(fontFamily: 'monospace', color: Colors.green)),
  );
}
