import 'package:flutter/material.dart';
/// Plan 步骤：✅纯 Flutter。骨架占位。
class PlanView extends StatelessWidget {
  final List<String> entries;
  const PlanView(this.entries, {super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: Column(children: [for (final e in entries) ListTile(title: Text(e))]),
  );
}
