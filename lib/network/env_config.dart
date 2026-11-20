/// 环境域名配置。数据源：route-BzScxxrM.js @1760807（getApiDomainByEnv）。
/// 与 endpoints.dart 中 WorkbuddyEnv / EnvConfig 对齐，此处作为网络层单一配置入口。
enum AppEnv { prod, international, pre }

class Environment {
  final AppEnv env;
  const Environment(this.env);

  factory Environment.fromString(String name) {
    switch (name.toLowerCase()) {
      case 'international':
      case 'intl':
        return const Environment(AppEnv.international);
      case 'pre':
        return const Environment(AppEnv.pre);
      default:
        return const Environment(AppEnv.prod);
    }
  }

  String get api {
    switch (env) {
      case AppEnv.international:
        return 'https://api.account.tencentid.com';
      case AppEnv.pre:
        return 'https://api.pre-account.tencent.com';
      default:
        return 'https://api.account.tencent.com';
    }
  }

  String get oauth2 {
    switch (env) {
      case AppEnv.international:
        return 'https://oauth2.account.tencentid.com';
      case AppEnv.pre:
        return 'https://oauth2.pre-account.tencent.com';
      default:
        return 'https://oauth2.account.tencent.com';
    }
  }

  String get website {
    switch (env) {
      case AppEnv.international:
        return 'https://account.tencentid.com';
      case AppEnv.pre:
        return 'https://pre-account.tencent.com';
      default:
        return 'https://www.workbuddy.cn';
    }
  }

  /// 产品网关 endpoint（cli/product.json endpoint 字段）。
  /// 桌面认证接口（device/auth/code、auth/state、token、handoff）走此 host + /v2/plugin。
  /// 实测 www.workbuddy.cn/v2/plugin/auth/state → 200；api.account.tencent.com 同路径 → 404。
  String get endpoint {
    switch (env) {
      case AppEnv.international:
        return 'https://www.codebuddy.ai';
      case AppEnv.pre:
        return 'https://staging.workbuddy.cn';
      default:
        return 'https://www.workbuddy.cn';
    }
  }

  String get label {
    switch (env) {
      case AppEnv.international:
        return 'international';
      case AppEnv.pre:
        return 'pre';
      default:
        return 'prod';
    }
  }
}
