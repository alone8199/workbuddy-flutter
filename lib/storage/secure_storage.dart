import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储封装（Windows 走 DPAPI）。替换原 credentials.json/credentials.enc。
/// 多账号按 key 前缀隔离：前缀为 accountId，保证切账号不串 token。
class SecureStorage {
  // 当前账号的 key（无前缀，兼容旧数据）
  static const _kAccess = 'wb_access_token';
  static const _kRefresh = 'wb_refresh_token';
  static const _kExpires = 'wb_expires_at';
  static const _kEnterprise = 'wb_enterprise_id';
  static const _kAccount = 'wb_account_id';
  static const _kDevice = 'wb_device_id';
  static const _kAccounts = 'wb_accounts';
  static const _kCurrentAccount = 'wb_current_account_id';

  final FlutterSecureStorage _s;

  SecureStorage({FlutterSecureStorage? storage})
      : _s = storage ?? const FlutterSecureStorage();

  // —— current-account scoped getters ——
  Future<String?> get accessToken => _s.read(key: _kAccess);
  Future<String?> get refreshToken => _s.read(key: _kRefresh);
  Future<String?> get enterpriseId => _s.read(key: _kEnterprise);
  Future<String?> get accountId => _s.read(key: _kAccount);
  Future<String?> get deviceId => _s.read(key: _kDevice);
  Future<String?> get accounts => _s.read(key: _kAccounts);
  Future<String?> get currentAccountId => _s.read(key: _kCurrentAccount);

  Future<void> saveTokens({
    required String access,
    String? refresh,
    DateTime? expiresAt,
    String? enterpriseId,
    String? accountId,
  }) async {
    await _s.write(key: _kAccess, value: access);
    if (refresh != null) await _s.write(key: _kRefresh, value: refresh);
    if (expiresAt != null) {
      await _s.write(
        key: _kExpires,
        value: expiresAt.millisecondsSinceEpoch.toString(),
      );
    }
    if (enterpriseId != null) {
      await _s.write(key: _kEnterprise, value: enterpriseId);
    }
    if (accountId != null) {
      await _s.write(key: _kAccount, value: accountId);
      await _s.write(key: _kCurrentAccount, value: accountId);
    }
  }

  Future<void> setDeviceId(String id) => _s.write(key: _kDevice, value: id);
  Future<void> setAccounts(String json) => _s.write(key: _kAccounts, value: json);
  Future<void> setCurrentAccountId(String id) =>
      _s.write(key: _kCurrentAccount, value: id);

  // —— 多账号前缀隔离：wb_{accountId}_access_token 等 ——
  String _scoped(String accountId, String suffix) => 'wb_$accountId-$suffix';

  Future<void> saveAccountTokens(String accountId, AuthTokenPayload t) async {
    await _s.write(key: _scoped(accountId, 'access'), value: t.accessToken);
    if (t.refreshToken != null) {
      await _s.write(key: _scoped(accountId, 'refresh'), value: t.refreshToken!);
    }
    if (t.expiresAt != null) {
      await _s.write(
        key: _scoped(accountId, 'expires'),
        value: t.expiresAt!.millisecondsSinceEpoch.toString(),
      );
    }
  }

  Future<String?> scopedAccessToken(String accountId) =>
      _s.read(key: _scoped(accountId, 'access'));
  Future<String?> scopedRefreshToken(String accountId) =>
      _s.read(key: _scoped(accountId, 'refresh'));

  /// 切换账号：把目标账号的 scoped token 提升为当前生效 token。
  Future<void> activateAccount(String accountId) async {
    final access = await scopedAccessToken(accountId);
    final refresh = await scopedRefreshToken(accountId);
    if (access != null) await _s.write(key: _kAccess, value: access);
    if (refresh != null) await _s.write(key: _kRefresh, value: refresh);
    await _s.write(key: _kCurrentAccount, value: accountId);
  }

  Future<void> clearCurrentAccount() async {
    for (final k in [
      _kAccess,
      _kRefresh,
      _kExpires,
      _kEnterprise,
      _kAccount,
      _kCurrentAccount,
    ]) {
      await _s.delete(key: k);
    }
  }
}

/// 轻量 token 载荷（避免 storage 层直接依赖 models/auth.dart）。
class AuthTokenPayload {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  AuthTokenPayload({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });
}
