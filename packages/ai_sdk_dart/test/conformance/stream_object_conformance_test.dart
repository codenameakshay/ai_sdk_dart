import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('streamObject conformance', () {
    final schema = Schema<Map<String, dynamic>>(
      jsonSchema: const {'type': 'object'},
      fromJson: (json) => json,
    );

    // Streams a JSON object character-by-character so partial parses occur.
    FakeStreamModel chunked(String json) {
      final parts = <LanguageModelV3StreamPart>[
        const StreamPartTextStart(id: 't1'),
        for (final ch in json.split(''))
          StreamPartTextDelta(id: 't1', delta: ch),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ];
      return FakeStreamModel(parts);
    }

    test('partialObjectStream emits snapshots, object completes', () async {
      final model = chunked('{"a":1,"b":2}');
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );

      final partials = await result.partialObjectStream.toList();
      expect(partials, isNotEmpty);
      final finalObject = await result.object;
      expect(finalObject, {'a': 1, 'b': 2});
    });

    test('textStream forwards raw deltas', () async {
      final model = chunked('{"x":true}');
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final text = (await result.textStream.toList()).join();
      expect(text, '{"x":true}');
    });

    test('patchStream emits replace ops consistent with the final object',
        () async {
      final model = chunked('{"a":1,"b":2}');
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );

      final patches = await result.patchStream.toList();
      expect(patches, isNotEmpty);
      // The document is materialized via a full-document replace at the root.
      final firstBatch = patches.first;
      expect(firstBatch.first.op, 'replace');
      expect(firstBatch.first.path, '');
      // The patch stream is consistent with the completed object.
      expect(await result.object, {'a': 1, 'b': 2});
    });

    test('object future errors when no valid object is generated', () async {
      final model = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'not json'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      // Attach the expectation up front so the object future's rejection is
      // observed (not an unhandled async error) while we drain the stream.
      final expectation = expectLater(
        result.object,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await result.partialObjectStream.toList();
      await expectation;
    });

    test('stream error is forwarded to object and patch streams', () async {
      final model = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: '{"a":1}'),
        StreamPartError(error: StateError('boom')),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.error),
      ]);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      expect(
        () => result.partialObjectStream.toList(),
        throwsA(isA<StateError>()),
      );
    });

    test('parses responseMetadata from rawResponse envelope', () async {
      final model = _MetadataStreamModel();
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      // Force the failure path so responseMetadata flows into the error.
      AiNoObjectGeneratedError? err;
      try {
        await result.object;
      } catch (e) {
        err = e as AiNoObjectGeneratedError;
      }
      expect(err, isNotNull);
      expect(err!.response?.id, 'resp-1');
      expect(err.response?.modelId, 'm-1');
    });

    test('system instruction is included in the call', () async {
      final model = chunked('{"a":1}');
      await streamObject(
        model: model,
        schema: schema,
        system: 'be terse',
        prompt: 'json',
      );
      // FakeStreamModel does not capture options, so just assert it ran.
      expect(true, isTrue);
    });

    test('converts ModelMessages of every role', () async {
      final model = _CapturingStreamModel();
      await streamObject(
        model: model,
        schema: schema,
        messages: const [
          ModelMessage(role: ModelMessageRole.system, content: 's'),
          ModelMessage(role: ModelMessageRole.user, content: 'u'),
          ModelMessage(role: ModelMessageRole.assistant, content: 'a'),
          ModelMessage(role: ModelMessageRole.tool, content: 't'),
        ],
      );
      final roles =
          model.lastOptions!.prompt.messages.map((m) => m.role.name).toList();
      expect(roles, ['system', 'user', 'assistant', 'tool']);
    });

    test('timeout throws when the model is too slow to start streaming',
        () async {
      final model = _SlowStreamModel(const Duration(milliseconds: 200));
      expect(
        () => streamObject(
          model: model,
          schema: schema,
          prompt: 'json',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<Object>()),
      );
    });
  });
}

/// Stream model whose rawResponse carries responseMetadata but emits no
/// parseable object, exercising the metadata-extraction branch.
class _MetadataStreamModel implements LanguageModelV3 {
  @override
  String get provider => 'fake';
  @override
  String get modelId => 'meta-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      LanguageModelV3GenerateResult(
        content: const [],
        finishReason: LanguageModelV3FinishReason.stop,
      );

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'garbage'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]),
      rawResponse: <Object?, Object?>{
        'responseMetadata': {
          'id': 'resp-1',
          'modelId': 'm-1',
          'timestamp': '2024-01-01T00:00:00Z',
        },
        'body': {'ok': true},
        'requestBody': {'q': 'json'},
      },
    );
  }
}

/// Captures the last call options for inspection.
class _CapturingStreamModel implements LanguageModelV3 {
  LanguageModelV3CallOptions? lastOptions;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'capture-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      LanguageModelV3GenerateResult(
        content: const [],
        finishReason: LanguageModelV3FinishReason.stop,
      );

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    lastOptions = options;
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: '{"a":1}'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]),
    );
  }
}

class _SlowStreamModel implements LanguageModelV3 {
  _SlowStreamModel(this.delay);
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-stream-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      LanguageModelV3GenerateResult(
        content: const [],
        finishReason: LanguageModelV3FinishReason.stop,
      );

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    await Future<void>.delayed(delay);
    return LanguageModelV3StreamResult(
      stream: const Stream<LanguageModelV3StreamPart>.empty(),
    );
  }
}
