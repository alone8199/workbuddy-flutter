import 'package:flutter/material.dart';
/// 图片预览：✅纯 Flutter。骨架占位。
class ImageView extends StatelessWidget {
  final String url;
  const ImageView(this.url, {super.key});
  @override
  Widget build(BuildContext context) => const Icon(Icons.image);
}
