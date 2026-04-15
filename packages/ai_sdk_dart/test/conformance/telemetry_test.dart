import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _SpanRecord {
  final String name;
  final Map<String, Object?> startAttributes;
  final Map<String, Object?> setAttributes = {};
  Object? endError;
  bool ended = false;

  _SpanRecord(this.name, this.startAttributes);
}

class _TestSpan implements TelemetrySpan {
  _TestSpan(this._record);
  final _SpanRecord _record;

  @override
  void setAttribute(String key, TelemetryAttributeValue value) {
    _record.setAttributes[key] = value;
  }

  @override
  void recordException(Object error, {StackTrace? stackTrace}) {
    _record.setAttributes['error'] = error.toString();
  }

  @override
  void end({Object? error}) {
    _record.ended = true;
    _record.endError = error;
  }
}

class _TestRecorder implements TelemetryRecorder {
  final List<_SpanRecord> spans = [];

  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) {
    final record = _SpanRecord(name, Map.of(attributes));
    spans.add(record);
    return _TestSpan(record);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TelemetrySettings', () {
    test('defaults to disabled', () {
      const settings = TelemetrySettings();
      expect(settings.isEnabled, isFalse);
      expect(settings.functionId, isNull);
      expect(settings.metadata, isEmpty);
      expect(settings.recorder, isNull);
    });

    test('can be enabled with custom fields', () {
      const settings = TelemetrySettings(
        isEnabled: true,
        functionId: 'test-fn',
        metadata: {'env': 'test'},
      );
      expect(settings.isEnabled, isTrue);
      expect(settings.functionId, 'test-fn');
      expect(settings.metadata['env'], 'test');
    });
  });

  group('startTelemetrySpan', () {
    test('returns no-op span when settings is null', () {
      final span = startTelemetrySpan(
        null,
        spanName: 'test',
        attributes: {},
      );
      // No-op span should not throw when called.
      span.setAttribute('key', 'value');
      span.recordException(Exception('test'));
      span.end();
    });

    test('returns no-op span when disabled', () {
      final recorder = _TestRecorder();
      final span = startTelemetrySpan(
        TelemetrySettings(isEnabled: false, recorder: recorder),
        spanName: 'test',
        attributes: {},
      );
      span.end();
      expect(recorder.spans, isEmpty);
    });

    test('starts span with correct name when enabled', () {
      final recorder = _TestRecorder();
      final span = startTelemetrySpan(
        TelemetrySettings(isEnabled: true, recorder: recorder),
        spanName: 'ai.generateText',
        attributes: {'ai.model.id': 'gpt-4'},
      );
      span.end();

      expect(recorder.spans.length, 1);
      expect(recorder.spans.first.name, 'ai.generateText');
    });

    test('merges functionId and metadata into span attributes', () {
      final recorder = _TestRecorder();
      startTelemetrySpan(
        TelemetrySettings(
          isEnabled: true,
          functionId: 'my-function',
          metadata: {'userId': 'u-1'},
          recorder: recorder,
        ),
        spanName: 'ai.generateText',
        attributes: {'ai.model.id': 'gpt-4'},
      );

      final attrs = recorder.spans.first.startAttributes;
      expect(attrs['ai.telemetry.functionId'], 'my-function');
      expect(attrs['userId'], 'u-1');
      expect(attrs['ai.model.id'], 'gpt-4');
    });

    test('uses no-op recorder when enabled but recorder is null', () {
      // Should not throw.
      final span = startTelemetrySpan(
        const TelemetrySettings(isEnabled: true),
        spanName: 'ai.generateText',
        attributes: {},
      );
      span.setAttribute('key', 'value');
      span.end();
    });
  });

  group('generateText telemetry integration', () {
    test('records span when telemetry is enabled', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      await generateText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: true,
          recorder: recorder,
        ),
      );

      expect(recorder.spans.length, 1);
      expect(recorder.spans.first.name, 'ai.generateText');
      expect(recorder.spans.first.ended, isTrue);
    });

    test('records model provider and id as span attributes', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      await generateText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: true,
          recorder: recorder,
        ),
      );

      final attrs = recorder.spans.first.startAttributes;
      expect(attrs['ai.model.provider'], model.provider);
      expect(attrs['ai.model.id'], model.modelId);
      expect(attrs['ai.prompt'], 'Hi');
    });

    test('records usage on span after completion', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Done')],
      );

      await generateText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: true,
          recorder: recorder,
        ),
      );

      final span = recorder.spans.first;
      expect(span.setAttributes.containsKey('ai.usage.promptTokens'), isTrue);
      expect(
        span.setAttributes.containsKey('ai.usage.completionTokens'),
        isTrue,
      );
    });

    test('no span when telemetry is disabled', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      await generateText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: false,
          recorder: recorder,
        ),
      );

      expect(recorder.spans, isEmpty);
    });

    test('records error when model throws', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [],
        doGenerateError: Exception('model error'),
      );

      await expectLater(
        generateText(
          model: model,
          prompt: 'Hi',
          experimentalTelemetry: TelemetrySettings(
            isEnabled: true,
            recorder: recorder,
          ),
        ),
        throwsA(isA<Exception>()),
      );

      expect(recorder.spans.length, 1);
      expect(recorder.spans.first.ended, isTrue);
      expect(recorder.spans.first.endError, isNotNull);
    });

    test('records functionId from telemetry settings', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      await generateText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: true,
          functionId: 'chat-completion',
          recorder: recorder,
        ),
      );

      expect(
        recorder.spans.first.startAttributes['ai.telemetry.functionId'],
        'chat-completion',
      );
    });
  });

  group('streamText telemetry integration', () {
    test('records span when telemetry is enabled', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await streamText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: true,
          recorder: recorder,
        ),
      );
      await result.text; // drain the stream

      expect(recorder.spans.length, 1);
      expect(recorder.spans.first.name, 'ai.streamText');
    });

    test('span ended after stream finishes', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await streamText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: true,
          recorder: recorder,
        ),
      );
      await result.text;
      // Give the async .then() chain a microtask to settle.
      await Future<void>.delayed(Duration.zero);

      expect(recorder.spans.first.ended, isTrue);
    });

    test('no span when telemetry is disabled', () async {
      final recorder = _TestRecorder();
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await streamText(
        model: model,
        prompt: 'Hi',
        experimentalTelemetry: TelemetrySettings(
          isEnabled: false,
          recorder: recorder,
        ),
      );
      await result.text;

      expect(recorder.spans, isEmpty);
    });
  });
}
