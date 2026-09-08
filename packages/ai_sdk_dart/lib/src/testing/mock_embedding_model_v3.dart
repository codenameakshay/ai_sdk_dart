import 'mock_embedding_model_v2.dart';

/// A controllable mock embedding model for testing — v3 naming alias.
///
/// Mirrors `MockEmbeddingModelV3` from the JS AI SDK v6 `ai/test` sub-path.
/// Functionally identical to [MockEmbeddingModelV2]; provided under the V3
/// name for forward-compatibility as the JS SDK naming has moved ahead.
///
/// ```dart
/// final model = MockEmbeddingModelV3<String>(
///   embedding: [0.1, 0.2, 0.3],
/// );
/// final result = await embed(model: model, value: 'hello');
/// expect(result.embedding, [0.1, 0.2, 0.3]);
/// ```
typedef MockEmbeddingModelV3<VALUE> = MockEmbeddingModelV2<VALUE>;
