import 'dart:collection';

/// 轻量 Cookie 域管理（设计文档 1.2 Cookie 域专项）。
///
/// 原客户端：主站登录态在 .workbuddy.cn；OneID 在 account.tencent.com /
/// oauth2.account.tencent.com。跨域靠后端 state 关联，Flutter 不手动种跨域 cookie。
/// 这里只做「按 host 后缀匹配」的最小实现，真正的登录态由 WebView 的 CookieManager 管理。
class CookieStore {
  final Map<String, Map<String, String>> _byDomain =
      <String, Map<String, String>>{};

  /// 写入某域的 cookie（domain 为主机名，如 .workbuddy.cn）。
  void put(String domain, String name, String value) {
    _byDomain.putIfAbsent(domain, () => <String, String>{})[name] = value;
  }

  /// 按请求 URI 的 host 匹配所有适用域，拼成 Cookie 头。
  String headerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    final matched = <String, String>{};
    _byDomain.forEach((domain, cookies) {
      final d = domain.toLowerCase();
      final ok = d.startsWith('.')
          ? (host == d.substring(1) || host.endsWith(d))
          : host == d;
      if (ok) matched.addAll(cookies);
    });
    if (matched.isEmpty) return '';
    final sorted = SplayTreeMap<String, String>.from(matched);
    return sorted.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void clear() => _byDomain.clear();
}
