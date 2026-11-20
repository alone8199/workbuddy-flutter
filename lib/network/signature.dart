import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// 签名与 nonce 工具：全部为独立可单测的纯函数（随机数生成器可注入）。
///
/// 依据分析报告 01_接口清单.md 第 6 节结论：
///  - 登录/业务 HTTP 无独立签名，靠 TLS + Bearer/state_token/cookie；
///  - 静态可还原的算法只有：PKCE code_challenge、请求 ID、MCP 信封 HMAC-SHA256、nonce proof；
///  - 报告未给出「样例输入输出对」，故单测采用 RFC 7636 / RFC 4231 标准测试向量对拍，
///    不编造报告里不存在的样例；
///  - MCP 信封 secret / device-token 来源静态未确认（TODO dynamic-capture），
///    这里只提供算法骨架，secret 由调用方显式传入，函数本身不猜测任何密钥。
class SignatureUtil {
  static const String _pkceChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// PKCE code_verifier：RFC 7636 规定 43-128 个 unreserved 字符。
  static String generateCodeVerifier({int length = 64, Random? random}) {
    if (length < 43 || length > 128) {
      throw ArgumentError.value(length, 'length', 'RFC7636 requires 43..128');
    }
    final rnd = random ?? Random.secure();
    return List.generate(
      length,
      (_) => _pkceChars[rnd.nextInt(_pkceChars.length)],
    ).join();
  }

  /// code_challenge = BASE64URL(SHA256(verifier))，去掉 '=' padding（S256）。
  /// RFC 7636 Appendix B 测试向量可用于对拍。
  static String codeChallenge(String verifier) {
    final digest = crypto.sha256.convert(utf8.encode(verifier)).bytes;
    return base64Url.encode(Uint8List.fromList(digest)).replaceAll('=', '');
  }

  /// 请求 ID：16 字节随机 hex，等价 Node `randomBytes(16).toString('hex')`（32 位）。
  static String requestId({Random? random}) {
    final rnd = random ?? Random.secure();
    return List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 随机 base64url nonce（去 padding）。用于 clientNonce / ww_device_nonce / state。
  static String generateNonce({int byteLength = 16, Random? random}) {
    final rnd = random ?? Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(byteLength, (_) => rnd.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 4 字节大端长度前缀 + UTF8 内容（nonce proof 的 lengthPrefixed 编码）。
  static Uint8List lengthPrefixed(String value) {
    final body = utf8.encode(value);
    final out = BytesBuilder(copy: false)
      ..add(<int>[
        (body.length >> 24) & 0xff,
        (body.length >> 16) & 0xff,
        (body.length >> 8) & 0xff,
        body.length & 0xff,
      ])
      ..add(body);
    return out.takeBytes();
  }

  /// nonce proof = HMAC-SHA256(secret, LP(clientNonce) + LP(serverNonce)) 的 base64url。
  /// secret 来源静态未确认，由调用方传入。
  static String nonceProof({
    required String secret,
    required String clientNonce,
    required String serverNonce,
  }) {
    final transcript = Uint8List.fromList(<int>[
      ...lengthPrefixed(clientNonce),
      ...lengthPrefixed(serverNonce),
    ]);
    final mac = crypto.Hmac(
      crypto.sha256,
      utf8.encode(secret),
    ).convert(transcript).bytes;
    return base64Url.encode(Uint8List.fromList(mac)).replaceAll('=', '');
  }

  /// MCP 信封签名 = HMAC-SHA256(secret, envelope) 原始字节。
  static Uint8List envelopeSignature({
    required String secret,
    required String envelope,
  }) {
    final mac = crypto.Hmac(
      crypto.sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(envelope));
    return Uint8List.fromList(mac.bytes);
  }

  /// 规范参数排序：按 key 字母序输出 query（仅「签名类请求」使用）。
  /// 注：原客户端 axios 默认按对象插入序序列化，未见全局字母序排序。
  static String canonicalQuery(Map<String, String> params) {
    final sorted = SplayTreeMap<String, String>.from(params);
    final sb = StringBuffer();
    sorted.forEach((key, value) {
      if (sb.isNotEmpty) sb.write('&');
      sb.write('${Uri.encodeComponent(key)}=${Uri.encodeComponent(value)}');
    });
    return sb.toString();
  }

  /// JWT 时间戳（秒）：Math.floor(Date.now()/1000)。
  static int timestampSeconds([DateTime? now]) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

  /// 会话缓存时间戳（毫秒）：Date.now() + maxAge 的基准。
  static int timestampMillis([DateTime? now]) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch;
}
