import 'dart:io';

import 'package:flutter/material.dart';

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

/// 用系统默认浏览器打开登录链接。
/// 项目是 Windows-only：windows 用 rundll32（对含 & ? 的 URL 不做 shell 解析，最稳），
/// 非 Windows（如 Linux 测试进程）只记日志、不真正拉起浏览器，避免测试误触。
Future<void> defaultUrlLauncher(String url) async {
  final log = AppLogger.instance;
  log.i('LOGIN_UI', '打开默认浏览器: $url');
  try {
    if (Platform.isWindows) {
      await Process.run('rundll32', <String>[
        'url.dll,FileProtocolHandler',
        url,
      ]);
      log.i('LOGIN_UI', '已调用系统默认浏览器打开链接');
    } else {
      log.i('LOGIN_UI', '非 Windows 环境，仅记录链接不拉起浏览器');
    }
  } catch (e, st) {
    log.e('LOGIN_UI', '打开浏览器失败: $e', e, st);
  }
}

/// 登录页：仅"默认浏览器打开登录链接"一种方式（二维码入口已移除）。
/// 拿到 token 后回调校验手机号绑定；未绑定则展示"去网页绑定 → 重新登录"引导。
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
      } else if (e is EffectOpenBrowser) {
        // 拿到登录链接，直接用系统默认浏览器打开。
        unawaitedLaunch(e.url);
      } else if (e is EffectShowMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } else if (e is EffectRefreshQr) {
        _controller.dispatch(LoginRetry());
      }
    }
  }

  Future<void> unawaitedLaunch(String url) async {
    try {
      await widget.urlLauncher(url);
    } catch (e) {
      AppLogger.instance.e('LOGIN_UI', 'urlLauncher 抛错: $e');
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
          '浏览器登录，开启智能工作',
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
          _buildBrowserArea(st),
          const SizedBox(height: 20),
          _buildStatusHint(st),
        ],
      ),
    );
  }

  /// 浏览器登录引导区：大图标 + 说明 + 主按钮（重新打开浏览器）+ 登录链接。
  Widget _buildBrowserArea(LoginUiState st) {
    final url = st.qrContent;
    final failed = st.phase == LoginPhase.failed;
    final loading = url == null && !failed;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E8EF), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            loading ? Icons.hourglass_empty : Icons.open_in_browser,
            size: 44,
            color: failed ? Colors.redAccent : _primary,
          ),
          const SizedBox(height: 12),
          Text(
            failed
                ? (st.message ?? '获取登录链接失败')
                : loading
                    ? '正在获取登录链接…'
                    : '已为你打开默认浏览器',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: failed ? Colors.redAccent : _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '请在网页中完成登录，登录成功后本窗口会自动继续。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _subtle, height: 1.4),
          ),
          if (url != null && !failed) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE5E8EF)),
              ),
              child: Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _subtle),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: _outlineButton,
                onPressed: () => unawaitedLaunch(url),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('重新打开浏览器'),
              ),
            ),
          ],
        ],
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
      text = '点击下方按钮重新获取登录链接';
    } else if (waiting) {
      icon = Icons.public;
      iconColor = _primary;
      text = '正在等待网页登录完成…';
    } else {
      icon = Icons.hourglass_empty;
      iconColor = _subtle;
      text = st.message ?? '正在准备登录链接…';
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
            child: Text(
              st.message ?? '等待网页登录完成…',
              style: const TextStyle(fontSize: 12, color: _subtle),
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
            child: const Text('重新获取登录链接'),
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

  /// 未绑定手机号引导卡片：提示去网页绑定后重新登录。
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
            onPressed: () => unawaitedLaunch(info.bindUrl),
            child: const Text('前往网页绑定手机号'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: _outlineButton,
            onPressed: () {
              setState(() => _bindRequired = null);
              _controller.dispatch(LoginRetry());
            },
            child: const Text('绑定后重新登录'),
          ),
          const SizedBox(height: 14),
          const Text(
            '绑定完成后请回到这里重新登录。',
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
