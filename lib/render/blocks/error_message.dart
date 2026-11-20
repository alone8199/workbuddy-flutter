import 'package:flutter/material.dart';

/// 错误消息：错误样式 + 明确重试入口。
class ErrorMessage extends StatelessWidget {
  final String content;
  final String error;
  final VoidCallback? onRetry;
  const ErrorMessage({
    super.key,
    required this.content,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.error.withOpacity(0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.error_outline, size: 16, color: cs.error),
              const SizedBox(width: 6),
              Text('生成失败', style: TextStyle(color: cs.error, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            const SizedBox(height: 6),
            if (content.isNotEmpty) Text(content, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text(error, style: TextStyle(fontSize: 11, color: cs.error)),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('重试'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
