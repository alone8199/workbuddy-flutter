import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'network/env_config.dart';
import 'network/client.dart';
import 'auth/token_manager.dart';
import 'auth/auth_repository.dart';
import 'storage/secure_storage.dart';
import 'util/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日志：同时输出到控制台与磁盘文件；捕获 Flutter 框架异常与异步未捕获异常。
  final log = AppLogger.instance;
  await log.init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.e('FLUTTER', '未捕获的框架异常: ${details.exceptionAsString()}',
        details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.e('FLUTTER', '未捕获的异步异常: $error', error, stack);
    return true;
  };
  final storage = SecureStorage();
  final tokenManager = TokenManager(storage);
  await tokenManager.load();

  // 环境：默认 prod，可从 dart-define 覆盖（--dart-define=WB_ENV=pre）。
  const envName = String.fromEnvironment('WB_ENV', defaultValue: 'prod');
  final env = Environment.fromString(envName);
  log.i('APP', '启动：env=$envName api=${env.api} 日志文件=${log.filePath}');

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
