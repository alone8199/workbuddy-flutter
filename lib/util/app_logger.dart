import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

/// 日志等级（数值越大越严重）。
enum LogLevel {
  debug(0),
  info(1),
  warn(2),
  error(3);

  const LogLevel(this.value);
  final int value;
}

/// 全局日志器：同时输出到控制台（dart:developer，flutter run / IDE 可见）
/// 与磁盘文件（Windows 用户目录下 .workbuddy/logs/app.log，双击运行也能查）。
///
/// 设计要点：
///  - 单例，main() 启动时 [init] 一次；未初始化也能用（仅控制台），不会崩。
///  - 敏感头/字段统一脱敏（[mask]），避免 token/cookie 落盘。
///  - error 级自动 flush，保证崩溃前关键日志已写盘。
///  - 不依赖 path_provider（避免 Dart 3 传递依赖冲突），直接用 dart:io。
class AppLogger {
  static final AppLogger instance = AppLogger._internal();
  AppLogger._internal();

  LogLevel _minLevel = LogLevel.debug;
  bool _toConsole = true;
  IOSink? _sink;
  String? _filePath;
  bool _initialized = false;

  String get filePath => _filePath ?? '(未初始化，仅控制台输出)';

  Future<void> init({
    LogLevel minLevel = LogLevel.debug,
    bool toConsole = true,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _minLevel = minLevel;
    _toConsole = toConsole;
    try {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'];
      final base = home ?? Directory.current.path;
      final dir = Directory(
        '$base${Platform.pathSeparator}.workbuddy${Platform.pathSeparator}logs',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}${Platform.pathSeparator}app.log');
      _filePath = file.path;
      _sink = file.openWrite(mode: FileMode.append);
      _emit(LogLevel.info, 'LOGGER', '日志文件就绪: ${file.path}');
      await _sink!.flush();
    } catch (e, st) {
      _emit(LogLevel.warn, 'LOGGER', '日志文件初始化失败，仅控制台输出: $e', st);
    }
  }

  void d(String tag, String msg, [Object? err, StackTrace? st]) =>
      _emit(LogLevel.debug, tag, msg, err, st);

  void i(String tag, String msg, [Object? err, StackTrace? st]) =>
      _emit(LogLevel.info, tag, msg, err, st);

  void w(String tag, String msg, [Object? err, StackTrace? st]) =>
      _emit(LogLevel.warn, tag, msg, err, st);

  void e(String tag, String msg, [Object? err, StackTrace? st]) =>
      _emit(LogLevel.error, tag, msg, err, st);

  /// 脱敏：只保留前 6 后 4，其余打码。用于 token / cookie / 授权头。
  static String mask(String? value) {
    if (value == null || value.isEmpty) return '<empty>';
    if (value.length <= 10) return '***';
    return '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
  }

  /// 截断过长正文，避免单条日志爆掉（响应体可能很大）。
  static String truncate(Object? value, [int max = 2000]) {
    final s = value?.toString() ?? '<null>';
    return s.length <= max ? s : '${s.substring(0, max)}…(共 ${s.length} 字符)';
  }

  void _emit(
    LogLevel level,
    String tag,
    String msg, [
    Object? err,
    StackTrace? st,
  ]) {
    if (level.value < _minLevel.value) return;
    final ts = DateTime.now().toIso8601String();
    final lv = _name(level);
    final buf = StringBuffer('[$ts] [$lv] [$tag] $msg');
    if (err != null) buf.write('\n  ├─ error: $err');
    if (st != null) buf.write('\n  └─ stack: $st');
    final line = buf.toString();

    if (_toConsole) {
      dev.log(line, name: 'WB/$tag', level: _devLevel(level));
    }
    try {
      _sink?.write('$line\n');
    } catch (_) {
      // 写盘失败不影响主流程。
    }
    if (level == LogLevel.error) {
      unawaited(_sink?.flush() ?? Future<void>.value());
    }
  }

  String _name(LogLevel l) {
    switch (l) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO ';
      case LogLevel.warn:
        return 'WARN ';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  int _devLevel(LogLevel l) {
    switch (l) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warn:
        return 900;
      case LogLevel.error:
        return 1200;
    }
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
