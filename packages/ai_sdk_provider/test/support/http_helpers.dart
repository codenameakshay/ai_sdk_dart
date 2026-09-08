import 'dart:convert';
import 'dart:io';

/// Reads and JSON-decodes the body of [request].
Future<Map<String, dynamic>> captureBody(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return (jsonDecode(body) as Map).cast<String, dynamic>();
}

/// Responds to [request] with a minimal successful chat-completion payload.
void writeOk(HttpRequest request) {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': 'ok'},
        },
      ],
    }),
  );
  request.response.close();
}
