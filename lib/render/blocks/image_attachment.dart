import 'dart:convert';
import 'package:flutter/material.dart';

/// 图片与文件附件渲染：缩略图 + 点击查看 + 下载入口。
/// image 块（base64/uri）与 resource_link 块共用。
class ImageAttachment extends StatelessWidget {
  final String? data; // base64
  final String? uri;
  final String? name;
  final String? mimeType;
  const ImageAttachment({super.key, this.data, this.uri, this.name, this.mimeType});

  @override
  Widget build(BuildContext context) {
    final isImage = mimeType?.startsWith('image') ?? false;
    final isFile = uri != null && (name != null || !isImage);
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Column(children: [
          if (data != null && data!.isNotEmpty)
            _imageFromBase64(data!)
          else if (uri != null && isImage)
            Image.network(uri!, height: 140, errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 40))
          else
            const Icon(Icons.insert_drive_file, size: 40, color: Colors.grey),
          if (isFile || name != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(name ?? uri ?? '附件', style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
    );
  }

  Widget _imageFromBase64(String b64) {
    try {
      final bytes = base64Decode(b64.contains(',') ? b64.split(',').last : b64);
      return Image.memory(bytes, height: 140, errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image, size: 40));
    } catch (_) {
      return const Icon(Icons.broken_image, size: 40);
    }
  }

  void _open(BuildContext context) {
    // 点击查看/下载：真实感受限于 Flutter 桌面需平台插件；此处给出明确提示入口。
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('预览/下载附件: ${name ?? uri ?? '图片'}（平台文件能力待接入）')),
    );
  }
}
