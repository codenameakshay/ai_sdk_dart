import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../messages/model_message.dart';
import '../output/output.dart';
import '../tools/tool.dart';
import 'partial_json.dart';
import 'body_inclusion.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'shared/operation_scope.dart';
import 'shared/strict_json.dart';
import 'shared/stream_outcome.dart';
import '../telemetry/telemetry.dart';

/// A JSON Patch-style operation for incremental object updates.
///
/// Used by [StreamObjectResult.patchStream] to represent changes between
/// partial object snapshots.
class StreamObjectPatchOperation {
  const StreamObjectPatchOperation({
    required this.op,
    required this.path,
    this.value,
  });

  final String op;
  final String path;
  final Object? value;
}

/// Result returned by [streamObject].
///
/// Provides [stream] for completed objects, [partialObjectStream] for
/// incremental snapshots, [patchStream] for JSON Patch operations,
/// [rawStream] and [textStream] for raw data, and [object] future.
class StreamObjectResult<T> {
  const StreamObjectResult({
    required this.stream,
    required this.partialObjectStream,
    required this.patchStream,
    required this.rawStream,
    required this.textStream,
    required this.object,
  });

  final Stream<T> stream;

  /// Unvalidated JSON snapshots; only [object] and [stream] contain final T values.
  final Stream<Map<String, dynamic>> partialObjectStream;
  final Stream<List<StreamObjectPatchOperation>> patchStream;
  final Stream<LanguageModelV4StreamPart> rawStream;
  final Stream<String> textStream;
  final Future<T> object;
}

