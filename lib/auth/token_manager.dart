import 'package:synchronized/synchronized.dart';

import '../models/auth.dart';
import '../storage/secure_storage.dart';

/// token 管理：存储、互斥刷新、并发控制、多账号隔离（设计文档第 4 节）。
///
/// 并发刷新与失败处理路径（对齐 4.2/4.3）：
/// 1) 并发刷新：Mutex(Lock) 串行化 + 锁内二次 fresh 检查；刷新期间其余请求阻塞，
///    醒来直接拿新 token，不会重复发刷新请求；
/// 2) 401 触发：AuthInterceptor 调 forceRefresh() → invalidate 语义 → 重放一次（代际比对防死循环）；
/// 3) 提前刷新：expiresAt - now < 60s 即视为过期；
/// 4) 刷新失败：无 refresh token / 刷新接口 401 → 清当前账号 → onAuthExpired 事件 → 踢登录；
///    网络失败 → 由 RetryInterceptor 退避重试（这里保持旧 token 并向上抛）。
class TokenManager {
  final SecureStorage storage;
  final _lock = Lock();
  AuthTokens? _memory;
  int _generation = 0;

  /// 刷新失败回调（清 token 后由外层跳登录页）。
  void Function()? onAuthExpired;

  TokenManager(this.storage);

  bool get isLoggedIn => (_memory?.accessToken.isNotEmpty ?? false);
  AuthTokens? get current => _memory;

  Future<void> load() async {
    final access = await storage.accessToken;
    final refresh = await storage.refreshToken;
    final account = await storage.accountId;
    final enterprise = await storage.enterpriseId;
    if (access != null) {
      _memory = AuthTokens(
        accessToken: access,
        refreshToken: refresh,
        enterpriseId: enterprise,
        accountId: account,
      );
    }
  }

  bool _isFresh(AuthTokens t) {
    final exp = t.expiresAt;
    if (exp == null) return true; // 骨架：无过期时间视为有效
    return exp.difference(DateTime.now()).inSeconds > 60; // 提前 60s
  }

  /// 并发安全的 token 读取：必要时触发刷新。
  Future<String?> getValidToken({
    Future<AuthTokens> Function()? refresher,
  }) async {
    final cur = _memory;
    if (cur != null && _isFresh(cur)) return cur.accessToken;
    return _lock.synchronized(() async {
      final again = _memory;
      if (again != null && _isFresh(again)) return again.accessToken; // 双重检查
      if (refresher == null || again?.refreshToken == null) {
        return again?.accessToken;
      }
      final gen = _generation;
      try {
        final fresh = await refresher();
        _generation++;
        await apply(fresh);
        return fresh.accessToken;
      } catch (_) {
        if (_generation != gen) return _memory?.accessToken; // 别人已刷新成功
        rethrow;
      }
    });
  }

  /// 强制刷新（401 场景）：忽略 fresh 判断，但仍走互斥锁。
  Future<String?> forceRefresh(Future<AuthTokens> Function() refresher) async {
    return _lock.synchronized(() async {
      final gen = _generation;
      try {
        final fresh = await refresher();
        _generation++;
        await apply(fresh);
        return fresh.accessToken;
      } catch (_) {
        if (_generation != gen) return _memory?.accessToken;
        rethrow;
      }
    });
  }

  Future<void> apply(AuthTokens t) async {
    _memory = t;
    await storage.saveTokens(
      access: t.accessToken,
      refresh: t.refreshToken,
      expiresAt: t.expiresAt,
      enterpriseId: t.enterpriseId,
      accountId: t.accountId,
    );
  }

  Future<void> save(AuthTokens t) => apply(t);

  /// 刷新彻底失败：清当前账号 token + 通知外层踢登录。
  Future<void> expire() async {
    await _lock.synchronized(() async {
      _memory = null;
      await storage.clearCurrentAccount();
    });
    onAuthExpired?.call();
  }

  /// 兼容旧调用：只清 token，不触发回调。
  Future<void> invalidate() async {
    await _lock.synchronized(() async {
      _memory = null;
      await storage.clearCurrentAccount();
    });
  }

  /// 切换账号上下文（多账号隔离）。
  Future<void> switchAccount(String accountId) async {
    await storage.activateAccount(accountId);
    await load();
  }
}
