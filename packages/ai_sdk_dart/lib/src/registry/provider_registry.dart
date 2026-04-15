import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A registry mapping `'provider:modelId'` strings to model factories.
///
/// Supports all model types: language, embedding, image, speech, transcription,
/// and video. Modeled after the JS SDK's `createProviderRegistry()`.
///
/// ```dart
/// final registry = createProviderRegistry({
///   'openai': RegistrableProvider(
///     languageModelFactory: openai.call,
///     embeddingModelFactory: openai.embedding,
///     imageModelFactory: openai.image,
///   ),
/// });
///
/// final model  = registry.languageModel('openai:gpt-4o');
/// final embed  = registry.textEmbeddingModel('openai:text-embedding-3-small');
/// final image  = registry.imageModel('openai:dall-e-3');
/// ```
class ProviderRegistry {
  ProviderRegistry._(this._providers);

  final Map<String, _ProviderLike> _providers;

  /// Resolve a language model by `'provider:modelId'`.
  LanguageModelV3 languageModel(String id) {
    final (provider, modelId) = _splitId(id);
    return _resolve(provider).languageModel(modelId);
  }

  /// Resolve an embedding model by `'provider:modelId'`.
  EmbeddingModelV2<String> textEmbeddingModel(String id) {
    final (provider, modelId) = _splitId(id);
    return _resolve(provider).textEmbeddingModel(modelId);
  }

  /// Resolve an image model by `'provider:modelId'`.
  ImageModelV3 imageModel(String id) {
    final (provider, modelId) = _splitId(id);
    return _resolve(provider).imageModel(modelId);
  }

  /// Resolve a speech model by `'provider:modelId'`.
  SpeechModelV1 speechModel(String id) {
    final (provider, modelId) = _splitId(id);
    return _resolve(provider).speechModel(modelId);
  }

  /// Resolve a transcription model by `'provider:modelId'`.
  TranscriptionModelV1 transcriptionModel(String id) {
    final (provider, modelId) = _splitId(id);
    return _resolve(provider).transcriptionModel(modelId);
  }

  /// Resolve a video model by `'provider:modelId'`.
  VideoModelV1 videoModel(String id) {
    final (provider, modelId) = _splitId(id);
    return _resolve(provider).videoModel(modelId);
  }

  _ProviderLike _resolve(String provider) {
    final p = _providers[provider];
    if (p == null) {
      throw ArgumentError(
        'No provider registered for "$provider". '
        'Available: ${_providers.keys.join(', ')}',
      );
    }
    return p;
  }

  (String, String) _splitId(String id) {
    final idx = id.indexOf(':');
    if (idx < 0) {
      throw ArgumentError(
        'Provider registry id must be in the form "provider:modelId", '
        'got "$id".',
      );
    }
    return (id.substring(0, idx), id.substring(idx + 1));
  }
}

abstract interface class _ProviderLike {
  LanguageModelV3 languageModel(String modelId);
  EmbeddingModelV2<String> textEmbeddingModel(String modelId);
  ImageModelV3 imageModel(String modelId);
  SpeechModelV1 speechModel(String modelId);
  TranscriptionModelV1 transcriptionModel(String modelId);
  VideoModelV1 videoModel(String modelId);
}

class _CallableProvider implements _ProviderLike {
  const _CallableProvider({
    required this.languageModelFactory,
    required this.embeddingModelFactory,
    this.imageModelFactory,
    this.speechModelFactory,
    this.transcriptionModelFactory,
    this.videoModelFactory,
  });

  final LanguageModelV3 Function(String) languageModelFactory;
  final EmbeddingModelV2<String> Function(String) embeddingModelFactory;
  final ImageModelV3 Function(String)? imageModelFactory;
  final SpeechModelV1 Function(String)? speechModelFactory;
  final TranscriptionModelV1 Function(String)? transcriptionModelFactory;
  final VideoModelV1 Function(String)? videoModelFactory;

  @override
  LanguageModelV3 languageModel(String modelId) =>
      languageModelFactory(modelId);

  @override
  EmbeddingModelV2<String> textEmbeddingModel(String modelId) =>
      embeddingModelFactory(modelId);

  @override
  ImageModelV3 imageModel(String modelId) {
    if (imageModelFactory == null) {
      throw UnsupportedError(
        'This provider does not expose an imageModelFactory.',
      );
    }
    return imageModelFactory!(modelId);
  }

  @override
  SpeechModelV1 speechModel(String modelId) {
    if (speechModelFactory == null) {
      throw UnsupportedError(
        'This provider does not expose a speechModelFactory.',
      );
    }
    return speechModelFactory!(modelId);
  }

  @override
  TranscriptionModelV1 transcriptionModel(String modelId) {
    if (transcriptionModelFactory == null) {
      throw UnsupportedError(
        'This provider does not expose a transcriptionModelFactory.',
      );
    }
    return transcriptionModelFactory!(modelId);
  }

  @override
  VideoModelV1 videoModel(String modelId) {
    if (videoModelFactory == null) {
      throw UnsupportedError(
        'This provider does not expose a videoModelFactory.',
      );
    }
    return videoModelFactory!(modelId);
  }
}

/// Creates a [ProviderRegistry] from a map of provider name → [RegistrableProvider].
///
/// Supports all six model types: language, embedding, image, speech,
/// transcription, and video. Only [languageModelFactory] and
/// [embeddingModelFactory] are required; the rest are optional.
///
/// Example:
/// ```dart
/// final registry = createProviderRegistry({
///   'openai': RegistrableProvider(
///     languageModelFactory: openai.call,
///     embeddingModelFactory: openai.embedding,
///     imageModelFactory: openai.image,
///     speechModelFactory: openai.speech,
///     transcriptionModelFactory: openai.transcription,
///   ),
/// });
/// ```
ProviderRegistry createProviderRegistry(
  Map<String, RegistrableProvider> providers,
) {
  return ProviderRegistry._(
    providers.map(
      (name, provider) => MapEntry(
        name,
        _CallableProvider(
          languageModelFactory: provider.languageModelFactory,
          embeddingModelFactory: provider.embeddingModelFactory,
          imageModelFactory: provider.imageModelFactory,
          speechModelFactory: provider.speechModelFactory,
          transcriptionModelFactory: provider.transcriptionModelFactory,
          videoModelFactory: provider.videoModelFactory,
        ),
      ),
    ),
  );
}

/// Describes a provider that can be registered in a [ProviderRegistry].
///
/// [languageModelFactory] and [embeddingModelFactory] are required.
/// Image, speech, transcription, and video factories are optional; calling
/// the corresponding [ProviderRegistry] method on a provider that lacks
/// the factory throws [UnsupportedError].
class RegistrableProvider {
  const RegistrableProvider({
    required this.languageModelFactory,
    required this.embeddingModelFactory,
    this.imageModelFactory,
    this.speechModelFactory,
    this.transcriptionModelFactory,
    this.videoModelFactory,
  });

  final LanguageModelV3 Function(String modelId) languageModelFactory;
  final EmbeddingModelV2<String> Function(String modelId) embeddingModelFactory;
  final ImageModelV3 Function(String modelId)? imageModelFactory;
  final SpeechModelV1 Function(String modelId)? speechModelFactory;
  final TranscriptionModelV1 Function(String modelId)? transcriptionModelFactory;
  final VideoModelV1 Function(String modelId)? videoModelFactory;
}
