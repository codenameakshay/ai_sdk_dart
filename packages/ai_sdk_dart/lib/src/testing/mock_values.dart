/// Returns an incrementing integer ID starting from 0.
///
/// Each call to the returned function produces the next integer as a string.
/// Mirrors `mockId` from the JS AI SDK v6 `ai/test` sub-path.
///
/// ```dart
/// final id = mockId();
/// expect(id(), '0');
/// expect(id(), '1');
/// ```
String Function() mockId() {
  var counter = 0;
  return () => '${counter++}';
}

/// Returns a function that cycles through [values] on each call.
///
/// Mirrors `mockValues` from the JS AI SDK v6 `ai/test` sub-path.
///
/// ```dart
/// final next = mockValues(['a', 'b', 'c']);
/// expect(next(), 'a');
/// expect(next(), 'b');
/// expect(next(), 'c');
/// // After the last value, keeps returning the last element:
/// expect(next(), 'c');
/// ```
T Function() mockValues<T>(List<T> values) {
  if (values.isEmpty) {
    throw ArgumentError('values must not be empty');
  }
  var index = 0;
  return () {
    final value = values[index];
    if (index < values.length - 1) index++;
    return value;
  };
}
