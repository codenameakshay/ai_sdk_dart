import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

const _hostedCall = LanguageModelV4ToolCallPart(
  toolCallId: 'hosted',
  toolName: 'search',
  input: {},
  providerExecuted: true,
);
const _hostedResult = LanguageModelV4ToolResultPart(
  toolCallId: 'hosted',
  toolName: 'search',
  output: ToolResultOutputText('remote'),
);

class _HostedModel extends LanguageModelV4 {
  _HostedModel({this.withLocalCall = false});

  final bool withLocalCall;
  var calls = 0;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'hosted';
  @override
  String get specificationVersion => 'v4';

  List<LanguageModelV4ContentPart> get _content => calls == 1
      ? [
          _hostedCall,
          _hostedResult,
          if (withLocalCall)
            const LanguageModelV4ToolCallPart(
              toolCallId: 'local',
              toolName: 'lookup',
              input: {},
            ),
          const LanguageModelV4TextPart(text: 'first'),
        ]
      : [const LanguageModelV4TextPart(text: 'second')];

  LanguageModelV4FinishReason get _finish => withLocalCall && calls == 1
      ? LanguageModelV4FinishReason.toolCalls
      : LanguageModelV4FinishReason.stop;

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    calls++;
    return LanguageModelV4GenerateResult(
      content: _content,
      finishReason: _finish,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    calls++;
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        for (final part in _content)
          ?switch (part) {
            LanguageModelV4ToolCallPart() => StreamPartToolCall(toolCall: part),
            LanguageModelV4ToolResultPart() => StreamPartToolResult(
              toolResult: part,
            ),
            _ => null,
          },
        const StreamPartTextStart(id: 't'),
        StreamPartTextDelta(
          id: 't',
          delta: _content.whereType<LanguageModelV4TextPart>().first.text,
        ),
        const StreamPartTextEnd(id: 't'),
        StreamPartFinish(finishReason: _finish),
      ]),
    );
  }
}

Map<String, Tool> _tools(void Function() onExecute) => {
  'search': dynamicTool<String>(
    execute: (_, _) async {
      onExecute();
      return 'local-search';
    },
  ),
  'lookup': dynamicTool<String>(execute: (_, _) async => 'found'),
};

void main() {
  group('provider-executed tool calls', () {
    test('generateText stops after a hosted-only step', () async {
      final model = _HostedModel();
      var localRuns = 0;
      final result = await generateText(
        model: model,
        prompt: 'search',
        maxSteps: 3,
        tools: _tools(() => localRuns++),
      );
      expect(model.calls, 1);
      expect(localRuns, 0);
      expect(result.text, 'first');
      expect(result.steps.single.toolResults, [_hostedResult]);
    });

    test('streamText stops after a hosted-only step', () async {
      final model = _HostedModel();
      var localRuns = 0;
      final result = await streamText(
        model: model,
        prompt: 'search',
        maxSteps: 3,
        tools: _tools(() => localRuns++),
      );
      expect(await result.text, 'first');
      expect(model.calls, 1);
      expect(localRuns, 0);
      expect((await result.steps).single.toolResults, [_hostedResult]);
    });

    test('generateText continues when a local call accompanies a hosted '
        'call', () async {
      final model = _HostedModel(withLocalCall: true);
      var localRuns = 0;
      final result = await generateText(
        model: model,
        prompt: 'search',
        maxSteps: 3,
        tools: _tools(() => localRuns++),
      );
      expect(model.calls, 2);
      expect(localRuns, 0);
      expect(result.text, 'second');
    });

    test('streamText continues when a local call accompanies a hosted '
        'call', () async {
      final model = _HostedModel(withLocalCall: true);
      var localRuns = 0;
      final result = await streamText(
        model: model,
        prompt: 'search',
        maxSteps: 3,
        tools: _tools(() => localRuns++),
      );
      expect(await result.text, 'second');
      expect(model.calls, 2);
      expect(localRuns, 0);
    });
  });
}
