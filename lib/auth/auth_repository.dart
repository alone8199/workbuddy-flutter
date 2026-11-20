import 'package:dio/dio.dart';

import '../network/client.dart';
import '../network/endpoints.dart';
import '../network/api_error.dart';
import '../models/auth.dart';
import '../util/app_logger.dart';

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
  /// 响应结构：{code:0, msg:"OK", data:{state, authUrl}}（实测 www.workbuddy.cn/v2/plugin/auth/state → 200）。
  Future<Map<String, dynamic>> authState(String platform) async {
    final r = await net.dio.post<dynamic>(env.authState(platform));
    final body = (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
    // 解包 data 层，同时保留 code/msg 供判断。
    if (body['data'] is Map) {
      final data = Map<String, dynamic>.from(body['data'] as Map);
      data.putIfAbsent('code', () => body['code']);
      data.putIfAbsent('msg', () => body['msg']);
      return data;
    }
    return body;
  }

  /// 轮询换 token（auth/state 或 device code 模式）。
  /// pending 时服务端返回 {code:11217, msg:"login ing..."}（实测），此处返回 null 表示继续轮询。
  /// 登录成功后返回 {access_token, refresh_token, ...} 或包在 data 里，两种都兼容。
  Future<AuthTokens?> pollToken(String state) async {
    final r = await net.dio.get<dynamic>(env.authToken(state));
    if (r.data is! Map) return null;
    final body = Map<String, dynamic>.from(r.data as Map);
    // 成功结构优先取顶层，其次取 data 层。
    final tokenMap = body['access_token'] != null
        ? body
        : (body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : body);
    if (tokenMap['access_token'] != null) {
      return AuthTokens.fromJson(tokenMap);
    }
    // pending / 其他业务码：记录到日志由上层处理，这里按"未完成"返回 null。
    AppLogger.instance.d('AUTH_REPO',
        'pollToken 未完成: code=${body['code']} msg=${body['msg']}');
    return null;
  }

  /// 扫码成功后回调校验：拉取账号资料判断手机号绑定状态。
  /// 注意：此处必须用刚拿到的 token 显式带 Authorization，因为 token 尚未存入 TokenManager，
  /// AuthInterceptor 的 tokenProvider 此刻拿不到它。extra.skipAuth 让拦截器不覆盖此头，
  /// 同时该路径不在 noAuthPaths，401 刷新逻辑仍可正常工作。
  Future<dynamic> fetchAccountProfile(AuthTokens tokens) async {
    final url = env.accountProfile;
    AppLogger.instance.i('AUTH_REPO', 'GET accountProfile(绑定校验) → $url');
    final r = await net.dio.get<dynamic>(
      url,
      options: Options(
        headers: <String, dynamic>{
          'Authorization': 'Bearer ${tokens.accessToken}',
        },
        extra: <String, dynamic>{'skipAuth': true},
      ),
    );
    return r.data;
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
    AppLogger.instance.i('AUTH_REPO', 'POST deviceAuthCode → ${env.deviceAuthCode}');
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
