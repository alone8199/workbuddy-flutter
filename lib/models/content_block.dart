/// ACP 内容块（5 种基础类型）。
/// 数据源：acp-DdDO41dd.js content union。
/// 注意：markdown / 代码块 / thinking 不是独立 type，由 text 块 + 渲染器实现。
enum ContentBlockType { text, image, audio, resourceLink, resource }

ContentBlockType _parseType(String t) {
  switch (t) {
    case 'image':
      return ContentBlockType.image;
    case 'audio':
      return ContentBlockType.audio;
    case 'resource_link':
      return ContentBlockType.resourceLink;
    case 'resource':
      return ContentBlockType.resource;
    default:
      return ContentBlockType.text;
  }
}

String _typeName(ContentBlockType t) {
  switch (t) {
    case ContentBlockType.image:
      return 'image';
    case ContentBlockType.audio:
      return 'audio';
    case ContentBlockType.resourceLink:
      return 'resource_link';
    case ContentBlockType.resource:
      return 'resource';
    default:
      return 'text';
  }
}

class ContentBlock {
  final ContentBlockType type;
  final String? text;
  final String? data; // base64 (image/audio)
  final String? mimeType;
  final String? uri;
  final String? name;

  const ContentBlock._({
    required this.type,
    this.text,
    this.data,
    this.mimeType,
    this.uri,
    this.name,
  });

  factory ContentBlock.text(String text) =>
      ContentBlock._(type: ContentBlockType.text, text: text);

  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    return ContentBlock._(
      type: _parseType(json['type'] as String? ?? 'text'),
      text: json['text'] as String?,
      data: json['data'] as String?,
      mimeType: json['mimeType'] as String?,
      uri: json['uri'] as String?,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': _typeName(type),
        if (text != null) 'text': text,
        if (data != null) 'data': data,
        if (mimeType != null) 'mimeType': mimeType,
        if (uri != null) 'uri': uri,
        if (name != null) 'name': name,
      };
}
