import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'network/env_config.dart';
import 'network/client.dart';
import 'auth/token_manager.dart';
import 'auth/auth_repository.dart';
import 'storage/secure_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = SecureStorage();
  final tokenManager = TokenManager(storage);
  await tokenManager.load();

  // 环境：默认 prod，可从 dart-define 覆盖（--dart-define=WB_ENV=pre）。
  const envName = String.fromEnvironment('WB_ENV', defaultValue: 'prod');
  final env = Environment.fromString(envName);

  late final AuthRepository authRepo;

  final network = NetworkClient(
    appVersion: '5.11.3',
    language: 'zh-CN,zh;q=0.9',
    environment: env,
    deviceId: null, // TODO(dynamic-capture): 首次生成持久化的 deviceId
    tokenProvider: () => tokenManager.getValidToken(
      refresher: () => authRepo.refresh(),
    ),
    forceRefreshProvider: () => tokenManager.forceRefresh(
      () => authRepo.refresh(),
    ),
    onAuthExpired: () async {
      await tokenManager.expire();
    },
  );
  authRepo = AuthRepository(network);

  runApp(
    ProviderScope(
      child: WorkbuddyApp(
        tokenManager: tokenManager,
        authRepository: authRepo,
        network: network,
      ),
    ),
  );
}
