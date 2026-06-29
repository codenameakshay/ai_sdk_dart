import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A provider built from explicit factory functions and an optional fallback.
///
/// Mirrors `customProvider()` from the JS AI SDK v6. Use when you need to
/// define a provider on-the-fly from lambdas or to add a fallback chain.
///
/// ```dart
/// final provider = customProvider(
///   languageModels: {
///     'fast': myFastModel,
///     'slow': mySlowModel,
///   },
///   embeddingModels: {
///     'embed': myEmbeddingModel,
///   },
///   fallbackProvider: openai,
/// );
///
/// final model = provider.languageModel('fast');
/// final embed = provider.textEmbeddingModel('embed');
/// // Falls back to openai for unknown IDs:
/// final gpt = provider.languageModel('gpt-4o');
/// ```
class CustomProvider {
  const CustomProvider._({
    required Map<String, LanguageModelV3> languageModels,
    required Map<String, EmbeddingModelV2<String>> embeddingModels,
    required Map<String, ImageModelV3> imageModels,
    required Map<String, SpeechModelV1> speechModels,
    required Map<String, TranscriptionModelV1> transcriptionModels,
    required _ProviderFallback? fallback,
  })  : _languageModels = languageModels,
        _embeddingModels = embeddingModels,
        _imageModels = imageModels,
        _speechModels = speechModels,
        _transcriptionModels = transcriptionModels,
        _fallback = fallback;

  final Map<String, LanguageModelV3> _languageModels;
  final Map<String, EmbeddingModelV2<String>> _embeddingModels;
  final Map<String, ImageModelV3> _imageModels;
  final Map<String, SpeechModelV1> _speechModels;
  final Map<String, TranscriptionModelV1> _transcriptionModels;
  final _ProviderFallback? _fallback;

  /// Resolve a language model by [modelId].
  ///
  /// If not found in this provider's map, delegates to the fallback.
  /// Throws [ArgumentError] when neither map nor fallback knows the id.
  LanguageModelV3 languageModel(String modelId) {
    if (_languageModels.containsKey(modelId)) {
      return _languageModels[modelId]!;
    }
    if (_fallback != null && _fallback.supportsLanguageModel(modelId)) {
      return _fallback.languageModel(modelId);
    }
    throw ArgumentError(
      'No language model registered for "$modelId". '
      'Available: ${_languageModels.keys.join(', ')}',
    );
  }

  /// Resolve an embedding model by [modelId].
  EmbeddingModelV2<String> textEmbeddingModel(String modelId) {
    if (_embeddingModels.containsKey(modelId)) {
      return _embeddingModels[modelId]!;
    }
    if (_fallback != null && _fallback.supportsEmbeddingModel(modelId)) {
      return _fallback.textEmbeddingModel(modelId);
    }
    throw ArgumentError(
      'No embedding model registered for "$modelId". '
      'Available: ${_embeddingModels.keys.join(', ')}',
    );
  }

  /// Resolve an image model by [modelId].
  ImageModelV3 imageModel(String modelId) {
    if (_imageModels.containsKey(modelId)) {
      return _imageModels[modelId]!;
    }
    if (_fallback != null && _fallback.supportsImageModel(modelId)) {
      return _fallback.imageModel(modelId);
    }
    throw ArgumentError(
      'No image model registered for "$modelId". '
      'Available: ${_imageModels.keys.join(', ')}',
    );
  }

  /// Resolve a speech model by [modelId].
  SpeechModelV1 speechModel(String modelId) {
    if (_speechModels.containsKey(modelId)) {
      return _speechModels[modelId]!;
    }
    if (_fallback != null && _fallback.supportsSpeechModel(modelId)) {
      return _fallback.speechModel(modelId);
    }
    throw ArgumentError(
      'No speech model registered for "$modelId". '
      'Available: ${_speechModels.keys.join(', ')}',
    );
  }

  /// Resolve a transcription model by [modelId].
  TranscriptionModelV1 transcriptionModel(String modelId) {
    if (_transcriptionModels.containsKey(modelId)) {
      return _transcriptionModels[modelId]!;
    }
    if (_fallback != null && _fallback.supportsTranscriptionModel(modelId)) {
      return _fallback.transcriptionModel(modelId);
    }
    throw ArgumentError(
      'No transcription model registered for "$modelId". '
      'Available: ${_transcriptionModels.keys.join(', ')}',
    );
  }
}

/// Fallback interface passed to [customProvider].
///
/// Implement this to delegate unknown model IDs to another provider.
abstract interface class _ProviderFallback {
  bool supportsLanguageModel(String modelId);
  LanguageModelV3 languageModel(String modelId);

