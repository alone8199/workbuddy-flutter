/// 非敏感配置（语言/环境/上次登录方式）。
/// 骨架占位：真实实现用 shared_preferences（未加入最小依赖集，留接口）。
class Preferences {
  String? _language;
  String? lastLoginMethod;

  String get language => _language ?? 'zh-CN';
  set language(String v) => _language = v;
}
