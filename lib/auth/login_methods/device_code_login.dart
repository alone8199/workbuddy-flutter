import 'dart:async';

import '../../models/auth.dart';
import '../../util/app_logger.dart';
import '../auth_repository.dart';
import '../post_login_checker.dart';
import '../login_state_machine.dart';
import '../login_controller.dart';
import '../login_events.dart';
import 'base_login.dart';

/// 浏览器直开登录 / 设备码轮询（客户端侧纯请求）。
/// 流程：auth/state 拿 authUrl+state → 用系统默认浏览器打开 authUrl → 按间隔轮询 token
/// → 处理待登录/已确认/已过期/失败，过期可刷新；拿到 token 后跑后置绑定校验。
/// 说明：不用二维码渲染、不接收任何客户端回调（无自定义 scheme / 本地回调服务），
/// "登录完成"完全靠轮询服务端 state 感知，因此不存在唤起原版应用的问题。
/// TODO(dynamic-capture): expiresIn 单位（秒/毫秒）未定，这里按秒处理（报告基线）。
class DeviceCodeLoginController extends LoginController {
  final AuthRepository repo;
  final String websiteOrigin;
  final PostLoginChecker postLoginChecker;
  Timer? _pollTimer;
  static const int _pollIntervalMs = 2000;
  DateTime? _deadline;

