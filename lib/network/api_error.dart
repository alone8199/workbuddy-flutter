import 'package:dio/dio.dart';

/// 统一业务/网络错误码（网络层 + 登录层的错误归一化）。
enum ApiErrorCode {
  network, // 网络不可达 / 超时
  server, // 5xx
  unauthorized, // 401
  forbidden, // 403
  rateLimited, // 429 / 频率超限
  invalidCaptcha, // 验证码错误
  invalidPhone, // 号码格式错误
  qrExpired, // 二维码过期
  ticketExpired, // ticket/state 失效
  tokenExchangeFailed, // 换取 token 失败
  cancelled, // 用户取消
  unknown,
}

/// 统一错误对象，注入 DioException.error，供 UI 直接读取 message。
class ApiError implements Exception {
  final ApiErrorCode code;
  final String message;
  final int? statusCode;
  final String? rawCode; // 服务端原始 code，如 wecom_user_unbound

  const ApiError(this.code, this.message, {this.statusCode, this.rawCode});

  @override
  String toString() => 'ApiError($code, $message, status=$statusCode)';
}

/// 供登录/业务层抛出的带 ApiError 的异常包装。
class ApiFailure implements Exception {
  final ApiError apiError;
  const ApiFailure(this.apiError);

  @override
  String toString() => apiError.toString();
}

/// 错误码映射：HTTP 状态 + 服务端原始 code → ApiError（纯函数，可单测）。
class ErrorMapper {
  /// 服务端原始业务码 → 文案。数据源：登录报告 B 各方式失败分支。
  static const Map<String, ApiError> _serverCodes = <String, ApiError>{
    'wecom_user_unbound': ApiError(ApiErrorCode.unauthorized, '企业微信账号未绑定，请先绑定'),
    'wecom_corp_unauthorized': ApiError(ApiErrorCode.forbidden, '企业微信企业未授权'),
    'wecom_user_no_seat': ApiError(ApiErrorCode.forbidden, '企业微信无可用席位'),
    'wecom_user_not_admin': ApiError(ApiErrorCode.forbidden, '需要企业微信管理员权限'),
    'invalid or expired login credential': ApiError(
      ApiErrorCode.qrExpired,
      '二维码已失效，请刷新',
    ),
  };

  static ApiError map(DioException err) {
    final status = err.response?.statusCode;
    final data = err.response?.data;
    String? rawCode;
    if (data is Map) {
      rawCode = data['code']?.toString() ?? data['error']?.toString();
    }
    if (rawCode != null && _serverCodes.containsKey(rawCode)) {
      return _serverCodes[rawCode]!;
    }
    switch (status) {
      case 401:
        return const ApiError(ApiErrorCode.unauthorized, '登录已失效，请重新登录', statusCode: 401);
      case 403:
        return const ApiError(ApiErrorCode.forbidden, '没有权限访问', statusCode: 403);
      case 429:
        return const ApiError(ApiErrorCode.rateLimited, '操作过于频繁，请稍后再试', statusCode: 429);
      default:
        if (status != null && status >= 500) {
          return ApiError(ApiErrorCode.server, '服务暂时不可用（$status）', statusCode: status);
        }
        if (status != null && status >= 400) {
          return ApiError(ApiErrorCode.unknown, '请求失败（$status）', statusCode: status);
        }
        return const ApiError(ApiErrorCode.network, '网络连接失败，请检查网络');
    }
  }

  /// 登录域专用验证码/号码错误码映射（静态报告列出的语义）。
  static ApiError mapAuthCode(String code) {
    switch (code) {
      case 'captcha_invalid':
      case 'verify_code_error':
      case 'code_invalid':
        return const ApiError(ApiErrorCode.invalidCaptcha, '验证码错误，请重新输入');
      case 'rate_limit_exceeded':
      case 'too_many_requests':
        return const ApiError(ApiErrorCode.rateLimited, '获取验证码过于频繁，请稍后再试');
      case 'phone_format_error':
      case 'invalid_mobile':
        return const ApiError(ApiErrorCode.invalidPhone, '手机号格式不正确');
      case 'qrcode_expired':
      case 'expired':
        return const ApiError(ApiErrorCode.qrExpired, '二维码已过期，请刷新');
      case 'ticket_expired':
      case 'state_expired':
        return const ApiError(ApiErrorCode.ticketExpired, '登录已超时，请重试');
      default:
        return ApiError(ApiErrorCode.unknown, code);
    }
  }
}
