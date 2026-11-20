import 'package:dio/dio.dart';

import '../../util/app_logger.dart';

/// 网络链路日志拦截器：记录每个请求的完整特征与结果，失败时打印原始响应体，
/// 让"网络异常，二维码获取失败"这类笼统提示能被定位到具体 URL / 状态码 / body。
///
/// 放在拦截器链最前面（onRequest 最先执行、onError 最后执行），因此能看到
/// HeaderInterceptor 注入之前的原始请求，也能看到 ErrorInterceptor 归一化之后
/// 的错误。脱敏由 [AppLogger.mask] 处理。
class LoggingInterceptor extends Interceptor {
  final AppLogger _log = AppLogger.instance;
  final bool logHeaders;
  final bool logBody;

  LoggingInterceptor({this.logHeaders = true, this.logBody = true});

  static const String _startKey = 'wb_log_start_ms';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    const tag = 'NET';
    _log.i(tag, '→ ${options.method} ${options.uri}');
    if (logHeaders) {
      _log.d(tag, '  请求头: ${_maskHeaders(options.headers)}');
    }
    if (logBody && options.data != null) {
      _log.d(tag, '  请求体: ${AppLogger.truncate(options.data)}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = response.requestOptions.extra[_startKey] as int?;
    final cost = start == null
        ? '?ms'
        : '${DateTime.now().millisecondsSinceEpoch - start}ms';
    final uri = response.requestOptions.uri;
    _log.i(
      'NET',
      '← ${response.statusCode} ${response.requestOptions.method} $uri ($cost)',
    );
    if (logBody) {
      _log.d('NET', '  响应体: ${AppLogger.truncate(response.data)}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = err.requestOptions.extra[_startKey] as int?;
    final cost = start == null
        ? '?ms'
        : '${DateTime.now().millisecondsSinceEpoch - start}ms';
    final uri = err.requestOptions.uri;
    final status = err.response?.statusCode;
    final apiError = err.requestOptions.extra['apiError'];

    _log.e(
      'NET',
      '✖ ${err.requestOptions.method} $uri '
      '(${err.type.name}${status == null ? '' : ', HTTP $status'}, $cost) '
      'message=${err.message}',
      err.error,
      err.stackTrace,
    );
    if (apiError != null) {
      _log.e('NET', '  归一化错误: $apiError');
    }
    if (err.response != null) {
      _log.e('NET', '  原始响应体: ${AppLogger.truncate(err.response!.data)}');
    }
    if (logHeaders) {
      _log.d('NET', '  请求头: ${_maskHeaders(err.requestOptions.headers)}');
    }
    handler.next(err);
  }

  /// 对敏感头脱敏后输出，避免 token/cookie 落盘。
  String _maskHeaders(Map<String, dynamic> headers) {
    final sensitive = <String>{
      'authorization',
      'cookie',
      'set-cookie',
      'x-device-token',
      'x-auth-token',
    };
    return headers.map((k, v) {
      final masked = sensitive.contains(k.toLowerCase()) ? AppLogger.mask(v?.toString()) : v;
      return MapEntry<String, dynamic>(k, masked);
    }).toString();
  }
}
