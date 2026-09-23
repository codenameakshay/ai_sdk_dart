import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:flutter/material.dart';

const _localTool = 'deleteFile';

/// Keyless local conversation route. The scripted model emits a tool call,
/// waits for the scaffold's approval card, executes the tool, then streams a
/// final answer.
class LocalConversationPage extends StatefulWidget {
  const LocalConversationPage({super.key});

  @override
  State<LocalConversationPage> createState() => _LocalConversationPageState();
}

class _LocalConversationPageState extends State<LocalConversationPage> {
  final _model = _ApprovalModel();
  late final ConversationController _conversation = ConversationController(
    LocalConversationBackend(
      agent: ToolLoopAgent(
        model: _model,
        tools: {
          _localTool: Tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            approvalPolicy: ToolApprovalPolicy.always,
            executeDynamic: (input, options) async {
              _model.executions++;
              final path = input is Map ? input['path'] : null;
              return 'deleted $path';
            },
          ),
        },
      ),
      initial: Conversation(id: 'local-demo', messages: const []),
    ),
  );

  @override
  void dispose() {
    _conversation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local conversation')),
    body: AiChatScaffold.conversation(conversationController: _conversation),
  );
}

/// Remote route for the local reference server in `examples/remote_backend`.
class RemoteConversationPage extends StatefulWidget {
  const RemoteConversationPage({super.key});

  @override
  State<RemoteConversationPage> createState() => _RemoteConversationPageState();
}

class _RemoteConversationPageState extends State<RemoteConversationPage> {
  late final ConversationController _conversation = ConversationController(
    RemoteConversationBackend(
      transport: RemoteConversationTransport(
        endpoint: Uri.parse(
          const String.fromEnvironment(
            'REMOTE_BACKEND_URL',
            defaultValue: 'http://127.0.0.1:8081/chat',
          ),
        ),
      ),
      initial: Conversation(id: 'remote-demo', messages: const []),
    ),
  );

  @override
  void dispose() {
    _conversation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Remote conversation')),
    body: AiChatScaffold.conversation(conversationController: _conversation),
  );
}

class _ApprovalModel extends LanguageModelV4 {
  int _calls = 0;
  int executions = 0;

  @override
  String get provider => 'example';

  @override
  String get modelId => 'approval-script';

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
    _calls++;
    String? continuation;
    if (_calls > 1) {
      final result = options.prompt.messages
          .expand((message) => message.content)
          .whereType<LanguageModelV4ToolResultPart>()
          .single;
      if (result.isError) {
        if (executions != 0) throw StateError('Denied tool executed');
        continuation = 'Tool denied; no local action ran.';
      } else {
        final output = result.output;
        if (executions != 1 ||
            output is! ToolResultOutputText ||
            output.text != 'deleted /tmp/example') {
          throw StateError('Expected one execution and its actual tool result');
        }
        continuation = 'Tool result: ${output.text}';
      }
    }
    final parts = _calls == 1
        ? <LanguageModelV4StreamPart>[
            const StreamPartToolInputStart(
              id: 'local-call-1',
              toolName: _localTool,
            ),
            const StreamPartToolInputDelta(
              id: 'local-call-1',
              delta: '{"path":"/tmp/example"}',
            ),
            const StreamPartToolInputEnd(id: 'local-call-1'),
            const StreamPartToolCall(
              toolCall: LanguageModelV4ToolCallPart(
                toolCallId: 'local-call-1',
                toolName: _localTool,
                input: {'path': '/tmp/example'},
              ),
            ),
          ]
        : <LanguageModelV4StreamPart>[
            const StreamPartTextStart(id: 'local-text-1'),
            StreamPartTextDelta(id: 'local-text-1', delta: continuation!),
            const StreamPartTextEnd(id: 'local-text-1'),
          ];
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        ...parts,
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}
