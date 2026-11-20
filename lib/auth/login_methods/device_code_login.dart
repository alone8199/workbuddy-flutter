import 'dart:async';

import '../../models/auth.dart';
import '../auth_repository.dart';
import '../login_state_machine.dart';
import '../login_controller.dart';
import '../login_events.dart';
import 'base_login.dart';

/// 扫码确认 / 设备登录确认（方式 9，客户端侧纯请求）。
/// 流程：生成 deviceCode → qr_flutter 本地渲染二维码 → 按间隔轮询 token →
/// 处理待扫/已扫/已确认/已过期/失败，过期可刷新。
/// TODO(dynamic-capture): expiresIn 单位（秒/毫秒）未定，这里按秒处理（报告基线）。
class DeviceCodeLoginController extends LoginController {
  final AuthRepository repo;
  final String websiteOrigin;
  Timer? _pollTimer;
  static const int _pollIntervalMs = 2000;
  DateTime? _deadline;

  DeviceCodeLoginController({
    required this.repo,
    this.websiteOrigin = 'https://www.workbuddy.cn',
  }) : super(LoginMethod.deviceCode);

  @override
  void handle(LoginEvent event) {
    if (event is LoginStart) {
      _start();
    } else if (event is LoginQrRefreshed) {
      _applyQr(event.qrContent, event.deviceCode);
    } else if (event is LoginPollingTick) {
      _poll();
    } else if (event is LoginPollingExpired) {
      _expire();
    } else if (event is LoginRetry) {
      _start();
    } else if (event is LoginCancel) {
      _cancel();
    }
  }

  Future<void> _start() async {
    initMachine();
    go(LoginPhase.pendingInput);
    setState(state.copyWith(loading: true, message: '正在获取登录二维码…'));
    try {
      final resp = await repo.deviceAuthCode();
      final code = resp['deviceCode'] as String?;
      if (code == null) {
        fail('获取二维码失败，请重试');
        return;
      }
      // 二维码内容：${websiteOrigin}/console/client-login?code=${code}&target=
      final qr = '$websiteOrigin/console/client-login?code=$code&target=';
      final rawExpiry = resp['expiresIn'] ?? resp['expires_in'];
      final seconds = rawExpiry is num ? rawExpiry.toInt() : 300; // 5 分钟基线
      _deadline = DateTime.now().add(Duration(seconds: seconds));
      _applyQr(qr, code);
    } catch (_) {
      fail('网络异常，二维码获取失败');
    }
  }

  void _applyQr(String qr, String deviceCode) {
    go(LoginPhase.submitted);
    go(LoginPhase.awaitingCallback);
    setState(state.copyWith(
      loading: false,
      qrContent: qr,
      codeOrTicket: deviceCode,
      message: '请用手机扫码并在浏览器完成登录',
      pollAttempt: 0,
    ));
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: _pollIntervalMs), (_) {
      if (_deadline != null && DateTime.now().isAfter(_deadline!)) {
        _expire();
        return;
      }
      _poll();
    });
  }

  Future<void> _poll() async {
    final deviceCode = state.codeOrTicket;
    if (deviceCode == null) return;
    try {
      // state 轮询：报告为 GET /v2{prefix}/auth/token?state=；这里用 deviceCode 作 state。
      final tokens = await repo.pollToken(deviceCode);
      if (tokens != null) {
        _pollTimer?.cancel();
        go(LoginPhase.exchangingToken);
        succeed(tokens);
        return;
      }
      setState(state.copyWith(
        pollAttempt: state.pollAttempt + 1,
        message: '等待扫码确认…（第 ${state.pollAttempt + 1} 次轮询）',
      ));
    } catch (_) {
      // 轮询网络抖动不终止，继续下一 tick。
      setState(state.copyWith(message: '网络波动，重试轮询中…'));
    }
  }

  void _expire() {
    _pollTimer?.cancel();
    setState(state.copyWith(
      message: '二维码已过期，请点击刷新',
      qrContent: null,
      clearQr: true,
    ));
    emit(EffectRefreshQr());
    emit(EffectShowMessage('二维码已过期', isError: true));
  }

  void _cancel() {
    _pollTimer?.cancel();
    go(LoginPhase.idle);
    setState(state.copyWith(qrContent: null, clearQr: true, message: null));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// 策略适配器（保留旧抽象）。
class DeviceCodeLogin implements LoginStrategy {
  final AuthRepository repo;
  DeviceCodeLogin(this.repo);

  @override
  LoginMethod get method => LoginMethod.deviceCode;

  @override
  bool get needsWebView => false;

  @override
  Future<void> start(LoginStateMachine machine) async {
    // 控制器驱动流程，此适配器仅保留入口元信息。
  }
}
