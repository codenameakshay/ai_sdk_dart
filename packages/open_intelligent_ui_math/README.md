# open_intelligent_ui_math

Math component for Open Intelligent UI: LaTeX formulas drawn with flutter_math_fork. It brings
flutter_math_fork, which bundles the KaTeX fonts.

Install:

```sh
fvm flutter pub add open_intelligent_ui_math
```

## Use

```dart
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';
import 'package:open_intelligent_ui_math/open_intelligent_ui_math.dart';

final builders = composeBuilders([mathBuilders]);
final library = intelligentUiFor(builders);
final session = OpenUiSession(library)..update(textSoFar, streaming: true);

OpenUiView(session: session, builders: builders);
```

The library from `intelligentUiFor` lists `Math`, so `library.systemPrompt(chatPromptFor(library))`
tells the model it exists.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
