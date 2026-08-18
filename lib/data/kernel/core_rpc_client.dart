import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class CoreRpcException implements Exception {
  CoreRpcException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() =>
      code == null ? 'CoreRpcException: $message' : 'CoreRpcException($code): $message';
}

/// 本机 astral-core JSON-RPC 2.0 客户端（`POST http://host:port/`）。
class CoreRpcClient {
  CoreRpcClient({
    required this.target,
    this.timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// 例如 `127.0.0.1:50051`
  final String target;
  final Duration timeout;
  final http.Client _http;
  var _nextId = 0;
  var _closed = false;

  Uri get _uri {
    final raw = target.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.parse(raw);
    }
    return Uri.parse('http://$raw/');
  }

  Future<dynamic> call(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    if (_closed) {
      throw CoreRpcException('内核未连接');
    }
    final id = ++_nextId;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params ?? const <String, dynamic>{},
    });
    final resp = await _http
        .post(
          _uri,
          headers: const {'content-type': 'application/json'},
          body: body,
        )
        .timeout(timeout ?? this.timeout);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) {
      throw CoreRpcException('非法 JSON-RPC 响应');
    }
    final error = decoded['error'];
    if (error is Map) {
      throw CoreRpcException(
        '${error['message'] ?? 'rpc error'}',
        code: error['code'] is int ? error['code'] as int : int.tryParse('${error['code']}'),
      );
    }
    return decoded['result'];
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close();
  }
}
