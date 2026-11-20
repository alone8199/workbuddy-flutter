import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/auth/auth_repository.dart';
import 'package:workbuddy/auth/login_events.dart';
import 'package:workbuddy/auth/login_methods/device_code_login.dart';
import 'package:workbuddy/auth/login_state_machine.dart';
import 'package:workbuddy/auth/post_login_checker.dart';
import 'package:workbuddy/models/auth.dart';
import 'package:workbuddy/models/phone_binding.dart';
import 'package:workbuddy/network/client.dart';

/// 把 const 构造换成普通构造（AuthTokens 非 const）。
AuthTokens _tokens() => AuthTokens(accessToken: 'AT-1');

/// 按路径分发的 fake adapter：
/// - auth/state → 返回 state + authUrl
/// - auth/token → 成功返回 token
/// - console/accounts → 账号资料（绑定状态，按 _profileBody 变化）
class _Adapter implements HttpClientAdapter {
  final String profileBody;
  _Adapter(this.profileBody);

  String _body(String path) {
    if (path.contains('auth/state')) {
      return '{"code":0,"data":{"state":"ST-1","authUrl":"https://www.workbuddy.cn/login?state=ST-1"}}';
    }
    if (path.contains('auth/token')) {
      return '{"access_token":"AT-1","refresh_token":"RT-1","expires_in":3600}';
    }
    if (path.contains('console/accounts')) return profileBody;
    return '{"code":0,"data":{}}';
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(_body(options.path), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        });
  }

  @override
  void close({bool force = false}) {}
}

NetworkClient _net(String profileBody) {
  final dio = Dio();
  dio.httpClientAdapter = _Adapter(profileBody);
  return NetworkClient(
    appVersion: '5.11.3',
    language: 'zh-CN,zh;q=0.9',
    tokenProvider: () async => null,
    forceRefreshProvider: () async => null,
    onAuthExpired: () async {},
    dioInstance: dio,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsePhoneBinding 纯函数解析', () {
    test('未绑定业务码 → unbound', () {
      final b = parsePhoneBinding({'code': 'phone_not_bound', 'msg': 'please bind phone'});
      expect(b.status, PhoneBindingStatus.unbound);
    });

    test('中文未绑定文案 → unbound', () {
      final b = parsePhoneBinding({'msg': '该账号未绑定手机号'});
      expect(b.status, PhoneBindingStatus.unbound);
    });

    test('hasPhone=false → unbound', () {
      final b = parsePhoneBinding({'data': {'hasPhone': false}});
      expect(b.status, PhoneBindingStatus.unbound);
    });

    test('手机号非空（脱敏）→ bound', () {
      final b = parsePhoneBinding({'data': {'phone': '13800138000'}});
      expect(b.status, PhoneBindingStatus.bound);
      expect(b.phone, '138****8000');
    });

    test('data 层 code+data 解包 → unbound', () {
      final b = parsePhoneBinding({'code': 0, 'data': {'phoneBind': false}});
      expect(b.status, PhoneBindingStatus.unbound);
    });

    test('无有效字段 → unknown', () {
      final b = parsePhoneBinding({'code': 0, 'data': {'nickname': 'x'}});
      expect(b.status, PhoneBindingStatus.unknown);
    });
  });

  group('PostLoginChecker 策略', () {
    test('明确未绑定 → blocked，携带绑定 URL', () async {
      final repo = AuthRepository(_net('{"code":"phone_not_bound"}'));
      final checker = PhoneBindingChecker(repo: repo, blockOnUnknown: false);
      final outcome = await checker.check(
        _tokens(),
      );
      expect(outcome, isA<PostLoginBlocked>());
      final blocked = outcome as PostLoginBlocked;
      expect(blocked.binding.isUnbound, isTrue);
      expect(blocked.bindUrl, contains('workbuddy.cn'));
      expect(blocked.message, contains('未绑定手机号'));
    });

    test('已绑定 → allowed', () async {
      final repo = AuthRepository(_net('{"data":{"phone":"13800138000"}}'));
      final checker = PhoneBindingChecker(repo: repo);
      final outcome = await checker.check(
        _tokens(),
      );
      expect(outcome, isA<PostLoginAllowed>());
    });

    test('unknown + 非严格 → allowed（保守放行）', () async {
      final repo = AuthRepository(_net('{"code":0,"data":{}}'));
      final checker = PhoneBindingChecker(repo: repo, blockOnUnknown: false);
      final outcome = await checker.check(
        _tokens(),
      );
      expect(outcome, isA<PostLoginAllowed>());
    });

    test('unknown + 严格 → blocked', () async {
      final repo = AuthRepository(_net('{"code":0,"data":{}}'));
      final checker = PhoneBindingChecker(repo: repo, blockOnUnknown: true);
      final outcome = await checker.check(
        _tokens(),
      );
      expect(outcome, isA<PostLoginBlocked>());
    });
  });

  test('扫码成功回调校验未绑定 → 发 EffectBindPhoneRequired 且不跳转主页', () async {
    final net = _net('{"code":"phone_not_bound"}');
    final repo = AuthRepository(net);
    final checker = PhoneBindingChecker(repo: repo);
    final controller = DeviceCodeLoginController(
      repo: repo,
      postLoginChecker: checker,
    );

    controller.dispatch(LoginStart(LoginMethod.deviceCode));
    // 等二维码拿到 + 一次轮询 tick 触发 token 成功 → 回调校验。
    await Future<void>.delayed(const Duration(milliseconds: 100));
    controller.dispatch(LoginPollingTick());
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final effects = controller.consumeEffects();
    final bind = effects.whereType<EffectBindPhoneRequired>().toList();
    expect(bind, isNotEmpty);
    expect(bind.first.bindingStatus, PhoneBindingStatus.unbound);
    expect(effects.whereType<EffectNavigateHome>(), isEmpty);
    expect(controller.state.qrContent, isNull);
    expect(controller.state.phase, LoginPhase.failed);
    controller.dispose();
  });
}
