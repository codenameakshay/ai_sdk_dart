import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

const _arabicStrings = AiSdkUiStrings(
  messageHint: 'اكتب رسالة…',
  attachFile: 'إرفاق ملف',
  sendMessage: 'إرسال',
  stopResponse: 'إيقاف',
  retry: 'إعادة المحاولة',
  dismiss: 'إغلاق',
  assistantTyping: 'المساعد يكتب',
  assistantResponding: 'المساعد يكتب…',
  approveToolCall: 'يرجى الموافقة على استدعاء الأداة للمتابعة.',
  toolApprovalTitle: 'هل توافق على استدعاء الأداة؟',
  approve: 'موافقة',
  deny: 'رفض',
  approvalReasonHint: 'السبب (اختياري)',
);

/// Application context bound to the `deleteFile` tool via [toolWithContext],
/// mirroring the pattern on the Tools Chat page.
class _WorkspaceContext {
  const _WorkspaceContext(this.rootPath);
  final String rootPath;
}

/// Demonstrates the conversation stack: [ConversationController] +
/// [LocalConversationBackend] rendered through [AiChatScaffold.conversation],
/// with an in-memory snapshot saved and restored via [ConversationCodec],
/// approval + retry ([ConversationRetryInfo]) support, and localized/RTL UI
/// strings.
///
/// [testAgent], when supplied, replaces the OpenAI-backed agent so tests can
/// drive the whole flow — including tool approval — against a fake model
/// with no network access.
class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, this.testAgent});

  final ToolLoopAgent? testAgent;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  late final _openAi = OpenAIProvider(apiKey: openAiApiKey);
  static final _deleteFileSchema = Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
      },
      'required': ['path'],
    },
    fromJson: (j) => j,
  );

  static final _weatherSchema = Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
      'required': ['city'],
    },
    fromJson: (j) => j,
  );

  late final _tools = <String, Tool<dynamic, dynamic>>{
    'getWeather': tool<Map<String, dynamic>, String>(
      description: 'Get the current weather for a city.',
      inputSchema: _weatherSchema,
      execute: (input, _) async =>
          'Sunny, 22°C in ${input['city'] ?? 'that city'}.',
    ),
    'deleteFile':
        toolWithContext<Map<String, dynamic>, String, _WorkspaceContext>(
          description:
              'Delete a file from the workspace. Always needs approval.',
          inputSchema: _deleteFileSchema,
          context: const _WorkspaceContext('/workspace'),
          execute: (input, workspace, _) async =>
              'Deleted ${workspace.rootPath}/${input['path']}',
        ),
  };

  late ConversationController _controller;
  Map<String, dynamic>? _savedSnapshot;
  bool _rtl = false;

  @override
  void initState() {
    super.initState();
    _controller = _newController();
  }

  ToolLoopAgent _buildAgent() =>
      widget.testAgent ??
      ToolLoopAgent(
        model: _openAi('gpt-4.1-mini'),
        instructions:
            'You are a helpful assistant with access to file tools. Use '
            'getWeather for weather questions and deleteFile when asked to '
            'remove a file.',
        tools: _tools,
        maxSteps: 3,
        maxToolConcurrency: 2,
        // Request-level approval policy: only deleteFile pauses for a human.
        approvalPolicyFor: (toolName, input) =>
            toolName == 'deleteFile' ? ToolApprovalPolicy.always : null,
      );

  ConversationController _newController() => ConversationController(
    LocalConversationBackend(
      agent: _buildAgent(),
      initial: Conversation(
        id: 'conversation-${DateTime.now().microsecondsSinceEpoch}',
        messages: const [],
      ),
    ),
  );

  Future<void> _newConversation() async {
    final old = _controller;
    setState(() => _controller = _newController());
    await old.interrupt();
    unawaited(old.dispose());
  }

  void _save() {
    setState(
      () => _savedSnapshot = ConversationCodec.encode(_controller.conversation),
    );
    _snack('Saved (${_controller.conversation.messages.length} messages).');
  }

  Future<void> _restore() async {
    final snapshot = _savedSnapshot;
    if (snapshot == null) {
      _snack('Nothing saved yet.');
      return;
    }
    // ConversationCodec.decode + restore only decode data — no tool or
    // provider call happens as part of restoring a snapshot.
    await _controller.restore(snapshot);
    _snack('Conversation restored.');
  }

  Future<void> _retry() async {
    final info = _controller.retryInfo;
    if (!info.isAvailable) {
      _snack(info.reason ?? 'Retry is not available for this conversation.');
      return;
    }
    try {
      await _controller.retryLastTurn();
    } catch (e) {
      _snack('Retry failed: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    _openAi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
        actions: [
          IconButton(
            tooltip: _rtl ? 'Switch to LTR' : 'Switch to RTL (Arabic)',
            icon: Icon(
              _rtl
                  ? Icons.format_textdirection_l_to_r
                  : Icons.format_textdirection_r_to_l,
            ),
            onPressed: () => setState(() => _rtl = !_rtl),
          ),
          IconButton(
            tooltip: 'Save snapshot',
            icon: const Icon(Icons.save_outlined),
            onPressed: _save,
          ),
          IconButton(
            tooltip: 'Restore snapshot',
            icon: const Icon(Icons.restore),
            onPressed: _savedSnapshot == null ? null : _restore,
          ),
          IconButton(
            tooltip: 'Retry last turn',
            icon: const Icon(Icons.refresh),
            onPressed: _retry,
          ),
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newConversation,
          ),
        ],
      ),
      body: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: AiSdkUiStringsScope(
          strings: _rtl ? _arabicStrings : const AiSdkUiStrings(),
          child: AiChatScaffold.conversation(
            key: ValueKey(_controller),
            conversationController: _controller,
            disposeConversationController: false,
            hintText: 'Ask about weather, or request a file deletion…',
            emptyState: Center(
              child: Text(
                'Ask about the weather or say "delete q3.pdf" to see '
                'approval + retry in action.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
