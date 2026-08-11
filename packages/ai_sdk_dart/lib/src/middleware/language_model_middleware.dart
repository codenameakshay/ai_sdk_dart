import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A middleware function that can intercept and transform language model calls.
///
/// Three hook points (all optional via [LanguageModelMiddlewareBase]):
///
/// - [transformParams] — modify call options **before** any generate/stream
///   call.  Runs first; result is forwarded to the inner model.
/// - [wrapGenerate] — intercept the synchronous doGenerate call.
/// - [wrapStream]   — intercept the streaming doStream call.
///
/// Mirrors the JS AI SDK v6 middleware interface.
abstract interface class LanguageModelMiddleware {
  /// Transform [LanguageModelV4CallOptions] before the call reaches the model.
  ///
  /// Return modified options (or the same instance if no change is needed).
  /// Runs before both [wrapGenerate] and [wrapStream].
  FutureOr<LanguageModelV4CallOptions> transformParams({
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  });

  /// Optionally wrap the doGenerate call.
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  });

  /// Optionally wrap the doStream call.
  Future<LanguageModelV4StreamResult> wrapStream({
    required Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    )
    doStream,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  });
}

/// Wraps a [LanguageModelV4] with one or more [LanguageModelMiddleware] layers.
///
/// Mirrors the JS AI SDK v6 signature:
/// ```dart
/// final wrapped = wrapLanguageModel(
///   model: openai('gpt-4o'),
///   middleware: extractReasoningMiddleware(),
/// );
/// // or with multiple middleware:
/// final wrapped = wrapLanguageModel(
///   model: openai('gpt-4o'),
///   middleware: [mw1, mw2],
/// );
/// ```
///
/// When [middleware] is a single [LanguageModelMiddleware] it is treated as a
/// one-element list. When it is a `List<LanguageModelMiddleware>` middleware is
/// applied left-to-right (first entry is the outermost layer).
LanguageModelV4 wrapLanguageModel({
  required LanguageModelV4 model,
  required Object middleware,
}) {
  final List<LanguageModelMiddleware> mwList;
  if (middleware is LanguageModelMiddleware) {
    mwList = [middleware];
  } else if (middleware is List<LanguageModelMiddleware>) {
    mwList = middleware;
  } else {
    throw ArgumentError(
      'middleware must be a LanguageModelMiddleware or '
      'List<LanguageModelMiddleware>',
    );
  }
  var wrapped = model;
  for (final mw in mwList.reversed) {
    wrapped = _WrappedLanguageModel(inner: wrapped, middleware: mw);
  }
  return wrapped;
}

class _WrappedLanguageModel extends LanguageModelV4 {
  const _WrappedLanguageModel({required this.inner, required this.middleware});

  final LanguageModelV4 inner;
  final LanguageModelMiddleware middleware;

  @override
  String get provider => inner.provider;

  @override
  String get modelId => inner.modelId;

  @override
  String get specificationVersion => inner.specificationVersion;

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => inner.supportedUrls;

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final transformed = await middleware.transformParams(
      options: options,
      model: inner,
    );
    return middleware.wrapGenerate(
      doGenerate: inner.doGenerate,
      options: transformed,
      model: inner,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final transformed = await middleware.transformParams(
      options: options,
      model: inner,
    );
    return middleware.wrapStream(
      doStream: inner.doStream,
      options: transformed,
      model: inner,
    );
  }
}

/// Base class providing pass-through defaults for middleware.
///
/// Extend this and override only the methods you need.
abstract class LanguageModelMiddlewareBase implements LanguageModelMiddleware {
  const LanguageModelMiddlewareBase();

