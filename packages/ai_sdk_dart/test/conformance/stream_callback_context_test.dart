import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'stream callbacks retain generation context and step instructions',
    () async {
      final context = Object();
      Object? startContext;
      Object? prepareContext;
      String? stepInstructions;
      final agent = ToolLoopAgent(
        model: FakeTextModel('ok'),
        generationContext: context,
      );
      final result = await agent.stream(
        prompt: 'go',
        onStart: (event) => startContext = event.generationContext,
        prepareStep: (event) {
          prepareContext = event.generationContext;
          return const GenerateTextPrepareStepResult(instructions: 'updated');
        },
        onStepStart: (event) => stepInstructions = event.instructions,
      );
      expect(await result.text, 'ok');
      expect(startContext, same(context));
      expect(prepareContext, same(context));
      expect(stepInstructions, 'updated');
    },
  );
}
