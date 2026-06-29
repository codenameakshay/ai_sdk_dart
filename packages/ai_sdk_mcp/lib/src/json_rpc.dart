import 'dart:async';

// ---------------------------------------------------------------------------
// JSON-RPC primitives
// ---------------------------------------------------------------------------

/// JSON-RPC 2.0 request.
///
/// Internal to `ai_sdk_mcp`; shared between the client and the transport
/// implementations. Not part of the public API.
class JsonRpcRequest {
  JsonRpcRequest({required this.method, required this.id, this.params});

  final String method;
  final int id;
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  };
}

/// JSON-RPC 2.0 response.
///
/// Internal to `ai_sdk_mcp`; shared between the client and the transport
/// implementations. Not part of the public API.
class JsonRpcResponse {
  const JsonRpcResponse({this.result, this.error, this.id});

  final Object? result;
  final Map<String, dynamic>? error;
  final int? id;

  bool get isError => error != null;

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) {
    return JsonRpcResponse(
      result: json['result'],
      error: json['error'] is Map
          ? (json['error'] as Map).cast<String, dynamic>()
          : null,
      id: json['id'] is int ? json['id'] as int : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Exception thrown when an MCP operation fails.
class MCPException implements Exception {
  const MCPException(this.message);
  final String message;

  @override
  String toString() => 'MCPException: $message';
}

// ---------------------------------------------------------------------------
// Transport interface
// ---------------------------------------------------------------------------

/// Abstract transport for MCP JSON-RPC communication.
abstract class MCPTransport {
  /// Send a JSON-RPC request and receive the response.
  Future<JsonRpcResponse> send(JsonRpcRequest request);

  /// Stream of server-initiated JSON-RPC messages (notifications and
  /// server→client requests) that arrive out-of-band — i.e. not as the direct
  /// response to a [send] call.
  ///
  /// Transports that cannot receive server-initiated messages (e.g. a plain
  /// request/response HTTP transport) return an empty stream.
  Stream<Map<String, dynamic>> get notifications => const Stream.empty();

  /// Close the transport.
  Future<void> close();
}
