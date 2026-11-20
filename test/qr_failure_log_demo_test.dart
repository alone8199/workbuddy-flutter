import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/auth/auth_repository.dart';
import 'package:workbuddy/auth/login_events.dart';
import 'package:workbuddy/auth/login_methods/device_code_login.dart';
import 'package:workbuddy/auth/login_state_machine.dart';
import 'package:workbuddy/models/auth.dart';
import 'package:workbuddy/network/client.dart';

/// 按路径分发的 fake adapter：
///  - auth/state → 200 + {code:0, data:{state, authUrl}}（实测公开端点行为）
///  - auth/token → 200 + {code:11217, msg:"login ing..."}（pending）
class _FakeAdapter implements HttpClientAdapter {
  String _body(String path) {
    if (path.contains('auth/state')) {
      return '{"code":0,"msg":"OK","data":{"state":"ST-123","authUrl":"https://www.workbuddy.cn/login?platform=workbuddy&state=ST-123"}}';
    }
    if (path.contains('auth/token')) {
      return '{"code":11217,"msg":"login ing..."}';
    }
    return '{"code":0,"data":{}}';
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(_body(options.path), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('二维码登录走 auth/state 公开流程并生成二维码', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter();
    final net = NetworkClient(
        appVersion: '5.11.3',
        language: 'zh-CN,zh;q=0.9',
        tokenProvider: () async => null,
        forceRefreshProvider: () async => null,
        onAuthExpired: () async {},
        dioInstance: dio);
    final repo = AuthRepository(net);
    final controller = DeviceCodeLoginController(repo: repo);

    controller.dispatch(LoginStart(LoginMethod.deviceCode));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(controller.state.qrContent,
        'https://www.workbuddy.cn/login?platform=workbuddy&state=ST-123');
    expect(controller.state.codeOrTicket, 'ST-123');
    expect(controller.state.phase, LoginPhase.awaitingCallback);
    controller.dispose();
  });

  test('auth/state 解析解包 data 层', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter();
    final net = NetworkClient(
        appVersion: '5.11.3',
        language: 'zh-CN,zh;q=0.9',
        tokenProvider: () async => null,
        forceRefreshProvider: () async => null,
        onAuthExpired: () async {},
        dioInstance: dio);
    final repo = AuthRepository(net);
    final s = await repo.authState('workbuddy');
    expect(s['state'], 'ST-123');
    expect(s['authUrl'], contains('www.workbuddy.cn/login'));
  });
}
