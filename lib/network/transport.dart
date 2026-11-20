import 'package:dio/dio.dart';

import 'client.dart';

/// 最小可用请求通道（设计文档方案 C：dio 直连）。
/// 提供一次 GET 与一次带 body 的 POST，并把响应（状态/头/体）原样回传 Dart 层。
class TransportChannel {
  final NetworkClient client;
  TransportChannel(this.client);

  /// GET：query 作为 Map 传入，返回原始 Response 供上层解析。
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return client.dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// POST：data 作为 JSON body，返回原始 Response。
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return client.dio.post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  /// 探测响应摘要（状态 + 关键头 + body 截断），用于抓包记录。
  Map<String, dynamic> summarize(Response<dynamic> r) {
    return <String, dynamic>{
      'statusCode': r.statusCode,
      'headers': r.headers.map,
      'body': r.data is String
          ? (r.data as String).substring(0, (r.data as String).length > 300 ? 300 : (r.data as String).length)
          : r.data,
    };
  }
}
