import 'package:flutter/material.dart';
/// mermaid / drawio / artifact / 文档预览：🔴需 WebView。骨架占位。
/// 设计文档 6.1。
class WebViewRenderer extends StatelessWidget {
  final String url;
  const WebViewRenderer(this.url, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    child: Text('[WebView 渲染占位] $url'),
  );
}
