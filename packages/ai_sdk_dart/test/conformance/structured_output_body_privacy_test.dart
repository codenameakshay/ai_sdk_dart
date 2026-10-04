import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

final _schema = Schema<Map<String, dynamic>>(
  jsonSchema: const {'type': 'object'},
  fromJson: (json) => json,
);

const _privateBody = {'secret': 'provider response'};
const _metadata = LanguageModelV4ResponseMetadata(
  id: 'response-1',
  body: _privateBody,
);

void main() {
  test(
    'generateText hides response body on structured output failure',
    () async {
      await expectLater(
        generateText<Map<String, dynamic>>(
          model: _InvalidStructuredOutputModel(),
          prompt: 'prompt',
          output: Output.object(schema: _schema),
        ),
        throwsA(
          isA<AiNoObjectGeneratedError>().having(
            (error) => error.response?.body,
            'response body',
            isNull,
          ),
        ),
      );
    },
  );

  test('generateText retains response body when explicitly opted in', () async {
    await expectLater(
      generateText<Map<String, dynamic>>(
        model: _InvalidStructuredOutputModel(),
        prompt: 'prompt',
        output: Output.object(schema: _schema),
        bodyInclusion: const BodyInclusionPolicy(responseBody: true),
      ),
      throwsA(
        isA<AiNoObjectGeneratedError>().having(
          (error) => error.response?.body,
          'response body',
          _privateBody,
        ),
      ),
    );
  });

  test(
    'streamText hides initial response body on structured output failure',
    () async {
      final result = await streamText<Map<String, dynamic>>(
        model: _InvalidStructuredOutputModel(),
        prompt: 'prompt',
        output: Output.object(schema: _schema),
      );
      await expectLater(
        result.output,
        throwsA(
          isA<AiNoObjectGeneratedError>().having(
            (error) => error.response?.body,
            'response body',
            isNull,
          ),
        ),
      );
    },
  );

  test('streamText retains initial response body when opted in', () async {
    final result = await streamText<Map<String, dynamic>>(
      model: _InvalidStructuredOutputModel(),
      prompt: 'prompt',
      output: Output.object(schema: _schema),
      bodyInclusion: const BodyInclusionPolicy(responseBody: true),
    );
    await expectLater(
      result.output,
      throwsA(
        isA<AiNoObjectGeneratedError>().having(
          (error) => error.response?.body,
          'response body',
          _privateBody,
        ),
      ),
    );
  });
}

class _InvalidStructuredOutputModel extends LanguageModelV4 {
  @override
  String get provider => 'fixture';
  @override
  String get modelId => 'invalid-structured-output';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => const LanguageModelV4GenerateResult(
    content: [LanguageModelV4TextPart(text: 'invalid json')],
    response: _metadata,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
      StreamPartTextStart(id: 'text'),
      StreamPartTextDelta(id: 'text', delta: 'invalid json'),
      StreamPartTextEnd(id: 'text'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]),
    response: _metadata,
  );
}
