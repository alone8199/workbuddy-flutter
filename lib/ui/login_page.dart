import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/auth.dart';
import '../models/phone_binding.dart';
import '../auth/auth_repository.dart';
import '../auth/login_controller.dart';
import '../auth/login_events.dart';
import '../auth/login_state_machine.dart';
import '../auth/login_methods/device_code_login.dart';
import '../auth/post_login_checker.dart';
import '../util/app_logger.dart';

/// 打开外部网页的回调（便于测试注入，默认实现见 [defaultUrlLauncher]）。
typedef UrlLauncher = Future<void> Function(String url);

Future<void> defaultUrlLauncher(String url) async {
  AppLogger.instance.i('LOGIN_UI', '请求打开外部网页: $url');
  // 桌面 Windows：由 url_launcher / 系统浏览器接管；此处仅记录，避免误触发沙箱内的网络栈。
  // 真实产物中由注入实现调用系统默认浏览器打开 [url]。
}

/// 登录页：仅二维码扫码登录（其余登录方式按需求移除）。
/// 扫码成功回调校验未绑定手机号时，展示"去网页绑定 → 重新扫码"引导。
class LoginPage extends StatefulWidget {
  final AuthRepository repo;
  final PostLoginChecker postLoginChecker;
  final void Function(AuthTokens tokens) onSuccess;
  final UrlLauncher urlLauncher;

  const LoginPage({
    super.key,
    required this.repo,
    required this.postLoginChecker,
    required this.onSuccess,
    this.urlLauncher = defaultUrlLauncher,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  late final LoginController _controller;
  late final AnimationController _pulse;

  // 未绑定手机号引导（由 EffectBindPhoneRequired 填充）。
  EffectBindPhoneRequired? _bindRequired;

  // 主题：贴近原版 TDesign 主蓝 #0052D9。
  static const Color _primary = Color(0xFF0052D9);
  static const Color _ink = Color(0xFF1D2129);
  static const Color _subtle = Color(0xFF86909C);
  static const double _radius = 16.0;

  ButtonStyle get _primaryButton => ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _primary.withOpacity(0.5),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  ButtonStyle get _outlineButton => OutlinedButton.styleFrom(
        foregroundColor: _primary,
        side: const BorderSide(color: _primary),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _controller = DeviceCodeLoginController(
      repo: widget.repo,
      postLoginChecker: widget.postLoginChecker,
    );
    _controller.addListener(_onControllerChanged);
    _controller.dispatch(LoginStart(LoginMethod.deviceCode));
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final effects = _controller.consumeEffects();
    for (final e in effects) {
      if (e is EffectNavigateHome) {
        widget.onSuccess(e.tokens);
      } else if (e is EffectBindPhoneRequired) {
        setState(() => _bindRequired = e);
      } else if (e is EffectShowMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } else if (e is EffectRefreshQr) {
        _controller.dispatch(LoginRetry());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFF2F6FF), Color(0xFFEAF0FB)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: SizedBox(
              width: 420,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    _bindRequired != null ? _buildBindCard() : _buildLoginCard(_controller.state),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 品牌头：图标 + 标题 + 副标题。
  Widget _buildBrand() {
    return Column(
      children: const <Widget>[
        CircleAvatar(
          radius: 30,
          backgroundColor: _primary,
          child: Icon(Icons.auto_awesome, color: Colors.white, size: 30),
        ),
        SizedBox(height: 14),
        Text(
          'WorkBuddy',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: _ink,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '扫码登录，开启智能工作',
          style: TextStyle(fontSize: 13, color: _subtle),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A0052D9),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
        child: child,
      ),
    );
  }

  Widget _buildLoginCard(LoginUiState st) {
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildBrand(),
          const SizedBox(height: 28),
          _buildQrArea(st),
          const SizedBox(height: 20),
          _buildStatusHint(st),
        ],
      ),
    );
  }

  Widget _buildQrArea(LoginUiState st) {
    final qr = st.qrContent;
    final failed = st.phase == LoginPhase.failed;

    Widget inner;
    if (qr != null) {
      inner = AbsorbPointer(
        child: QrImageView(
          data: qr,
          version: QrVersions.auto,
          size: 196,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: _ink,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: _ink,
          ),
        ),
      );
    } else if (failed) {
      inner = SizedBox(
        height: 196,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  st.message ?? '二维码获取失败',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      inner = const SizedBox(
        height: 196,
        child: Center(
          child: CircularProgressIndicator(color: _primary),
        ),
      );
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E8EF), width: 1),
        ),
        child: inner,
      ),
    );
  }

  Widget _buildStatusHint(LoginUiState st) {
    final failed = st.phase == LoginPhase.failed;
    final waiting = st.phase == LoginPhase.awaitingCallback;

    IconData icon;
    Color iconColor;
    String text;
    if (failed) {
      icon = Icons.refresh;
      iconColor = _primary;
      text = '点击重新获取二维码';
    } else if (waiting) {
      icon = Icons.qr_code_scanner;
      iconColor = _primary;
      text = '请使用手机扫码并在浏览器中完成登录';
    } else {
      icon = Icons.hourglass_empty;
      iconColor = _subtle;
      text = st.message ?? '正在准备二维码…';
    }

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: failed ? _primary : _subtle),
              ),
            ),
          ],
        ),
        if (waiting) ...<Widget>[
          const SizedBox(height: 6),
          FadeTransition(
            opacity: _pulse,
            child: const Text(
              '等待扫码确认…',
              style: TextStyle(fontSize: 12, color: _subtle),
            ),
          ),
        ],
        if (failed) ...<Widget>[
          const SizedBox(height: 14),
          ElevatedButton(
            style: _primaryButton,
            onPressed: () {
              setState(() => _bindRequired = null);
              _controller.dispatch(LoginRetry());
            },
            child: const Text('重新获取二维码'),
          ),
          const SizedBox(height: 10),
          const Text(
            '失败原因详见日志（用户目录 .workbuddy/logs/app.log）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: _subtle),
          ),
        ],
      ],
    );
  }

  /// 未绑定手机号引导卡片：提示去网页绑定后重新扫码。
  Widget _buildBindCard() {
    final info = _bindRequired!;
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 4),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.phone_disabled, size: 34, color: Color(0xFFD46B08)),
          ),
          const SizedBox(height: 18),
          const Text(
            '需要绑定手机号',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _ink),
          ),
          const SizedBox(height: 10),
          Text(
            info.message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF4E5969), height: 1.5),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '绑定状态：${_statusLabel(info.bindingStatus)}（${info.bindingStatus.name}）',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _subtle),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: _primaryButton,
            onPressed: () => widget.urlLauncher(info.bindUrl),
            child: const Text('前往网页绑定手机号'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: _outlineButton,
            onPressed: () {
              setState(() => _bindRequired = null);
              _controller.dispatch(LoginRetry());
            },
            child: const Text('绑定后重新扫码'),
          ),
          const SizedBox(height: 14),
          const Text(
            '绑定完成后请回到这里重新扫码登录。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _subtle),
          ),
        ],
      ),
    );
  }

  String _statusLabel(PhoneBindingStatus s) {
    switch (s) {
      case PhoneBindingStatus.unbound:
        return '未绑定';
      case PhoneBindingStatus.unknown:
        return '未能确认（接口待坐实）';
      case PhoneBindingStatus.bound:
        return '已绑定';
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }
}