  bool supportsEmbeddingModel(String modelId);
  EmbeddingModelV2<String> textEmbeddingModel(String modelId);

  bool supportsImageModel(String modelId);
  ImageModelV3 imageModel(String modelId);

  bool supportsSpeechModel(String modelId);
  SpeechModelV1 speechModel(String modelId);

  bool supportsTranscriptionModel(String modelId);
  TranscriptionModelV1 transcriptionModel(String modelId);
}

/// Concrete fallback backed by factory functions.
class _FunctionFallback implements _ProviderFallback {
  const _FunctionFallback({
    this.languageModelFactory,
    this.embeddingModelFactory,
    this.imageModelFactory,
    this.speechModelFactory,
    this.transcriptionModelFactory,
  });

  final LanguageModelV3 Function(String)? languageModelFactory;
  final EmbeddingModelV2<String> Function(String)? embeddingModelFactory;
  final ImageModelV3 Function(String)? imageModelFactory;
  final SpeechModelV1 Function(String)? speechModelFactory;
  final TranscriptionModelV1 Function(String)? transcriptionModelFactory;

  @override
  bool supportsLanguageModel(String id) => languageModelFactory != null;
  @override
  LanguageModelV3 languageModel(String id) => languageModelFactory!(id);

  @override
  bool supportsEmbeddingModel(String id) => embeddingModelFactory != null;
  @override
  EmbeddingModelV2<String> textEmbeddingModel(String id) =>
      embeddingModelFactory!(id);

  @override
  bool supportsImageModel(String id) => imageModelFactory != null;
  @override
  ImageModelV3 imageModel(String id) => imageModelFactory!(id);

  @override
  bool supportsSpeechModel(String id) => speechModelFactory != null;
  @override
  SpeechModelV1 speechModel(String id) => speechModelFactory!(id);

  @override
  bool supportsTranscriptionModel(String id) =>
      transcriptionModelFactory != null;
  @override
  TranscriptionModelV1 transcriptionModel(String id) =>
      transcriptionModelFactory!(id);
}

/// Creates a [CustomProvider] from explicit model maps and an optional fallback.
///
/// Mirrors `customProvider()` from the JS AI SDK v6.
///
/// Parameters:
/// - [languageModels] — map of model ID → [LanguageModelV3] instance.
/// - [embeddingModels] — map of model ID → [EmbeddingModelV2] instance.
/// - [imageModels] — map of model ID → [ImageModelV3] instance.
/// - [speechModels] — map of model ID → [SpeechModelV1] instance.
/// - [transcriptionModels] — map of model ID → [TranscriptionModelV1] instance.
/// - [fallbackLanguageModel] — factory to resolve unknown language model IDs.
/// - [fallbackEmbeddingModel] — factory to resolve unknown embedding model IDs.
/// - [fallbackImageModel] — factory to resolve unknown image model IDs.
CustomProvider customProvider({
  Map<String, LanguageModelV3>? languageModels,
  Map<String, EmbeddingModelV2<String>>? embeddingModels,
  Map<String, ImageModelV3>? imageModels,
  Map<String, SpeechModelV1>? speechModels,
  Map<String, TranscriptionModelV1>? transcriptionModels,
  LanguageModelV3 Function(String modelId)? fallbackLanguageModel,
  EmbeddingModelV2<String> Function(String modelId)? fallbackEmbeddingModel,
  ImageModelV3 Function(String modelId)? fallbackImageModel,
  SpeechModelV1 Function(String modelId)? fallbackSpeechModel,
  TranscriptionModelV1 Function(String modelId)? fallbackTranscriptionModel,
}) {
  final hasFallback = fallbackLanguageModel != null ||
      fallbackEmbeddingModel != null ||
      fallbackImageModel != null ||
      fallbackSpeechModel != null ||
      fallbackTranscriptionModel != null;

  return CustomProvider._(
    languageModels: languageModels ?? const {},
    embeddingModels: embeddingModels ?? const {},
    imageModels: imageModels ?? const {},
    speechModels: speechModels ?? const {},
    transcriptionModels: transcriptionModels ?? const {},
    fallback: hasFallback
        ? _FunctionFallback(
            languageModelFactory: fallbackLanguageModel,
            embeddingModelFactory: fallbackEmbeddingModel,
            imageModelFactory: fallbackImageModel,
            speechModelFactory: fallbackSpeechModel,
            transcriptionModelFactory: fallbackTranscriptionModel,
          )
        : null,
  );
}
