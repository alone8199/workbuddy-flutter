// ignore_for_file: avoid_print
/// 网络层探测脚本（纯 dart 运行，不依赖 Flutter 引擎）。
///
/// 目的：验证请求特征是否按设计文档对齐。分两段：
///  A. 本地 echo 服务：让「同一套拦截器链」打到本地，回显实际发出的完整请求头，
///     这是能拿到「真实发出的头」的可靠方式（对端回显）；
///  B. 真实公开接口：对 https://www.workbuddy.cn/login/（公开登录页，无需鉴权）
///     发一次 GET，验证连通与响应。
///
/// 约束：只打公开接口，不登录、不带任何凭据、不碰业务接口。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:workbuddy/network/interceptor/header_interceptor.dart';
import 'package:workbuddy/network/interceptor/auth_interceptor.dart';
import 'package:workbuddy/network/interceptor/error_interceptor.dart';
import 'package:workbuddy/network/interceptor/retry_interceptor.dart';

const String kAppVersion = '5.11.3';
const String kLanguage = 'zh-CN,zh;q=0.9';
// 静态未确认 device-token 算法，这里用显式占位，不伪造真实风控 token。
const String kDeviceId = 'PROBE-DEVICE-ID-PLACEHOLDER';

Future<void> main() async {
  print('===== WorkBuddy 网络层探测（公开接口，无鉴权）=====');
  print('时间(UTC): ${DateTime.now().toUtc().toIso8601String()}');

  // —— A. 本地 echo 服务，抓取实际发出的完整请求头 ——
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  server.listen((HttpRequest req) async {
    final headers = <String, dynamic>{};
    req.headers.forEach((name, values) => headers[name] = values.join(', '));
    final bodyBytes = <int>[];
    await for (final chunk in req) {
      bodyBytes.addAll(chunk);
    }
    final body = utf8.decode(bodyBytes);
    final payload = <String, dynamic>{
      'method': req.method,
      'path': req.uri.toString(),
      'headers': headers,
      'body': body,
    };
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(payload));
    await req.response.close();
  });
  print('本地 echo 服务: http://127.0.0.1:$port');

  final dio = Dio(BaseOptions(
    baseUrl: 'http://127.0.0.1:$port',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: const <String, dynamic>{'Content-Type': 'application/json'},
  ));
  final retry = RetryInterceptor();
  dio.interceptors.addAll(<Interceptor>[
    HeaderInterceptor(
      appVersion: kAppVersion,
      language: kLanguage,
      deviceId: kDeviceId,
      enterpriseId: null,
    ),
    ErrorInterceptor(),
    retry,
    AuthInterceptor(
      tokenProvider: () async => null, // 公开接口：不注入 Authorization
      forceRefreshProvider: () async => null,
      onAuthExpired: () async {},
    ),
  ]);
  retry.dio = dio;

  // GET 探测
  final getResp = await dio.get<dynamic>('/probe/public', queryParameters: <String, dynamic>{
    'z': 'last',
    'a': 'first',
    'platform': 'win32',
  });
  print('\n----- [A1] GET /probe/public 实际发出的完整请求头 -----');
  _printEcho(getResp.data);

  // 带 body 的 POST 探测
  final postResp = await dio.post<dynamic>(
    '/probe/public/submit',
    data: <String, dynamic>{'echo': 'hello', 'ts': 1},
  );
  print('\n----- [A2] POST /probe/public/submit 实际发出的完整请求头 + body -----');
  _printEcho(postResp.data);

  await server.close(force: true);

  // —— B. 真实公开接口：登录页（无需鉴权） ——
  print('\n----- [B] 真实公开接口 GET https://www.workbuddy.cn/login/ -----');
  try {
    final realDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
    ));
    final real = await realDio.get<dynamic>(
      'https://www.workbuddy.cn/login/',
      options: Options(
        headers: <String, dynamic>{
          'User-Agent': 'WorkBuddy/$kAppVersion',
          'Accept-Language': kLanguage,
          'X-IDE-Type': 'WorkBuddy',
          'X-Client-Version': kAppVersion,
          'X-Product': 'workbuddy',
          'X-TOA-LANG': 'zh-CN',
          'X-Request-ID': '0123456789abcdef0123456789abcdef',
        },
      ),
    );
    print('statusCode: ${real.statusCode}');
    print('content-type: ${real.headers.value('content-type')}');
    final data = real.data is String ? real.data as String : jsonEncode(real.data);
    print('body(前160字): ${data.length > 160 ? data.substring(0, 160) : data}');
    print('结论: 公开接口连通 OK（未登录、未提交表单、未打业务接口）');
  } on DioException catch (e) {
    print('公开接口请求失败: ${e.type} / ${e.message}');
  }
}

void _printEcho(dynamic data) {
  if (data is! Map) {
    print('(非预期响应) $data');
    return;
  }
  final m = Map<String, dynamic>.from(data);
  print('method: ${m['method']}  path: ${m['path']}');
  final headers = Map<String, dynamic>.from(m['headers'] as Map);
  final keys = headers.keys.toList()..sort();
  for (final k in keys) {
    print('  $k: ${headers[k]}');
  }
  if (m['body'] != null && (m['body'] as String).isNotEmpty) {
    print('body: ${m['body']}');
  }
}
