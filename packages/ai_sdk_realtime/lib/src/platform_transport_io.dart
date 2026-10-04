import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connectAuthenticatedWebSocket(
  Uri uri,
  Map<String, String> headers,
) async {
  final channel = IOWebSocketChannel.connect(uri, headers: headers);
  await channel.ready;
  return channel;
}
