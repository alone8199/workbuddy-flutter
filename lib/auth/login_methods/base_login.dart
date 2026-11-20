import '../../models/auth.dart';
import '../login_state_machine.dart';

/// 登录策略抽象。纯请求方式实现 execute；WebView 方式由 UI 层驱动回调。
abstract class LoginStrategy {
  LoginMethod get method;
  bool get needsWebView;

  Future<void> start(LoginStateMachine machine);
}
