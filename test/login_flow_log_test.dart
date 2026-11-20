import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/auth/auth_repository.dart';
import 'package:workbuddy/auth/login_controller.dart';
import 'package:workbuddy/auth/login_events.dart';
import 'package:workbuddy/auth/login_methods/device_code_login.dart';
import 'package:workbuddy/auth/login_methods/passwordless_login.dart';
import 'package:workbuddy/auth/login_methods/webview_oauth_login.dart';
import 'package:workbuddy/auth/post_login_checker.dart';
import 'package:workbuddy/models/auth.dart';
import 'package:workbuddy/models/phone_binding.dart';
import 'package:workbuddy/network/client.dart';

/// 测试用放行校验器：让扫码流程能走到 EffectNavigateHome。
class _AllowChecker extends PostLoginChecker {
  @override
  Future<PostLoginOutcome> check(AuthTokens tokens) async =>
      PostLoginAllowed(tokens, const PhoneBinding(PhoneBindingStatus.bound));
}

/// mock 驱动：为每种登录方式跑一遍完整状态机流程，打印状态迁移与副作用日志。
/// 用 fake Dio adapter 按端点返回构造响应，不打真实服务端、不登录、无凭据。
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(String path) responder;
  _FakeAdapter(this.responder);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List?>? requestStream,
      Future<void>? cancelFuture) async {
    final payload = responder(options.path);
    final status = (payload['__status'] as int?) ?? 200;
    final body = Map<String, dynamic>.from(payload)..remove('__status');
    return ResponseBody.fromString(
      _encode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  String _encode(Map<String, dynamic> m) =>
      '{${m.entries.map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}').join(',')}}';

  @override
  void close({bool force = false}) {}
}

String _phase(LoginController c) => c.state.phase.name;

void _watch(String title, LoginController c, List<String> log) {
  c.addListener(() {
    final line = '    [state] phase=${_phase(c)} msg=${c.state.message ?? '-'} '
        'qr=${c.state.qrContent != null ? 'yes' : 'no'} '
        'countdown=${c.state.countdown} poll=${c.state.pollAttempt}';
    log.add(line);
  });
  log.add('--- $title ---');
}

void main() {
  late AuthRepository repo;

  setUp(() {
    final dio = Dio();
    final net = NetworkClient(
      appVersion: '5.11.3',
      language: 'zh-CN,zh;q=0.9',
      tokenProvider: () async => null,
      forceRefreshProvider: () async => null,
      onAuthExpired: () async {},
      dioInstance: dio,
    );
    dio.httpClientAdapter = _FakeAdapter((path) {
      if (path.contains('device/auth/code')) {
        return <String, dynamic>{'deviceCode': 'DC-123', 'expiresIn': 300};
      }
      if (path.contains('person/code:send') || path.contains('email/code/send')) {
        return <String, dynamic>{'sent': true, 'interval': 60};
      }
      // 所有换取凭证/轮询端点统一返回 token，确保 mock 流程走到终态
      return <String, dynamic>{
        'access_token': 'AT', 'refresh_token': 'RT', 'expires_in': 3600,
      };
    });
    repo = AuthRepository(net);
  });

  final log = <String>[];

  test('登录流程日志（9 种方式 mock 全流程）', () async {
    log.add('================================================================');
    log.add('登录模块 · 各方式完整流程日志（mock 驱动，非真实登录）');
    log.add('时间: ${DateTime.now().toUtc().toIso8601String()}');
    log.add('================================================================');

    // 方式 1 手机号
    final phone = PasswordlessLoginController(target: LoginMethod.phone, repo: repo);
    _watch('方式1 手机号验证码登录', phone, log);
    phone.dispatch(LoginStart(LoginMethod.phone));
    phone.dispatch(LoginSendCode('13800138000'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    phone.dispatch(LoginSubmitCode('123456'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    log.add('    结果: phase=${_phase(phone)} （成功换 token → EffectNavigateHome）');
    phone.dispose();

    // 方式 2 邮箱
    final email = PasswordlessLoginController(target: LoginMethod.email, repo: repo);
    _watch('方式2 邮箱验证码登录', email, log);
    email.dispatch(LoginStart(LoginMethod.email));
    email.dispatch(LoginSendCode('test@example.com'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    email.dispatch(LoginSubmitCode('654321'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    log.add('    结果: phase=${_phase(email)}');
    email.dispose();

    // 方式 9 扫码确认
    final qr = DeviceCodeLoginController(repo: repo, postLoginChecker: _AllowChecker());
    _watch('方式9 扫码确认登录(device code + 轮询)', qr, log);
    qr.dispatch(LoginStart(LoginMethod.deviceCode));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    log.add('    二维码内容: ${qr.state.qrContent}');
    qr.dispatch(LoginPollingTick());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    log.add('    结果: phase=${_phase(qr)}');
    qr.dispose();

    // 方式 3-8 WebView 登录
    for (final m in [
      LoginMethod.wechat,
      LoginMethod.qq,
      LoginMethod.wecom,
      LoginMethod.ioa,
      LoginMethod.sso,
      LoginMethod.asus,
    ]) {
      final c = WebViewOAuthLoginController(target: m, repo: repo);
      _watch('方式 ${m.wireName} (WebView OAuth)', c, log);
      c.dispatch(LoginStart(m));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final effects = c.consumeEffects();
      for (final e in effects) {
        if (e is EffectOpenWebView) {
          log.add('    [effect] 打开授权页: ${e.url}');
          log.add('    [effect] 回调路由: ${e.callbackPaths.join(', ')}');
        } else if (e is EffectShowMessage) {
          log.add('    [effect] 提示: ${e.message}');
        }
      }
      log.add('    结果: phase=${_phase(c)}');
      c.dispose();
    }

    // 异常路径：验证码错误
    final bad = PasswordlessLoginController(target: LoginMethod.phone, repo: repo);
    _watch('异常路径 验证码错误', bad, log);
    bad.dispatch(LoginStart(LoginMethod.phone));
    bad.dispatch(LoginSubmitCode('000000'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    log.add('    结果: phase=${_phase(bad)}');
    bad.dispose();

    log.add('================================================================');
    log.add('说明: 以上为状态机 + 副作用日志，接口响应为 mock 构造；');
    log.add('      真实登录需测试账号 + 动态抓包参数（见卡点清单）。');
    log.add('================================================================');

    // 输出日志供命令行抓取
    // ignore: avoid_print
    for (final line in log) {
      // ignore: avoid_print
      print(line);
    }
  });
}
