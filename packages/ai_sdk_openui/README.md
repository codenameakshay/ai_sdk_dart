# ai_sdk_openui

OpenUI Lang 1.0 in pure Dart, and the
[Open Intelligent UI](https://github.com/thesysdev/open-intelligent-ui) component library spec.

The model answers with a small program instead of prose. This package parses it while it
streams, evaluates it against local `$state` and your tools, and generates the system prompt
that teaches the model the language. It has no Flutter dependency, so a Dart server can build
the prompt or check a program. Render it in Flutter with
[`open_intelligent_ui`](../open_intelligent_ui).

It is a line-by-line port of `@openuidev/lang-core` 1.0.0 (parser, streaming parser,
validation, evaluator, store, query manager, prompt generator, message envelope, statement
merge and serializer, form validation, structured errors, MCP helpers, `library.extend()` and
the OpenUI Cloud prompt), of react-lang's state, query and action handling, and of the
reference app's library at commit `9df2e64`: 55 components, 59 `@functions`,
`@CopyToClipboard`, the chat and dashboard prompt options, and the demo data tools.
`package:ai_sdk_openui/lang_core.dart` exports the low-level lang-core surface under its
JavaScript names.

## Use

```dart
import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';

// The system prompt for the agent.
final instructions = intelligentUi.systemPrompt(chatPrompt);

// One session per assistant answer. Pass the full text on every chunk.
final session = OpenUiSession(intelligentUi, tools: demoTools());
session.update(textSoFar, streaming: true);
session.update(finalText, streaming: false); // queries start

final root = session.root; // the evaluated element tree
final saved = session.state; // JSON to restore later as initialState

// A click: run the element's action; host steps come back as events.
await session.run(root!.props.action('action'), label: 'Go', emit: (event) {
  if (event.type == ActionEvent.continueConversation) {
    // send event.humanFriendlyMessage, with event.formState, as the next user turn
  }
});

// A server-side check without running anything.
final report = intelligentUi.parse(program);
print(report.isClean ? 'ok' : report.errors);
```

## Fidelity

- `spec.json` from the reference is reproduced byte for byte, and both system prompts match the
  reference's generated files except for eight lines where those files predate the reference's
  own source (`test/prompt_drift.dart` lists them).
- The reference's 45 gallery programs parse with no errors, stream to the same tree, and
  evaluate with no issues (`test/conformance_test.dart`). Its four function test files are
  ported case for case, and the JavaScript-sensitive functions (number and currency
  formatting, date parsing, case mapping) are checked against Node.
- Lang-core's telemetry and devtools are not ported. See `DESIGN.md` in `open_intelligent_ui`
  for the deliberate differences.
