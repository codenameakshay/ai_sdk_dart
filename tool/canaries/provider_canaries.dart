import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Environment configuration for one credentialed provider canary.
class ProviderCanaryConfig {
  const ProviderCanaryConfig({
    required this.name,
    required this.apiKey,
    required this.model,
  });

  final String name;
  final String? apiKey;
  final String? model;

  bool get isConfigured => apiKey?.isNotEmpty == true;

  void validate() {
    final hasKey = apiKey?.isNotEmpty == true;
    final hasModel = model?.isNotEmpty == true;
    if (hasKey != hasModel) {
      throw FormatException(
        '$name canary requires both its API key and explicit model ID.',
      );
    }
  }
}

/// Reads canary keys and explicit model IDs without exposing key values.
class ProviderCanaryConfiguration {
  const ProviderCanaryConfiguration(this.providers);

  factory ProviderCanaryConfiguration.fromEnvironment(
    Map<String, String> environment,
  ) => ProviderCanaryConfiguration([
    ProviderCanaryConfig(
      name: 'openai',
      apiKey: _value(environment, 'OPENAI_API_KEY'),
      model: _value(environment, 'OPENAI_CANARY_MODEL'),
    ),
    ProviderCanaryConfig(
      name: 'anthropic',
      apiKey: _value(environment, 'ANTHROPIC_API_KEY'),
      model: _value(environment, 'ANTHROPIC_CANARY_MODEL'),
    ),
    ProviderCanaryConfig(
      name: 'google',
      apiKey: _value(environment, 'GOOGLE_API_KEY'),
      model: _value(environment, 'GOOGLE_CANARY_MODEL'),
    ),
  ]);

  final List<ProviderCanaryConfig> providers;

  List<ProviderCanaryConfig> get configuredProviders {
    for (final provider in providers) {
      provider.validate();
    }
    return providers.where((provider) => provider.isConfigured).toList();
  }

  static String? _value(Map<String, String> environment, String name) {
    final value = environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

const _canaryTimeout = TimeoutConfiguration(
  total: Duration(minutes: 2),
  step: Duration(seconds: 45),
  tool: Duration(seconds: 30),
);

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/canaries/provider_canaries.dart --live',
    );
    stdout.writeln(
      'Set each provider API key and matching explicit *_CANARY_MODEL env var.',
    );
    return;
  }

  final configuration = ProviderCanaryConfiguration.fromEnvironment(
    Platform.environment,
  );
  final providers = configuration.configuredProviders;
  if (!arguments.contains('--live')) {
    stdout.writeln(
      'Live provider canaries are opt-in. Configured providers: '
      '${providers.map((provider) => '${provider.name}:${provider.model}').join(', ')}',
    );
    stdout.writeln('Pass --live to make network requests.');
    return;
  }
  if (providers.isEmpty) {
    stderr.writeln(
      'NOT RUN: no complete provider canary key/model pair is configured.',
    );
    throw StateError(
      'No provider canary credentials are configured. Set at least one API '
      'key and matching explicit model ID before using --live.',
    );
  }

  var failures = 0;
  for (final provider in providers) {
    try {
      await runProviderCanary(provider);
      stdout.writeln('PASS ${provider.name} model=${provider.model}');
    } catch (error) {
      failures++;
      stderr.writeln(
        'FAIL ${provider.name} model=${provider.model} error=${error.runtimeType}',
      );
    }
  }
  if (failures > 0) {
    throw StateError('$failures provider canary(s) failed.');
  }
}

/// Runs text, streaming, structured output, tool continuation, and reasoning
/// checks.
Future<void> runProviderCanary(
  ProviderCanaryConfig configuration, {
  LanguageModelV4? modelOverride,
}) async {
  final key = configuration.apiKey;
  final modelId = configuration.model;
  if (key == null || modelId == null) {
    throw ArgumentError('Provider canary configuration is incomplete.');
  }
  final model =
      modelOverride ??
      switch (configuration.name) {
        'openai' => OpenAIProvider(apiKey: key).responses(modelId),
        'anthropic' => AnthropicProvider(apiKey: key).call(modelId),
        'google' => GoogleGenerativeAIProvider(apiKey: key).call(modelId),
        _ => throw ArgumentError('Unknown provider ${configuration.name}.'),
      };

  await _textCanary(model);
  await _streamingCanary(model);
  await _structuredCanary(model);
  await _toolContinuationCanary(model);
  await _reasoningContinuationCanary(model, configuration.name);
}

Future<void> _textCanary(LanguageModelV4 model) async {
  final result = await generateText(
    model: model,
    prompt: 'Reply with the single word READY.',
    maxOutputTokens: 64,
    maxRetries: 0,
    timeout: _canaryTimeout,
  );
  _require(result.text.trim() == 'READY', 'text response was not READY');
}

