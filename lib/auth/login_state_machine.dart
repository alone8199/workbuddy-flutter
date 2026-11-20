import '../models/auth.dart';

/// 登录流程阶段（设计文档 3.2 统一状态机）。
enum LoginPhase {
  idle,
  pendingInput,
  submitted,
  awaitingCallback,
  exchangingToken,
  authenticated,
  failed,
}

/// 每种登录方式的统一状态机上下文。
class LoginState {
  final LoginMethod method;
  final LoginPhase phase;
  final String? message;
  final String? codeOrTicket; // 回调拿到的 code / ticket / deviceCode

  const LoginState({
    required this.method,
    required this.phase,
    this.message,
    this.codeOrTicket,
  });

  LoginState copyWith({
    LoginPhase? phase,
    String? message,
    String? codeOrTicket,
  }) =>
      LoginState(
        method: method,
        phase: phase ?? this.phase,
        message: message ?? this.message,
        codeOrTicket: codeOrTicket ?? this.codeOrTicket,
      );
}

/// 状态机骨架：定义合法迁移，具体请求由各 strategy 实现。
class LoginStateMachine {
  LoginState _state = const LoginState(
    method: LoginMethod.deviceCode,
    phase: LoginPhase.idle,
  );

  LoginState get state => _state;

  /// 迁移校验：失败返回 false（不修改状态）。
  bool transition(LoginPhase next) {
    final allowed = _allowed(_state.phase, next);
    if (!allowed) return false;
    _state = _state.copyWith(phase: next);
    return true;
  }

  bool _allowed(LoginPhase from, LoginPhase to) {
    switch (from) {
      case LoginPhase.idle:
        return to == LoginPhase.pendingInput;
      case LoginPhase.pendingInput:
        return to == LoginPhase.submitted || to == LoginPhase.failed || to == LoginPhase.idle;
      case LoginPhase.submitted:
        return to == LoginPhase.awaitingCallback || to == LoginPhase.failed;
      case LoginPhase.awaitingCallback:
        return to == LoginPhase.exchangingToken ||
            to == LoginPhase.failed ||
            to == LoginPhase.idle;
      case LoginPhase.exchangingToken:
        return to == LoginPhase.authenticated || to == LoginPhase.failed;
      case LoginPhase.failed:
        return to == LoginPhase.idle || to == LoginPhase.pendingInput;
      case LoginPhase.authenticated:
        return false;
    }
  }

  void setMethod(LoginMethod m) {
    _state = LoginState(method: m, phase: LoginPhase.idle);
  }

  void setCode(String code) {
    _state = _state.copyWith(codeOrTicket: code);
  }
}
