import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../errors/ai_errors.dart';
import '../messages/model_message.dart';
import '../tools/tool.dart';

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
  final Stream<LanguageModelV3StreamPart> rawStream;
  final Stream<String> textStream;
  final Future<T> object;
}

Future<StreamObjectResult<T>> streamObject<T>({
  required LanguageModelV3 model,
  required Schema<T> schema,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
}) async {
  final normalizedMessages = <LanguageModelV3Message>[
    if (prompt != null)
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: prompt)],
      ),
    ...?messages?.map(
      (m) => LanguageModelV3Message(
        role: switch (m.role) {
          ModelMessageRole.system => LanguageModelV3Role.system,
          ModelMessageRole.user => LanguageModelV3Role.user,
          ModelMessageRole.assistant => LanguageModelV3Role.assistant,
          ModelMessageRole.tool => LanguageModelV3Role.tool,
        },
        content: m.parts ?? [LanguageModelV3TextPart(text: m.content ?? '')],
      ),
    ),
  ];

  final instruction = [
    if (system != null && system.isNotEmpty) system,
    'Return a single JSON object that matches this schema exactly:',
    jsonEncode(schema.jsonSchema),
    'Do not include markdown fences or extra text.',
  ].join('\n');

  final response = await model.doStream(
    LanguageModelV3CallOptions(
      prompt: LanguageModelV3Prompt(
        system: instruction,
        messages: normalizedMessages,
      ),
    ),
  );
  LanguageModelV3ResponseMetadata? responseMetadata;
  if (response.rawResponse is Map) {
    final raw = (response.rawResponse as Map).cast<Object?, Object?>();
    final meta = raw['responseMetadata'];
    if (meta is Map) {
      final map = meta.cast<Object?, Object?>();
      final ts = map['timestamp']?.toString();
      responseMetadata = LanguageModelV3ResponseMetadata(
        id: map['id']?.toString(),
        modelId: map['modelId']?.toString(),
        timestamp: ts == null ? null : DateTime.tryParse(ts),
        headers: null,
        body: raw['body'],
        requestBody: raw['requestBody'],
      );
    }
  }

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
    Map<String, dynamic>? previousJson;
    T? lastObject;
    try {
      await for (final part in broadcast) {
        if (part is StreamPartTextDelta) {
          buffer.write(part.delta);
          final parsedJson = _tryParseObjectJson(buffer.toString());
          if (parsedJson != null) {
            final parsed = schema.fromJson(parsedJson);
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
          objectController.addError(part.error);
          patchController.addError(part.error);
        }
      }

      if (lastObject != null) {
        objectCompleter.complete(lastObject);
      } else {
        objectCompleter.completeError(
          AiNoObjectGeneratedError(
            message: 'Failed to generate a valid structured object.',
            text: buffer.toString(),
            response: responseMetadata,
            usage: null,
          ),
        );
      }
    } finally {
      await objectController.close();
      await patchController.close();
    }
  }());

  return StreamObjectResult<T>(
    stream: objectController.stream,
    partialObjectStream: objectController.stream,
    patchStream: patchController.stream,
    rawStream: broadcast,
    textStream: textStream,
    object: objectCompleter.future,
  );
}

Map<String, dynamic>? _tryParseObjectJson(String text) {
  final parsed =
      _safeParseJson(text.trim()) ??
      _safeParseJson(_extractLastJsonObject(text) ?? '');
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }
  if (parsed is Map) {
    return parsed.cast<String, dynamic>();
  }
  return null;
}

String? _extractLastJsonObject(String text) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  int? topLevelStart;
  String? lastComplete;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }

    if (char == '{') {
      if (depth == 0) {
        topLevelStart = i;
      }
      depth++;
      continue;
    }

    if (char == '}') {
      depth--;
      if (depth == 0 && topLevelStart != null) {
        lastComplete = text.substring(topLevelStart, i + 1);
        topLevelStart = null;
      }
    }
  }

  return lastComplete;
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

  if (!_jsonValueEquals(previous, current)) {
    out.add(
      StreamObjectPatchOperation(op: 'replace', path: path, value: current),
    );
  }
}

String _escapeJsonPointerToken(String token) {
  return token.replaceAll('~', '~0').replaceAll('/', '~1');
}

bool _jsonValueEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key)) return false;
      if (!_jsonValueEquals(left[key], right[key])) return false;
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_jsonValueEquals(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

Object? _safeParseJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]+?)\s*```',
    ).firstMatch(text);
    if (fenceMatch != null) {
      final fenced = fenceMatch.group(1);
      if (fenced != null) {
        try {
          return jsonDecode(fenced);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }
}
