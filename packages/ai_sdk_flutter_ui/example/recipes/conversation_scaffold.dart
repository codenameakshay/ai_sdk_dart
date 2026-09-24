import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';

/// A keyless, runnable recipe for the prebuilt conversation scaffold.
///
/// Replace [MockLanguageModelV4] with a provider model in an application that
/// has credentials. The UI and persistence boundary stay the same.
class ConversationScaffoldExample extends StatefulWidget {
  const ConversationScaffoldExample({super.key});

  @override
  State<ConversationScaffoldExample> createState() =>
      _ConversationScaffoldExampleState();
}

class _ConversationScaffoldExampleState
    extends State<ConversationScaffoldExample> {
  late final ConversationController _conversation;

  @override
  void initState() {
    super.initState();
    _conversation = ConversationController(
      LocalConversationBackend(
        agent: ToolLoopAgent(
          model: MockLanguageModelV4(
            response: [mockText('Hello from the conversation backend.')],
          ),
        ),
        initial: Conversation(id: 'recipe', messages: const []),
      ),
    );
  }

  @override
  void dispose() {
    _conversation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AiChatScaffold.conversation(conversationController: _conversation);
  }
}
