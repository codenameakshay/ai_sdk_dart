import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A middleware function that can intercept and transform language model calls.
abstract interface class LanguageModelMiddleware {
  /// Optionally wrap the doGenerate call.
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  });

  /// Optionally wrap the doStream call.
  Future<LanguageModelV3StreamResult> wrapStream({
    required Future<LanguageModelV3StreamResult> Function(
      LanguageModelV3CallOptions options,
    )
    doStream,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  });
}

/// Wraps a [LanguageModelV3] with one or more [LanguageModelMiddleware] layers.
///
/// Middleware is applied left-to-right (first middleware is the outermost layer).
LanguageModelV3 wrapLanguageModel(
  LanguageModelV3 model,
  List<LanguageModelMiddleware> middleware,
) {
  var wrapped = model;
  for (final mw in middleware.reversed) {
    wrapped = _WrappedLanguageModel(inner: wrapped, middleware: mw);
  }
  return wrapped;
}

class _WrappedLanguageModel implements LanguageModelV3 {
  const _WrappedLanguageModel({required this.inner, required this.middleware});

  final LanguageModelV3 inner;
  final LanguageModelMiddleware middleware;

  @override
  String get provider => inner.provider;

  @override
  String get modelId => inner.modelId;

  @override
  String get specificationVersion => inner.specificationVersion;

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) {
    return middleware.wrapGenerate(
      doGenerate: inner.doGenerate,
      options: options,
      model: inner,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) {
    return middleware.wrapStream(
      doStream: inner.doStream,
      options: options,
      model: inner,
    );
  }
}

/// Base class providing pass-through defaults for middleware.
///
/// Extend this and override only the methods you need.
abstract class LanguageModelMiddlewareBase implements LanguageModelMiddleware {
  const LanguageModelMiddlewareBase();

  @override
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) => doGenerate(options);

  @override
  Future<LanguageModelV3StreamResult> wrapStream({
    required Future<LanguageModelV3StreamResult> Function(
      LanguageModelV3CallOptions options,
    )
    doStream,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) => doStream(options);
}

/// Middleware that extracts reasoning enclosed in XML-style tags from
/// text deltas, routing it to [StreamPartReasoningDelta] parts.
///
/// Usage: `extractReasoningMiddleware(tagName: 'think')`
LanguageModelMiddleware extractReasoningMiddleware({String tagName = 'think'}) {
  return _ExtractReasoningMiddleware(tagName: tagName);
}

class _ExtractReasoningMiddleware extends LanguageModelMiddlewareBase {
  const _ExtractReasoningMiddleware({required this.tagName});

  final String tagName;

