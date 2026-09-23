import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class _ThrowingRecorder implements TelemetryRecorder {
  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) => throw StateError('recorder secret');
}

class _CapturingRecorder implements TelemetryRecorder {
  final attributes = <String, Object?>{};
  Object? recordedException;
  Object? endedError;

  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) {
    this.attributes.addAll(attributes);
    return _Span(this);
  }
}

class _Span implements TelemetrySpan {
  _Span(this.owner);
  final _CapturingRecorder owner;
  @override
  void setAttribute(String key, Object? value) => owner.attributes[key] = value;
  @override
  void recordException(Object error, {StackTrace? stackTrace}) =>
      owner.recordedException = error;
  @override
  void end({Object? error}) => owner.endedError = error;
}

class _ThrowingSpan implements TelemetrySpan {
  @override
  void setAttribute(String key, Object? value) => throw StateError('set');

  @override
  void recordException(Object error, {StackTrace? stackTrace}) =>
      throw StateError('record');

  @override
  void end({Object? error}) => throw StateError('end');
}

class _ThrowingSpanRecorder implements TelemetryRecorder {
  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) => _ThrowingSpan();
}

void main() {
  test('default telemetry excludes prompt and exception content', () async {
    final recorder = _CapturingRecorder();
    Object? thrown;
    try {
      await generateText(
        model: MockLanguageModelV4(
          doGenerateError: StateError('secret prompt and exception'),
        ),
        prompt: 'secret prompt',
        telemetry: TelemetrySettings(isEnabled: true, recorder: recorder),
      );
    } catch (error) {
      thrown = error;
    }
    expect(thrown, isA<StateError>());
    expect(recorder.attributes, isNot(containsValue('secret prompt')));
    expect(recorder.recordedException.toString(), isNot(contains('secret')));
    expect(recorder.endedError.toString(), isNot(contains('secret')));
  });

  test('recorder failures do not fail generation', () async {
    final result = await generateText(
      model: MockLanguageModelV4(response: [mockText('ok')]),
      prompt: 'hello',
      telemetry: TelemetrySettings(
        isEnabled: true,
        recorder: _ThrowingRecorder(),
      ),
    );
    expect(result.text, 'ok');
  });

  test('exception details are sanitized unless explicitly captured', () {
    final recorder = _CapturingRecorder();
    final span = startTelemetrySpan(
      TelemetrySettings(isEnabled: true, recorder: recorder),
      spanName: 'ai.generateText',
      attributes: {'ai.prompt': 'secret'},
    );
    span.recordException(StateError('secret message'));
    span.end(error: StateError('secret message'));
    expect(recorder.attributes, isNot(containsValue('secret')));
    expect(
      recorder.recordedException.toString(),
      isNot(contains('secret message')),
    );
    expect(recorder.endedError.toString(), isNot(contains('secret message')));
  });

  test('capture and redaction are explicit opt-ins', () {
    final recorder = _CapturingRecorder();
    final span = startTelemetrySpan(
      TelemetrySettings(
        isEnabled: true,
        recorder: recorder,
        captureInputs: true,
        captureExceptionDetails: true,
        redactAttribute: (key, value) =>
            key == 'ai.prompt' ? '[REDACTED]' : value,
      ),
      spanName: 'ai.generateText',
      attributes: {'ai.prompt': 'secret prompt'},
    );
    span.recordException(StateError('secret message'));
    span.end(error: StateError('secret message'));
    expect(recorder.attributes['ai.prompt'], '[REDACTED]');
    expect(recorder.recordedException.toString(), contains('secret message'));
    expect(recorder.endedError.toString(), contains('secret message'));
  });

  test('a failing redactor is isolated from the generation call', () {
    final recorder = _CapturingRecorder();
    expect(
      () => startTelemetrySpan(
        TelemetrySettings(
          isEnabled: true,
          recorder: recorder,
          captureInputs: true,
          redactAttribute: (_, _) => throw StateError('redactor failure'),
        ),
        spanName: 'ai.generateText',
        attributes: {'ai.prompt': 'secret prompt'},
      ),
      returnsNormally,
    );
    expect(recorder.attributes, isEmpty);
  });

  test('post-start content is filtered while usage metrics are preserved', () {
    final recorder = _CapturingRecorder();
    final span = startTelemetrySpan(
      TelemetrySettings(isEnabled: true, recorder: recorder),
      spanName: 'ai.generateText',
      attributes: {'ai.usage.promptTokens': 7},
    );
    span.setAttribute('ai.prompt', 'secret prompt');
    span.setAttribute('ai.usage.outputTokens', 3);
    expect(recorder.attributes, containsPair('ai.usage.promptTokens', 7));
    expect(recorder.attributes, containsPair('ai.usage.outputTokens', 3));
    expect(recorder.attributes, isNot(contains('ai.prompt')));
  });

  test('null redaction omits content at start and after start', () {
    final recorder = _CapturingRecorder();
    final span = startTelemetrySpan(
      TelemetrySettings(
        isEnabled: true,
        recorder: recorder,
        captureInputs: true,
        redactAttribute: (_, _) => null,
      ),
      spanName: 'ai.generateText',
      attributes: {'ai.prompt': 'secret prompt'},
    );
    span.setAttribute('ai.prompt', 'secret prompt 2');
    expect(recorder.attributes, isEmpty);
  });

  test('throwing span methods do not fail generation telemetry', () {
    final span = startTelemetrySpan(
      TelemetrySettings(isEnabled: true, recorder: _ThrowingSpanRecorder()),
      spanName: 'ai.generateText',
      attributes: {},
    );
    expect(
      () => span.setAttribute('ai.usage.outputTokens', 1),
      returnsNormally,
    );
    expect(() => span.recordException(StateError('secret')), returnsNormally);
    expect(() => span.end(error: StateError('secret')), returnsNormally);
  });

  test('streaming failures retain sanitized telemetry', () async {
    final recorder = _CapturingRecorder();
    final result = await streamText(
      model: MockLanguageModelV4(doStreamError: StateError('stream secret')),
      prompt: 'prompt secret',
      telemetry: TelemetrySettings(isEnabled: true, recorder: recorder),
    );
    await expectLater(result.text, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    expect(recorder.attributes, isNot(containsValue('prompt secret')));
    expect(recorder.endedError.toString(), isNot(contains('stream secret')));
  });

  test(
    'streamObject telemetry does not retain the prompt by default',
    () async {
      final recorder = _CapturingRecorder();
      final schema = Schema<Map<String, dynamic>>(
        jsonSchema: const {'type': 'object'},
        fromJson: (json) => json,
      );
      final result = await streamObject(
        model: textDeltaStream(['{"ok":true}']),
        schema: schema,
        prompt: 'object prompt secret',
        telemetry: TelemetrySettings(isEnabled: true, recorder: recorder),
      );
      await result.object;
      expect(recorder.attributes, isNot(containsValue('object prompt secret')));
      expect(
        recorder.attributes.toString(),
        isNot(contains('object prompt secret')),
      );
    },
  );
}
