# open_intelligent_ui_web

HtmlView and YouTube components for Open Intelligent UI, drawn in a web view. It brings webview_flutter
and web.

Install:

```sh
fvm flutter pub add open_intelligent_ui_web
```

## Use

```dart
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';
import 'package:open_intelligent_ui_web/open_intelligent_ui_web.dart';

final builders = composeBuilders([webBuilders]);
final library = intelligentUiFor(builders);
final session = OpenUiSession(library)..update(textSoFar, streaming: true);

OpenUiView(session: session, builders: builders);
```

The library from `intelligentUiFor` lists `HtmlView` and `YouTube`, so `library.systemPrompt(chatPromptFor(library))`
tells the model they exist.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
