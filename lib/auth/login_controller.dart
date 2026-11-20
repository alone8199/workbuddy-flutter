import 'package:flutter/foundation.dart';

import '../models/auth.dart';
import 'login_state_machine.dart';
import 'login_events.dart';

/// 每种登录方式的状态管理基类（ChangeNotifier）。
/// 状态（state）/ 事件（dispatch）/ 副作用（effects）三者分离：
///  - 子类实现 [_handle] 处理事件、改变 state；
///  - 需要一次性 UI 动作时调用 [emit]；
///  - UI 通过 [consumeEffects] 取走副作用（消费即清空）。
abstract class LoginController extends ChangeNotifier {
  final LoginMethod method;
  final LoginStateMachine _machine = LoginStateMachine();
  final List<LoginEffect> _effects = <LoginEffect>[];

  LoginUiState _ui = const LoginUiState(phase: LoginPhase.idle);

  LoginController(this.method);

  LoginUiState get state => _ui;
  LoginPhase get phase => _ui.phase;
  bool get isTerminal =>
      phase == LoginPhase.authenticated || phase == LoginPhase.failed;

  /// 统一事件入口：子类可覆写做前置处理，最终走 [_handle]。
  void dispatch(LoginEvent event) {
    _handle(event);
  }

  @protected
  void handle(LoginEvent event);

  void _handle(LoginEvent event) => handle(event);

  /// 更新 UI 状态并通知监听器。
  @protected
  void setState(LoginUiState newState) {
    _ui = newState;
    notifyListeners();
  }

  /// 发出一次性副作用，等待 UI 消费。
  @protected
  void emit(LoginEffect effect) {
    _effects.add(effect);
  }

  /// 取走并清空副作用队列。
  List<LoginEffect> consumeEffects() {
    if (_effects.isEmpty) return const <LoginEffect>[];
    final copy = List<LoginEffect>.from(_effects);
    _effects.clear();
    return copy;
  }

  /// 状态机迁移（带合法性校验）。
  @protected
  bool go(LoginPhase next) {
    final ok = _machine.transition(next);
    if (ok) {
      _ui = _ui.copyWith(phase: next);
      notifyListeners();
    }
    return ok;
  }

  @protected
  void initMachine() {
    _machine.setMethod(method);
  }

  /// 登录成功：迁移到 authenticated 并发出跳转副作用。
  @protected
  void succeed(AuthTokens tokens) {
    if (_machine.state.phase == LoginPhase.exchangingToken) {
      go(LoginPhase.authenticated);
    } else {
      _ui = _ui.copyWith(phase: LoginPhase.authenticated);
      notifyListeners();
    }
    emit(EffectNavigateHome(tokens));
  }

  /// 失败：迁移到 failed 并提示。
  @protected
  void fail(String message) {
    final cur = _machine.state.phase;
    if (cur != LoginPhase.failed) {
      // failed 可从多数阶段进入；若状态机拒绝，直接改 UI 状态保证提示可见。
      if (!_machine.transition(LoginPhase.failed)) {
        _ui = _ui.copyWith(phase: LoginPhase.failed);
      }
    }
    _ui = _ui.copyWith(message: message, loading: false);
    notifyListeners();
    emit(EffectShowMessage(message, isError: true));
  }

  @override
  void dispose() {
    _effects.clear();
    super.dispose();
  }
}
