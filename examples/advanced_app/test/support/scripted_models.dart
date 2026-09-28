import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Streams one scripted response per call, repeating the last one.
class QueuedLanguageModel extends LanguageModelV4 {
  QueuedLanguageModel(this._responses);

  final List<List<LanguageModelV4ContentPart>> _responses;
  int _index = 0;

  @override
  String get provider => 'mock';
  @override
  String get modelId => 'mock-queued-model';
  @override
  String get specificationVersion => 'v4';

  List<LanguageModelV4ContentPart> _next() {
    final content =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return content;
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4GenerateResult(
    content: _next(),
    finishReason: LanguageModelV4FinishReason.stop,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final parts = <LanguageModelV4StreamPart>[
      const StreamPartStreamStart(warnings: []),
    ];
    for (final part in _next()) {
      if (part case LanguageModelV4TextPart(:final text)) {
        parts.addAll([
          const StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          const StreamPartTextEnd(id: 'text-1'),
        ]);
      } else if (part case final LanguageModelV4ToolCallPart call) {
        parts.addAll([
          StreamPartToolInputStart(
            id: call.toolCallId,
            toolName: call.toolName,
          ),
          StreamPartToolInputDelta(
            id: call.toolCallId,
            delta: jsonEncode(call.input),
          ),
          StreamPartToolInputEnd(id: call.toolCallId),
          StreamPartToolCall(toolCall: call),
        ]);
      }
    }
    parts.add(
      const StreamPartFinish(
        finishReason: LanguageModelV4FinishReason.stop,
        usage: LanguageModelV4Usage(),
      ),
    );
    return LanguageModelV4StreamResult(stream: Stream.fromIterable(parts));
  }
}

/// A fake model for the Responses page: streams reasoning, text, and a
/// hosted-tool source citation, so the page's ReasoningView/SourceCitations
/// rendering can be exercised without a network call.
class ResponsesFakeModel extends LanguageModelV4 {
  ResponsesFakeModel({
    this.reasoning = 'Checking sources…',
    this.text = 'Flutter 3.44 is current.',
    this.sources = const [
      LanguageModelV4SourcePart(
        id: 'source-1',
        url: 'https://flutter.dev/docs/release',
        title: 'Flutter release notes',
      ),
    ],
  });

  final String reasoning;
  final String text;
  final List<LanguageModelV4SourcePart> sources;

  @override
  String get provider => 'mock';
  @override
  String get modelId => 'mock-responses-model';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4GenerateResult(
    content: [LanguageModelV4TextPart(text: text)],
    finishReason: LanguageModelV4FinishReason.stop,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartStreamStart(warnings: []),
        const StreamPartReasoningStart(id: 'r1'),
        StreamPartReasoningDelta(id: 'r1', delta: reasoning),
        const StreamPartReasoningEnd(id: 'r1'),
        const StreamPartTextStart(id: 't1'),
        StreamPartTextDelta(id: 't1', delta: text),
        const StreamPartTextEnd(id: 't1'),
        for (final source in sources) StreamPartSource(source: source),
        const StreamPartFinish(
          finishReason: LanguageModelV4FinishReason.stop,
          usage: LanguageModelV4Usage(),
        ),
      ]),
    );
  }
}