  DeviceCodeLoginController({
    required this.repo,
    required this.postLoginChecker,
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
    final log = AppLogger.instance;
    initMachine();
    go(LoginPhase.pendingInput);
    setState(state.copyWith(loading: true, message: '正在获取登录二维码…'));

    // 主路径：auth/state 公开流程（实测 www.workbuddy.cn/v2/plugin/auth/state → 200，
    // 返回 {state, authUrl}，全公开无需网关鉴权）。二维码内容=authUrl，轮询 key=state。
    try {
      log.i('QR_LOGIN', '获取登录二维码：POST auth/state?platform=workbuddy');
      final s = await repo.authState('workbuddy');
      log.i('QR_LOGIN', 'auth/state 返回: ${AppLogger.truncate(s)}');
      final authUrl = s['authUrl'] as String?;
      final pollKey = s['state'] as String?;
      if (authUrl != null && authUrl.isNotEmpty && pollKey != null) {
        _deadline = DateTime.now().add(const Duration(minutes: 5));
        log.i('QR_LOGIN', '二维码已生成(auth/state), state=${AppLogger.mask(pollKey)} url=$authUrl');
        _applyQr(authUrl, pollKey);
        return;
      }
      log.w('QR_LOGIN', 'auth/state 缺少 authUrl/state，回退 device/auth/code');
    } catch (e, st) {
      log.w('QR_LOGIN', 'auth/state 失败，回退 device/auth/code: $e', e, st);
    }

    // 回退路径：device/auth/code（POST /v2/plugin/device/auth/code）。
    // 实测该端点在正确 host 上返回 401（网关鉴权），静态未坐实所需凭据，可能失败。
    try {
      log.i('QR_LOGIN', '回退：POST deviceAuthCode()');
      final resp = await repo.deviceAuthCode();
      log.i('QR_LOGIN', 'deviceAuthCode 返回: ${AppLogger.truncate(resp)}');
      final code = resp['deviceCode'] as String?;
      if (code == null) {
        log.w('QR_LOGIN', '响应缺少 deviceCode 字段，原始响应=${AppLogger.truncate(resp)}');
        fail('获取二维码失败：服务端未返回 deviceCode（详见日志）');
        return;
      }
      final qr = '$websiteOrigin/console/client-login?code=$code&target=';
      final rawExpiry = resp['expiresIn'] ?? resp['expires_in'];
      final seconds = rawExpiry is num ? rawExpiry.toInt() : 300;
      _deadline = DateTime.now().add(Duration(seconds: seconds));
      log.i('QR_LOGIN', '二维码已生成(deviceCode), deviceCode=${AppLogger.mask(code)}, 有效期=${seconds}s');
      _applyQr(qr, code);
    } catch (e, st) {
      // 不再吞异常：完整打印类型/堆栈，UI 提示带简短原因。
      log.e('QR_LOGIN', '获取二维码失败: $e', e, st);
      fail('网络异常，二维码获取失败（${_shortReason(e)}）');
    }
  }

  /// 把异常压成一句人话，便于 UI 直接看到失败原因。
  String _shortReason(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Connection refused')) {
      return '无法连接服务端';
    }
    if (s.contains('TimeoutException') || s.contains('timeout')) {
      return '请求超时';
    }
    if (s.contains('404')) return '接口 404（端点未开放）';
    if (s.contains('403')) return '403 被拒绝';
    if (s.contains('500') || s.contains('502') || s.contains('503')) {
      return '服务端 5xx';
    }
    // 返回前 60 字符，避免撑破卡片。
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  void _applyQr(String qr, String deviceCode) {
    go(LoginPhase.submitted);
    go(LoginPhase.awaitingCallback);
    setState(state.copyWith(
      loading: false,
      qrContent: qr,
      codeOrTicket: deviceCode,
      message: '已打开浏览器，请在网页完成登录',
      pollAttempt: 0,
    ));
    // 不再渲染二维码：拿到 authUrl 直接让 UI 用系统默认浏览器打开。
    // 轮询仍用 state(deviceCode) 感知登录完成，全程无需任何客户端回调/scheme 唤起。
    emit(EffectOpenBrowser(qr));
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
    final log = AppLogger.instance;
    final deviceCode = state.codeOrTicket;
    if (deviceCode == null) return;
    try {
      // state 轮询：报告为 GET /v2{prefix}/auth/token?state=；这里用 deviceCode 作 state。
      final tokens = await repo.pollToken(deviceCode);
      if (tokens != null) {
        log.i('QR_LOGIN', '轮询成功，拿到 token，停止轮询，进入回调校验');
        _pollTimer?.cancel();
        go(LoginPhase.exchangingToken);
        await _runPostLoginCheck(tokens);
        return;
      }
      final attempt = state.pollAttempt + 1;
      log.d('QR_LOGIN', '轮询第 $attempt 次：待确认（token=null，通常=authorization_pending）');
      setState(state.copyWith(
        pollAttempt: attempt,
        message: '等待网页登录完成…（第 $attempt 次轮询）',
      ));
    } catch (e, st) {
      // 轮询网络抖动不终止，继续下一 tick，但完整记录异常。
      log.w('QR_LOGIN', '轮询网络异常，本轮忽略继续: $e', e, st);
      setState(state.copyWith(message: '网络波动，重试轮询中…'));
    }
  }

  /// 扫码拿到 token 后的回调校验：未绑定手机号则拦截，引导去网页绑定后重新扫码。
  Future<void> _runPostLoginCheck(AuthTokens tokens) async {
    final log = AppLogger.instance;
    setState(state.copyWith(loading: true, message: '正在校验账号信息…'));
    try {
      final outcome = await postLoginChecker.check(tokens);
      if (outcome is PostLoginAllowed) {
        log.i('QR_LOGIN', '回调校验通过，登录成功');
        succeed(tokens);
      } else if (outcome is PostLoginBlocked) {
        log.w('QR_LOGIN',
            '回调校验拦截：状态=${outcome.binding.statusName}，账号未绑定手机号');
        // 拦截：停轮询、清空二维码与 token 上下文，停留在 awaitingCallback 之前的阶段，
        // 让用户可以在 UI 引导下去网页绑定后点击重新扫码。
        _pollTimer?.cancel();
        go(LoginPhase.failed);
        setState(state.copyWith(
          loading: false,
          qrContent: null,
          codeOrTicket: null,
          clearQr: true,
          message: outcome.message,
        ));
        emit(EffectBindPhoneRequired(
          outcome.bindUrl,
          outcome.message,
          outcome.binding.status,
        ));
      }
    } catch (e, st) {
      // 校验器自身异常：保守放行，避免把已登录用户挡在门外（记录完整日志）。
      log.e('QR_LOGIN', '回调校验异常，保守放行: $e', e, st);
      succeed(tokens);
    }
  }

  void _expire() {
    AppLogger.instance.i('QR_LOGIN', '二维码过期，停止轮询，等待刷新');
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
