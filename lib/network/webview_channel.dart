import 'dart:async';

/// WebView2 关键请求通道（设计文档方案 A，Windows only）。
///
/// 设计文档 2.2 推荐混合方案：对话/业务/token 走 dio 直连（方案 C，见 transport.dart），
/// 登录链路走 WebView2（方案 A）。本文件提供 WebView 侧「加载授权页 → 拦截回调路由 →
/// 回传 code/ticket 给 Dart」的最小骨架。
///
/// 说明：webview_windows 0.4.0 依赖 Windows WebView2 Runtime，仅能在 Windows 目标编译；
/// 当前 Linux 沙箱无法 build windows，故这里用抽象 + 回调契约实现，Windows 端注入真实
/// WebViewController 适配即可，Dart 侧交互契约保持不变。
abstract class WebViewAuthChannel {
  /// 加载授权 URL；回调路由命中时通过 onCallback 回传（code/ticket/state）。
  Future<void> loadAuthorization({
    required String url,
    required Set<String> callbackPathContains,
    required void Function(Uri callbackUri) onCallback,
    void Function(Object error)? onError,
  });

  Future<void> close();
}

/// 内存实现：用于单测 / Linux 联调，模拟回调注入，验证 Dart 侧状态机不被平台绑死。
class InMemoryWebViewChannel implements WebViewAuthChannel {
  @override
  Future<void> loadAuthorization({
    required String url,
    required Set<String> callbackPathContains,
    required void Function(Uri callbackUri) onCallback,
    void Function(Object error)? onError,
  }) async {
    // 真实实现：webview_windows loadUrl + onNavigationRequest 拦截 callbackPathContains。
    // 这里仅记录，等待测试主动调用 emitCallback。
    _lastUrl = url;
  }

  String? _lastUrl;
  String? get lastUrl => _lastUrl;

  /// 测试入口：模拟 WebView 拦截到回调。
  void emitCallback(Uri uri) {
    // 真实实现由平台回调驱动；此处直接暴露给调用方注册。
    _callback?.call(uri);
  }

  void Function(Uri)? _callback;

  @override
  Future<void> close() async {
    _callback = null;
  }

  void bind(void Function(Uri) cb) => _callback = cb;
}
