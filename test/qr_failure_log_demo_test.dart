import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/auth/auth_repository.dart';
import 'package:workbuddy/auth/login_events.dart';
import 'package:workbuddy/auth/login_methods/device_code_login.dart';
import 'package:workbuddy/models/auth.dart';
import 'package:workbuddy/network/client.dart';
import 'package:workbuddy/util/app_logger.dart';

/// 模拟一次"二维码获取失败"（服务端返回 404），驱动真实 controller 的失败路径，
/// 验证详细日志能落到文件、且失败原因可见。产出日志样例供交付展示。
class _Fake404Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"Not Found","path":"${options.path}"}',
      404,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('二维码失败路径产出详细日志', () async {
    final log = AppLogger.instance;
    await log.init();

    final dio = Dio();
    dio.httpClientAdapter = _Fake404Adapter();
    final net = NetworkClient(
      appVersion: '5.11.3',
      language: 'zh-CN,zh;q=0.9',
      tokenProvider: () async => null,
      forceRefreshProvider: () async => null,
      onAuthExpired: () async {},
      dioInstance: dio,
    );
    final repo = AuthRepository(net);
    final controller = DeviceCodeLoginController(repo: repo);

    // 驱动开始 → deviceAuthCode() 拿到 404 → 走 fail() 分支。
    controller.dispatch(LoginStart(LoginMethod.deviceCode));
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // 打印最终 UI 状态，证明失败原因已携带。
    // ignore: avoid_print
    print('DEMO_UI_MESSAGE=${controller.state.message}');

    await Future<void>.delayed(const Duration(milliseconds: 100));
    final content = await File(log.filePath).readAsString();
    // ignore: avoid_print
    print('DEMO_LOG_HEAD');
    // 只取最后 40 行展示。
    final lines = content.split('\n');
    final tail = lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
    // ignore: avoid_print
    print(tail.join('\n'));
    // ignore: avoid_print
    print('DEMO_LOG_END');
  });
}
