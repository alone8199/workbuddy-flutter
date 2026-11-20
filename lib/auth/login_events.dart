import '../models/auth.dart';
import 'login_state_machine.dart';

/// 登录模块事件/副作用模型（状态管理分离：State / Event / Effect）。
/// - LoginState（login_state_machine.dart）：当前状态快照
/// - LoginEvent：驱动状态机的输入事件
/// - LoginEffect：一次性副作用（跳转、提示、拉起 WebView），由 UI 消费

/// 驱动状态机的事件。
abstract class LoginEvent {}

class LoginStart extends LoginEvent {
  final LoginMethod method;
  LoginStart(this.method);
}

class LoginSubmitCode extends LoginEvent {
  final String code;
  LoginSubmitCode(this.code);
}

class LoginSendCode extends LoginEvent {
  final String account; // 手机号或邮箱
  LoginSendCode(this.account);
}

class LoginQrRefreshed extends LoginEvent {
  final String deviceCode;
  final String qrContent;
  LoginQrRefreshed(this.deviceCode, this.qrContent);
}

class LoginCallbackReceived extends LoginEvent {
  final String codeOrTicket;
  LoginCallbackReceived(this.codeOrTicket);
}

class LoginPollingTick extends LoginEvent {}

class LoginPollingExpired extends LoginEvent {}

class LoginRetry extends LoginEvent {}

class LoginCancel extends LoginEvent {}

/// 一次性副作用：UI 层监听并执行。
abstract class LoginEffect {}

class EffectShowMessage extends LoginEffect {
  final String message;
  final bool isError;
  EffectShowMessage(this.message, {this.isError = false});
}

class EffectOpenWebView extends LoginEffect {
  final String url;
  final Set<String> callbackPaths;
  EffectOpenWebView(this.url, this.callbackPaths);
}

class EffectNavigateHome extends LoginEffect {
  final AuthTokens tokens;
  EffectNavigateHome(this.tokens);
}

class EffectStartCountdown extends LoginEffect {
  final int seconds;
  EffectStartCountdown(this.seconds);
}

class EffectRefreshQr extends LoginEffect {}

/// 倒计时/轮询等派生 UI 状态（与 LoginPhase 正交）。
class LoginUiState {
  final LoginPhase phase;
  final String? message;
  final String? qrContent; // 二维码内容（qr_flutter 渲染）
  final String? codeOrTicket;
  final int countdown; // 发码倒计时（秒）
  final int pollAttempt; // 轮询次数
  final bool loading;

  const LoginUiState({
    required this.phase,
    this.message,
    this.qrContent,
    this.codeOrTicket,
    this.countdown = 0,
    this.pollAttempt = 0,
    this.loading = false,
  });

  LoginUiState copyWith({
    LoginPhase? phase,
    String? message,
    String? qrContent,
    String? codeOrTicket,
    int? countdown,
    int? pollAttempt,
    bool? loading,
    bool clearQr = false,
  }) {
    return LoginUiState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      qrContent: clearQr ? null : (qrContent ?? this.qrContent),
      codeOrTicket: codeOrTicket ?? this.codeOrTicket,
      countdown: countdown ?? this.countdown,
      pollAttempt: pollAttempt ?? this.pollAttempt,
      loading: loading ?? this.loading,
    );
  }
}
