import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? "streamText" : "generateText"} skips execution cancelled by the start callback',
      () async {
        var executions = 0;
        final tools = {
          'lookup': dynamicTool<String>(
            execute: (_, _) async {
              executions++;
              return 'must not run';
            },
          ),
        };
        final model = FakeToolModel(toolName: 'lookup', toolInput: {});
        final operation = streaming
            ? (await streamText(
                model: model,
                prompt: 'go',
                tools: tools,
                onToolExecutionStart: (event) =>
                    event.options.abortSignal!.cancel(),
              )).text
            : generateText(
                model: model,
                prompt: 'go',
                tools: tools,
                onToolExecutionStart: (event) =>
                    event.options.abortSignal!.cancel(),
              );
        await expectLater(operation, throwsA(isA<AiOperationCancelledError>()));
        expect(executions, 0);
      },
    );
  }
}
