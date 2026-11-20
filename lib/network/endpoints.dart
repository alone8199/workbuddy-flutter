/// ACP 传输端点常量（相对路径，host 由 daemon 配置）。
class Endpoints {
  static const acp = '/acp';
  static const acpBootstrap = '/acp/bootstrap';
}

/// 环境域名基线与接口路径常量。数据源：route-BzScxxrM.js @1760807。
enum WorkbuddyEnv { prod, international, pre }

class EnvConfig {
  final WorkbuddyEnv env;
  const EnvConfig(this.env);

  String get api {
    switch (env) {
      case WorkbuddyEnv.international: return 'https://api.account.tencentid.com';
      case WorkbuddyEnv.pre: return 'https://api.pre-account.tencent.com';
      default: return 'https://api.account.tencent.com';
    }
  }

  String get oauth2 {
    switch (env) {
      case WorkbuddyEnv.international: return 'https://oauth2.account.tencentid.com';
      case WorkbuddyEnv.pre: return 'https://oauth2.pre-account.tencent.com';
      default: return 'https://oauth2.account.tencent.com';
    }
  }

  String get website => 'https://www.workbuddy.cn';

  /// 产品网关 endpoint（cli/product.json 的 endpoint 字段）。
  /// 桌面客户端认证接口（auth/state、device/auth/code、auth/token、handoff、refresh）
  /// 全部走这个 host + /v2{prefix} 前缀（prefix=/plugin，见 product.json authentication.prefixPath）。
  /// 实测：www.workbuddy.cn/v2/plugin/auth/state → 200；
  ///       api.account.tencent.com/v2/plugin/* → 404 Route Not Found（域名用错）。
  String get endpoint {
    switch (env) {
      case WorkbuddyEnv.international: return 'https://www.codebuddy.ai';
      case WorkbuddyEnv.pre: return 'https://staging.workbuddy.cn';
      default: return 'https://www.workbuddy.cn';
    }
  }

  /// 认证链路 prefix（cli/product.json authentication.attributes.prefixPath）。
  static const String prefix = '/plugin';

  // 桌面认证链路（cli / main）：endpoint + /v2{prefix}/...
  String authState(String platform) =>
      '$endpoint/v2$prefix/auth/state?platform=$platform';
  String authToken(String state) =>
      '$endpoint/v2$prefix/auth/token?state=$state';
  String get authRefresh => '$endpoint/v2$prefix/auth/token/refresh';
  String get authHandoff => '$endpoint/v2$prefix/auth/handoff/token';

  /// 设备码：源码路径为 /v2/plugin/device/auth/code（plugin 已含在路径里）。
  String get deviceAuthCode => '$endpoint/v2$prefix/device/auth/code';

  // 登录页 finalize（远端下发，走主站）。
  String get signinFinalize => '$website/signin/finalize';

  // ACP 传输端点（相对路径，host 由 daemon 配置，需动态确认）。
  static const acp = '/acp';
  static const acpBootstrap = '/acp/bootstrap';
}
