import 'package:flutter/material.dart';
/// Elicitation 动态表单：✅纯 Flutter（按 JSON Schema 画字段）。骨架占位。
class ElicitationForm extends StatelessWidget {
  final String message;
  const ElicitationForm(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(10), child: Text('表单: $message')),
  );
}
