# ai_sdk_conversation

Optional immutable conversation snapshots for Dart and Flutter. This package has no runtime dependencies and performs no network requests or tool execution.

```dart
import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';

final conversation = Conversation(
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
final wire = ConversationCodec.encode(conversation);
final restored = ConversationCodec.decode(wire);
```

Application code assigns stable conversation, message and part IDs. Persist the map using your chosen JSON store. Schema version 1 is independent of the package version. Unsupported schema versions raise `ConversationSchemaException`; malformed states raise `ConversationValidationException`.

Parts represent text, reasoning with opaque signatures, file references, sources, tool calls, tool results and approvals. Unknown part types and extension fields are preserved. Metadata, arguments and output are recursively copied into immutable JSON containers. Retained JSON trees reject cycles, nonfinite numbers, non-JSON values, depth beyond 64 and more than 10,000 visited nodes.

A tool result or approval must refer to a call in the snapshot. Duplicate message/part IDs and duplicate call IDs are rejected. Interrupted and pending-approval states survive round trips. Restoring a pending approval does not authorize or execute a tool; the application's execution policy must verify the call and policy revision before acting.

Files are referenced by URI and media type; the codec does not download or embed bytes. The application owns persistence, encryption, binary storage and deletion. This is a persistence model, not a provider prompt converter or an HTTP resumption protocol.
