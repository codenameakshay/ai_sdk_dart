import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/streaming/structured_output.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

Schema<Map<String, dynamic>> _objectSchema() => Schema.decoderOnly(
  jsonSchema: const {'type': 'object'},
  fromJson: (json) => json,
);

void main() {
  test(
    'cancellation observers attached after cancellation get one event',
    () async {
      final token = CancellationToken()..cancel();
      await token.onCancelled;
      await expectLater(token.cancellationEvents, emits(null));
    },
  );

  test('decoder-only schemas decode complete object output', () async {
    final result = await generateObject<Map<String, dynamic>>(
      model: FakeTextModel('{"ok":true}'),
      schema: _objectSchema(),
      prompt: 'json',
    );
    expect(result.object, {'ok': true});
  });

  test('shared output decoder handles text and non-strict arrays', () {
    expect(parseOutput<String>(Output.text(), 'plain'), 'plain');
    expect(
      parseOutput<List<dynamic>>(
        Output.array(element: _objectSchema()),
        '[{"ok":true}]',
      ),
      [
        {'ok': true},
      ],
    );
  });

  test(
    'streamText decodes text output through its structured output path',
    () async {
      final result = await streamText<String>(
        model: FakeTextModel('plain text'),
        prompt: 'text',
        output: Output.text(),
      );
      expect(await result.output, 'plain text');
    },
  );

  test('streamText decodes a valid structured array', () async {
    final result = await streamText<List<dynamic>>(
      model: FakeTextModel('[{"ok":true}]'),
      prompt: 'json',
      output: Output.array(element: _objectSchema()),
    );
    expect(await result.output, [
      {'ok': true},
    ]);
  });

  test(
    'streamText preserves malformed structured output as terminal errors',
    () async {
      final result = await streamText<List<dynamic>>(
        model: FakeTextModel('[}'),
        prompt: 'json',
        output: Output.array(element: _objectSchema()),
      );
      await expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await expectLater(
        result.finish,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await expectLater(
        result.elementStream.toList(),
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    },
  );

  test('streamText records approval and source telemetry payloads', () async {
    const call = LanguageModelV4ToolCallPart(
      toolCallId: 'call-1',
      toolName: 'lookup',
      input: {},
    );
    final result = await streamText(
      model: FakeStreamModel([
        const StreamPartToolApprovalRequest(
          approvalRequest: LanguageModelV4ToolApprovalRequestPart(
            approvalId: 'approval-1',
            toolCall: call,
          ),
        ),
        const StreamPartSource(
          source: LanguageModelV4SourcePart(
            id: 'source-1',
            url: 'https://example.test/source',
          ),
        ),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
      prompt: 'lookup',
      telemetry: const TelemetrySettings(isEnabled: true),
    );
    await result.fullStream.toList();
  });

  test('streamText records source telemetry independently', () async {
    final result = await streamText(
      model: FakeStreamModel([
        const StreamPartSource(
          source: LanguageModelV4SourcePart(
            id: 'source-1',
            url: 'https://example.test/source',
          ),
        ),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
      prompt: 'source',
      telemetry: const TelemetrySettings(isEnabled: true),
    );
    await result.fullStream.toList();
  });

  test('streamObject reports a non-object JSON response', () async {
    final result = await streamObject(
      model: FakeTextModel('[1,2]'),
      schema: _objectSchema(),
      prompt: 'json',
    );
    await expectLater(result.object, throwsA(isA<AiNoObjectGeneratedError>()));
  });

  test('streamText cancels a provider stream returned after timeout', () async {
    final released = Completer<void>();
    final source = StreamController<LanguageModelV4StreamPart>(
      onCancel: () => released.complete(),
    );
    final result = await streamText(
      model: _LateStreamModel(source),
      prompt: 'late',
      timeout: const TimeoutConfiguration(step: Duration(milliseconds: 1)),
    );
    await expectLater(result.text, throwsA(isA<TimeoutException>()));
    await released.future.timeout(const Duration(seconds: 1));
    await source.close();
  });

  test(
    'telemetry callback sink forwards metrics and reports exporter errors',
    () {
      TelemetryMetric? recorded;
      final sink = CallbackTelemetryMetricSink((metric) => recorded = metric);
      const metric = TelemetryMetric(
        name: 'test',
        value: 2,
        attributes: {'ai.output.text': 'private'},
      );
      sink.record(metric);
      expect(recorded, same(metric));

      Object? diagnostic;
      final filtered = <TelemetryMetric>[];
      recordTelemetryMetric(
        TelemetrySettings(
          isEnabled: true,
          metricSink: CallbackTelemetryMetricSink(filtered.add),
          onDiagnostic: (error) => diagnostic = error,
        ),
        metric,
      );
      expect(filtered.single.attributes, isNot(contains('ai.output.text')));

      recordTelemetryMetric(
        TelemetrySettings(
          isEnabled: true,
          metricSink: CallbackTelemetryMetricSink(
            (_) => throw StateError('sink'),
          ),
          onDiagnostic: (error) => diagnostic = error,
        ),
        const TelemetryMetric(name: 'failure', value: 1),
      );
      expect(diagnostic, isA<StateError>());
    },
  );

  test('embedMany rejects a provider limit below one', () async {
    await expectLater(
      embedMany(model: _InvalidLimitEmbeddingModel(), values: ['value']),
      throwsArgumentError,
    );
  });

  test(
    'tool execution receives runtime context without binding it to the tool',
    () async {
      Object? receivedContext;
      final model = FakeMultiStepModel([
        LanguageModelV4GenerateResult(
          content: const [
            LanguageModelV4ToolCallPart(
              toolCallId: 'call-1',
              toolName: 'inspect',
              input: {},
            ),
          ],
          finishReason: LanguageModelV4FinishReason.toolCalls,
        ),
        LanguageModelV4GenerateResult(
          content: const [LanguageModelV4TextPart(text: 'done')],
          finishReason: LanguageModelV4FinishReason.stop,
        ),
      ]);
      await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 2,
        runtimeContext: const {'tenant': 'acme'},
        approvalPolicyFor: (_, _) => ToolApprovalPolicy.never,
        tools: {
          'inspect': tool<Map<String, dynamic>, String>(
            inputSchema: _objectSchema(),
            execute: (_, options) async {
              receivedContext = options.runtimeContext;
              return 'ok';
            },
          ),
        },
      );
      expect(receivedContext, {'tenant': 'acme'});
    },
  );

  test(
    'simulated streaming forwards document and reasoning-file media',
    () async {
      final model = FakeMultiStepModel([
        LanguageModelV4GenerateResult(
          content: const [
            LanguageModelV4DocumentSourcePart(
              id: 'doc',
              mediaType: 'text/plain',
              title: 'Document',
            ),
            LanguageModelV4ReasoningFilePart(
              data: DataContentBase64('WA=='),
              mediaType: 'text/plain',
              filename: 'reasoning.txt',
            ),
          ],
          finishReason: LanguageModelV4FinishReason.stop,
        ),
      ]);
      final wrapped = wrapLanguageModel(
        model: model,
        middleware: simulateStreamingMiddleware(),
      );
      final response = await wrapped.doStream(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final parts = await response.stream.toList();
      expect(parts.whereType<StreamPartDocumentSource>(), hasLength(1));
      expect(parts.whereType<StreamPartReasoningFile>(), hasLength(1));
    },
  );

  test(
    'embedding middleware exposes the wrapped model specification version',
    () {
      final wrapped = wrapEmbeddingModel(
        model: FakeEmbeddingModel([0.1]),
        middleware: _PassthroughEmbeddingMiddleware(),
      );
      expect(wrapped.specificationVersion, 'v2');
    },
  );
}

class _PassthroughEmbeddingMiddleware
    extends EmbeddingModelMiddlewareBase<String> {}

class _InvalidLimitEmbeddingModel extends FakeEmbeddingModel {
  _InvalidLimitEmbeddingModel() : super([0.1]);

  @override
  int? get maxEmbeddingsPerCall => 0;
}

class _LateStreamModel extends LanguageModelV4 {
  _LateStreamModel(this.source);

  final StreamController<LanguageModelV4StreamPart> source;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'late-stream';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return LanguageModelV4StreamResult(stream: source.stream);
  }
}
