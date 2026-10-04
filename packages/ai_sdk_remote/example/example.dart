import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    print('Usage: dart run example/example.dart <backend-chat-url>');
    return;
  }
  final endpoint = Uri.parse(arguments.single);
  if (!endpoint.hasAuthority ||
      (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
    throw ArgumentError('The backend URL must use HTTP or HTTPS.');
  }
  final transport = RemoteConversationTransport(endpoint: endpoint);
  final conversation = Conversation(
    id: 'example-conversation',
    messages: [
      ConversationMessage(
        id: 'example-user',
        role: ConversationRole.user,
        parts: [TextPart(id: 'example-input', text: 'Hello')],
      ),
    ],
  );
  try {
    var previousText = '';
    await for (final snapshot in transport.send(conversation)) {
      final text = snapshot.messages
          .where((message) => message.role == ConversationRole.assistant)
          .expand((message) => message.parts)
          .whereType<TextPart>()
          .map((part) => part.text)
          .join();
      if (text != previousText) {
        print(text);
        previousText = text;
      }
    }
  } finally {
    transport.dispose();
  }
}
