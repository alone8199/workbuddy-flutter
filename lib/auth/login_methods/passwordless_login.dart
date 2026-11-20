import 'dart:async';

import '../../models/auth.dart';
import '../../network/api_error.dart';
import '../../util/app_logger.dart';
import '../auth_repository.dart';
import '../login_state_machine.dart';
import '../login_controller.dart';
import '../login_events.dart';
import 'base_login.dart';

/// 手机号 / 邮箱验证码登录控制器（方式 1、2，纯请求 C）。
/// 事件：发码（含倒计时）、提交验证码、失败码逐个处理、重试。
/// 倒计时从响应 cooldown 或默认 60s（静态未确认间隔，取报告"今日次数上限/60s"基线）。
class PasswordlessLoginController extends LoginController {
  final LoginMethod target; // phone / email
  final AuthRepository repo;
  Timer? _countdownTimer;

  PasswordlessLoginController({
    required this.target,
    required this.repo,
  }) : super(target);

  @override
  void handle(LoginEvent event) {
    if (event is LoginStart) {
      initMachine();
      go(LoginPhase.pendingInput);
      setState(state.copyWith(message: '请输入${target == LoginMethod.phone ? '手机号' : '邮箱'}验证码'));
    } else if (event is LoginSendCode) {
      _sendCode(event.account);
    } else if (event is LoginSubmitCode) {
      _submitCode(event.code);
    } else if (event is LoginRetry) {
      dispatch(LoginStart(target));
    } else if (event is LoginCancel) {
      _cancel();
    }
  }

  Future<void> _sendCode(String account) async {
    final log = AppLogger.instance;
    log.i('CODE_LOGIN', '发码 target=${target.name} account=${AppLogger.mask(account)}');
    setState(state.copyWith(loading: true));
    emit(EffectShowMessage('正在发送验证码…'));
    try {
      final resp = await repo.sendCode(target, account);
      log.i('CODE_LOGIN', '发码响应: ${AppLogger.truncate(resp)}');
      // 倒计时：优先用响应里的 interval/cooldown（秒），否则 60s。
      final dynamic interval = resp['interval'] ?? resp['cooldown'] ?? resp['resendInterval'];
      final seconds = interval is num ? interval.toInt() : 60;
      go(LoginPhase.submitted);
      setState(state.copyWith(loading: false, message: '验证码已发送'));
      emit(EffectStartCountdown(seconds));
      _startCountdown(seconds);
    } on ApiFailure catch (f) {
      log.w('CODE_LOGIN', '发码失败 ApiFailure: ${f.apiError}', f);
      fail(f.apiError.message);
    } catch (e, st) {
      log.e('CODE_LOGIN', '发码网络异常: $e', e, st);
      fail('网络异常，发送失败，请重试');
    }
  }

  Future<void> _submitCode(String code) async {
    setState(state.copyWith(loading: true));
    try {
      final tokens = await repo.verifyCode(target, code);
      if (tokens == null) {
        go(LoginPhase.exchangingToken);
        setState(state.copyWith(loading: false));
        emit(EffectShowMessage('登录已提交，正在换取凭证…'));
      } else {
        go(LoginPhase.exchangingToken);
        succeed(tokens);
      }
    } on ApiFailure catch (f) {
      AppLogger.instance.w('CODE_LOGIN', '验证失败 ApiFailure: ${f.apiError}', f);
      // 验证码错回 PendingInput 让用户重填，不直接终止流程。
      if (f.apiError.code == ApiErrorCode.invalidCaptcha) {
        setState(state.copyWith(loading: false, message: f.apiError.message));
        emit(EffectShowMessage(f.apiError.message, isError: true));
      } else {
        fail(f.apiError.message);
      }
    } catch (e, st) {
      AppLogger.instance.e('CODE_LOGIN', '验证网络异常: $e', e, st);
      fail('网络异常，验证失败，请重试');
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    int remain = seconds;
    setState(state.copyWith(countdown: remain));
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      remain--;
      setState(state.copyWith(countdown: remain > 0 ? remain : 0));
      if (remain <= 0) t.cancel();
    });
  }

  void _cancel() {
    _countdownTimer?.cancel();
    go(LoginPhase.idle);
    setState(state.copyWith(countdown: 0, message: null));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}

/// 策略适配器：保留旧的 LoginStrategy 抽象实现，供 UI 选择入口使用。
class PasswordlessLogin implements LoginStrategy {
  final LoginMethod target;
  PasswordlessLogin(this.target);

  @override
  LoginMethod get method => target;

  @override
  bool get needsWebView => false;

  @override
  Future<void> start(LoginStateMachine machine) async {
    // 控制器驱动流程，此适配器仅保留入口元信息。
  }
}