/// Streams a structured object as it is generated.
///
/// Dart convenience API for streaming object-only generation. For combined
/// text + tools or structured output in [streamText], use [Output.object]
/// with [StreamTextResult.partialOutputStream] or [StreamTextResult.elementStream].
///
/// Example:
/// ```dart
/// final result = await streamObject(
///   model: model,
///   schema: mySchema,
///   prompt: 'Generate a recipe.',
/// );
/// await for (final partial in result.partialObjectStream) {
///   print(partial);
/// }
/// ```
Future<StreamObjectResult<T>> streamObject<T>({
  required LanguageModelV4 model,
  required Schema<T> schema,
  String? instructions,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  Duration? timeout,
  CancellationToken? abortSignal,
  bool allowSystemInMessages = false,
  BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
  TelemetrySettings? telemetry,
}) async {
  rejectSystemMessages(
    messages ?? const [],
    allowSystemInMessages: allowSystemInMessages,
  );
  final normalizedMessages = <LanguageModelV4Message>[
    if (prompt != null)
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: prompt)],
      ),
    ...?messages?.map(toLanguageModelMessage),
  ];

  final output = Output.object(schema: schema);

  final telemetrySpan = startTelemetrySpan(
    telemetry,
    spanName: 'ai.streamObject',
    attributes: {
      AiTelemetryKeys.modelProvider: model.provider,
      AiTelemetryKeys.modelId: model.modelId,
      if (telemetry?.captureInputs == true && prompt != null)
        'ai.prompt': prompt,
    },
  );
  final metricStopwatch = Stopwatch()..start();
  var terminalMetricRecorded = false;
  void recordMetric(
    String name,
    num value, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) {
    recordTelemetryMetric(
      telemetry,
      TelemetryMetric(
        name: name,
        value: value,
        attributes: {
          AiTelemetryKeys.modelProvider: model.provider,
          AiTelemetryKeys.modelId: model.modelId,
          AiTelemetryKeys.operation: 'streamObject',
          ...attributes,
        },
      ),
    );
  }

  void recordTerminal({required bool success, required bool cancelled}) {
    if (terminalMetricRecorded) return;
    terminalMetricRecorded = true;
    recordMetric(
      AiTelemetryMetrics.totalMs,
      metricStopwatch.elapsedMicroseconds / 1000,
      attributes: {
        AiTelemetryKeys.operationStatus: cancelled
            ? 'cancelled'
            : (success ? 'success' : 'failure'),
      },
    );
    recordMetric(
      success
          ? AiTelemetryMetrics.success
          : (cancelled
                ? AiTelemetryMetrics.cancelled
                : AiTelemetryMetrics.failure),
      1,
    );
    telemetrySpan.end();
  }

  final scope = OperationScope(abortSignal: abortSignal, timeout: timeout);
  final LanguageModelV4StreamResult response;
  try {
    response = await scope.run(() {
      final pending = model.doStream(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            system: buildOutputSystemInstruction(
              instructions ?? system,
              output,
            ),
            messages: normalizedMessages,
          ),
          responseFormat: buildResponseFormat(output),
          abortSignal: scope.signal,
        ),
      );
      unawaited(
        pending.then((lateResponse) async {
          if (scope.signal.isCancelled) {
            try {
              final subscription = lateResponse.stream.listen(
                (_) {},
                onError: (_, _) {},
              );
              await subscription.cancel();
            } catch (_) {}
          }
        }, onError: (_) {}),
      );
      return pending;
    }, raceCancellation: true);
  } catch (error, stackTrace) {
    scope.close();
    final filtered = filterBodyBearingError(error, bodyInclusion);
    telemetrySpan.recordException(filtered, stackTrace: stackTrace);
    recordTerminal(success: false, cancelled: scope.signal.isCancelled);
    Error.throwWithStackTrace(filtered, stackTrace);
  }
  final responseMetadata = response.response;

  final rawController = StreamController<LanguageModelV4StreamPart>.broadcast();
  final textController = StreamController<String>.broadcast();

  final objectController = StreamController<Map<String, dynamic>>.broadcast();
  final patchController =
      StreamController<List<StreamObjectPatchOperation>>.broadcast();
  final objectCompleter = Completer<T>();
  unawaited(() async {
    final buffer = StringBuffer();
    final partialJsonTracker = PartialJsonTracker();
    LanguageModelV4Usage? reportedUsage;
    var firstMeaningfulRecorded = false;
    Map<String, dynamic>? previousJson;
    String? lastPartialFingerprint;
    final iterator = StreamIterator(captureStreamErrors(response.stream));
    try {
      while (await scope.run(iterator.moveNext, raceCancellation: true)) {
        final part = iterator.current.unwrap();
        if (part case StreamPartFinish(:final usage)) {
          reportedUsage = usage;
        }
        final meaningful = switch (part) {
          StreamPartTextDelta(:final delta) => delta.isNotEmpty,
          _ => false,
        };
        if (!firstMeaningfulRecorded && meaningful) {
          firstMeaningfulRecorded = true;
          recordMetric(
            AiTelemetryMetrics.firstMeaningfulMs,
            metricStopwatch.elapsedMicroseconds / 1000,
          );
        }
        if (part is StreamPartRaw && !bodyInclusion.rawChunks) {
          continue;
        }
        if (part is StreamPartError) {
          final filtered = filterBodyBearingError(part.error, bodyInclusion);
          rawController.add(StreamPartError(error: filtered));
          throw filtered;
        }
        if (part is StreamPartResponseMetadata) {
          rawController.add(
            StreamPartResponseMetadata(
              metadata: _filterObjectMetadata(part.metadata, bodyInclusion),
            ),
          );
        } else {
          rawController.add(part);
        }
        if (part is StreamPartTextDelta) {
          textController.add(part.delta);
          buffer.write(part.delta);
          final cadence = partialJsonTracker.append(part.delta);
          if (!cadence.shouldAttemptValue) {
            continue;
          }

          final parsedJson = _tryParseObjectJson(buffer.toString());
          if (parsedJson != null) {
            final fingerprint = partialJsonFingerprint(parsedJson);
            if (fingerprint == lastPartialFingerprint) {
              continue;
            }

            lastPartialFingerprint = fingerprint;
            objectController.add(
              freezePartialJson(parsedJson) as Map<String, dynamic>,
            );

            final patch = _diffObjectPatch(previousJson, parsedJson);
            if (patch.isNotEmpty) {
              patchController.add(patch);
            }
            previousJson = Map<String, dynamic>.from(parsedJson);
          }
        }
      }

      final object = await scope.run(() async {
        late final Map<String, dynamic> finalJson;
        try {
          finalJson = parseCompleteJsonObject(buffer.toString());
        } catch (error) {
          throw AiNoObjectGeneratedError(
            message: 'Failed to generate a valid structured object.',
            text: buffer.toString(),
            response: responseMetadata == null
                ? null
                : _filterObjectMetadata(responseMetadata, bodyInclusion),
            usage: null,
            cause: error,
          );
        }
        return schema.fromJson(finalJson);
      }, raceCancellation: true);
      objectCompleter.complete(object);
      recordMetric(
        AiTelemetryMetrics.usageKnown,
        sumUsage([reportedUsage]) == null ? 0 : 1,
      );
      recordTerminal(success: true, cancelled: false);
    } catch (error, stackTrace) {
      final filtered = filterBodyBearingError(error, bodyInclusion);
      final wasCancelled = scope.signal.isCancelled;
      scope.signal.cancel();
      objectCompleter.completeError(filtered, stackTrace);
      objectController.addError(filtered, stackTrace);
      patchController.addError(filtered, stackTrace);
      rawController.addError(filtered, stackTrace);
      textController.addError(filtered, stackTrace);
      telemetrySpan.recordException(filtered, stackTrace: stackTrace);
      recordTerminal(success: false, cancelled: wasCancelled);
    } finally {
      scope.close();
      unawaited(() async {
        try {
          await iterator.cancel();
        } catch (_) {}
      }());
      unawaited(objectController.close());
      unawaited(patchController.close());
      unawaited(rawController.close());
      unawaited(textController.close());
    }
  }());

  return StreamObjectResult<T>(
    stream: objectCompleter.future.asStream(),
    partialObjectStream: objectController.stream,
    patchStream: patchController.stream,
    rawStream: rawController.stream,
    textStream: textController.stream,
    object: objectCompleter.future,
  );
}