  @override
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) async {
    final result = await doGenerate(options);
    final newContent = <LanguageModelV3ContentPart>[];
    for (final part in result.content) {
      if (part is LanguageModelV3TextPart) {
        final extracted = _extractReasoning(part.text, tagName);
        if (extracted.reasoning != null) {
          newContent.add(
            LanguageModelV3ReasoningPart(text: extracted.reasoning!),
          );
        }
        if (extracted.text.isNotEmpty) {
          newContent.add(LanguageModelV3TextPart(text: extracted.text));
        }
      } else {
        newContent.add(part);
      }
    }
    return LanguageModelV3GenerateResult(
      content: newContent,
      finishReason: result.finishReason,
      rawFinishReason: result.rawFinishReason,
      usage: result.usage,
      warnings: result.warnings,
      response: result.response,
      providerMetadata: result.providerMetadata,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> wrapStream({
    required Future<LanguageModelV3StreamResult> Function(
      LanguageModelV3CallOptions options,
    )
    doStream,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) async {
    final result = await doStream(options);
    final transformedStream = _transformStream(result.stream);
    return LanguageModelV3StreamResult(stream: transformedStream);
  }

  Stream<LanguageModelV3StreamPart> _transformStream(
    Stream<LanguageModelV3StreamPart> source,
  ) async* {
    final openTag = '<$tagName>';
    final closeTag = '</$tagName>';
    final buffer = StringBuffer();
    var inReasoning = false;

    await for (final part in source) {
      if (part is StreamPartTextDelta) {
        buffer.write(part.delta);
        final accumulated = buffer.toString();

        if (!inReasoning) {
          final start = accumulated.indexOf(openTag);
          if (start >= 0) {
            final before = accumulated.substring(0, start);
            if (before.isNotEmpty) {
              yield StreamPartTextDelta(id: part.id, delta: before);
            }
            buffer.clear();
            buffer.write(accumulated.substring(start + openTag.length));
            inReasoning = true;
          } else {
            // No tag found yet — safe to emit everything except the last
            // openTag.length-1 chars which might be a partial tag.
            final safeEnd = accumulated.length - (openTag.length - 1);
            if (safeEnd > 0) {
              final safe = accumulated.substring(0, safeEnd);
              yield StreamPartTextDelta(id: part.id, delta: safe);
              buffer.clear();
              buffer.write(accumulated.substring(safeEnd));
            }
          }
        } else {
          final end = accumulated.indexOf(closeTag);
          if (end >= 0) {
            final reasoningChunk = accumulated.substring(0, end);
            if (reasoningChunk.isNotEmpty) {
              yield StreamPartReasoningDelta(delta: reasoningChunk);
            }
            buffer.clear();
            buffer.write(accumulated.substring(end + closeTag.length));
            inReasoning = false;
          } else {
            final safeEnd = accumulated.length - (closeTag.length - 1);
            if (safeEnd > 0) {
              final safe = accumulated.substring(0, safeEnd);
              yield StreamPartReasoningDelta(delta: safe);
              buffer.clear();
              buffer.write(accumulated.substring(safeEnd));
            }
          }
        }
      } else {
        // Flush any buffered text before non-text parts.
        final remaining = buffer.toString();
        if (remaining.isNotEmpty) {
          buffer.clear();
          if (inReasoning) {
            yield StreamPartReasoningDelta(delta: remaining);
          } else {
            // Use a placeholder id since we may not have one here.
            yield StreamPartTextDelta(id: 'mw-text', delta: remaining);
          }
        }
        yield part;
      }
    }
    // Flush remaining buffer.
    final remaining = buffer.toString();
    if (remaining.isNotEmpty) {
      if (inReasoning) {
        yield StreamPartReasoningDelta(delta: remaining);
      } else {
        yield StreamPartTextDelta(id: 'mw-text', delta: remaining);
      }
    }
  }
}

({String? reasoning, String text}) _extractReasoning(
  String text,
  String tagName,
) {
  final openTag = '<$tagName>';
  final closeTag = '</$tagName>';
  final start = text.indexOf(openTag);
  final end = text.indexOf(closeTag);
  if (start >= 0 && end > start) {
    final reasoning = text.substring(start + openTag.length, end);
    final remaining =
        (text.substring(0, start) + text.substring(end + closeTag.length))
            .trim();
    return (reasoning: reasoning, text: remaining);
  }
  return (reasoning: null, text: text);
}

/// Middleware that strips markdown code fences (``` blocks) from text output,
/// useful when a model wraps JSON in ```json ... ``` blocks.
LanguageModelMiddleware extractJsonMiddleware() => _ExtractJsonMiddleware();

class _ExtractJsonMiddleware extends LanguageModelMiddlewareBase {
  @override
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) async {
    final result = await doGenerate(options);
    return LanguageModelV3GenerateResult(
      content: result.content.map((part) {
        if (part is LanguageModelV3TextPart) {
          return LanguageModelV3TextPart(text: _stripCodeFences(part.text));
        }
        return part;
      }).toList(),
      finishReason: result.finishReason,
      rawFinishReason: result.rawFinishReason,
      usage: result.usage,
      warnings: result.warnings,
      response: result.response,
      providerMetadata: result.providerMetadata,
    );
  }

  String _stripCodeFences(String text) {
    final trimmed = text.trim();
    final fencePattern = RegExp(
      r'^```(?:json|[a-zA-Z]*)?\s*\n?([\s\S]*?)\n?```$',
      multiLine: false,
    );
    final match = fencePattern.firstMatch(trimmed);
    return match != null ? match.group(1)!.trim() : trimmed;
  }
}

/// Middleware that wraps a non-streaming model to simulate streaming.
///
/// Useful for models that only support `doGenerate` — this middleware
/// fans out the result as a sequence of stream parts.
LanguageModelMiddleware simulateStreamingMiddleware() =>
    _SimulateStreamingMiddleware();

class _SimulateStreamingMiddleware extends LanguageModelMiddlewareBase {
  @override
  Future<LanguageModelV3StreamResult> wrapStream({
    required Future<LanguageModelV3StreamResult> Function(
      LanguageModelV3CallOptions options,
    )
    doStream,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) async {
    final generateResult = await model.doGenerate(options);
    final controller = StreamController<LanguageModelV3StreamPart>();

    controller.onListen = () {
      unawaited(() async {
        try {
          for (final part in generateResult.content) {
            if (part is LanguageModelV3TextPart) {
              controller.add(StreamPartTextStart(id: 'sim-text'));
              controller.add(
                StreamPartTextDelta(id: 'sim-text', delta: part.text),
              );
              controller.add(StreamPartTextEnd(id: 'sim-text'));
            } else if (part is LanguageModelV3ReasoningPart) {
              controller.add(StreamPartReasoningDelta(delta: part.text));
            } else if (part is LanguageModelV3ToolCallPart) {
              final argsJson = part.input.toString();
              controller.add(
                StreamPartToolCallStart(
                  toolCallId: part.toolCallId,
                  toolName: part.toolName,
                ),
              );
              controller.add(
                StreamPartToolCallDelta(
                  toolCallId: part.toolCallId,
                  toolName: part.toolName,
                  argsTextDelta: argsJson,
                ),
              );
              controller.add(
                StreamPartToolCallEnd(
                  toolCallId: part.toolCallId,
                  toolName: part.toolName,
                  input: part.input,
                ),
              );
            } else if (part is LanguageModelV3SourcePart) {
              controller.add(StreamPartSource(source: part));
            } else if (part is LanguageModelV3FilePart) {
              controller.add(StreamPartFile(file: part));
            }
          }
          controller.add(
            StreamPartFinish(
              finishReason: generateResult.finishReason,
              rawFinishReason: generateResult.rawFinishReason,
              usage: generateResult.usage,
              providerMetadata: generateResult.providerMetadata,
            ),
          );
        } catch (e, st) {
          controller.addError(e, st);
        } finally {
          await controller.close();
        }
      }());
    };

    return LanguageModelV3StreamResult(stream: controller.stream);
  }
}

/// Middleware that applies default call option overrides to every call.
///
/// Settings provided at call time take precedence over [defaults].
LanguageModelMiddleware defaultSettingsMiddleware({
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  int? seed,
  ProviderOptions? providerOptions,
}) {
  return _DefaultSettingsMiddleware(
    maxOutputTokens: maxOutputTokens,
    temperature: temperature,
    topP: topP,
    seed: seed,
    providerOptions: providerOptions,
  );
}

class _DefaultSettingsMiddleware extends LanguageModelMiddlewareBase {
  const _DefaultSettingsMiddleware({
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.seed,
    this.providerOptions,
  });

  final int? maxOutputTokens;
  final double? temperature;
  final double? topP;
  final int? seed;
  final ProviderOptions? providerOptions;

  LanguageModelV3CallOptions _applyDefaults(LanguageModelV3CallOptions opts) {
    return LanguageModelV3CallOptions(
      prompt: opts.prompt,
      tools: opts.tools,
      toolChoice: opts.toolChoice,
      maxOutputTokens: opts.maxOutputTokens ?? maxOutputTokens,
      temperature: opts.temperature ?? temperature,
      topP: opts.topP ?? topP,
      presencePenalty: opts.presencePenalty,
      frequencyPenalty: opts.frequencyPenalty,
      stopSequences: opts.stopSequences,
      seed: opts.seed ?? seed,
      headers: opts.headers,
      providerOptions: opts.providerOptions ?? providerOptions,
    );
  }

  @override
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) => doGenerate(_applyDefaults(options));

  @override
  Future<LanguageModelV3StreamResult> wrapStream({
    required Future<LanguageModelV3StreamResult> Function(
      LanguageModelV3CallOptions options,
    )
    doStream,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) => doStream(_applyDefaults(options));
}

/// Middleware that enriches tool descriptions with their [inputExamples],
/// formatting them as JSON snippets appended to the description.
///
/// This helps models that don't natively support `inputExamples` to still
/// benefit from example-driven prompting.
LanguageModelMiddleware addToolInputExamplesMiddleware() =>
    _AddToolInputExamplesMiddleware();

class _AddToolInputExamplesMiddleware extends LanguageModelMiddlewareBase {
  LanguageModelV3CallOptions _enrich(LanguageModelV3CallOptions opts) {
    final enriched = opts.tools.map((tool) {
      final examples = tool.inputExamples;
      if (examples == null || examples.isEmpty) return tool;
      final examplesText = examples.map((e) => jsonEncode(e)).join('\n');
      final baseDescription = tool.description ?? tool.name;
      return LanguageModelV3FunctionTool(
        name: tool.name,
        inputSchema: tool.inputSchema,
        description: '$baseDescription\n\nExamples:\n$examplesText',
        strict: tool.strict,
        inputExamples: tool.inputExamples,
      );
    }).toList();

    return LanguageModelV3CallOptions(
      prompt: opts.prompt,
      tools: enriched,
      toolChoice: opts.toolChoice,
      maxOutputTokens: opts.maxOutputTokens,
      temperature: opts.temperature,
      topP: opts.topP,
      topK: opts.topK,
      presencePenalty: opts.presencePenalty,
      frequencyPenalty: opts.frequencyPenalty,
      stopSequences: opts.stopSequences,
      seed: opts.seed,
      headers: opts.headers,
      providerOptions: opts.providerOptions,
    );
  }

  @override
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) => doGenerate(_enrich(options));

  @override
  Future<LanguageModelV3StreamResult> wrapStream({
    required Future<LanguageModelV3StreamResult> Function(
      LanguageModelV3CallOptions options,
    )
    doStream,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) => doStream(_enrich(options));
}
