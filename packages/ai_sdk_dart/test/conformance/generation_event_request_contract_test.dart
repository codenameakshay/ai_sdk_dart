import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'step-start events receive generation context in both execution modes',
    () async {
      final context = Object();
      Object? generatedContext;
      Object? streamedContext;

      final generated = await generateText<String>(
        model: FakeTextModel('generated'),
        generationContext: context,
        onStepStart: (event) => generatedContext = event.generationContext,
      );
      final streamed = await streamText<String>(
        model: FakeTextModel('streamed'),
        generationContext: context,
        onStepStart: (event) => streamedContext = event.generationContext,
      );

      expect(generated.text, 'generated');
      expect(await streamed.text, 'streamed');
      expect(generatedContext, same(context));
      expect(streamedContext, same(context));
    },
  );

  for (final (label, instructions, system) in <(String, String?, String?)>[
    ('canonical instructions', 'canonical', null),
    ('legacy system fallback', null, 'legacy'),
  ]) {
    test('$label is recorded in generateText request', () async {
      final result = await generateText<String>(
        model: FakeTextModel('ok'),
        instructions: instructions,
        system: system,
      );

      expect(result.request.instructions, instructions ?? system);
      expect(result.request.system, instructions ?? system);
    });

    test('$label is recorded in streamText request', () async {
      final result = await streamText<String>(
        model: FakeTextModel('ok'),
        instructions: instructions,
        system: system,
      );
      await result.text;
      final request = await result.request;

      expect(request.instructions, instructions ?? system);
      expect(request.system, instructions ?? system);
    });
  }

  test(
    'request instructions retain the initial value after first-step override',
    () async {
      final generated = await generateText<String>(
        model: FakeTextModel('generated'),
        instructions: 'initial',
        prepareStep: (_) =>
            const GenerateTextPrepareStepResult(instructions: 'step override'),
      );
      final streamed = await streamText<String>(
        model: FakeTextModel('streamed'),
        instructions: 'initial',
        prepareStep: (_) =>
            const GenerateTextPrepareStepResult(instructions: 'step override'),
      );
      await streamed.text;

      expect(generated.request.instructions, 'initial');
      expect(generated.request.system, 'initial');
      expect((await streamed.request).instructions, 'initial');
      expect((await streamed.request).system, 'initial');
    },
  );
}
