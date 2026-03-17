import '../shared/json_value.dart';

/// A function-style tool the model can call.
///
/// The model generates inputs that match [inputSchema], and the SDK
/// (or user) executes the tool.
class LanguageModelV3FunctionTool {
  const LanguageModelV3FunctionTool({
    required this.name,
    required this.inputSchema,
    this.description,
    this.strict,
    this.inputExamples,
  });

  /// The tool name (must be unique within a tool set).
  final String name;

  /// JSON Schema describing the expected input.
  final JsonObject inputSchema;

  /// Optional description to guide the model on when to use this tool.
  final String? description;

  /// Enable strict schema validation (provider-dependent).
  final bool? strict;

  /// Optional example inputs for the tool (provider-dependent support).
  final List<JsonObject>? inputExamples;
}

/// A provider-defined tool whose schema is controlled by the provider.
///
/// Examples: Anthropic bash_20250124, computer_20241022.
class LanguageModelV3ProviderDefinedTool {
  const LanguageModelV3ProviderDefinedTool({
    required this.id,
    required this.name,
    this.description,
    this.args,
  });

  /// Provider-specific tool ID (e.g., 'anthropic.bash_20250124').
  final String id;

  /// The name for this tool instance.
  final String name;

  final String? description;

  /// Provider-specific configuration arguments.
  final JsonObject? args;
}
