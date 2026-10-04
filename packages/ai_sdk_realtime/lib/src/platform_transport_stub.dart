import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connectAuthenticatedWebSocket(
  Uri uri,
  Map<String, String> headers,
) => throw UnsupportedError(
  'The default authenticated WebSocket connector requires dart:io. '
  'Inject a browser-safe connector with an ephemeral credential.',
);
