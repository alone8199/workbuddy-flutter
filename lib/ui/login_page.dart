import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/auth.dart';
import '../auth/auth_repository.dart';
import '../auth/login_controller.dart';
import '../auth/login_events.dart';
import '../auth/login_state_machine.dart';
import '../auth/login_methods/passwordless_login.dart';
import '../auth/login_methods/device_code_login.dart';
import '../auth/login_methods/webview_oauth_login.dart';

/// 登录页主容器。布局/配色参照登录页报告（TDesign 蓝主题，卡片居中，
/// 主方式 + "更多方式" tab/网格），不自行发挥配色与字号。
class LoginPage extends StatefulWidget {
  final AuthRepository repo;
  final void Function(AuthTokens tokens) onSuccess;
  const LoginPage({super.key, required this.repo, required this.onSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  LoginMethod _current = LoginMethod.phone;
  LoginController? _controller;
  final TextEditingController _account = TextEditingController();
  final TextEditingController _code = TextEditingController();

  // 登录页样式常量（贴合原 TDesign 主蓝 #0052D9，圆角 6，正文 14）
  static const Color _primary = Color(0xFF0052D9);
  static const double _radius = 6.0;

  @override
  void initState() {
    super.initState();
    _select(LoginMethod.phone);
  }

  void _select(LoginMethod method) {
    _controller?.dispose();
    setState(() {
      _current = method;
      switch (method) {
        case LoginMethod.phone:
        case LoginMethod.email:
          _controller = PasswordlessLoginController(
            target: method,
            repo: widget.repo,
          );
          break;
        case LoginMethod.deviceCode:
          _controller = DeviceCodeLoginController(repo: widget.repo);
          break;
        default:
          _controller = WebViewOAuthLoginController(
            target: method,
            repo: widget.repo,
          );
      }
    });
    _controller!.addListener(_onControllerChanged);
    _controller!.dispatch(LoginStart(method));
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final effects = _controller!.consumeEffects();
    for (final e in effects) {
      if (e is EffectNavigateHome) {
        widget.onSuccess(e.tokens);
      } else if (e is EffectShowMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } else if (e is EffectStartCountdown) {
        // 倒计时由 controller 内部 UI state 驱动按钮禁用。
      } else if (e is EffectOpenWebView) {
        // WebView 容器：端点未坐实（iOA/SSO/华硕）时 controller 已给出提示。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('需在 WebView2 中打开：${e.url}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: AnimatedBuilder(
              animation: _controller!,
              builder: (context, _) => _buildCard(_controller!.state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(LoginUiState st) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '登录 WorkBuddy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildMethodTabs(),
            const SizedBox(height: 20),
            _buildMethodBody(st),
            if (st.message != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                st.message!,
                style: TextStyle(
                  fontSize: 12,
                  color: st.phase == LoginPhase.failed ? Colors.red : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMethodTabs() {
    // 主方式 tab：手机号 / 邮箱 / 二维码；更多方式以 Wrap 提供。
    final methods = <LoginMethod>[
      LoginMethod.phone,
      LoginMethod.email,
      LoginMethod.deviceCode,
    ];
    return Row(
      children: methods.map((m) {
        final selected = _current == m;
        return Expanded(
          child: GestureDetector(
            onTap: () => _select(m),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? _primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                _label(m),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? _primary : Colors.grey[700],
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMethodBody(LoginUiState st) {
    switch (_current) {
      case LoginMethod.phone:
      case LoginMethod.email:
        return _buildPasswordless(st);
      case LoginMethod.deviceCode:
        return _buildQr(st);
      default:
        return _buildMoreMethods();
    }
  }

  Widget _buildPasswordless(LoginUiState st) {
    final isPhone = _current == LoginMethod.phone;
    return Column(
      children: <Widget>[
        TextField(
          controller: _account,
          decoration: InputDecoration(
            labelText: isPhone ? '手机号' : '邮箱',
            border: const OutlineInputBorder(),
            prefixText: isPhone ? '+86 ' : null,
          ),
          keyboardType: isPhone ? TextInputType.phone : TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: '验证码',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _primary),
              onPressed: st.countdown > 0
                  ? null
                  : () => _controller!.dispatch(LoginSendCode(_account.text.trim())),
              child: Text(st.countdown > 0 ? '${st.countdown}s 后重发' : '获取验证码'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            onPressed: st.loading
                ? null
                : () => _controller!.dispatch(LoginSubmitCode(_code.text.trim())),
            child: const Text('登录'),
          ),
        ),
      ],
    );
  }

  Widget _buildQr(LoginUiState st) {
    final qr = st.qrContent;
    return Column(
      children: <Widget>[
        if (qr != null)
          QrImageView(data: qr, version: QrVersions.auto, size: 180)
        else
          Container(
            height: 180,
            alignment: Alignment.center,
            color: Colors.grey[100],
            child: const Text('二维码加载中…'),
          ),
        const SizedBox(height: 12),
        if (st.phase == LoginPhase.failed || st.qrContent == null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            onPressed: () => _controller!.dispatch(LoginRetry()),
            child: const Text('刷新二维码'),
          ),
      ],
    );
  }

  Widget _buildMoreMethods() {
    // "更多方式"：微信/QQ/企微/iOA/SSO/华硕，与主方式同一入口组。
    final more = <LoginMethod>[
      LoginMethod.wechat,
      LoginMethod.qq,
      LoginMethod.wecom,
      LoginMethod.ioa,
      LoginMethod.sso,
      LoginMethod.asus,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: more.map((m) {
        return OutlinedButton(
          onPressed: () => _select(m),
          child: Text(_label(m)),
        );
      }).toList(),
    );
  }

  String _label(LoginMethod m) {
    switch (m) {
      case LoginMethod.phone:
        return '手机号';
      case LoginMethod.email:
        return '邮箱';
      case LoginMethod.deviceCode:
        return '二维码';
      case LoginMethod.wechat:
        return '微信';
      case LoginMethod.qq:
        return 'QQ';
      case LoginMethod.wecom:
        return '企业微信';
      case LoginMethod.ioa:
        return 'iOA';
      case LoginMethod.sso:
        return 'SSO';
      case LoginMethod.asus:
        return '华硕账号';
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _account.dispose();
    _code.dispose();
    super.dispose();
  }
}
