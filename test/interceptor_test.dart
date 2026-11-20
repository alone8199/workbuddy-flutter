import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/network/interceptor/header_interceptor.dart';
import 'package:workbuddy/network/interceptor/auth_interceptor.dart';
import 'package:workbuddy/network/api_error.dart';
import 'package:workbuddy/network/interceptor/error_interceptor.dart';

/// 用本地 echo 服务验证拦截器确实把头写到了「实际发出的请求」上。
void main() {
  late HttpServer server;
  late int port;
  late Map<String, dynamic> lastCaptured;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      final headers = <String, String>{};
      req.headers.forEach((k, v) => headers[k] = v.join(', '));
      final bytes = <int>[];
      await for (final c in req) {
        bytes.addAll(c);
      }
      lastCaptured = <String, dynamic>{
        'headers': headers,
        'body': utf8.decode(bytes),
        'method': req.method,
      };
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(<String, dynamic>{'ok': true}));
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  Dio buildDio({
    bool noAuth = false,
    String language = 'zh-CN,zh;q=0.9',
    String? deviceId,
  }) {
    final d = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:$port',
      headers: const <String, dynamic>{'Content-Type': 'application/json'},
    ));
    d.interceptors.addAll(<Interceptor>[
      HeaderInterceptor(
        appVersion: '5.11.3',
        language: language,
        deviceId: deviceId,
      ),
      ErrorInterceptor(),
      AuthInterceptor(
        tokenProvider: () async => 'test-access-token',
        forceRefreshProvider: () async => 'refreshed-token',
        onAuthExpired: () async {},
      ),
    ]);
    return d;
  }

  test('请求头逐项齐全（对齐设计文档 1.1）', () async {
    final dio = buildDio(deviceId: 'DEV-123');
    await dio.get<dynamic>('/headers', queryParameters: <String, dynamic>{'x': 1});
    final h = lastCaptured['headers'] as Map<String, String>;

    expect(h['user-agent'], 'WorkBuddy/5.11.3');
    expect(h['x-ide-type'], 'WorkBuddy');
    expect(h['x-client-version'], '5.11.3');
    expect(h['x-product'], 'workbuddy');
    expect(h['accept-language'], 'zh-CN,zh;q=0.9');
    expect(h['x-toa-lang'], 'zh-CN');
    expect(h['x-request-id'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(h['x-trace-id'], isNotEmpty);
    expect(h['x-b3-traceid'], h['x-trace-id']);
    expect(h['x-b3-spanid'], isNotEmpty);
    expect(h['b3'], isNotEmpty);
    expect(h['origin'], 'https://www.workbuddy.cn');
    expect(h['referer'], 'https://www.workbuddy.cn/');
    expect(h['x-device-id'], 'DEV-123');
    expect(h['authorization'], 'Bearer test-access-token');
  });

  test('no-auth 端点注入 X-No-* 且不带 Authorization', () async {
    final dio = buildDio();
    await dio.post<dynamic>('/v2/auth/state');
    final h = lastCaptured['headers'] as Map<String, String>;
    expect(h['x-no-authorization'], 'true');
    expect(h['x-no-user-id'], 'true');
    expect(h['x-no-enterprise-id'], 'true');
    expect(h.containsKey('authorization'), isFalse);
  });

  test('POST body 正确回传', () async {
    final dio = buildDio();
    await dio.post<dynamic>('/submit', data: <String, dynamic>{'k': 'v'});
    expect(jsonDecode(lastCaptured['body'] as String), <String, dynamic>{'k': 'v'});
  });

  test('错误码映射：401/429/5xx/网络', () {
    ApiError e401 = ErrorMapper.map(DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response<dynamic>(statusCode: 401, requestOptions: RequestOptions(path: '/x')),
      type: DioExceptionType.badResponse,
    ));
    expect(e401.code, ApiErrorCode.unauthorized);

    ApiError e429 = ErrorMapper.map(DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response<dynamic>(statusCode: 429, requestOptions: RequestOptions(path: '/x')),
      type: DioExceptionType.badResponse,
    ));
    expect(e429.code, ApiErrorCode.rateLimited);

    ApiError e500 = ErrorMapper.map(DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response<dynamic>(statusCode: 500, requestOptions: RequestOptions(path: '/x')),
      type: DioExceptionType.badResponse,
    ));
    expect(e500.code, ApiErrorCode.server);

    ApiError enet = ErrorMapper.map(DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    ));
    expect(enet.code, ApiErrorCode.network);
  });

  test('服务端原始错误码映射（企微分支）', () {
    final e = ErrorMapper.map(DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response<dynamic>(
        statusCode: 400,
        data: <String, dynamic>{'code': 'wecom_user_no_seat'},
        requestOptions: RequestOptions(path: '/x'),
      ),
      type: DioExceptionType.badResponse,
    ));
    expect(e.code, ApiErrorCode.forbidden);
    expect(e.message, contains('席位'));
  });
}
