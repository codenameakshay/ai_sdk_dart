import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _ResumeAutoResultModel extends LanguageModelV4 {
  final responses = <List<LanguageModelV4ContentPart>>[
    const [
      LanguageModelV4ToolCallPart(
        toolCallId: 'approval-call',
        toolName: 'approveFirst',
        input: {'path': '/tmp/approved'},
      ),
    ],
    const [
      LanguageModelV4TextPart(text: 'continuing'),
      LanguageModelV4ToolCallPart(
        toolCallId: 'auto-call',
        toolName: 'automaticStep',
        input: {'path': '/tmp/automatic'},
      ),
    ],
    const [LanguageModelV4TextPart(text: 'finished')],
  ];
  final seenPrompts = <List<LanguageModelV4Message>>[];
  var _call = 0;

  @override
  String get provider => 'test';

  @override
  String get modelId => 'resume-auto-result';

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
    seenPrompts.add(List.unmodifiable(options.prompt.messages));
    final parts = <LanguageModelV4StreamPart>[];
    var index = 0;
    for (final part in responses[_call++]) {
      final id = 'response-$index';
      switch (part) {
        case LanguageModelV4TextPart(:final text):
          parts
            ..add(StreamPartTextStart(id: id))
            ..add(StreamPartTextDelta(id: id, delta: text))
            ..add(StreamPartTextEnd(id: id));
        case LanguageModelV4ToolCallPart(
          :final toolCallId,
          :final toolName,
          :final input,
        ):
          parts
            ..add(StreamPartToolInputStart(id: toolCallId, toolName: toolName))
            ..add(
              StreamPartToolInputDelta(
                id: toolCallId,
                delta: jsonEncode(input),
              ),
            )
            ..add(StreamPartToolInputEnd(id: toolCallId))
            ..add(StreamPartToolCall(toolCall: part));
        default:
          throw StateError('Unsupported test response part $part');
      }
      index++;
    }
    parts.add(
      const StreamPartFinish(
        finishReason: LanguageModelV4FinishReason.stop,
        rawFinishReason: 'stop',
      ),
    );
    return LanguageModelV4StreamResult(stream: Stream.fromIterable(parts));
  }
}

Tool<Map<String, dynamic>, String> _pathTool({
  required ToolApprovalPolicy approvalPolicy,
  required List<String> executions,
}) => Tool<Map<String, dynamic>, String>(
  inputSchema: Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  ),
  approvalPolicy: approvalPolicy,
  executeDynamic: (input, options) async {
    executions.add((input as Map<String, dynamic>)['path'] as String);
    return 'done';
  },
);

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition not met after 200 event-loop turns.');
}

void main() {
  test(
    'approval resume keeps an automatic tool result once in chronology',
    () async {
      final model = _ResumeAutoResultModel();
      final approvalExecutions = <String>[];
      final automaticExecutions = <String>[];
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(
          model: model,
          maxSteps: 4,
          tools: {
            'approveFirst': _pathTool(
              approvalPolicy: ToolApprovalPolicy.always,
              executions: approvalExecutions,
            ),
            'automaticStep': _pathTool(
              approvalPolicy: ToolApprovalPolicy.never,
              executions: automaticExecutions,
            ),
          },
        ),
        initial: Conversation(id: 'resume-auto-result', messages: const []),
      );

      await backend.send('run the sequence');
      await _pumpUntil(
        () =>
            backend.conversation.messages.last.status ==
                ConversationMessageStatus.pendingApproval ||
            backend.conversation.messages.last.status ==
                ConversationMessageStatus.failed,
      );
      expect(
        backend.conversation.messages.last.status,
        ConversationMessageStatus.pendingApproval,
        reason: '${backend.conversation.messages.last.parts}',
      );
      final approval = backend.conversation.messages.last.parts
          .whereType<ApprovalPart>()
          .single;
      await backend.respondToApproval(
        approvalId: approval.approvalId!,
        approved: true,
      );
      await _pumpUntil(
        () =>
            backend.conversation.messages.last.status ==
                ConversationMessageStatus.complete ||
            backend.conversation.messages.last.status ==
                ConversationMessageStatus.failed,
      );
      expect(
        backend.conversation.messages.last.status,
        ConversationMessageStatus.complete,
        reason: '${backend.conversation.messages.last.parts}',
      );

      expect(approvalExecutions, ['/tmp/approved']);
      expect(automaticExecutions, ['/tmp/automatic']);
      final assistant = backend.conversation.messages.last;
      expect(
        assistant.parts.whereType<ToolResultPart>().map((part) => part.callId),
        ['approval-call', 'auto-call'],
      );
      expect(
        assistant.parts.map(
          (part) => switch (part) {
            TextPart(:final text) => 'text:$text',
            ToolCallPart(:final callId) => 'call:$callId',
            ApprovalPart(:final callId) => 'approval:$callId',
            ToolResultPart(:final callId) => 'result:$callId',
            _ => part.type,
          },
        ),
        [
          'call:approval-call',
          'approval:approval-call',
          'result:approval-call',
          'text:continuing',
          'call:auto-call',
          'result:auto-call',
          'text:finished',
        ],
      );
      final prompts = model.seenPrompts;
      expect(prompts, hasLength(3));
      expect(
        prompts.last
            .expand((message) => message.content)
            .whereType<LanguageModelV4ToolResultPart>()
            .map((part) => part.toolCallId),
        ['approval-call', 'auto-call'],
      );
      await backend.dispose();
    },
  );
}
