import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../example/example.dart' as example;

class _Provider extends OpenAIProvider {
  _Provider({this.fails = true}) : super(apiKey: 'test');

  final bool fails;
  bool disposed = false;

  @override
  LanguageModelV4 call(String modelId) => _Model(fails);

  @override
  void dispose({bool force = true}) {
    disposed = true;
    super.dispose(force: force);
  }
}

class _Model extends LanguageModelV4 {
  _Model(this.fails);

  final bool fails;

  @override
  String get provider => 'test';

  @override
  String get modelId => 'test';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    if (fails) throw StateError('generation failed');
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'Done.')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream.fromIterable(const [
      StreamPartTextStart(id: 'text'),
      StreamPartTextDelta(id: 'text', delta: 'Done.'),
      StreamPartTextEnd(id: 'text'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]),
  );
}

void main() {
  test('example disposes its provider when generation fails', () async {
    final provider = _Provider();
    expect(provider.disposed, isFalse);
    await expectLater(example.runExamples(provider), throwsStateError);
    expect(provider.disposed, isTrue);
  });

  test('example disposes its provider after all demos complete', () async {
    final provider = _Provider(fails: false);
    expect(provider.disposed, isFalse);
    await example.runExamples(provider);
    expect(provider.disposed, isTrue);
  });
}
