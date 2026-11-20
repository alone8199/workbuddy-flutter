import 'package:dio/dio.dart';
import '../api_error.dart';

/// key：归一化后的 ApiError 写入 RequestOptions.extra，供上层统一读取。
const String kApiErrorExtra = 'apiError';

/// 响应拦截器：把任意 DioException 归一化为 ApiError，写入 extra 供 UI 读取。
/// Dio 5.x 的 DioException.error 为 final，故不能覆盖，改写入 extra。
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    err.requestOptions.extra.putIfAbsent(
      kApiErrorExtra,
      () => ErrorMapper.map(err),
    );
    handler.next(err);
  }
}
