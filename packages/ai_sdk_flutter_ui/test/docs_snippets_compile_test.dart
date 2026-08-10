import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('flutter_ui README and example snippets build', (tester) async {
    final agent = ToolLoopAgent(
      model: MockLanguageModelV3(response: [mockText('reply')]),
    );
    final chat = ChatController();
    final completion = CompletionController(agent: agent);
    final objectController = ObjectStreamController<Map<String, dynamic>>(
      model: MockLanguageModelV3(response: [mockText('{"country":"Japan"}')]),
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'country': {'type': 'string'},
          },
        },
        fromJson: (json) => json,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            Expanded(child: AiChatScaffold(controller: chat, agent: agent)),
            StreamingTextView(
              text: completion.completion,
              isStreaming: completion.isStreaming,
            ),
            Expanded(
              child: ObjectStreamView<Map<String, dynamic>>(
                controller: objectController,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(AiChatScaffold), findsOneWidget);
    expect(find.byType(StreamingTextView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ObjectStreamView<Map<String, dynamic>>,
      ),
      findsOneWidget,
    );

    chat.dispose();
    completion.dispose();
    objectController.dispose();
  });
}