  /// Default implementation: returns [options] unchanged.
  @override
  FutureOr<LanguageModelV4CallOptions> transformParams({
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => options;

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => doGenerate(options);

  @override
  Future<LanguageModelV4StreamResult> wrapStream({
    required Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    )
    doStream,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => doStream(options);
}

/// Extracts reasoning enclosed in XML-style tags from text deltas.
///
/// Routes extracted content to [StreamPartReasoningDelta] parts.
/// Mirrors `extractReasoningMiddleware` from the JS AI SDK v6.
///
/// Usage: `extractReasoningMiddleware(tagName: 'think')`
LanguageModelMiddleware extractReasoningMiddleware({String tagName = 'think'}) {
  return _ExtractReasoningMiddleware(tagName: tagName);
}

class _ExtractReasoningMiddleware extends LanguageModelMiddlewareBase {
  const _ExtractReasoningMiddleware({required this.tagName});

  final String tagName;

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    final result = await doGenerate(options);
    final newContent = <LanguageModelV4ContentPart>[];
    for (final part in result.content) {
      if (part is LanguageModelV4TextPart) {
        final extracted = _extractReasoning(part.text, tagName);
        if (extracted.reasoning != null) {
          newContent.add(
            LanguageModelV4ReasoningPart(text: extracted.reasoning!),
          );
        }
        if (extracted.text.isNotEmpty) {
          newContent.add(LanguageModelV4TextPart(text: extracted.text));
        }
      } else {
        newContent.add(part);
      }
    }
    return LanguageModelV4GenerateResult(
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
  Future<LanguageModelV4StreamResult> wrapStream({
    required Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    )
    doStream,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    final result = await doStream(options);
    final transformedStream = _transformStream(result.stream);
    return LanguageModelV4StreamResult(stream: transformedStream);
  }

  Stream<LanguageModelV4StreamPart> _transformStream(
    Stream<LanguageModelV4StreamPart> source,
  ) async* {
    final openTag = '<$tagName>';
    final closeTag = '</$tagName>';
    const reasoningId = 'mw-reasoning';
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
            yield const StreamPartReasoningStart(id: reasoningId);
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
              yield StreamPartReasoningDelta(
                id: reasoningId,
                delta: reasoningChunk,
              );
            }
            buffer.clear();
            buffer.write(accumulated.substring(end + closeTag.length));
            inReasoning = false;
            yield const StreamPartReasoningEnd(id: reasoningId);
          } else {
            final safeEnd = accumulated.length - (closeTag.length - 1);
            if (safeEnd > 0) {
              final safe = accumulated.substring(0, safeEnd);
              yield StreamPartReasoningDelta(id: reasoningId, delta: safe);
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
            yield StreamPartReasoningDelta(id: reasoningId, delta: remaining);
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
        yield StreamPartReasoningDelta(id: reasoningId, delta: remaining);
        yield const StreamPartReasoningEnd(id: reasoningId);
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

/// Strips markdown code fences (``` blocks) from text output.
///
/// Useful when a model wraps JSON in ```json ... ``` blocks.
/// Mirrors `extractJsonMiddleware` from the JS AI SDK v6.
LanguageModelMiddleware extractJsonMiddleware() => _ExtractJsonMiddleware();

class _ExtractJsonMiddleware extends LanguageModelMiddlewareBase {
  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    final result = await doGenerate(options);
    return LanguageModelV4GenerateResult(
      content: result.content.map((part) {
        if (part is LanguageModelV4TextPart) {
          return LanguageModelV4TextPart(text: _stripCodeFences(part.text));
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

/// Wraps a non-streaming model to simulate streaming.
///
/// Useful for models that only support `doGenerate` — fans out the
/// result as a sequence of stream parts.
/// Mirrors `simulateStreamingMiddleware` from the JS AI SDK v6.
LanguageModelMiddleware simulateStreamingMiddleware() =>
    _SimulateStreamingMiddleware();

class _SimulateStreamingMiddleware extends LanguageModelMiddlewareBase {
  @override
  Future<LanguageModelV4StreamResult> wrapStream({
    required Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    )
    doStream,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    final generateResult = await model.doGenerate(options);
    final controller = StreamController<LanguageModelV4StreamPart>();

    controller.onListen = () {
      unawaited(() async {
        try {
          controller.add(
            StreamPartStreamStart(
              warnings: List.unmodifiable(generateResult.warnings),
            ),
          );
          for (final part in generateResult.content) {
            if (part is LanguageModelV4TextPart) {
              controller.add(StreamPartTextStart(id: 'sim-text'));
              controller.add(
                StreamPartTextDelta(id: 'sim-text', delta: part.text),
              );
              controller.add(StreamPartTextEnd(id: 'sim-text'));
            } else if (part is LanguageModelV4ReasoningPart) {
              controller.add(
                const StreamPartReasoningStart(id: 'sim-reasoning'),
              );
              controller.add(
                StreamPartReasoningDelta(id: 'sim-reasoning', delta: part.text),
              );
              controller.add(const StreamPartReasoningEnd(id: 'sim-reasoning'));
            } else if (part is LanguageModelV4ToolCallPart) {
              final argsJson = part.input.toString();
              controller.add(
                StreamPartToolInputStart(
                  id: part.toolCallId,
                  toolName: part.toolName,
                ),
              );
              controller.add(
                StreamPartToolInputDelta(id: part.toolCallId, delta: argsJson),
              );
              controller.add(StreamPartToolInputEnd(id: part.toolCallId));
              controller.add(StreamPartToolCall(toolCall: part));
            } else if (part is LanguageModelV4SourcePart) {
              controller.add(StreamPartSource(source: part));
            } else if (part is LanguageModelV4FilePart) {
              controller.add(StreamPartFile(file: part));
            }
          }
          if (generateResult.response != null) {
            controller.add(
              StreamPartResponseMetadata(metadata: generateResult.response!),
            );
          }
          controller.add(
            StreamPartFinish(
              finishReason: generateResult.finishReason,
              rawFinishReason: generateResult.rawFinishReason,
              usage: generateResult.usage,
              providerMetadata: generateResult.providerMetadata,
            ),
          );
          // Defensive: fanning out an already-resolved generate result over
          // the controller cannot throw (a doGenerate error surfaces earlier).
          // coverage:ignore-start
        } catch (e, st) {
          controller.addError(e, st);
          // coverage:ignore-end
        } finally {
          await controller.close();
        }
      }());
    };

    return LanguageModelV4StreamResult(stream: controller.stream);
  }
}

/// Applies default call option overrides to every call.
///
/// Settings provided at call time take precedence over these defaults.
/// Mirrors `defaultSettingsMiddleware` from the JS AI SDK v6.
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

  LanguageModelV4CallOptions _applyDefaults(LanguageModelV4CallOptions opts) {
    return LanguageModelV4CallOptions(
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
      responseFormat: opts.responseFormat,
      includeRawChunks: opts.includeRawChunks,
      abortSignal: opts.abortSignal,
      reasoning: opts.reasoning,
    );
  }

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => doGenerate(_applyDefaults(options));

  @override
  Future<LanguageModelV4StreamResult> wrapStream({
    required Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    )
    doStream,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => doStream(_applyDefaults(options));
}

/// Enriches tool descriptions with [inputExamples] as JSON snippets.
///
/// Helps models that don't natively support input examples.
/// Mirrors `addToolInputExamplesMiddleware` from the JS AI SDK v6.
LanguageModelMiddleware addToolInputExamplesMiddleware() =>
    _AddToolInputExamplesMiddleware();

class _AddToolInputExamplesMiddleware extends LanguageModelMiddlewareBase {
  LanguageModelV4CallOptions _enrich(LanguageModelV4CallOptions opts) {
    final enriched = opts.tools.map((tool) {
      if (tool is! LanguageModelV4FunctionTool) return tool;
      final examples = tool.inputExamples;
      if (examples == null || examples.isEmpty) return tool;
      final examplesText = examples.map((e) => jsonEncode(e)).join('\n');
      final baseDescription = tool.description ?? tool.name;
      return LanguageModelV4FunctionTool(
        name: tool.name,
        inputSchema: tool.inputSchema,
        description: '$baseDescription\n\nExamples:\n$examplesText',
        strict: tool.strict,
        inputExamples: tool.inputExamples,
        providerOptions: tool.providerOptions,
      );
    }).toList();

    return LanguageModelV4CallOptions(
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
      responseFormat: opts.responseFormat,
      includeRawChunks: opts.includeRawChunks,
      abortSignal: opts.abortSignal,
      reasoning: opts.reasoning,
    );
  }

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => doGenerate(_enrich(options));

  @override
  Future<LanguageModelV4StreamResult> wrapStream({
    required Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    )
    doStream,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) => doStream(_enrich(options));
}
