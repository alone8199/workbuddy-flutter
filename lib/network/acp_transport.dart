import 'dart:async';

/// ACP 传输抽象：把「JSON-RPC 请求-响应 / 通知 / SSE 订阅」从具体实现中抽出，
/// 便于会话模块与单测注入 fake，不依赖真实 dio。
/// 数据源：报告01（Streamable HTTP 双通道）、报告05（session/* 方法表）。
abstract class AcpTransport {
  /// 发 JSON-RPC 请求并等待响应 result。
  /// session/new、session/load、session/list 等需要拿返回值的方法走这里。
  Future<Map<String, dynamic>> requestAwait(
      String method, Map<String, dynamic> params);

  /// 发 JSON-RPC 通知（无 id、不等响应）。session/prompt、session/cancel 走这里。
  Future<void> notify(String method, Map<String, dynamic> params);

  /// 回应服务端主动发起的交互式请求（权限确认/elicitation/提问）。
  /// id 为原请求的 id，result 为用户回应。
  Future<void> respond(int id, Map<String, dynamic> result);

  /// 已解析出的 JSON-RPC 消息流（session/update 通知、请求响应等）。
  Stream<Map<String, dynamic>> get messages;

  /// 启动 SSE 长连接订阅（event:message 里的 jsonrpc 消息推入 messages）。
  Future<void> startSubscribe();

  /// 建立/关闭底层连接。
  Future<void> bootstrap();
  Future<void> close();
}
