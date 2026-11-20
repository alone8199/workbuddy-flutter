/// 认证数据类。接口字段来源：login/signin finalize、cli auth/token。
class AuthTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? enterpriseId;
  final String? accountId;

  AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.enterpriseId,
    this.accountId,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'];
    DateTime? exp;
    if (expiresIn is num) {
      exp = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
    }
    return AuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresAt: exp,
      enterpriseId: json['enterpriseId'] as String?,
      accountId: json['accountId'] as String?,
    );
  }
}

enum LoginMethod { phone, email, wechat, qq, wecom, ioa, sso, asus, deviceCode }

/// 9 种登录方式标识。数据源：last-login 白名单 + 扫码确认。
extension LoginMethodName on LoginMethod {
  String get wireName {
    switch (this) {
      case LoginMethod.phone: return 'phone';
      case LoginMethod.email: return 'email';
      case LoginMethod.wechat: return 'wechat';
      case LoginMethod.qq: return 'qq';
      case LoginMethod.wecom: return 'wecom';
      case LoginMethod.ioa: return 'ioa';
      case LoginMethod.sso: return 'sso';
      case LoginMethod.asus: return 'asus';
      case LoginMethod.deviceCode: return 'device_code';
    }
  }
}
