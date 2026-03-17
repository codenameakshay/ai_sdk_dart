import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('fullStream golden conformance snapshot', () async {
    final fixture = _readFixture('fullstream-basic.json');
    final result = await streamText<String>(
      model: _ConformanceStreamModel(),
      maxSteps: 1,
      tools: {
        'weather': tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          execute: (_, __) async => 'ok',
        ),
      },
    );

    final events = (await result.fullStream.toList())
        .where((event) => event is! StreamTextRawEvent)
        .map(_toSnapshot)
        .toList();

    expect(events, fixture['events']);
  });
}

Map<String, dynamic> _readFixture(String name) {
  final file = File('packages/ai_sdk/test/fixtures/stream_conformance/$name');
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
}

Map<String, dynamic> _toSnapshot(StreamTextEvent event) {
  return switch (event) {
    StreamTextStartEvent() => {'type': 'start'},
    StreamTextStartStepEvent(:final stepNumber) => {
      'type': 'start-step',
      'stepNumber': stepNumber,
    },
    StreamTextTextStartEvent(:final id) => {'type': 'text-start', 'id': id},
    StreamTextTextDeltaEvent(:final id, :final delta) => {
      'type': 'text-delta',
      'id': id,
      'delta': delta,
    },
    StreamTextTextEndEvent(:final id) => {'type': 'text-end', 'id': id},
    StreamTextSourceEvent(:final source) => {
      'type': 'source',
      'id': source.id,
      'url': source.url,
    },
    StreamTextFileEvent(:final file) => {
      'type': 'file',
      'mediaType': file.mediaType,
    },
    StreamTextToolInputStartEvent(:final toolName) => {
      'type': 'tool-input-start',
      'toolName': toolName,
    },
    StreamTextToolInputDeltaEvent(:final toolName, :final delta) => {
      'type': 'tool-input-delta',
      'toolName': toolName,
      'delta': delta,
    },
    StreamTextToolInputEndEvent(:final toolName) => {
      'type': 'tool-input-end',
      'toolName': toolName,
    },
    StreamTextToolResultEvent(:final preliminary) => {
      'type': 'tool-result',
      'preliminary': preliminary,
    },
    StreamTextFinishStepEvent(:final step) => {
      'type': 'finish-step',
      'stepNumber': step.stepNumber,
    },
    StreamTextFinishEvent() => {'type': 'finish'},
    _ => {'type': 'ignored'},
  };
}

class _ConformanceStreamModel implements LanguageModelV3 {
  @override
  String get modelId => 'conformance-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        const StreamPartTextStart(id: 'text-0'),
        const StreamPartTextDelta(id: 'text-0', delta: 'hi'),
        const StreamPartTextEnd(id: 'text-0'),
        const StreamPartSource(
          source: LanguageModelV3SourcePart(
            id: 'src-1',
            url: 'https://example.com',
          ),
        ),
        StreamPartFile(
          file: LanguageModelV3FilePart(
            data: DataContentUrl(Uri.parse('https://example.com/a.pdf')),
            mediaType: 'application/pdf',
          ),
        ),
        const StreamPartToolCallStart(
          toolCallId: 'call_1',
          toolName: 'weather',
        ),
        const StreamPartToolCallDelta(
          toolCallId: 'call_1',
          toolName: 'weather',
          argsTextDelta: '{"city":"Paris"}',
        ),
        const StreamPartToolCallEnd(
          toolCallId: 'call_1',
          toolName: 'weather',
          input: {'city': 'Paris'},
        ),
        const StreamPartFinish(
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
      ]),
    );
  }
}