Future<void> _streamingCanary(LanguageModelV4 model) async {
  final result = await streamText(
    model: model,
    prompt: 'Stream the single word READY.',
    maxOutputTokens: 64,
    maxRetries: 0,
    timeout: _canaryTimeout,
  );
  final chunks = <String>[];
  await for (final chunk in result.textStream) {
    chunks.add(chunk);
  }
  final streamedText = chunks.join().trim();
  _require(streamedText.isNotEmpty, 'text stream was empty');
  _require(streamedText == 'READY', 'text stream was not READY');
  final finalText = (await result.text).trim();
  _require(
    finalText == streamedText,
    'streamed text did not match the final result',
  );
}

Future<void> _structuredCanary(LanguageModelV4 model) async {
  final result = await generateText<Map<String, dynamic>>(
    model: model,
    prompt: 'Return an object with answer equal to READY.',
    maxOutputTokens: 128,
    output: Output.object(
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'answer': {'type': 'string'},
          },
          'required': ['answer'],
          'additionalProperties': false,
        },
        fromJson: (json) => json,
      ),
    ),
    maxRetries: 0,
    timeout: _canaryTimeout,
  );
  _require(
    result.output['answer'] == 'READY',
    'structured answer was not READY',
  );
}

Future<void> _toolContinuationCanary(LanguageModelV4 model) async {
  final result = await generateText(
    model: model,
    prompt: 'Call lookup exactly once, then reply with the lookup result.',
    maxSteps: 2,
    maxOutputTokens: 128,
    tools: {
      'lookup': tool<Map<String, dynamic>, String>(
        description: 'Returns a fixed canary value.',
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
        execute: (_, _) async => 'READY',
      ),
    },
    prepareStep: (context) => context.stepNumber == 0
        ? const GenerateTextPrepareStepResult(
            toolChoice: ToolChoiceSpecific(toolName: 'lookup'),
          )
        : null,
    maxRetries: 0,
    timeout: _canaryTimeout,
  );
  _require(result.toolCalls.length == 1, 'tool call count was not one');
  _require(result.toolResults.length == 1, 'tool result count was not one');
  _require(result.toolResults.single.toolName == 'lookup', 'wrong tool ran');
  _require(
    result.steps.length >= 2,
    'tool continuation did not make two steps',
  );
  _require(result.text.trim().isNotEmpty, 'tool continuation had no text');
}

Future<void> _reasoningContinuationCanary(
  LanguageModelV4 model,
  String providerName,
) async {
  final result = await generateText(
    model: model,
    prompt:
        'Reason briefly, call lookup exactly once, then answer with its result.',
    maxSteps: 2,
    maxOutputTokens: 4096,
    reasoning: LanguageModelV4Reasoning.medium,
    providerOptions: _reasoningProviderOptions(providerName),
    maxRetries: 0,
    timeout: _canaryTimeout,
    tools: {
      'lookup': tool<Map<String, dynamic>, String>(
        description: 'Returns a fixed canary value.',
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
        execute: (_, _) async => 'READY',
      ),
    },
    prepareStep: (context) {
      if (context.stepNumber == 1) {
        final firstStep = context.steps.first;
        final replayedReasoning = context.messages
            .expand((message) => message.content)
            .whereType<LanguageModelV4ReasoningPart>();
        _require(
          firstStep.reasoning.isNotEmpty,
          'reasoning was not returned before continuation',
        );
        for (final expected in firstStep.reasoning) {
          _require(
            replayedReasoning.any((actual) => _sameReasoning(expected, actual)),
            'reasoning/signature was not retained in continuation input',
          );
        }
      }
      return null;
    },
  );
  _require(
    result.steps.length >= 2,
    'reasoning continuation did not make two steps',
  );
  _require(
    result.toolCalls.length == 1,
    'reasoning continuation tool call count was not one',
  );
  _require(
    result.toolResults.length == 1,
    'reasoning continuation tool result count was not one',
  );
  _require(
    result.steps.first.reasoning.isNotEmpty,
    'reasoning was not retained before continuation',
  );
  _require(result.text.trim().isNotEmpty, 'reasoning continuation had no text');
}

bool _sameReasoning(
  LanguageModelV4ReasoningPart expected,
  LanguageModelV4ReasoningPart actual,
) {
  if (expected.text != actual.text ||
      expected.signature != null && expected.signature != actual.signature) {
    return false;
  }
  final expectedOptions = expected.providerOptions;
  return expectedOptions == null ||
      jsonEncode(expectedOptions) == jsonEncode(actual.providerOptions);
}

Map<String, Map<String, dynamic>>? _reasoningProviderOptions(
  String providerName,
) => switch (providerName) {
  'openai' => {
    'openai': const OpenAILanguageModelOptions(
      reasoningEffort: 'medium',
      reasoningSummary: 'detailed',
    ).toMap(),
  },
  'anthropic' => {
    'anthropic': const AnthropicThinkingOptions(budgetTokens: 1024).toMap(),
  },
  'google' => {
    'google': {
      'thinkingConfig': {'thinkingBudget': 2048, 'includeThoughts': true},
    },
  },
  _ => null,
};

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
