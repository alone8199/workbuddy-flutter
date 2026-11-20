import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

import 'client.dart';
import 'endpoints.dart';
import 'sse_parser.dart';
import 'acp_transport.dart';

/// ACP JSON-RPC 客户端：POST /acp 发请求 + GET /acp 订阅 SSE 推送。
/// 数据源：common-BUTGRJ4Z.js（Streamable HTTP）。
/// TODO(dynamic-capture): /acp 的绝对 host、bootstrap 契约、响应走 POST 还是 SSE 需抓包确认。
class AcpClient implements AcpTransport {
  final NetworkClient net;
  final SseParser _parser = SseParser();
  String? _connectionId;
  int _id = 0;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  AcpClient(this.net);

  @override
  Future<void> bootstrap() async {
    try {
      final resp = await net.dio.post<dynamic>(Endpoints.acpBootstrap);
      _connectionId = resp.headers.value('Acp-Connection-Id');
    } catch (_) {
      // 允许无 bootstrap 继续（联调后改为强校验）。
    }
  }

  Map<String, dynamic> _envelope(String method, Map<String, dynamic> params,
      {bool withId = true}) {
    final m = <String, dynamic>{
      'jsonrpc': '2.0',
      if (withId) 'id': ++_id,
      'method': method,
      'params': params,
    };
    return m;
  }

  /// 发请求并等待响应 result。
  /// Streamable HTTP 中 POST /acp 的响应可能是 application/json（直接拿 result），
  /// 也可能是 text/event-stream（result 随 SSE 推送）。两种都处理。
  @override
  Future<Map<String, dynamic>> requestAwait(
      String method, Map<String, dynamic> params) async {
    final body = _envelope(method, params);
    final resp = await net.dio.post<dynamic>(
      Endpoints.acp,
      data: body,
      options: Options(headers: {
        if (_connectionId != null) 'Acp-Connection-Id': _connectionId,
      }),
    );
    final ct = resp.headers.value('content-type') ?? '';
    if (ct.contains('text/event-stream')) {
      // 响应本身是 SSE：等对应的 result 帧（id 匹配）。
      return _awaitResultFromSse(resp, body['id'] as int);
    }
    return _extractResult(resp.data, body['id'] as int);
  }

  /// 发通知（不等响应）。
  @override
  Future<void> notify(String method, Map<String, dynamic> params) async {
    final body = _envelope(method, params, withId: false);
    await net.dio.post<dynamic>(
      Endpoints.acp,
      data: body,
      options: Options(headers: {
        if (_connectionId != null) 'Acp-Connection-Id': _connectionId,
      }),
    );
  }

  /// 回应服务端交互式请求。
  @override
  Future<void> respond(int id, Map<String, dynamic> result) async {
    await net.dio.post<dynamic>(
      Endpoints.acp,
      data: <String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      },
      options: Options(headers: {
        if (_connectionId != null) 'Acp-Connection-Id': _connectionId,
      }),
    );
  }

  Map<String, dynamic> _extractResult(dynamic data, int id) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('result')) {
        final r = data['result'];
        return r is Map<String, dynamic> ? r : <String, dynamic>{'value': r};
      }
      if (data.containsKey('error')) {
        throw AcpException('JSON-RPC error: ${data['error']}');
      }
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _awaitResultFromSse(
      Response<dynamic> resp, int id) async {
    final raw = resp.data;
    Stream<List<int>>? stream;
    if (raw is ResponseBody) {
      stream = raw.stream;
    }
    if (stream == null) return <String, dynamic>{};
    final parser = SseParser();
    final completer = Completer<Map<String, dynamic>>();
    await for (final bytes in stream) {
      for (final ev in parser.feedAndDrain(utf8.decode(bytes, allowMalformed: true))) {
        final msg = parser.parseJson(ev);
        if (msg == null) continue;
        if (msg['id'] == id) {
          if (!completer.isCompleted) completer.complete(_extractResult(msg, id));
        }
      }
      if (completer.isCompleted) break;
    }
    if (!completer.isCompleted) completer.complete(<String, dynamic>{});
    return completer.future;
  }

  /// 订阅 SSE 长连接，解析 event:message 里的 jsonrpc 消息。
  @override
  Future<void> startSubscribe() async {
    final resp = await net.dio.get<ResponseBody>(
      Endpoints.acp,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept': 'text/event-stream',
          if (_connectionId != null) 'Acp-Connection-Id': _connectionId,
        },
      ),
    );
    final body = resp.data;
    if (body == null) return;
    await for (final bytes in body.stream) {
      for (final ev in _parser.feedAndDrain(utf8.decode(bytes, allowMalformed: true))) {
        final msg = _parser.parseJson(ev);
        if (msg != null && msg.containsKey('jsonrpc')) {
          _messages.add(msg);
        }
      }
    }
  }

  @override
  Future<void> close() async {
    if (!_messages.isClosed) await _messages.close();
  }
}

class AcpException implements Exception {
  final String message;
  AcpException(this.message);
  @override
  String toString() => 'AcpException($message)';
}