LanguageModelV4ResponseMetadata _filterObjectMetadata(
  LanguageModelV4ResponseMetadata metadata,
  BodyInclusionPolicy policy,
) => LanguageModelV4ResponseMetadata(
  id: metadata.id,
  modelId: metadata.modelId,
  timestamp: metadata.timestamp,
  headers: metadata.headers,
  body: policy.responseBody ? metadata.body : null,
);

Map<String, dynamic>? _tryParseObjectJson(String text) {
  final parsed = tryParsePartialJsonValue(
    text,
    phase: PartialJsonParsePhase.streamObjectSnapshot,
    trigger: PartialJsonParseTrigger.candidateClosed,
    fallbackCandidate: extractLastJsonObject(text),
    repairIncomplete: true,
  );
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }
  return null;
}

List<StreamObjectPatchOperation> _diffObjectPatch(
  Map<String, dynamic>? previous,
  Map<String, dynamic> current,
) {
  if (previous == null) {
    return [
      StreamObjectPatchOperation(
        op: 'replace',
        path: '',
        value: freezePartialJson(current),
      ),
    ];
  }

  final patch = <StreamObjectPatchOperation>[];
  _diffJson(previous, current, path: '', out: patch);
  return patch;
}

void _diffJson(
  Object? previous,
  Object? current, {
  required String path,
  required List<StreamObjectPatchOperation> out,
}) {
  if (previous is Map && current is Map) {
    final previousMap = previous.cast<Object?, Object?>();
    final currentMap = current.cast<Object?, Object?>();

    for (final entry in currentMap.entries) {
      final key = entry.key?.toString() ?? '';
      final nextPath = '$path/${_escapeJsonPointerToken(key)}';
      if (!previousMap.containsKey(entry.key)) {
        out.add(
          StreamObjectPatchOperation(
            op: 'add',
            path: nextPath,
            value: freezePartialJson(entry.value),
          ),
        );
        continue;
      }
      _diffJson(previousMap[entry.key], entry.value, path: nextPath, out: out);
    }

    for (final key in previousMap.keys) {
      if (!currentMap.containsKey(key)) {
        out.add(
          StreamObjectPatchOperation(
            op: 'remove',
            path: '$path/${_escapeJsonPointerToken(key?.toString() ?? '')}',
          ),
        );
      }
    }
    return;
  }

  if (previous is List && current is List) {
    final common = previous.length < current.length
        ? previous.length
        : current.length;
    for (var i = 0; i < common; i++) {
      _diffJson(previous[i], current[i], path: '$path/$i', out: out);
    }
    for (var i = common; i < current.length; i++) {
      out.add(
        StreamObjectPatchOperation(
          op: 'add',
          path: '$path/$i',
          value: freezePartialJson(current[i]),
        ),
      );
    }
    for (var i = previous.length - 1; i >= current.length; i--) {
      out.add(StreamObjectPatchOperation(op: 'remove', path: '$path/$i'));
    }
    return;
  }

  if (previous != current) {
    out.add(
      StreamObjectPatchOperation(
        op: 'replace',
        path: path,
        value: freezePartialJson(current),
      ),
    );
  }
}

String _escapeJsonPointerToken(String token) {
  return token.replaceAll('~', '~0').replaceAll('/', '~1');
}
