# open_intelligent_ui_chat

OpenUiChat and OpenUiUserMessage: Open Intelligent UI answers in an `ai_sdk_flutter_ui` chat. It brings
ai_sdk_dart and ai_sdk_flutter_ui.

Install:

```sh
fvm flutter pub add open_intelligent_ui_chat
```

## Use

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:open_intelligent_ui_chat/open_intelligent_ui_chat.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';
import 'package:open_intelligent_ui_maps/open_intelligent_ui_maps.dart';

final builders = composeBuilders([mapBuilders]);
final library = intelligentUiFor(builders);
final agent = ToolLoopAgent(
  model: model,
  instructions: library.systemPrompt(chatPromptFor(library)),
);
final chat = OpenUiChat(
  controller: controller,
  agent: agent,
  library: library,
  builders: builders,
);

AiChatScaffold(
  controller: controller,
  agent: agent,
  chatMessageBuilder: chat.buildMessage,
);
```

`OpenUiChat` advertises only the components its builders draw. Pass the builders of the plugins you
add, as above.

## Custom transport

`send` carries `@ToAssistant` turns over any transport instead of an agent. The chat does not add
the turn to the transcript; the transport does, as `ConversationChatController.sendText` does.

```dart
final chat = OpenUiChat(
  controller: controller,
  send: (text) async {
    controller.append(ModelMessage(role: ModelMessageRole.user, content: text));
    final reply = await myServer.answer(text); // OpenUI text
    controller.append(
      ModelMessage(role: ModelMessageRole.assistant, content: reply),
    );
  },
  locale: 'en-US',
  records: (id) => [BoundRecord('orders', orders)],
);
```

## Render one answer

`OpenUiAnswerView` renders one message of an `OpenUiAnswers` (ai_sdk_openui) by its id, for a
transport that keeps answers outside a chat transcript:

```dart
final answers = OpenUiAnswers(library: library, onSave: (id, text) => store(id, text));
answers.append(id, delta); // or update, patch, listen, finish
OpenUiAnswerView(answers: answers, id: id, onToAssistant: sendTurn);
```

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
