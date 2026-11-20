import 'package:flutter/material.dart';
/// 文件 diff：✅纯 Flutter（diff 算法 + 双栏）。骨架占位。
class DiffView extends StatelessWidget {
  final String oldText;
  final String newText;
  const DiffView({super.key, required this.oldText, required this.newText});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    color: Theme.of(context).colorScheme.surfaceVariant,
    child: Text('- $oldText\n+ $newText', style: const TextStyle(fontFamily: 'monospace')),
  );
}
