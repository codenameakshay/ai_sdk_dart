import '../shared/json_value.dart';

/// Requested shape of the model response.
sealed class LanguageModelV4ResponseFormat {
  const LanguageModelV4ResponseFormat();
}

/// Plain-text model output.
class LanguageModelV4TextResponseFormat extends LanguageModelV4ResponseFormat {
  const LanguageModelV4TextResponseFormat(); // coverage:ignore-line
}

/// JSON model output, optionally constrained by a schema.
class LanguageModelV4JsonResponseFormat extends LanguageModelV4ResponseFormat {
  const LanguageModelV4JsonResponseFormat({
    // coverage:ignore-line
    this.schema,
    this.name,
    this.description,
  });

  final JsonObject? schema;
  final String? name;
  final String? description;
}
