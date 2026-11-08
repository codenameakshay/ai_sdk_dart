import '../spec/library.dart';
import '../spec/schema.dart';

/// `@CopyToClipboard(text)`: the host copies the text.
final copyToClipboard = ActionSpec(
  'CopyToClipboard',
  description:
      'Copy text to the clipboard, e.g. a shopping list built with @Join',
  params: {'text': S.string()},
);
