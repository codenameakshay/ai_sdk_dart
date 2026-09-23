import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test('instructions takes precedence over system in generateText', () async {
    final model = FakeCapturingModel(responseText: 'ok');
    await generateText(
      model: model,
      instructions: 'canonical',
      system: 'legacy',
      prompt: 'hi',
    );
    expect(model.capturedOptions.single.prompt.system, 'canonical');
  });

  test('instructions takes precedence over system in streamText', () async {
    final model = FakeCapturingStreamModel('ok');
    final result = await streamText(
      model: model,
      instructions: 'canonical',
      system: 'legacy',
      prompt: 'hi',
    );
    await result.text;
    expect(model.lastOptions!.prompt.system, 'canonical');
  });

  test('system messages are rejected before provider invocation', () async {
    final generateModel = FakeCapturingModel(responseText: 'ok');
    await expectLater(
      generateText(
        model: generateModel,
        messages: const [ModelMessage(role: ModelMessageRole.system, content: 's')],
      ),
      throwsArgumentError,
    );
    expect(generateModel.capturedOptions, isEmpty);

    final streamModel = FakeCapturingStreamModel('ok');
    await expectLater(
      streamText(
        model: streamModel,
        messages: const [ModelMessage(role: ModelMessageRole.system, content: 's')],
      ),
      throwsArgumentError,
    );
    expect(streamModel.lastOptions, isNull);
  });

  test('system messages require explicit opt-in', () async {
    final model = FakeCapturingModel(responseText: 'ok');
    await generateText(
      model: model,
      allowSystemInMessages: true,
      messages: const [ModelMessage(role: ModelMessageRole.system, content: 'trusted')],
    );
    expect(model.capturedOptions.single.prompt.messages.single.role,
        LanguageModelV4Role.system);
  });

  test('prepareStep instructions persist, clear, and expose compacted messages', () async {
    final model = _SequenceModel([
      _toolCall(),
      _toolCall(),
      _text('done'),
    ]);
    final executionTool = tool<dynamic, Object?>(
      inputSchema: Schema<dynamic>(jsonSchema: const {'type': 'object'}, fromJson: (j) => j),
      execute: (_, _) async => 'ok',
    );
    final seen = <String?>[];
    final systems = <String>[];
    final messageCounts = <int>[];
    await generateText(
      model: model,
      instructions: 'initial',
      tools: {'tool': executionTool},
      maxSteps: 3,
      prepareStep: (context) {
        seen.add(context.instructions);
        messageCounts.add(context.messages.length);
        return GenerateTextPrepareStepResult(
          instructions: context.stepNumber == 0 ? 'step-one' : '',
          messages: context.stepNumber == 1 ? const [] : null,
        );
      },
    );
    systems.addAll(model.options.map((o) => o.prompt.system ?? ''));
    expect(seen, ['initial', 'step-one', '']);
    expect(systems, ['step-one', '', '']);
    expect(model.options[1].prompt.messages, isEmpty);
    expect(model.options[2].prompt.messages, isNotEmpty);
  });

  test('canonical callbacks win over deprecated callbacks and fire once', () async {
    final model = _SequenceModel([_toolCall(), _text('done')]);
    final executionTool = tool<dynamic, Object?>(
      inputSchema: Schema<dynamic>(jsonSchema: const {'type': 'object'}, fromJson: (j) => j),
      execute: (_, _) async => 'ok',
    );
    var starts = 0, oldStarts = 0, stepStarts = 0, oldStepStarts = 0;
    var toolStarts = 0, oldToolStarts = 0, toolEnds = 0, oldToolEnds = 0;
    var ends = 0, oldEnds = 0;
    String? startInstructions;
    final stepInstructions = <String?>[];
    await generateText(
      model: model,
      instructions: 'canonical',
      system: 'legacy',
      tools: {'tool': executionTool},
      maxSteps: 2,
      onStart: (event) {
        starts++;
        startInstructions = event.instructions;
      },
      experimentalOnStart: (_) => oldStarts++,
      onStepStart: (event) {
        stepStarts++;
        stepInstructions.add(event.instructions);
      },
      experimentalOnStepStart: (_) => oldStepStarts++,
      onToolExecutionStart: (_) => toolStarts++,
      experimentalOnToolCallStart: (_) => oldToolStarts++,
      onToolExecutionEnd: (_) => toolEnds++,
      experimentalOnToolCallFinish: (_) => oldToolEnds++,
      onEnd: (_) => ends++,
      onFinish: (_) => oldEnds++,
    );
    expect(starts, 1);
    expect(oldStarts, 0);
    expect(stepStarts, 2);
    expect(oldStepStarts, 0);
    expect(toolStarts, 1);
    expect(oldToolStarts, 0);
    expect(toolEnds, 1);
    expect(oldToolEnds, 0);
    expect(ends, 1);
    expect(oldEnds, 0);
    expect(startInstructions, 'canonical');
    expect(stepInstructions, ['canonical', 'canonical']);
  });

  test('ToolLoopAgent forwards canonical end callback', () async {
    final model = FakeCapturingModel(responseText: 'ok');
    var ends = 0;
    final agent = ToolLoopAgent(model: model, instructions: 'agent guidance');
    await agent.generate(prompt: 'hi', onEnd: (_) => ends++);
    expect(ends, 1);
    expect(model.capturedOptions.single.prompt.system, 'agent guidance');
  });
}

LanguageModelV4GenerateResult _text(String value) => LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: value)],
      finishReason: LanguageModelV4FinishReason.stop,
    );

LanguageModelV4GenerateResult _toolCall() => LanguageModelV4GenerateResult(
      content: [
        const LanguageModelV4ToolCallPart(
          toolCallId: 'call',
          toolName: 'tool',
          input: <String, dynamic>{},
        ),
      ],
      finishReason: LanguageModelV4FinishReason.toolCalls,
    );

class _SequenceModel extends LanguageModelV4 {
  _SequenceModel(this.responses);
  final List<LanguageModelV4GenerateResult> responses;
  final options = <LanguageModelV4CallOptions>[];
  var index = 0;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'sequence';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    this.options.add(options);
    return responses[index++];
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => throw UnimplementedError();
}
