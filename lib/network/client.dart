import 'package:dio/dio.dart';

import 'env_config.dart';
import 'interceptor/header_interceptor.dart';
import 'interceptor/auth_interceptor.dart';
import 'interceptor/retry_interceptor.dart';
import 'interceptor/error_interceptor.dart';
import 'interceptor/cookie/cookie_store.dart';

/// 全局网络客户端：dio 实例 + 拦截器链编排（设计文档 2.3 方案 C）。
/// - baseUrl 按 Environment 多环境切换；
/// - 统一超时；重试（指数退避，仅网络错误/5xx）在 RetryInterceptor；
/// - 401 刷新在 AuthInterceptor；错误归一化在 ErrorInterceptor。
class NetworkClient {
  late final Dio dio;
  final Environment environment;
  final CookieStore cookieStore;

  NetworkClient({
    required String appVersion,
    required String language,
    required TokenProvider tokenProvider,
    required ForceRefreshProvider forceRefreshProvider,
    required Future<void> Function() onAuthExpired,
    Environment? environment,
    String? product,
    String? enterpriseId,
    String? deviceId,
    bool sortQueryParams = false,
    Set<String>? noAuthPaths,
    Dio? dioInstance,
  })  : environment = environment ?? const Environment(AppEnv.prod),
        cookieStore = CookieStore() {
    final env = this.environment;
    dio = dioInstance ??
        Dio(BaseOptions(
          baseUrl: env.api,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
          headers: const <String, dynamic>{'Content-Type': 'application/json'},
        ));
    if (dioInstance != null) {
      dio.options.baseUrl = env.api;
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      dio.options.sendTimeout = const Duration(seconds: 15);
    }

    // onRequest 按插入顺序执行；onError 逆序执行。
    final retry = RetryInterceptor();
    final auth = AuthInterceptor(
      tokenProvider: tokenProvider,
      forceRefreshProvider: forceRefreshProvider,
      onAuthExpired: onAuthExpired,
      noAuthPaths: noAuthPaths,
    );
    dio.interceptors.addAll(<Interceptor>[
      HeaderInterceptor(
        appVersion: appVersion,
        language: language,
        product: product ?? 'workbuddy',
        websiteOrigin: env.website,
        deviceId: deviceId,
        enterpriseId: enterpriseId,
        sortQueryParams: sortQueryParams,
        cookieStore: cookieStore,
      ),
      ErrorInterceptor(),
      retry,
      auth,
    ]);
    // dio 构造完成后注入重放所需的实例引用。
    retry.dio = dio;
    auth.dio = dio;
  }

  /// 运行时切换环境（更新 baseUrl 与 Referer/Origin 基线由重建拦截器完成）。
  void useEnvironment(Environment env) {
    dio.options.baseUrl = env.api;
  }
}
