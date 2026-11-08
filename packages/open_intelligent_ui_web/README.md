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

## Network

- HtmlView renders its page in a web view, or a sandboxed frame on the web. The page may load scripts from
  cdn.jsdelivr.net, unpkg.com, cdnjs.cloudflare.com and esm.sh, styles and fonts from fonts.googleapis.com
  and fonts.gstatic.com, and images from any https host. Its Content Security Policy sets these limits.
- YouTube embeds load from www.youtube-nocookie.com. Its thumbnail is an image, so `imageLoader` gates it.
- To keep these off, leave this package out of your app. The library then does not list `HtmlView` or
  `YouTube`, so the model does not ask for them.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
