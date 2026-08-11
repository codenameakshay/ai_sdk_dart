import 'dart:async';

// ---------------------------------------------------------------------------
// JSON-RPC primitives
// ---------------------------------------------------------------------------

/// JSON-RPC 2.0 request.
///
/// Stable transport-extension primitive shared between [MCPClient] and custom
/// [MCPTransport] implementations.
///
/// Import this through `package:ai_sdk_mcp/ai_sdk_mcp.dart` when implementing
/// a transport outside this package.
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

/// JSON-RPC 2.0 notification.
///
/// Stable transport-extension primitive for fire-and-forget MCP messages.
///
/// Notifications are serialized without an `id`, so no response is expected.
class JsonRpcNotification {
  JsonRpcNotification({required this.method, this.params});

  final String method;
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'method': method,
    if (params != null) 'params': params,
  };
}

/// JSON-RPC 2.0 response.
///
/// Stable transport-extension primitive shared between [MCPClient] and custom
/// [MCPTransport] implementations.
///
/// Import this through `package:ai_sdk_mcp/ai_sdk_mcp.dart` when implementing
/// a transport outside this package.
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

/// Exception thrown when an MCP transport fails at the HTTP layer.
class MCPTransportException extends MCPException {
  MCPTransportException({
    required this.method,
    required Uri uri,
    this.statusCode,
    this.context,
  }) : uri = _sanitizeUri(uri),
       super(
         _buildMessage(
           method: method,
           uri: _sanitizeUri(uri),
           statusCode: statusCode,
           context: context,
         ),
       );

  final String method;
  final Uri uri;
  final int? statusCode;

  /// Optional, bounded context string that avoids echoing raw response bodies.
  final String? context;

  @override
  String toString() => 'MCPTransportException: $message';

  static Uri _sanitizeUri(Uri uri) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
  }

  static String _buildMessage({
    required String method,
    required Uri uri,
    int? statusCode,
    String? context,
  }) {
    final buffer = StringBuffer();
    if (statusCode != null) {
      buffer.write('HTTP $statusCode');
    } else {
      buffer.write('Transport error');
    }
    buffer.write(' for $method $uri');
    if (context != null && context.isNotEmpty) {
      buffer.write(' ($context)');
    }
    return buffer.toString();
  }
}

/// Exception thrown when an MCP Streamable HTTP session has expired.
///
/// Per the MCP 2025-06-18 transport spec, a `404 Not Found` response to a
/// request carrying `Mcp-Session-Id` means the client must start a new session
/// with a fresh initialize request.
class MCPSessionExpiredException extends MCPTransportException {
  MCPSessionExpiredException({
    required super.method,
    required super.uri,
    super.statusCode,
    super.context,
  });
}

// ---------------------------------------------------------------------------
// Transport interface
// ---------------------------------------------------------------------------

/// Public transport contract for MCP JSON-RPC communication.
///
/// Custom transports should implement this interface and use the JSON-RPC
/// primitives in this file as the stable request/notification/response types.
abstract class MCPTransport {
  /// Send a JSON-RPC request and receive the response.
  Future<JsonRpcResponse> send(JsonRpcRequest request);

  /// Send a JSON-RPC notification without waiting for a response body.
  Future<void> sendNotification(JsonRpcNotification notification);

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
