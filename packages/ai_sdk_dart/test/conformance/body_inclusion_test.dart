import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test(
    'body inclusion defaults omit bodies from result and callbacks',
    () async {
      GenerateTextFinishEvent<String>? finish;
      final result = await generateText<String>(
        model: _BodyModel(),
        onEnd: (event) => finish = event,
      );
      expect(result.request.body, isNull);
      expect(result.responseInfo.body, isNull);
      expect(result.responseInfo.metadata?.body, isNull);
      expect(result.steps.single.response.request?.body, isNull);
      expect(result.steps.single.response.response?.body, isNull);
      expect(finish!.response.body, isNull);
    },
  );

  test('body inclusion opt-in retains request and response bodies', () async {
    GenerateTextFinishEvent<String>? finish;
    final result = await generateText<String>(
      model: _BodyModel(),
      bodyInclusion: const BodyInclusionPolicy(
        requestBody: true,
        responseBody: true,
      ),
      onEnd: (event) => finish = event,
    );
    expect(result.request.body, isA<Map<String, dynamic>>());
    expect(result.responseInfo.body, isA<Map<String, dynamic>>());
    expect(result.steps.single.response.request?.body, isNotNull);
    expect(result.steps.single.response.response?.body, isNotNull);
    expect(finish!.response.body, isNotNull);
  });

  test(
    'stream body inclusion applies to final step and step callbacks',
    () async {
      final stepBodies = <Object?>[];
      GenerateTextStepFinishEvent? callbackStep;
      final result = await streamText<String>(
        model: _BodyModel(),
        bodyInclusion: const BodyInclusionPolicy(
          requestBody: true,
          responseBody: true,
        ),
        onStepEnd: (event) => callbackStep = event,
      );
      final step = (await result.steps).single;
      stepBodies.add(step.response.request?.body);
      stepBodies.add(step.response.response?.body);
      expect(stepBodies, everyElement(isNotNull));
      expect((await result.request).body, isNotNull);
      expect((await result.response).body, isNotNull);
      expect(callbackStep, isNotNull);
      expect((await result.finalStep).response.response?.body, isNotNull);
    },
  );

  test('stream provider metadata and errors omit bodies by default', () async {
    Object? observed;
    final providerParts = <LanguageModelV4StreamPart>[];
    Object? providerError;
    final providerDone = Completer<void>();
    final result = await streamText<String>(
      model: _BodyErrorModel(),
      onError: (error) => observed = error,
    );
    result.providerStream.listen(
      providerParts.add,
      onError: (error, _) {
        providerError = error;
        providerDone.complete();
      },
    );
    await expectLater(result.text, throwsA(isA<AiApiCallError>()));
    expect(observed, isA<AiApiCallError>());
    expect((observed! as AiApiCallError).responseBody, isNull);
    await providerDone.future;
    final metadata = providerParts
        .whereType<StreamPartResponseMetadata>()
        .single;
    expect(metadata.metadata.body, isNull);
    expect(providerError, isA<AiApiCallError>());
    expect((providerError! as AiApiCallError).responseBody, isNull);
  });

  test('stream provider raw chunks are opt-in', () async {
    final defaultResult = await streamText<String>(model: _BodyModel());
    final defaultParts = await defaultResult.providerStream.toList();
    expect(defaultParts.whereType<StreamPartRaw>(), isEmpty);

    final optedInResult = await streamText<String>(
      model: _BodyModel(),
      bodyInclusion: const BodyInclusionPolicy.all(),
    );
    final optedInParts = await optedInResult.providerStream.toList();
    expect(optedInParts.whereType<StreamPartRaw>().single.rawValue, {
      'secret': 'raw',
    });
  });

  test('stream callbacks omit response bodies by default', () async {
    StreamTextFinishEvent<String>? finish;
    final result = await streamText<String>(
      model: _BodyModel(),
      onEnd: (event) => finish = event,
    );
    await result.text;
    expect(finish, isNotNull);
    expect(finish!.response.body, isNull);
  });

  test(
    'streamObject filters response metadata and raw chunks by default',
    () async {
      final schema = Schema<Map<String, dynamic>>(
        jsonSchema: const {'type': 'object'},
        fromJson: (json) => json,
      );
      final result = await streamObject(
        model: _BodyObjectModel(),
        schema: schema,
      );
      final partsFuture = result.rawStream.toList();
      expect(await result.object, {'ok': true});
      final parts = await partsFuture;
      expect(parts.whereType<StreamPartRaw>(), isEmpty);
      expect(
        parts.whereType<StreamPartResponseMetadata>().single.metadata.body,
        isNull,
      );

      final optedIn = await streamObject(
        model: _BodyObjectModel(),
        schema: schema,
        bodyInclusion: const BodyInclusionPolicy.all(),
      );
      final optedInPartsFuture = optedIn.rawStream.toList();
      expect(await optedIn.object, {'ok': true});
      final optedInParts = await optedInPartsFuture;
      expect(optedInParts.whereType<StreamPartRaw>().single.rawValue, {
        'secret': 'raw',
      });
      expect(
        optedInParts
            .whereType<StreamPartResponseMetadata>()
            .single
            .metadata
            .body,
        {'secret': 'response'},
      );
    },
  );
}

class _BodyModel extends LanguageModelV4 {
  @override
  String get provider => 'test';

  @override
  String get modelId => 'body-test';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => _result();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream.fromIterable(const [
      StreamPartTextStart(id: 't1'),
      StreamPartRaw(rawValue: {'secret': 'raw'}),
      StreamPartTextDelta(id: 't1', delta: 'ok'),
      StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]),
    request: const LanguageModelV4RequestMetadata(body: {'secret': 'request'}),
    response: const LanguageModelV4ResponseMetadata(
      id: 'response-1',
      body: {'secret': 'response'},
    ),
  );

  static LanguageModelV4GenerateResult _result() =>
      const LanguageModelV4GenerateResult(
        content: [LanguageModelV4TextPart(text: 'ok')],
        request: LanguageModelV4RequestMetadata(body: {'secret': 'request'}),
        response: LanguageModelV4ResponseMetadata(
          id: 'response-1',
          body: {'secret': 'response'},
        ),
      );
}

class _BodyErrorModel extends _BodyModel {
  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream.fromIterable([
      const StreamPartResponseMetadata(
        metadata: LanguageModelV4ResponseMetadata(
          id: 'response-1',
          body: {'secret': 'response'},
        ),
      ),
      StreamPartError(
        error: const AiApiCallError(
          'secret failure',
          responseBody: 'secret body',
          cause: 'secret cause',
        ),
      ),
    ]),
    request: const LanguageModelV4RequestMetadata(body: {'secret': 'request'}),
    response: const LanguageModelV4ResponseMetadata(
      id: 'response-1',
      body: {'secret': 'response'},
    ),
  );
}

class _BodyObjectModel extends _BodyModel {
  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream.fromIterable(const [
      StreamPartResponseMetadata(
        metadata: LanguageModelV4ResponseMetadata(
          id: 'object-response',
          body: {'secret': 'response'},
        ),
      ),
      StreamPartRaw(rawValue: {'secret': 'raw'}),
      StreamPartTextStart(id: 't1'),
      StreamPartTextDelta(id: 't1', delta: '{"ok":true}'),
      StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]),
    request: const LanguageModelV4RequestMetadata(body: {'secret': 'request'}),
    response: const LanguageModelV4ResponseMetadata(
      id: 'object-response',
      body: {'secret': 'response'},
    ),
  );
}
