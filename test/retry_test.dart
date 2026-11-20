import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/network/interceptor/retry_interceptor.dart';

/// 自定义 adapter：按状态码/类型返回，用于统计重试次数（无需真实网络）。
class _CountingAdapter implements HttpClientAdapter {
  final int statusCode;
  final bool networkError;
  int calls = 0;

  _CountingAdapter({this.statusCode = 200, this.networkError = false});

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List?>? requestStream,
      Future<void>? cancelFuture) async {
    calls++;
    if (networkError) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated network error',
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Dio build(int status, {bool networkError = false, int maxRetries = 3}) {
    final d = Dio();
    final retry = RetryInterceptor(
      maxRetries: maxRetries,
      baseDelay: const Duration(milliseconds: 1),
      maxDelay: const Duration(milliseconds: 4),
    );
    d.interceptors.add(retry);
    retry.dio = d;
    d.httpClientAdapter = _CountingAdapter(statusCode: status, networkError: networkError);
    return d;
  }

  test('4xx 不重试（只调用 1 次）', () async {
    final d = build(404);
    try {
      await d.get<dynamic>('http://x/test');
    } on DioException catch (_) {}
    final adapter = d.httpClientAdapter as _CountingAdapter;
    expect(adapter.calls, 1);
  });

  test('401 不重试（交给 AuthInterceptor，只调用 1 次）', () async {
    final d = build(401);
    try {
      await d.get<dynamic>('http://x/test');
    } on DioException catch (_) {}
    final adapter = d.httpClientAdapter as _CountingAdapter;
    expect(adapter.calls, 1);
  });

  test('5xx 重试到上限（maxRetries=2 → 共 3 次）', () async {
    final d = build(503, maxRetries: 2);
    try {
      await d.get<dynamic>('http://x/test');
    } on DioException catch (_) {}
    final adapter = d.httpClientAdapter as _CountingAdapter;
    expect(adapter.calls, 3);
  });

  test('网络错误重试到上限', () async {
    final d = build(0, networkError: true, maxRetries: 2);
    try {
      await d.get<dynamic>('http://x/test');
    } on DioException catch (_) {}
    final adapter = d.httpClientAdapter as _CountingAdapter;
    expect(adapter.calls, 3);
  });

  test('2xx 成功不发重试', () async {
    final d = build(200);
    final r = await d.get<dynamic>('http://x/test');
    expect(r.statusCode, 200);
    final adapter = d.httpClientAdapter as _CountingAdapter;
    expect(adapter.calls, 1);
  });
}
