import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/network/signature.dart';

/// 字节数组转小写 hex（避免引入额外依赖）。
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PKCE code_challenge (RFC 7636 Appendix B 标准向量)', () {
    // RFC 7636 B: verifier -> challenge 官方样例
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    const expected = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
    test('对拍官方样例', () {
      expect(SignatureUtil.codeChallenge(verifier), expected);
    });
    test('独立 SHA256 复算校验', () {
      final digest = sha256.convert(utf8.encode(verifier)).bytes;
      final expect2 = base64Url.encode(Uint8List.fromList(digest)).replaceAll('=', '');
      expect(SignatureUtil.codeChallenge(verifier), expect2);
    });
    test('code_verifier 长度约束 43-128', () {
      expect(() => SignatureUtil.generateCodeVerifier(length: 42), throwsArgumentError);
      expect(() => SignatureUtil.generateCodeVerifier(length: 129), throwsArgumentError);
      final v = SignatureUtil.generateCodeVerifier(
        length: 43,
        random: Random(1),
      );
      expect(v.length, 43);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
    });
  });

  group('HMAC-SHA256 (RFC 4231 标准向量)', () {
    // RFC 4231 Test Case 1: key=0x0b*20, data="Hi There"
    test('envelopeSignature 对拍 RFC 4231 case 1', () {
      final key = String.fromCharCodes(List<int>.filled(20, 0x0b));
      final sig = SignatureUtil.envelopeSignature(secret: key, envelope: 'Hi There');
      expect(_hex(sig),
          'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
    });
  });

  group('requestId / nonce', () {
    test('requestId 为 32 位小写 hex', () {
      final id = SignatureUtil.requestId(random: Random(42));
      expect(id.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    });
    test('nonce 为 base64url 且无 padding', () {
      final n = SignatureUtil.generateNonce(random: Random(7));
      expect(n.contains('='), isFalse);
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(n), isTrue);
    });
    test('lengthPrefixed 4 字节大端长度前缀', () {
      final lp = SignatureUtil.lengthPrefixed('abc');
      expect(lp.sublist(0, 4), Uint8List.fromList([0, 0, 0, 3]));
      expect(utf8.decode(lp.sublist(4)), 'abc');
    });
  });

  group('时间戳与参数排序', () {
    test('秒/毫秒单位正确', () {
      final t = DateTime.utc(2020, 1, 2, 3, 4, 5, 678);
      expect(SignatureUtil.timestampSeconds(t), t.millisecondsSinceEpoch ~/ 1000);
      expect(SignatureUtil.timestampMillis(t), t.millisecondsSinceEpoch);
    });
    test('canonicalQuery 按 key 字母序', () {
      final q = SignatureUtil.canonicalQuery(<String, String>{
        'z': '1',
        'a': '2',
        'm': 'hello world',
      });
      expect(q, 'a=2&m=hello%20world&z=1');
    });
  });
}
