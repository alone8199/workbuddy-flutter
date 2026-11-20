import 'dart:collection';

import 'package:dio/dio.dart';

import '../signature.dart';
import 'cookie/cookie_store.dart';

/// 公共请求头注入（设计文档 1.1 / 1.2 节逐项对齐）。
///
/// 已坐实项按报告值注入；未坐实项以可配置入参 + TODO(dynamic-capture) 呈现，不填猜测值：
///  - Referer / Origin：报告未给出确切值，默认用 websiteOrigin，且允许外部覆盖；
///  - X-Device-Token / X-Device-Token-Error / X-Custom-Channel-Id / X-Device-Id-List：
///    生成规则需动态抓包，默认不注入（发了假值反而会被风控识别），留 TODO；
///  - signature：登录/业务 HTTP 无独立签名，故公共拦截器不注入签名头。
class HeaderInterceptor extends Interceptor {
  final String appVersion;
  final String language; // 例如 zh-CN,zh;q=0.9
  final String product; // workbuddy / learn / ai
  final String websiteOrigin; // Referer / Origin 基线
  final String? refererOverride;
  final String? originOverride;
  final String? deviceId; // 首次生成持久化的设备 ID
  final String? enterpriseId; // account.enterpriseId，登录后可得
  final bool sortQueryParams; // 是否按 key 字母序排序 query
  final CookieStore? cookieStore;

  HeaderInterceptor({
    required this.appVersion,
    required this.language,
    this.product = 'workbuddy',
    this.websiteOrigin = 'https://www.workbuddy.cn',
    this.refererOverride,
    this.originOverride,
    this.deviceId,
    this.enterpriseId,
    this.sortQueryParams = false, // 对齐 axios 默认插入序
    this.cookieStore,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final h = options.headers;

    // —— 已坐实：客户端标识 ——
    h.putIfAbsent('User-Agent', () => 'WorkBuddy/$appVersion');
    h.putIfAbsent('X-IDE-Type', () => 'WorkBuddy');
    h.putIfAbsent('X-Client-Version', () => appVersion);
    h.putIfAbsent('X-Product', () => product);

    // —— 已坐实：语言 ——
    h.putIfAbsent('Accept-Language', () => language);
    h.putIfAbsent('X-TOA-LANG', () => language.split(',').first.trim());

    // —— 已坐实：请求 ID / 链路追踪 ——
    h.putIfAbsent('X-Request-ID', () => SignatureUtil.requestId());
    final traceId = h.putIfAbsent('X-Trace-Id', () => SignatureUtil.requestId());
    h.putIfAbsent('X-B3-TraceId', () => traceId ?? h['X-Trace-Id']);
    h.putIfAbsent('X-B3-SpanId', () => SignatureUtil.requestId().substring(0, 16));
    h.putIfAbsent('b3', () => '${h['X-B3-TraceId']}-${h['X-B3-SpanId']}');

    // —— 企业维度（登录后可得）——
    if (enterpriseId != null) {
      h.putIfAbsent('X-Enterprise-Id', () => enterpriseId);
    }

    // —— Referer / Origin：值未静态坐实，用 websiteOrigin 基线且可覆盖 ——
    // TODO(dynamic-capture): 确认桌面端关键请求的 Referer/Origin 是否带平台/渠道 query。
    h.putIfAbsent('Referer', () => refererOverride ?? '$websiteOrigin/');
    h.putIfAbsent('Origin', () => originOverride ?? websiteOrigin);

    // —— 设备 ID：首次生成持久化；算法（MachineGuid 种子）需抓包确认 ——
    // TODO(dynamic-capture): device-token / X-Device-Id-List 生成规则未确认，不注入假值。
    if (deviceId != null) {
      h.putIfAbsent('X-Device-Id', () => deviceId!);
    }

    // —— Cookie 域：按 URI 归属注入（domain 隔离见 cookie_store.dart）——
    final cookie = cookieStore?.headerFor(options.uri);
    if (cookie != null && cookie.isNotEmpty) {
      h.putIfAbsent('Cookie', () => cookie);
    }

    // —— 参数排序：默认对齐 axios 插入序；开关打开时按 key 字母序 ——
    if (sortQueryParams && options.queryParameters.isNotEmpty) {
      options.queryParameters =
          SplayTreeMap<String, dynamic>.from(options.queryParameters);
    }

    handler.next(options);
  }
}
