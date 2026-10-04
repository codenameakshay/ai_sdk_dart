import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';

void main() {
  final original = Conversation(
    id: 'conversation-1',
    messages: [
      ConversationMessage(
        id: 'message-1',
        role: ConversationRole.assistant,
        status: ConversationMessageStatus.interrupted,
        parts: [TextPart(id: 'part-1', text: 'Partial answer')],
      ),
    ],
  );
  final stored = jsonEncode(ConversationCodec.encode(original));
  final restored = ConversationCodec.decode(
    jsonDecode(stored) as Map<String, dynamic>,
  );
  if (restored != original) throw StateError('Conversation was not preserved');
}
