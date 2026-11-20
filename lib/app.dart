import 'package:flutter/material.dart';

import 'models/auth.dart';
import 'auth/token_manager.dart';
import 'auth/auth_repository.dart';
import 'auth/post_login_checker.dart';
import 'network/client.dart';
import 'ui/shell.dart';
import 'ui/login_page.dart';

/// 应用根 Widget：未登录进登录页，登录成功后进主壳；401 刷新失败踢回登录。
class WorkbuddyApp extends StatefulWidget {
  final TokenManager tokenManager;
  final AuthRepository authRepository;
  final NetworkClient network;
  const WorkbuddyApp({
    super.key,
    required this.tokenManager,
    required this.authRepository,
    required this.network,
  });

  @override
  State<WorkbuddyApp> createState() => _WorkbuddyAppState();
}

class _WorkbuddyAppState extends State<WorkbuddyApp> {
  late bool _loggedIn = widget.tokenManager.isLoggedIn;

  @override
  void initState() {
    super.initState();
    widget.tokenManager.onAuthExpired = () {
      if (mounted) setState(() => _loggedIn = false);
    };
  }

  void _onLoginSuccess(AuthTokens tokens) async {
    await widget.tokenManager.save(tokens);
    if (mounted) setState(() => _loggedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0052D9)),
      home: _loggedIn
          ? AppShell(tokenManager: widget.tokenManager, network: widget.network)
          : LoginPage(
              repo: widget.authRepository,
              postLoginChecker: PhoneBindingChecker(
                repo: widget.authRepository,
                // 绑定接口未坐实前保守放行 unknown；明确 unbound 仍会拦截。
                blockOnUnknown: false,
              ),
              onSuccess: _onLoginSuccess,
            ),
    );
  }
}
