import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/shared/operation_scope.dart';
import 'package:ai_sdk_dart/src/core/shared/tool_concurrency.dart';
import 'package:ai_sdk_dart/src/core/streaming/structured_output.dart';
import 'package:ai_sdk_dart/src/core/streaming/tool_execution.dart';
import 'package:ai_sdk_dart/src/core/timeout_helpers.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'runOperation reports a pre-cancelled signal before invoking work',
    () async {
      final token = CancellationToken()..cancel();
      var invoked = false;
      await expectLater(
        runOperation<void>(
          abortSignal: token,
          operation: (_) async {
            invoked = true;
          },
        ),
        throwsA(isA<AiOperationCancelledError>()),
      );
      expect(invoked, isFalse);
    },
  );

  test('operation scope rejects work after a deadline failure', () async {
    final scope = OperationScope(timeout: Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(scope.elapsed, greaterThanOrEqualTo(Duration.zero));
    expect(scope.checkDeadline, throwsA(isA<TimeoutException>()));
    await expectLater(
      scope.run(() async => 1),
      throwsA(isA<TimeoutException>()),
    );
    scope.close();
  });

  test('optional timeout forwards both absent and present timeouts', () async {
    final value = Future.value('ok');
    expect(await withOptionalTimeout(value, null), 'ok');
    expect(
      withOptionalTimeout(
        Future<void>.delayed(const Duration(milliseconds: 20)),
        const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('structured output handles strict arrays and invalid JSON', () {
    final output = Output.array(
      element: Schema<Map<String, dynamic>>(
        jsonSchema: const {'type': 'object'},
        fromJson: (json) => json,
      ),
    );
    expect(parseOutput<List<dynamic>>(output, '[{"ok":true}]', strict: true), [
      {'ok': true},
    ]);
    expect(
      () => parseOutput<Object?>(Output.json(), 'not json'),
      throwsA(isA<AiInvalidToolInputError>()),
    );
  });

  test(
    'bounded tool execution rejects invalid limits and cancellation',
    () async {
      expect(
        executeToolCallsBounded(
          calls: const [],
          maxConcurrency: 0,
          abortSignal: null,
          execute: (_) async => const ToolExecutionResult(),
        ),
        throwsArgumentError,
      );

      final token = CancellationToken();
      final gate = Completer<void>();
      final call = const LanguageModelV4ToolCallPart(
        toolCallId: 'call-1',
        toolName: 'tool',
        input: {},
      );
      final future = executeToolCallsBounded(
        calls: [call],
        maxConcurrency: 1,
        abortSignal: token,
        execute: (_) async {
          await gate.future;
          return const ToolExecutionResult();
        },
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      gate.complete();
      await expectLater(future, throwsA(isA<AiOperationCancelledError>()));
    },
  );

  test('streamText captures prompt telemetry when enabled', () async {
    final result = await streamText(
      model: FakeCapturingStreamModel('ok'),
      prompt: 'captured',
      telemetry: const TelemetrySettings(isEnabled: true, captureInputs: true),
    );
    expect(await result.text, 'ok');
  });

  test(
    'streamText rejects system messages introduced by prepareStep',
    () async {
      final result = await streamText(
        model: FakeCapturingStreamModel('ok'),
        prompt: 'go',
        prepareStep: (_) async => const GenerateTextPrepareStepResult(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.system,
              content: [LanguageModelV4TextPart(text: 'legacy system message')],
            ),
          ],
        ),
      );
      final output = expectLater(result.text, throwsA(isA<ArgumentError>()));
      await expectLater(
        result.fullStream.toList(),
        throwsA(isA<ArgumentError>()),
      );
      await output;
    },
  );

  test('generateText step exposes all result metadata getters', () async {
    final result = await generateText(
      model: FakeCapturingModel(responseText: 'ok'),
      prompt: 'go',
    );
    final step = result.steps.single;
    expect(step.rawFinishReason, isNull);
    expect(step.reasoningText, isEmpty);
    expect(step.providerMetadata, isNull);
    expect(step.responseMetadata, isNull);
  });

  test(
    'generateText rejects system messages introduced by prepareStep',
    () async {
      await expectLater(
        generateText(
          model: FakeCapturingModel(responseText: 'ok'),
          prompt: 'go',
          prepareStep: (_) async => const GenerateTextPrepareStepResult(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.system,
                content: [
                  LanguageModelV4TextPart(text: 'legacy system message'),
                ],
              ),
            ],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
