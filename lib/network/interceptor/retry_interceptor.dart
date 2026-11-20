import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

/// 重试策略（对齐任务要求）：
///  - 只对「网络错误」和「5xx」重试；
///  - 不重试 4xx（含 401，401 交给 AuthInterceptor 走刷新链路）；
///  - 指数退避：delay = base * 2^attempt + 抖动，单次上限 maxDelay。
///
/// 401 的刷新重放由 AuthInterceptor 负责（避免两处重复处理）。
class RetryInterceptor extends Interceptor {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random = Random();

  /// 由 NetworkClient 在 dio 构造后注入，用于重放请求。
  Dio? dio;

  RetryInterceptor({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
  });

  static bool _isNetworkError(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      default:
        return false;
    }
  }

  static bool _shouldRetry(DioException err) {
    final status = err.response?.statusCode;
    if (status != null) {
      // 只重试 5xx，绝不重试 4xx（401 由 AuthInterceptor 处理）。
      return status >= 500;
    }
    return _isNetworkError(err.type);
  }

  Duration _backoff(int attempt) {
    final ms = baseDelay.inMilliseconds * pow(2, attempt);
    final jitter = _random.nextInt(200);
    final capped = min(ms.toInt() + jitter, maxDelay.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_shouldRetry(err)) return handler.next(err);

    final opts = err.requestOptions;
    final attempt = (opts.extra['_retryAttempt'] as int?) ?? 0;
    if (attempt >= maxRetries) return handler.next(err);

    opts.extra['_retryAttempt'] = attempt + 1;
    await Future<void>.delayed(_backoff(attempt));
    try {
      final resp = await (dio ?? Dio()).fetch<dynamic>(opts);
      return handler.resolve(resp);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
