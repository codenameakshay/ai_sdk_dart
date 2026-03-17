import '../language_model/language_model_v3_data_content.dart';
import '../shared/json_value.dart';

/// Prompt options for image editing/generation.
class GenerateImagePrompt {
  const GenerateImagePrompt({this.images = const [], this.text, this.mask});

  final List<LanguageModelV3DataContent> images;
  final String? text;
  final LanguageModelV3DataContent? mask;
}

/// Call options for image generation models.
class ImageModelV3CallOptions {
  const ImageModelV3CallOptions({
    this.prompt,
    this.promptObject,
    this.n,
    this.size,
    this.aspectRatio,
    this.seed,
    this.headers,
    this.providerOptions,
  });

  final String? prompt;
  final GenerateImagePrompt? promptObject;
  final int? n;
  final String? size;
  final String? aspectRatio;
  final int? seed;
  final Map<String, String>? headers;
  final ProviderOptions? providerOptions;
}
