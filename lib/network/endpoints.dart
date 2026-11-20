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

  // 认证链路（cli / main）。prefixPath 需动态确认。
  String authState(String platform) => '$api/v2/auth/state?platform=$platform';
  String authToken(String state) => '$api/v2/auth/token?state=$state';
  String get authRefresh => '$api/v2/auth/token/refresh';
  String get authHandoff => '$api/v2/auth/handoff/token';
  String get deviceAuthCode => '$api/v2/plugin/device/auth/code';

  // 登录页 finalize（远端下发）。
  String get signinFinalize => '$website/signin/finalize';

  // ACP 传输端点（相对路径，host 由 daemon 配置，需动态确认）。
  static const acp = '/acp';
  static const acpBootstrap = '/acp/bootstrap';
}
