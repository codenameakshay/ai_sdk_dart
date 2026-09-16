import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../messages/model_message.dart';
import '../output/output.dart';
import '../tools/tool.dart';
import 'partial_json.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'timeout_helpers.dart';

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
  final Stream<T> partialObjectStream;
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
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  Duration? timeout,
}) async {
  final normalizedMessages = <LanguageModelV4Message>[
    if (prompt != null)
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: prompt)],
      ),
    ...?messages?.map(toLanguageModelMessage),
  ];

  final output = Output.object(schema: schema);

  final streamCall = model.doStream(
    LanguageModelV4CallOptions(
      prompt: LanguageModelV4Prompt(
        system: buildOutputSystemInstruction(system, output),
        messages: normalizedMessages,
      ),
      responseFormat: buildResponseFormat(output),
    ),
  );
  final response = await withOptionalTimeout(streamCall, timeout);
  final responseMetadata = response.response;

  final broadcast = response.stream.asBroadcastStream();
  final textStream = broadcast
      .where((part) => part is StreamPartTextDelta)
      .map((part) => (part as StreamPartTextDelta).delta);

  final objectController = StreamController<T>.broadcast();
  final patchController =
      StreamController<List<StreamObjectPatchOperation>>.broadcast();
  final objectCompleter = Completer<T>();
  unawaited(() async {
    final buffer = StringBuffer();
    final partialJsonTracker = PartialJsonTracker();
    Map<String, dynamic>? previousJson;
    String? lastPartialFingerprint;
    T? lastObject;
    Object? streamError;
    try {
      await for (final part in broadcast) {
        if (part is StreamPartTextDelta) {
          buffer.write(part.delta);
          final cadence = partialJsonTracker.append(part.delta);
          if (!cadence.shouldAttemptValue) {
            continue;
          }

          final parsedJson = _tryParseObjectJson(buffer.toString());
          if (parsedJson != null) {
            final parsed = schema.fromJson(parsedJson);
            final fingerprint = partialJsonFingerprint(parsedJson);
            if (fingerprint == lastPartialFingerprint) {
              continue;
            }

            lastPartialFingerprint = fingerprint;
            lastObject = parsed;
            objectController.add(parsed);

            final patch = _diffObjectPatch(previousJson, parsedJson);
            if (patch.isNotEmpty) {
              patchController.add(patch);
            }
            previousJson = Map<String, dynamic>.from(parsedJson);
          }
        }
        if (part is StreamPartError) {
          streamError ??= part.error;
          objectController.addError(part.error);
          patchController.addError(part.error);
        }
      }

      if (streamError != null) {
        objectCompleter.completeError(streamError);
      } else if (lastObject != null) {
        objectCompleter.complete(lastObject);
      } else {
        final error = AiNoObjectGeneratedError(
          message: 'Failed to generate a valid structured object.',
          text: buffer.toString(),
          response: responseMetadata,
          usage: null,
        );
        objectCompleter.completeError(error);
      }
    } finally {
      await objectController.close();
      await patchController.close();
    }
  }());

  return StreamObjectResult<T>(
    stream: objectCompleter.future.asStream(),
    partialObjectStream: objectController.stream,
    patchStream: patchController.stream,
    rawStream: broadcast,
    textStream: textStream,
    object: objectCompleter.future,
  );
}

Map<String, dynamic>? _tryParseObjectJson(String text) {
  final parsed = tryParsePartialJsonValue(
    text,
    phase: PartialJsonParsePhase.streamObjectSnapshot,
    trigger: PartialJsonParseTrigger.candidateClosed,
    fallbackCandidate: extractLastJsonObject(text),
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
      StreamObjectPatchOperation(op: 'replace', path: '', value: current),
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
            value: entry.value,
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
          value: current[i],
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
      StreamObjectPatchOperation(op: 'replace', path: path, value: current),
    );
  }
}

String _escapeJsonPointerToken(String token) {
  return token.replaceAll('~', '~0').replaceAll('/', '~1');
}
