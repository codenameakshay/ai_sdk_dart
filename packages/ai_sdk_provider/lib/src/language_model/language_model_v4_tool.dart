import '../shared/json_value.dart';

/// A tool exposed through the V4 provider seam.
sealed class LanguageModelV4Tool {
  const LanguageModelV4Tool();

  String get name;
  String? get description;
}

/// A function-style tool the model can call.
///
/// The model generates inputs that match [inputSchema], and the SDK
/// (or user) executes the tool.
class LanguageModelV4FunctionTool extends LanguageModelV4Tool {
  const LanguageModelV4FunctionTool({
    required this.name,
    required this.inputSchema,
    this.description,
    this.strict,
    this.inputExamples,
    this.providerOptions,
  }) : super();

  /// The tool name (must be unique within a tool set).
  @override
  final String name;

  /// JSON Schema describing the expected input.
  final JsonObject inputSchema;

  /// Optional description to guide the model on when to use this tool.
  @override
  final String? description;

  /// Enable strict schema validation (provider-dependent).
  final bool? strict;

  /// Optional example inputs for the tool (provider-dependent support).
  final List<JsonObject>? inputExamples;

  /// Provider-specific configuration for this function tool.
  final ProviderOptions? providerOptions;
}

/// A provider-defined tool whose schema is controlled by the provider.
///
/// Examples: Anthropic bash_20250124, computer_20241022.
class LanguageModelV4ProviderDefinedTool extends LanguageModelV4Tool {
  const LanguageModelV4ProviderDefinedTool({
    required this.id,
    required this.name,
    this.description,
    required this.args,
  }) : super();

  /// Provider-specific tool ID (e.g., 'anthropic.bash_20250124').
  final String id;

  /// The name for this tool instance.
  @override
  final String name;

  @override
  final String? description;

  /// Provider-specific configuration arguments.
  final JsonObject args;
}
