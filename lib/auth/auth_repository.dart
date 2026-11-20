import '../network/client.dart';
import '../network/endpoints.dart';
import '../network/api_error.dart';
import '../models/auth.dart';

/// 认证接口封装：state / token 轮询 / refresh / handoff / finalize / 发码 / 换码。
/// TODO(dynamic-capture): prefixPath、expiresIn 单位、各登录方式完整 authz 顺序需抓包；
/// 未坐实的参数以常量占位并在此注释，不猜值。
class AuthRepository {
  final NetworkClient net;
  final EnvConfig env;

  AuthRepository(this.net, {EnvConfig? env})
      : env = env ?? const EnvConfig(WorkbuddyEnv.prod);

  /// 把 DioException 里归一化好的 ApiError 取出来（ErrorInterceptor 写入 extra）。
  ApiError asApiError(dynamic error) {
    if (error is ApiFailure) return error.apiError;
    if (error is ApiError) return error;
    // DioException 的 extra 归一化由 ErrorInterceptor 完成，这里兜底。
    return const ApiError(ApiErrorCode.network, '网络请求失败');
  }

  /// 登录初始化：拿 authUrl 与 state。
  Future<Map<String, dynamic>> authState(String platform) async {
    final r = await net.dio.post<dynamic>(env.authState(platform));
    return (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
  }

  /// 轮询换 token（device code 模式）。
  Future<AuthTokens?> pollToken(String state) async {
    final r = await net.dio.get<dynamic>(env.authToken(state));
    if (r.data is Map && (r.data as Map)['access_token'] != null) {
      return AuthTokens.fromJson(Map<String, dynamic>.from(r.data as Map));
    }
    return null;
  }

  /// 刷新 token。
  Future<AuthTokens> refresh() async {
    final r = await net.dio.post<dynamic>(env.authRefresh);
    return AuthTokens.fromJson(Map<String, dynamic>.from(r.data as Map));
  }

  /// 浏览器一次性码换会话。
  Future<AuthTokens> handoff(String code) async {
    final r = await net.dio.post<dynamic>(
      env.authHandoff,
      data: <String, dynamic>{'code': code},
    );
    return AuthTokens.fromJson(Map<String, dynamic>.from(r.data as Map));
  }

  /// 生成设备码（扫码确认登录第一步）。
  Future<Map<String, dynamic>> deviceAuthCode() async {
    final r = await net.dio.post<dynamic>(env.deviceAuthCode);
    return (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
  }

  /// 发送验证码（手机号/邮箱）。端点来自接口清单 authz 栈。
  /// 请求体字段静态未完全坐实（报告用 b 占位），这里用常见字段 account + 场景标记。
  Future<Map<String, dynamic>> sendCode(LoginMethod target, String account) async {
    final path = target == LoginMethod.email
        ? '/authz/v1/authn/email/code/send'
        : '/authz/v1/authn/person/code:send';
    final r = await net.dio.post<dynamic>(
      '${env.oauth2}$path',
      data: <String, dynamic>{'account': account},
    );
    return (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
  }

  /// 校验验证码。成功返回 ticket/state_token（响应结构待抓包），可能为 null 表示需选号。
  Future<AuthTokens?> verifyCode(LoginMethod target, String code) async {
    final path = target == LoginMethod.email
        ? '/authz/v1/authn/email/code/login'
        : '/authz/v1/authn/person/code/login';
    final r = await net.dio.post<dynamic>(
      '${env.oauth2}$path',
      data: <String, dynamic>{'code': code},
    );
    if (r.data is Map) {
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['access_token'] != null) return AuthTokens.fromJson(m);
    }
    return null;
  }

  /// ticket 换 token（signin/finalize）。
  Future<AuthTokens?> finalize(String ticket) async {
    final r = await net.dio.get<dynamic>(
      env.signinFinalize,
      queryParameters: <String, dynamic>{
        'ticket': ticket,
        'response_type': 'token',
      },
    );
    if (r.data is Map && (r.data as Map)['access_token'] != null) {
      return AuthTokens.fromJson(Map<String, dynamic>.from(r.data as Map));
    }
    return null;
  }
}
