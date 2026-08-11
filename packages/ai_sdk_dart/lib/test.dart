/// Testing utilities for the AI SDK Dart.
///
/// Import this library in your tests to get access to mock/fake model
/// implementations that mirror the JS AI SDK v6 `ai/test` sub-path.
///
/// ```dart
/// import 'package:ai_sdk_dart/test.dart';
///
/// final model = MockLanguageModelV4(
///   response: [MockTextPart('Hello, world!')],
/// );
/// ```
library;

export 'src/testing/mock_language_model_v4.dart';
export 'src/testing/mock_embedding_model_v2.dart';
export 'src/testing/mock_embedding_model_v3.dart';
export 'src/testing/mock_image_model_v3.dart';
export 'src/testing/mock_values.dart';
