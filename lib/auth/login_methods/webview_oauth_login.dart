import '../../models/auth.dart';
import '../auth_repository.dart';
import '../login_state_machine.dart';
import '../login_controller.dart';
import '../login_events.dart';
import 'base_login.dart';

/// 微信/QQ/企微/iOA/SSO/华硕 6 种 WebView 登录共用控制器（方式 3-8）。
/// 流程：加载远端授权页 → 拦截回调路由拿 code/ticket → state 轮询或 handoff 换 token。
/// TODO(dynamic-capture): 各方式授权 URL / 回调路由 / IdP 端点多数未坐实：
///  - 微信：wechat-url 已确认；QQ：social/qq/login 已确认；
///  - 企微：open.weixin.qq.com + ww_device_nonce 已知，AIBot/ServiceApp/CorpApp 子模式细节待确认；
///  - iOA / SSO / 华硕：入口与 IdP 端点需抓包。
/// 未坐实的 URL 不猜值，emit EffectOpenWebView 时由 UI 用占位提示 + 卡点清单。
class WebViewOAuthLoginController extends LoginController {
  final LoginMethod target;
  final AuthRepository repo;

  /// 各方式授权 URL 构造（已坐实项填真实路径，未坐实返回 null）。
  static final Map<LoginMethod, String Function(String origin)> _urlBuilders =
      <LoginMethod, String Function(String origin)>{
    LoginMethod.wechat: (origin) =>
        '$origin/auth/realms/copilot/console/auth/wechat-url'
        '?client_id=login&response_type=code&self_redirect=true'
        '&kc_idp_hint=weixinwebchat&prompt=login&redirect_uri=',
    LoginMethod.qq: (origin) => '$origin/authz/v1/authn/social/qq/login',
    LoginMethod.wecom: (origin) =>
        'https://open.weixin.qq.com/connect/oauth2/authorize?appid=ww37a50841f065eb9c',
    // iOA / SSO / 华硕：静态未坐实，不猜 URL。
  };

  final Set<String> callbackPaths;

  WebViewOAuthLoginController({
    required this.target,
    required this.repo,
    String websiteOrigin = 'https://www.workbuddy.cn',
  })  : callbackPaths = _callbackPaths(target),
        super(target);

  static Set<String> _callbackPaths(LoginMethod m) {
    switch (m) {
      case LoginMethod.wechat:
        return const <String>{'/login/oneid-callback', '/callback'};
      case LoginMethod.qq:
        return const <String>{'/callback', '/authz/v1/authn/social/qq/callback'};
      case LoginMethod.wecom:
        return const <String>{'/login/wecom-oauth-callback'};
      case LoginMethod.ioa:
        return const <String>{'/ioa-callback'};
      default:
        return const <String>{'/callback'};
    }
  }

  @override
  void handle(LoginEvent event) {
    if (event is LoginStart) {
      _start();
    } else if (event is LoginCallbackReceived) {
      _exchange(event.codeOrTicket);
    } else if (event is LoginRetry) {
      _start();
    } else if (event is LoginCancel) {
      go(LoginPhase.idle);
    }
  }

  void _start() {
    initMachine();
    go(LoginPhase.pendingInput);
    final builder = _urlBuilders[target];
    if (builder == null) {
      // URL 未坐实：明确提示，不编造地址（卡点清单已列）。
      fail('${target.wireName} 登录端点需动态抓包确认，当前无法构造授权地址');
      return;
    }
    final url = builder('https://www.workbuddy.cn');
    setState(state.copyWith(message: '正在加载 ${target.wireName} 授权页…'));
    emit(EffectOpenWebView(url, callbackPaths));
    go(LoginPhase.submitted);
  }

  Future<void> _exchange(String codeOrTicket) async {
    go(LoginPhase.awaitingCallback);
    go(LoginPhase.exchangingToken);
    setState(state.copyWith(loading: true, codeOrTicket: codeOrTicket));
    try {
      // code/ticket → token：handoff（一次性码）或 finalize（ticket）。
      final tokens = await repo.handoff(codeOrTicket);
      succeed(tokens);
    } catch (_) {
      fail('换取登录凭证失败，请重试');
    }
  }
}

/// 策略适配器（保留旧抽象）。
class WebViewOAuthLogin implements LoginStrategy {
  final LoginMethod target;
  WebViewOAuthLogin(this.target);

  @override
  LoginMethod get method => target;

  @override
  bool get needsWebView => true;

  @override
  Future<void> start(LoginStateMachine machine) async {
    // 控制器驱动流程，此适配器仅保留入口元信息。
  }
}
