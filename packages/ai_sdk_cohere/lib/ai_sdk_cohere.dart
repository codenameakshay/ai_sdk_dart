/// Cohere provider for the AI SDK Dart.
///
/// Supports language model generation, embedding, and reranking.
///
/// ```dart
/// import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
///
/// final model = cohere('command-r-plus');
/// final embedder = cohere.embedding('embed-english-v3.0');
/// final ranker = cohere.rerank('rerank-english-v3.0');
/// ```
library ai_sdk_cohere;

export 'src/cohere_provider.dart';
