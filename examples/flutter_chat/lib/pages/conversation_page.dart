import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:flutter/material.dart';

import '../config.dart';

const _localTool = 'deleteFile';

const _englishStrings = AiSdkUiStrings();
const _arabicStrings = AiSdkUiStrings(
  messageHint: 'رسالة…',
  sendMessage: 'إرسال الرسالة',
  stopResponse: 'إيقاف الاستجابة',
  retry: 'إعادة المحاولة',
  dismiss: 'إغلاق',
  assistantResponding: 'المساعد يستجيب…',
  approveToolCall: 'وافق على استدعاء الأداة للمتابعة.',
  toolApprovalTitle: 'الموافقة على استدعاء الأداة؟',
  approve: 'موافقة',
  deny: 'رفض',
  userMessage: 'رسالة المستخدم',
  assistantMessage: 'رسالة المساعد',
  error: 'خطأ',
  toolResult: 'نتيجة الأداة',
  toolError: 'خطأ الأداة',
);

/// App bar toggle that swaps the scaffold's [AiSdkUiStrings] between English
/// (LTR) and a demo Arabic (RTL) localization.
class _LanguageToggleButton extends StatelessWidget {
  const _LanguageToggleButton({required this.arabic, required this.onToggle});

  final bool arabic;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('conversation-language-toggle'),
      icon: const Icon(Icons.language),
      tooltip: arabic ? 'Switch to English' : 'التبديل إلى العربية',
      onPressed: onToggle,
    );
  }
}

/// Keyless local conversation route. The scripted model emits a tool call,
/// waits for the scaffold's approval card, executes the tool, then streams a
/// final answer.
class LocalConversationPage extends StatefulWidget {
  const LocalConversationPage({super.key});

  @override
  State<LocalConversationPage> createState() => _LocalConversationPageState();
}

class _LocalConversationPageState extends State<LocalConversationPage> {
  bool _arabic = false;
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
  Widget build(BuildContext context) => Directionality(
    textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Local conversation'),
        actions: [
          _LanguageToggleButton(
            arabic: _arabic,
            onToggle: () => setState(() => _arabic = !_arabic),
          ),
        ],
      ),
      body: AiSdkUiStringsScope(
        strings: _arabic ? _arabicStrings : _englishStrings,
        child: AiChatScaffold.conversation(
          conversationController: _conversation,
        ),
      ),
    ),
  );
}

/// Remote route for the local reference server in `examples/remote_backend`.
class RemoteConversationPage extends StatefulWidget {
  const RemoteConversationPage({super.key});

  @override
  State<RemoteConversationPage> createState() => _RemoteConversationPageState();
}

class _RemoteConversationPageState extends State<RemoteConversationPage> {
  bool _arabic = false;
  late final ConversationController _conversation = ConversationController(
    RemoteConversationBackend(
      transport: RemoteConversationTransport(
        endpoint: Uri.parse(remoteBackendUrl),
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
  Widget build(BuildContext context) => Directionality(
    textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Remote conversation'),
        actions: [
          _LanguageToggleButton(
            arabic: _arabic,
            onToggle: () => setState(() => _arabic = !_arabic),
          ),
        ],
      ),
      body: AiSdkUiStringsScope(
        strings: _arabic ? _arabicStrings : _englishStrings,
        child: AiChatScaffold.conversation(
          conversationController: _conversation,
          errorBuilder: (context, controller, error, onRetry, onDismiss) =>
              ChatErrorView(
                error: error,
                message:
                    "Can't reach $remoteBackendUrl. Start the reference "
                    'backend with `cd examples/remote_backend/js && npm ci '
                    '&& node server.mjs`, or pass a different '
                    '--dart-define=REMOTE_BACKEND_URL.\n$error',
                onRetry: _conversation.retryInfo.isAvailable ? onRetry : null,
                onDismiss: onDismiss,
              ),
        ),
      ),
    ),
  );
}

class _ApprovalModel extends LanguageModelV4 {
  int _calls = 0;
  int _executionsBeforeCall = 0;
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
    final lastMessage = options.prompt.messages.last;
    final continuing = lastMessage.role == LanguageModelV4Role.tool;
    if (!continuing) {
      _calls++;
      _executionsBeforeCall = executions;
    }
    final callId = 'local-call-$_calls';
    String? continuation;
    if (continuing) {
      final result = lastMessage.content
          .whereType<LanguageModelV4ToolResultPart>()
          .single;
      if (result.isError) {
        if (executions != _executionsBeforeCall) {
          throw StateError('Denied tool executed');
        }
        continuation = 'Tool denied; no local action ran.';
      } else {
        final output = result.output;
        if (executions != _executionsBeforeCall + 1 ||
            output is! ToolResultOutputText ||
            output.text != 'deleted /tmp/example') {
          throw StateError('Expected one execution and its actual tool result');
        }
        continuation = 'Tool result: ${output.text}';
      }
    }
    final parts = !continuing
        ? <LanguageModelV4StreamPart>[
            StreamPartToolInputStart(id: callId, toolName: _localTool),
            StreamPartToolInputDelta(
              id: callId,
              delta: '{"path":"/tmp/example"}',
            ),
            StreamPartToolInputEnd(id: callId),
            StreamPartToolCall(
              toolCall: LanguageModelV4ToolCallPart(
                toolCallId: callId,
                toolName: _localTool,
                input: const {'path': '/tmp/example'},
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
