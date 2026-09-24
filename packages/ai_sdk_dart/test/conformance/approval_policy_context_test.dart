import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('request approval policy overrides the tool-local policy', () async {
    var executed = false;
    final model = _TwoStepModel();
    final result = await generateText(
      model: model,
      prompt: 'go',
      maxSteps: 1,
      approvalPolicy: ToolApprovalPolicy.always,
      tools: {
        'danger': _tool((_, _) async {
          executed = true;
          return 'done';
        }),
      },
    );
    expect(result.toolApprovalRequests, hasLength(1));
    expect(executed, isFalse);
  });

  test(
    'approval binding rejects changed arguments and policy revisions',
    () async {
      var executed = false;
      final model = _TwoStepModel();
      final first = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        approvalPolicyRevision: 'v1',
        tools: {
          'danger': _tool((_, _) async {
            executed = true;
            return 'done';
          }),
        },
      );
      final request = first.toolApprovalRequests.single;
      final response = LanguageModelV4ToolApprovalResponse(
        approvalId: request.approvalId,
        approved: true,
        toolCallId: request.toolCall.toolCallId,
        toolName: request.toolCall.toolName,
        argumentsFingerprint: request.argumentsFingerprint,
        policyRevision: 'v0',
      );
      final second = await generateText(
        model: _TwoStepModel(),
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        approvalPolicyRevision: 'v1',
        toolApprovalResponses: [response],
        tools: {
          'danger': _tool((_, _) async {
            executed = true;
            return 'done';
          }),
        },
      );
      expect(second.toolApprovalRequests, hasLength(1));
      expect(executed, isFalse);
      final changedArguments = await generateText(
        model: _TwoStepModel(),
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        approvalPolicyRevision: 'v1',
        toolApprovalResponses: [
          LanguageModelV4ToolApprovalResponse(
            approvalId: request.approvalId,
            approved: true,
            toolCallId: request.toolCall.toolCallId,
            toolName: request.toolCall.toolName,
            argumentsFingerprint: '{"value":999}',
            policyRevision: 'v1',
          ),
        ],
        tools: {
          'danger': _tool((_, _) async {
            executed = true;
            return 'done';
          }),
        },
      );
      expect(changedArguments.toolApprovalRequests, hasLength(1));
      expect(executed, isFalse);
    },
  );

  test(
    'generation context reaches tools without entering provider messages',
    () async {
      Object? seenContext;
      Object? seenToolContext;
      Object? seenPrepareContext;
      final model = _TwoStepModel();
      await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 2,
        generationContext: const {'secret': 'context-secret'},
        prepareStep: (context) {
          seenPrepareContext = context.generationContext;
          return null;
        },
        tools: {
          'danger': _tool((_, options) async {
            seenContext = options.generationContext;
            seenToolContext =
                (options.toolContext as ToolExecutionContext).value;
            return 'done';
          }, toolContext: const {'tool-secret': 'tool-only'}),
        },
      );
      expect(seenContext, const {'secret': 'context-secret'});
      expect(seenPrepareContext, const {'secret': 'context-secret'});
      expect(seenToolContext, const {'tool-secret': 'tool-only'});
      final promptText = model.seenMessages!
          .expand((message) => message.content)
          .whereType<LanguageModelV4TextPart>()
          .map((part) => part.text)
          .join('\n');
      expect(promptText, isNot(contains('context-secret')));
      expect(promptText, isNot(contains('tool-secret')));
    },
  );

  test(
    'bound approval executes and denied approval does not execute',
    () async {
      var executions = 0;
      final first = await generateText(
        model: _TwoStepModel(),
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        tools: {
          'danger': _tool((_, _) async {
            executions++;
            return 'ok';
          }),
        },
      );
      final request = first.toolApprovalRequests.single;
      final response = LanguageModelV4ToolApprovalResponse(
        approvalId: request.approvalId,
        approved: true,
        toolCallId: request.toolCall.toolCallId,
        toolName: request.toolCall.toolName,
        argumentsFingerprint: request.argumentsFingerprint,
        policyRevision: request.policyRevision,
      );
      final approved = await generateText(
        model: _TwoStepModel(),
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        toolApprovalResponses: [response],
        tools: {
          'danger': _tool((_, _) async {
            executions++;
            return 'ok';
          }),
        },
      );
      expect(approved.toolApprovalRequests, isEmpty);
      expect(executions, 1);
      final denied = await generateText(
        model: _TwoStepModel(),
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        toolApprovalResponses: [
          LanguageModelV4ToolApprovalResponse(
            approvalId: response.approvalId,
            approved: false,
            toolCallId: response.toolCallId,
            toolName: response.toolName,
            argumentsFingerprint: response.argumentsFingerprint,
            policyRevision: response.policyRevision,
          ),
        ],
        tools: {
          'danger': _tool((_, _) async {
            executions++;
            return 'ok';
          }),
        },
      );
      expect(denied.toolApprovalRequests, isEmpty);
      expect(executions, 1);
    },
  );

  test(
    'typed tool context binds the executor without exposing secrets',
    () async {
      const context = _TypedContext('typed-secret');
      _TypedContext? seen;
      final model = _TwoStepModel();
      await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 1,
        tools: {
          'danger':
              toolWithContext<Map<String, dynamic>, String, _TypedContext>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                context: context,
                execute: (_, value, _) async {
                  seen = value;
                  return 'done';
                },
              ),
        },
      );
      expect(seen, same(context));
      final promptText = model.seenMessages!
          .expand((message) => message.content)
          .whereType<LanguageModelV4TextPart>()
          .map((part) => part.text)
          .join('\n');
      expect(promptText, isNot(contains('typed-secret')));
    },
  );

  test('typed null context does not fall back to runtime context', () async {
    Object? seen;
    await generateText(
      model: _TwoStepModel(),
      prompt: 'go',
      maxSteps: 1,
      runtimeContext: const {'runtime-secret': 'must-not-bind'},
      tools: {
        'danger': toolWithContext<Map<String, dynamic>, String, _TypedContext?>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          context: null,
          execute: (_, value, _) async {
            seen = value;
            return 'done';
          },
        ),
      },
    );
    expect(seen, isNull);
  });

  test('approval responses require complete exact binding', () async {
    final first = await generateText(
      model: _TwoStepModel(),
      prompt: 'go',
      maxSteps: 1,
      approvalPolicy: ToolApprovalPolicy.always,
      approvalPolicyRevision: 'v1',
      tools: {'danger': _tool((_, _) async => 'done')},
    );
    final request = first.toolApprovalRequests.single;
    final valid = LanguageModelV4ToolApprovalResponse(
      approvalId: request.approvalId,
      approved: true,
      toolCallId: request.toolCall.toolCallId,
      toolName: request.toolCall.toolName,
      argumentsFingerprint: request.argumentsFingerprint,
      policyRevision: request.policyRevision,
    );
    final cases = <String, LanguageModelV4ToolApprovalResponse>{
      'missing binding': LanguageModelV4ToolApprovalResponse(
        approvalId: valid.approvalId,
        approved: true,
      ),
      'wrong call ID': LanguageModelV4ToolApprovalResponse(
        approvalId: valid.approvalId,
        approved: true,
        toolCallId: 'other',
        toolName: valid.toolName,
        argumentsFingerprint: valid.argumentsFingerprint,
        policyRevision: valid.policyRevision,
      ),
      'wrong name': _responseLike(valid, toolName: 'other'),
      'wrong arguments': _responseLike(valid, argumentsFingerprint: '{}'),
      'wrong revision': _responseLike(valid, policyRevision: 'v0'),
    };
    for (final entry in cases.entries) {
      var executions = 0;
      final result = await generateText(
        model: _TwoStepModel(),
        prompt: 'go',
        maxSteps: 1,
        approvalPolicy: ToolApprovalPolicy.always,
        approvalPolicyRevision: 'v1',
        toolApprovalResponses: [entry.value],
        tools: {
          'danger': _tool((_, _) async {
            executions++;
            return 'done';
          }),
        },
      );
      expect(result.toolApprovalRequests, hasLength(1), reason: entry.key);
      expect(executions, 0, reason: entry.key);
    }
  });

  test(
    'duplicate approval IDs are rejected before provider execution',
    () async {
      final response = LanguageModelV4ToolApprovalResponse(
        approvalId: 'duplicate',
        approved: true,
      );
      final model = _TwoStepModel();
      await expectLater(
        generateText(
          model: model,
          prompt: 'go',
          toolApprovalResponses: [response, response],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(model.calls, 0);
    },
  );

  test('stale approval stays pending after a policy downgrade', () async {
    final first = await generateText(
      model: _TwoStepModel(),
      prompt: 'go',
      maxSteps: 1,
      approvalPolicy: ToolApprovalPolicy.always,
      approvalPolicyRevision: 'v1',
      tools: {'danger': _tool((_, _) async => 'done')},
    );
    final request = first.toolApprovalRequests.single;
    var executed = false;
    final renewed = await generateText(
      model: _TwoStepModel(),
      prompt: 'go',
      maxSteps: 1,
      approvalPolicy: ToolApprovalPolicy.never,
      approvalPolicyRevision: 'v2',
      toolApprovalResponses: [
        LanguageModelV4ToolApprovalResponse(
          approvalId: request.approvalId,
          approved: true,
          toolCallId: request.toolCall.toolCallId,
          toolName: request.toolCall.toolName,
          argumentsFingerprint: request.argumentsFingerprint,
          policyRevision: 'v1',
        ),
      ],
      tools: {
        'danger': _tool((_, _) async {
          executed = true;
          return 'done';
        }),
      },
    );
    expect(renewed.toolApprovalRequests, hasLength(1));
    expect(executed, isFalse);
  });
}

LanguageModelV4ToolApprovalResponse _responseLike(
  LanguageModelV4ToolApprovalResponse value, {
  String? toolName,
  String? argumentsFingerprint,
  String? policyRevision,
}) => LanguageModelV4ToolApprovalResponse(
  approvalId: value.approvalId,
  approved: value.approved,
  toolCallId: value.toolCallId,
  toolName: toolName ?? value.toolName,
  argumentsFingerprint: argumentsFingerprint ?? value.argumentsFingerprint,
  policyRevision: policyRevision ?? value.policyRevision,
);

class _TypedContext {
  const _TypedContext(this.secret);
  final String secret;
}

Tool<Map<String, dynamic>, String> _tool(
  Future<String> Function(Map<String, dynamic>, ToolExecutionOptions) execute, {
  Object? toolContext,
}) => tool(
  inputSchema: Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  ),
  execute: execute,
  toolContext: toolContext,
);

class _TwoStepModel extends LanguageModelV4 {
  var calls = 0;
  List<LanguageModelV4Message>? seenMessages;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'approval-test';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    seenMessages = options.prompt.messages;
    calls++;
    if (calls.isOdd) {
      return LanguageModelV4GenerateResult(
        content: [
          const LanguageModelV4ToolCallPart(
            toolCallId: 'call-1',
            toolName: 'danger',
            input: {'value': 1},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'ok')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();
}
