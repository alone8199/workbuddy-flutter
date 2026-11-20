import '../../network/acp_transport.dart';
import '../../models/content_block.dart';

/// 会话元数据。数据源：报告05 session/new|list 返回结构。
class SessionInfo {
  final String sessionId;
  final String? title;
  final String? cwd;
  final DateTime? updatedAt;

  SessionInfo({
    required this.sessionId,
    this.title,
    this.cwd,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
        sessionId: json['sessionId']?.toString() ?? json['session_id']?.toString() ?? '',
        title: json['title']?.toString(),
        cwd: json['cwd']?.toString(),
      );
}

/// session/list 的一页结果（cursor 分页，报告05：cursor 用于会话列表分页）。
class SessionPage {
  final List<SessionInfo> sessions;
  final String? nextCursor;
  SessionPage(this.sessions, {this.nextCursor});
}

/// 会话级本地缓存：会话列表（含分页游标）+ 每会话消息历史。
/// 报告05：session/load 一次性加载历史（非消息分页），增量靠 SSE 推送。
class SessionCache {
  final Map<String, List<Map<String, dynamic>>> _history = {};
  final List<SessionInfo> _sessions = [];
  String? _listCursor;

  List<SessionInfo> get sessions => List.unmodifiable(_sessions);
  String? get listCursor => _listCursor;

  void putHistory(String sessionId, List<Map<String, dynamic>> messages) {
    _history[sessionId] = List.unmodifiable(messages);
  }

  List<Map<String, dynamic>> getHistory(String sessionId) =>
      List.unmodifiable(_history[sessionId] ?? const []);

  void appendMessage(String sessionId, Map<String, dynamic> message) {
    _history.putIfAbsent(sessionId, () => <Map<String, dynamic>>[]).add(message);
  }

  void mergeSessions(List<SessionInfo> page, {String? nextCursor, bool replace = false}) {
    if (replace) _sessions.clear();
    for (final s in page) {
      final idx = _sessions.indexWhere((x) => x.sessionId == s.sessionId);
      if (idx >= 0) {
        _sessions[idx] = s;
      } else {
        _sessions.add(s);
      }
    }
    _listCursor = nextCursor;
  }

  void removeSession(String sessionId) {
    _sessions.removeWhere((s) => s.sessionId == sessionId);
    _history.remove(sessionId);
  }
}

/// 会话接口封装。所有方法严格对应报告05的方法表，参数不自行增删。
class SessionRepository {
  final AcpTransport transport;
  final SessionCache cache;
  final String cwd;

  SessionRepository({
    required this.transport,
    required this.cwd,
    SessionCache? cache,
  }) : cache = cache ?? SessionCache();

  /// session/new {cwd, additionalDirectories?, mcpServers, systemPrompt?}
  Future<SessionInfo> create({
    List<String>? additionalDirectories,
    List<Map<String, dynamic>>? mcpServers,
    Map<String, dynamic>? systemPrompt,
  }) async {
    final result = await transport.requestAwait('session/new', <String, dynamic>{
      'cwd': cwd,
      if (additionalDirectories != null) 'additionalDirectories': additionalDirectories,
      'mcpServers': mcpServers ?? const [],
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
    });
    final info = SessionInfo.fromJson(result);
    cache.mergeSessions([info], replace: false);
    return info;
  }

  /// session/load {sessionId, cwd, mcpServers, ...}
  /// 历史一次性加载（emptyObjectResponse 语义），消息本体由 SSE session_message 推送。
  Future<void> load(String sessionId) async {
    await transport.requestAwait('session/load', <String, dynamic>{
      'sessionId': sessionId,
      'cwd': cwd,
      'mcpServers': const [],
    });
  }

  /// session/list {cwd?, cursor?} —— cursor 分页。
  Future<SessionPage> list({String? cursor, int? limit}) async {
    final result = await transport.requestAwait('session/list', <String, dynamic>{
      'cwd': cwd,
      if (cursor != null) 'cursor': cursor,
      if (limit != null) 'limit': limit,
    });
    final raw = result['sessions'] is List ? result['sessions'] as List : const [];
    final page = SessionPage(
      raw.whereType<Map<String, dynamic>>().map(SessionInfo.fromJson).toList(),
      nextCursor: result['nextCursor']?.toString(),
    );
    cache.mergeSessions(page.sessions,
        nextCursor: page.nextCursor, replace: cursor == null);
    return page;
  }

  Future<void> delete(String sessionId) async {
    await transport.requestAwait('session/delete', {'sessionId': sessionId});
    cache.removeSession(sessionId);
  }

  Future<SessionInfo> fork(String sessionId) async {
    final result = await transport.requestAwait('session/fork', <String, dynamic>{
      'sessionId': sessionId,
      'cwd': cwd,
      'mcpServers': const [],
    });
    final info = SessionInfo.fromJson(result);
    cache.mergeSessions([info]);
    return info;
  }

  Future<void> resume(String sessionId) async {
    await transport.requestAwait('session/resume', <String, dynamic>{
      'sessionId': sessionId,
      'cwd': cwd,
    });
  }

  Future<void> close(String sessionId) async {
    await transport.requestAwait('session/close', {'sessionId': sessionId});
  }

  /// session/prompt {sessionId, prompt: ContentBlock[]} —— 只发当前轮内容块，
  /// 历史由 sessionId 在服务端维护（报告01 §2.1，ActiveSession.prompt 只传 sessionId+prompt）。
  Future<void> prompt(String sessionId, List<ContentBlock> blocks) async {
    cache.appendMessage(sessionId, <String, dynamic>{
      'role': 'user',
      'content': blocks.map((b) => b.toJson()).toList(),
    });
    await transport.notify('session/prompt', <String, dynamic>{
      'sessionId': sessionId,
      'prompt': blocks.map((b) => b.toJson()).toList(),
    });
  }

  /// session/cancel（notification）—— 中断生成（报告05）。
  Future<void> cancel(String sessionId) async {
    await transport.notify('session/cancel', {'sessionId': sessionId});
  }
}
