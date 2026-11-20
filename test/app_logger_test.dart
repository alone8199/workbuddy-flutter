import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workbuddy/util/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppLogger 脱敏 / 等级 / 落文件', () async {
    final log = AppLogger.instance;

    // 脱敏纯函数
    expect(AppLogger.mask('abcdef1234567890'), 'abcdef…7890');
    expect(AppLogger.mask('short'), '***');
    expect(AppLogger.mask(null), '<empty>');

    // 截断纯函数
    expect(AppLogger.truncate('x' * 10, 5), 'xxxxx…(共 10 字符)');

    // 初始化到临时目录（用独立的实例无法，因为单例；直接测 filePath 已设置即可）
    await log.init();
    expect(log.filePath, isNot('(未初始化，仅控制台输出)'));
    final f = File(log.filePath);

    log.i('TEST_TAG', '这是一条 info 日志');
    log.e('TEST_TAG', '这是一条 error 日志', '模拟异常', StackTrace.current);
    // error 级日志会触发 sink.flush，把之前缓冲（含上面的 info）一起写入磁盘。
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final content = await f.readAsString();
    expect(content, contains('[INFO ] [TEST_TAG] 这是一条 info 日志'));
    expect(content, contains('[ERROR] [TEST_TAG] 这是一条 error 日志'));
    expect(content, contains('模拟异常'));
  });
}
