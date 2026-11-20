import 'package:dio/dio.dart';

/// Bearer token 注入 + 401 刷新触发（设计文档 4.2/4.3）。
/// token 由 tokenManager 惰性提供（可能触发互斥刷新）；刷新失败由 onAuthExpired 踢回登录。
typedef TokenProvider = Future<String?> Function();
typedef ForceRefreshProvider = Future<String?> Function();

class AuthInterceptor extends Interceptor {
  final TokenProvider tokenProvider;
  final ForceRefreshProvider forceRefreshProvider;
  final Future<void> Function() onAuthExpired;
  final Set<String> noAuthPaths;

  /// 由 NetworkClient 在 dio 构造后注入，用于 401 刷新后重放请求。
  Dio? dio;

  /// 每个请求只允许重放一次，避免 401 死循环。
  static const _authRetried = '_authRetried';

  AuthInterceptor({
    required this.tokenProvider,
    required this.forceRefreshProvider,
    required this.onAuthExpired,
    Set<String>? noAuthPaths,
  })  : noAuthPaths = noAuthPaths ?? const <String>{
          '/auth/state',
          '/auth/token',
          '/auth/handoff/token',
          '/auth/token/refresh',
          '/signin/',
        };

  bool _isNoAuth(String path) => noAuthPaths.any(path.contains);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isNoAuth(options.path)) {
      options.headers['X-No-Authorization'] = 'true';
      options.headers['X-No-User-Id'] = 'true';
      options.headers['X-No-Enterprise-Id'] = 'true';
      options.headers['X-No-Department-Info'] = 'true';
    } else {
      final token = await tokenProvider();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) return handler.next(err);
    // 刷新 token 接口自身的 401：直接失败，不再递归刷新。
    if (_isNoAuth(err.requestOptions.path)) return handler.next(err);
    // 已重放过一次仍 401：踢回登录。
    if (err.requestOptions.extra[_authRetried] == true) {
      await onAuthExpired();
      return handler.next(err);
    }

    err.requestOptions.extra[_authRetried] = true;
    try {
      final fresh = await forceRefreshProvider();
      if (fresh == null || fresh.isEmpty) {
        await onAuthExpired();
        return handler.next(err);
      }
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer $fresh';
      final resp = await (dio ?? Dio()).fetch<dynamic>(opts);
      return handler.resolve(resp);
    } on DioException catch (e) {
      await onAuthExpired();
      return handler.next(e);
    } catch (_) {
      await onAuthExpired();
      return handler.next(err);
    }
  }
}
