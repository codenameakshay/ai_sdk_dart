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

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
