import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Typed provider options for OpenAI language models.
///
/// Pass the result of [toMap] in [LanguageModelV4CallOptions.providerOptions]
/// under the `'openai'` key:
///
/// ```dart
/// await generateText(
///   model: openai('o3-mini'),
///   prompt: 'Solve this problem',
///   providerOptions: {
///     'openai': OpenAILanguageModelOptions(
///       reasoningEffort: 'high',
///     ).toMap(),
///   },
/// );
/// ```
class OpenAILanguageModelOptions {
  const OpenAILanguageModelOptions({
    this.reasoningEffort,
    this.reasoningSummary,
  });

  /// Controls how much reasoning the model does before responding.
  ///
  /// Supported values: `'low'`, `'medium'`, `'high'`.
  /// Only supported by reasoning models (e.g. `o3`, `o3-mini`, `o1`).
  final String? reasoningEffort;

  /// Controls the format of the reasoning summary returned by the model.
  ///
  /// Supported values: `'auto'`, `'concise'`, `'detailed'`.
  /// Only supported by reasoning models that expose a reasoning summary.
  final String? reasoningSummary;

  /// Serialises this object to the map format expected by the OpenAI API.
  Map<String, dynamic> toMap() => {
    'reasoning_effort': ?reasoningEffort,
    'reasoning_summary': ?reasoningSummary,
  };
}

/// A Responses web search tool. Pass it in [LanguageModelV4CallOptions.tools].
class OpenAIWebSearchTool extends LanguageModelV4ProviderDefinedTool {
  OpenAIWebSearchTool({String? userLocation, this.searchContextSize = 'medium'})
    : super(
        id: 'web_search_preview',
        name: 'web_search_preview',
        args: {
          'search_context_size': searchContextSize,
          if (userLocation case final location?)
            'user_location': {'type': 'approximate', 'city': location},
        },
      );

  final String searchContextSize;
}

/// A Responses file search tool backed by one or more vector stores.
class OpenAIFileSearchTool extends LanguageModelV4ProviderDefinedTool {
  OpenAIFileSearchTool({
    required List<String> vectorStoreIds,
    int? maxNumResults,
  }) : super(
         id: 'file_search',
         name: 'file_search',
         args: {
           'vector_store_ids': vectorStoreIds,
           'max_num_results': ?maxNumResults,
         },
       );
}

/// A Responses code interpreter tool executed in an OpenAI container.
class OpenAICodeInterpreterTool extends LanguageModelV4ProviderDefinedTool {
  OpenAICodeInterpreterTool({Map<String, dynamic>? container})
    : super(
        id: 'code_interpreter',
        name: 'code_interpreter',
        args: {'container': ?container},
      );
}

/// A Responses image generation tool executed by OpenAI.
class OpenAIImageGenerationTool extends LanguageModelV4ProviderDefinedTool {
  OpenAIImageGenerationTool({super.args = const {}})
    : super(id: 'image_generation', name: 'image_generation');
}

/// A Responses MCP tool connected to a remote MCP server.
class OpenAIMcpTool extends LanguageModelV4ProviderDefinedTool {
  OpenAIMcpTool({
    required String serverLabel,
    required String serverUrl,
    List<String>? allowedTools,
    Object? requireApproval,
    Map<String, String>? headers,
  }) : super(
         id: 'mcp',
         name: 'mcp',
         args: {
           'server_label': serverLabel,
           'server_url': serverUrl,
           'allowed_tools': ?allowedTools,
           'require_approval': ?requireApproval,
           'headers': ?headers,
         },
       );
}

/// Uppercase acronym spelling retained for discoverability.
class OpenAIMCPTool extends OpenAIMcpTool {
  OpenAIMCPTool({
    required super.serverLabel,
    required super.serverUrl,
    super.allowedTools,
    super.requireApproval,
    super.headers,
  });
}
