import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

import '../helpers.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

class _LifecycleBackend implements ConversationBackend {
  _LifecycleBackend([Conversation? initial])
    : _conversation =
          initial ?? Conversation(id: 'lifecycle', messages: const []);

  final Conversation _conversation;
  final _changes = StreamController<Conversation>.broadcast();
  final disposeSignal = Completer<void>();
  int disposeCount = 0;

  @override
  Conversation get conversation => _conversation;

  @override
  Stream<Conversation> get changes => _changes.stream;

  @override
  Future<void> send(String text) async {}

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> restore(Map<String, dynamic> encoded) async {}

  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async {}

  @override
  Future<void> dispose() async {
    disposeCount++;
    if (!disposeSignal.isCompleted) disposeSignal.complete();
    await _changes.close();
  }
}

const _approvalRequest = LanguageModelV4ToolApprovalRequestPart(
  approvalId: 'approval_c1',
  toolCall: LanguageModelV4ToolCallPart(
    toolCallId: 'c1',
    toolName: 'deleteFile',
    input: {'path': '/tmp/secret'},
  ),
);

class _ComposerProbeController extends ChatController {
  @override
  Future<void> sendMessage({
    required ToolLoopAgent agent,
    required String text,
  }) async {
    append(ModelMessage(role: ModelMessageRole.user, content: text));
  }
}

/// Base for the fixtures below: a [ChatController] that fakes its own
/// [statusListenable]/[contentListenable] (so tests can trigger notifications
/// without going through real generation) and backs [messages] with a plain
/// list the fixture can mutate directly.
abstract class _ProbeChatController extends ChatController {
  _ProbeChatController({List<ModelMessage> messages = const <ModelMessage>[]})
    : _statusNotifier = ChangeNotifier(),
      _contentNotifier = ChangeNotifier(),
      _probeMessages = List<ModelMessage>.from(messages);

  final ChangeNotifier _statusNotifier;
  final ChangeNotifier _contentNotifier;
  final List<ModelMessage> _probeMessages;

  @override
  Listenable get statusListenable => _statusNotifier;

  @override
  Listenable get contentListenable => _contentNotifier;

  @override
  List<ModelMessage> get messages => List.unmodifiable(_probeMessages);

  @override
  void dispose() {
    _statusNotifier.dispose();
    _contentNotifier.dispose();
    super.dispose();
  }
}

class _ErrorProbeController extends _ProbeChatController {
  ChatStatus _probeStatus = ChatStatus.ready;
  Object? _probeError;
  ToolLoopAgent? reloadAgent;
  int reloadCalls = 0;

  @override
  ChatStatus get status => _probeStatus;

  @override
  Object? get error => _probeError;

  void showError(Object error) {
    _probeError = error;
    _probeStatus = ChatStatus.error;
    _statusNotifier.notifyListeners();
  }

  @override
  Future<void> reload({ToolLoopAgent? agent}) async {
    reloadCalls++;
    reloadAgent = agent;
  }

  @override
  void clearError() {
    _probeError = null;
    _probeStatus = ChatStatus.ready;
    _statusNotifier.notifyListeners();
  }
}

class _ApprovalProbeController extends _ProbeChatController {
  _ApprovalProbeController({List<ModelMessage> initialMessages = const []})
    : super(messages: initialMessages);

  ChatStatus _probeStatus = ChatStatus.ready;
  List<LanguageModelV4ToolApprovalRequestPart> _pendingRequests =
      const <LanguageModelV4ToolApprovalRequestPart>[];
  String? lastApprovalId;
  bool? lastApproved;
  String? lastReason;

  @override
  ChatStatus get status => _probeStatus;

  @override
  List<LanguageModelV4ToolApprovalRequestPart> get pendingApprovalRequests =>
      List.unmodifiable(_pendingRequests);

  void showApproval([
    List<LanguageModelV4ToolApprovalRequestPart> requests = const [
      _approvalRequest,
    ],
  ]) {
    _pendingRequests = List<LanguageModelV4ToolApprovalRequestPart>.from(
      requests,
    );
    _probeStatus = ChatStatus.awaitingApproval;
    _statusNotifier.notifyListeners();
  }

  @override
  void addToolApprovalResponse({
    required String approvalId,
    required bool approved,
    String? reason,
  }) {
    lastApprovalId = approvalId;
    lastApproved = approved;
    lastReason = reason;
    _pendingRequests = _pendingRequests
        .where((request) => request.approvalId != approvalId)
        .toList();
    _probeStatus = ChatStatus.ready;
    _statusNotifier.notifyListeners();
  }
}

class _MetadataProbeController extends _ProbeChatController {
  _MetadataProbeController({
    required super.messages,
    required this.probeToolCalls,
    required this.probeSources,
    this.probeToolResults = const <LanguageModelV4ToolResultPart>[],
  });

  final List<LanguageModelV4ToolCallPart> probeToolCalls;
  final List<LanguageModelV4SourcePart> probeSources;
  final List<LanguageModelV4ToolResultPart> probeToolResults;

  @override
  ChatStatus get status => ChatStatus.ready;

  @override
  List<LanguageModelV4ToolCallPart> get lastToolCalls =>
      List.unmodifiable(probeToolCalls);

  @override
  List<LanguageModelV4SourcePart> get lastSources =>
      List.unmodifiable(probeSources);

  @override
  List<LanguageModelV4ToolResultPart> get lastToolResults =>
      List.unmodifiable(probeToolResults);
}

void main() {
  group('AiChatScaffold', () {
    testWidgets('composes a message list and a composer', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'seed message'),
        ],
      );
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(
        model: MockLanguageModelV4(response: [mockText('reply')]),
      );

      await tester.pumpWidget(
        _wrap(AiChatScaffold(controller: controller, agent: agent)),
      );

      expect(find.byType(ChatMessageList), findsOneWidget);
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(find.text('seed message'), findsOneWidget);
    });

    testWidgets('conversation constructor streams a local backend', (
      tester,
    ) async {
      final conversation = ConversationController(
        LocalConversationBackend(
          agent: textAgent('local backend reply'),
          initial: Conversation(id: 'local', messages: const []),
        ),
      );
      addTearDown(conversation.dispose);

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold.conversation(
            conversationController: conversation,
            disposeConversationController: false,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'hello local',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await pumpTesterUntil(
        tester,
        () => find.text('local backend reply').evaluate().isNotEmpty,
      );

      expect(find.text('hello local'), findsOneWidget);
      expect(find.text('local backend reply'), findsOneWidget);
    });

    testWidgets('conversation constructor renders and answers local approval', (
      tester,
    ) async {
      final conversation = ConversationController(
        LocalConversationBackend(
          agent: approvalAgent(repeatCallAfterApproval: false),
          initial: Conversation(id: 'approval', messages: const []),
        ),
      );
      addTearDown(conversation.dispose);

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold.conversation(
            conversationController: conversation,
            disposeConversationController: false,
          ),
        ),
      );
      await tester.runAsync(() => conversation.send('approve local'));
      await tester.pump();
      await pumpTesterUntil(
        tester,
        () => find.byType(ToolApprovalCard).evaluate().isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('tool-approval-approve')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
      await pumpTesterUntil(
        tester,
        () => find.text('final answer').evaluate().isNotEmpty,
      );
      expect(find.text('final answer'), findsOneWidget);
    });

    testWidgets('conversation constructor streams a remote backend', (
      tester,
    ) async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        return Response(
          'data: ${jsonEncode({'type': 'start', 'messageId': 'remote-a'})}\n\n'
          'data: ${jsonEncode({'type': 'text-start', 'id': 'remote-text'})}\n\n'
          'data: ${jsonEncode({'type': 'text-delta', 'id': 'remote-text', 'delta': 'remote reply'})}\n\n'
          'data: ${jsonEncode({'type': 'text-end', 'id': 'remote-text'})}\n\n'
          'data: ${jsonEncode({'type': 'finish'})}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {
            'x-vercel-ai-ui-message-stream': 'v1',
            'content-type': 'text/event-stream',
          },
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      final conversation = ConversationController(
        RemoteConversationBackend(
          transport: transport,
          initial: Conversation(id: 'remote', messages: const []),
        ),
      );
      addTearDown(conversation.dispose);
      addTearDown(client.close);

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold.conversation(
            conversationController: conversation,
            disposeConversationController: false,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'hello remote',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await pumpTesterUntil(
        tester,
        () => find.text('remote reply').evaluate().isNotEmpty,
      );

      expect(find.text('hello remote'), findsOneWidget);
      expect(find.text('remote reply'), findsOneWidget);
    });

    testWidgets('conversation scaffold disposes an owned controller', (
      tester,
    ) async {
      final backend = _LifecycleBackend();
      final conversation = ConversationController(backend);

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold.conversation(conversationController: conversation),
        ),
      );
      await tester.pumpWidget(_wrap(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await backend.disposeSignal.future;
      });

      expect(backend.disposeCount, 1);
    });

    testWidgets(
      'conversation scaffold can leave caller-owned controller alive',
      (tester) async {
        final backend = _LifecycleBackend();
        final conversation = ConversationController(backend);

        await tester.pumpWidget(
          _wrap(
            AiChatScaffold.conversation(
              conversationController: conversation,
              disposeConversationController: false,
            ),
          ),
        );
        expect(backend.disposeCount, 0);
        await backend.dispose();
        expect(backend.disposeCount, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('conversation scaffold replaces adapters with new backends', (
      tester,
    ) async {
      final firstBackend = _LifecycleBackend(
        Conversation(
          id: 'first',
          messages: [
            ConversationMessage(
              id: 'first-user',
              role: ConversationRole.user,
              parts: [TextPart(id: 'first-text', text: 'first conversation')],
            ),
          ],
        ),
      );
      final secondBackend = _LifecycleBackend(
        Conversation(
          id: 'second',
          messages: [
            ConversationMessage(
              id: 'second-user',
              role: ConversationRole.user,
              parts: [TextPart(id: 'second-text', text: 'second conversation')],
            ),
          ],
        ),
      );
      final first = ConversationController(firstBackend);
      final second = ConversationController(secondBackend);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(
        _wrap(AiChatScaffold.conversation(conversationController: first)),
      );
      expect(find.text('first conversation'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(AiChatScaffold.conversation(conversationController: second)),
      );
      expect(find.text('second conversation'), findsOneWidget);
      expect(find.text('first conversation'), findsNothing);
      expect(firstBackend.disposeCount, 1);
    });

    testWidgets(
      'conversation scaffold renders restored pending approval initially',
      (tester) async {
        final call = ToolCallPart(
          id: 'tool-c1',
          callId: 'c1',
          name: 'deleteFile',
          arguments: {'path': '/tmp/secret'},
        );
        final approval = ApprovalPart(
          id: 'approval-a1',
          approvalId: 'a1',
          callId: 'c1',
          toolName: 'deleteFile',
          status: ApprovalStatus.pending,
        );
        final backend = _LifecycleBackend(
          Conversation(
            id: 'restored',
            messages: [
              ConversationMessage(
                id: 'assistant-1',
                role: ConversationRole.assistant,
                status: ConversationMessageStatus.pendingApproval,
                parts: [call, approval],
              ),
            ],
          ),
        );
        final conversation = ConversationController(backend);
        addTearDown(conversation.dispose);

        await tester.pumpWidget(
          _wrap(
            AiChatScaffold.conversation(conversationController: conversation),
          ),
        );

        expect(find.byType(ToolApprovalCard), findsOneWidget);
        expect(find.text('deleteFile'), findsWidgets);
      },
    );

    testWidgets('sending via the composer drives the controller', (
      tester,
    ) async {
      final controller = _ComposerProbeController();
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(
        model: MockLanguageModelV4(doStreamError: StateError('ignored')),
      );

      await tester.pumpWidget(
        _wrap(AiChatScaffold(controller: controller, agent: agent)),
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'Hello',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();

      // The composer routes through the controller.
      expect(find.text('Hello'), findsOneWidget);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.content, 'Hello');
    });

    testWidgets('shows an empty state when there are no messages', (
      tester,
    ) async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(model: MockLanguageModelV4());

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold(
            controller: controller,
            agent: agent,
            emptyState: const Center(child: Text('No messages yet')),
          ),
        ),
      );
      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets(
      'retry delegates to controller.reload without an agent override',
      (tester) async {
        final controller = _ErrorProbeController();
        addTearDown(controller.dispose);
        final firstAgent = textAgent('first');
        final secondAgent = textAgent('second');

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: controller, agent: firstAgent)),
        );

        controller.showError(StateError('boom'));
        await tester.pump();

        expect(find.byType(ChatErrorView), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-error-retry')), findsOneWidget);

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: controller, agent: secondAgent)),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('chat-error-retry')));
        await tester.pump();

        expect(controller.reloadCalls, 1);
        expect(controller.reloadAgent, isNull);
      },
    );

    testWidgets('shows an inline error with explicit dismiss action', (
      tester,
    ) async {
      final controller = _ErrorProbeController();
      addTearDown(controller.dispose);
      final agent = textAgent('unused');

      await tester.pumpWidget(
        _wrap(AiChatScaffold(controller: controller, agent: agent)),
      );

      controller.showError(StateError('dismissed'));
      await tester.pump();

      expect(find.byType(ChatErrorView), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-error-dismiss')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-error-dismiss')));
      await tester.pump();

      expect(controller.status, ChatStatus.ready);
      expect(controller.error, isNull);
      expect(find.byType(ChatErrorView), findsNothing);
    });

    testWidgets(
      'shows approval cards, disables the composer, and resumes on approve',
      (tester) async {
        final controller = _ApprovalProbeController();
        addTearDown(controller.dispose);
        final agent = textAgent('unused');
        var attached = false;

        await tester.pumpWidget(
          _wrap(
            AiChatScaffold(
              controller: controller,
              agent: agent,
              onAttach: () => attached = true,
            ),
          ),
        );

        controller.showApproval();
        await tester.pump();

        expect(find.byType(ToolApprovalCard), findsOneWidget);
        expect(find.text('Approve the tool call to continue.'), findsOneWidget);
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('chat-composer-field')),
        );
        expect(field.enabled, isFalse);
        expect(
          find.byKey(const ValueKey('chat-composer-send')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('chat-composer-stop')), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('chat-composer-send')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('chat-composer-attach')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.byKey(const ValueKey('chat-composer-send')),
          warnIfMissed: false,
        );
        await tester.tap(
          find.byKey(const ValueKey('chat-composer-attach')),
          warnIfMissed: false,
        );
        expect(attached, isFalse);

        await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
        await tester.pump();

        expect(controller.lastApprovalId, 'approval_c1');
        expect(controller.lastApproved, isTrue);
        expect(controller.status, ChatStatus.ready);
        expect(find.byType(ToolApprovalCard), findsNothing);
      },
    );

    testWidgets(
      'deny on an approval card routes through addToolApprovalResponse',
      (tester) async {
        final controller = _ApprovalProbeController();
        addTearDown(controller.dispose);
        final agent = textAgent('unused');

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: controller, agent: agent)),
        );

        controller.showApproval();
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('tool-approval-deny')));
        await tester.pump();

        expect(controller.lastApprovalId, 'approval_c1');
        expect(controller.lastApproved, isFalse);
        expect(controller.status, ChatStatus.ready);
      },
    );

    testWidgets(
      'shows tool result and source metadata after an approval-resumed turn',
      (tester) async {
        final controller = ChatController();
        addTearDown(controller.dispose);
        final agent = RecordingStreamAgent();
        const source = LanguageModelV4SourcePart(
          id: 'source-1',
          url: 'https://example.com/weather',
          title: 'Weather source',
        );
        const call = LanguageModelV4ToolCallPart(
          toolCallId: 'c1',
          toolName: 'deleteFile',
          input: {'path': '/x'},
        );
        const result = LanguageModelV4ToolResultPart(
          toolCallId: 'c1',
          toolName: 'deleteFile',
          output: ToolResultOutputText('done'),
        );
        const request = LanguageModelV4ToolApprovalRequestPart(
          approvalId: 'approval_c1',
          toolCall: call,
        );

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: controller, agent: agent)),
        );

        unawaited(controller.sendMessage(agent: agent, text: 'Need approval'));
        await pumpTesterUntil(tester, () => agent.invocations.length == 1);
        await agent.invocations.first.finish(
          finalText: '',
          steps: const [
            GenerateTextStep(
              stepNumber: 1,
              content: [call, source],
              toolCalls: [call],
              toolResults: [result],
              toolApprovalRequests: [request],
              response: LanguageModelV4GenerateResult(
                content: [call, source],
                finishReason: LanguageModelV4FinishReason.toolCalls,
              ),
              text: '',
              finishReason: LanguageModelV4FinishReason.toolCalls,
            ),
          ],
          sources: const [source],
          toolCalls: const [call],
          toolResults: const [result],
        );
        await pumpTesterUntil(
          tester,
          () => controller.status == ChatStatus.awaitingApproval,
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
        await tester.pump();
        await pumpTesterUntil(tester, () => agent.invocations.length == 2);
        agent.invocations.last.emitText('final answer');
        await agent.invocations.last.finish(finalText: 'final answer');
        await pumpTesterUntil(
          tester,
          () => controller.status == ChatStatus.ready,
        );
        await tester.pump();

        expect(find.text('final answer'), findsOneWidget);
        expect(find.text('deleteFile'), findsOneWidget);
        expect(find.text('done'), findsOneWidget);
        expect(find.text('Weather source'), findsOneWidget);
      },
    );

    testWidgets(
      'renders trailing tool and source metadata without keeping stale prior-turn content',
      (tester) async {
        final controller = ChatController();
        addTearDown(controller.dispose);
        final agent = RecordingStreamAgent();
        const source = LanguageModelV4SourcePart(
          id: 'source-1',
          url: 'https://example.com/weather',
          title: 'Weather source',
        );
        const call = LanguageModelV4ToolCallPart(
          toolCallId: 'tool-1',
          toolName: 'lookupWeather',
          input: {'city': 'Paris'},
        );
        const result = LanguageModelV4ToolResultPart(
          toolCallId: 'tool-1',
          toolName: 'lookupWeather',
          output: ToolResultOutputText('sunny'),
        );

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: controller, agent: agent)),
        );

        unawaited(controller.sendMessage(agent: agent, text: 'First'));
        await pumpTesterUntil(tester, () => agent.invocations.length == 1);
        agent.invocations.single.emitText('Answer');
        await agent.invocations.single.finish(
          finalText: 'Answer',
          sources: const [source],
          toolCalls: const [call],
          toolResults: const [result],
        );
        await pumpTesterUntil(
          tester,
          () => controller.status == ChatStatus.ready,
        );
        await tester.pump();

        expect(find.text('lookupWeather'), findsOneWidget);
        expect(find.text('sunny'), findsOneWidget);
        expect(find.text('Weather source'), findsOneWidget);

        unawaited(controller.sendMessage(agent: agent, text: 'Second'));
        await pumpTesterUntil(tester, () => agent.invocations.length == 2);
        await tester.pump();

        expect(find.text('lookupWeather'), findsNothing);
        expect(find.text('sunny'), findsNothing);
        expect(find.text('Weather source'), findsNothing);

        agent.invocations.last.emitText('Second answer');
        await agent.invocations.last.finish(finalText: 'Second answer');
        await pumpTesterUntil(
          tester,
          () => controller.status == ChatStatus.ready,
        );
        await tester.pump();

        expect(find.text('lookupWeather'), findsNothing);
        expect(find.text('sunny'), findsNothing);
        expect(find.text('Weather source'), findsNothing);
      },
    );

    testWidgets(
      'does not duplicate metadata that is already inline on the assistant message',
      (tester) async {
        const inlineSource = LanguageModelV4SourcePart(
          id: 'source-inline',
          url: 'https://example.com/inline',
          title: 'Inline source',
        );
        const inlineCall = LanguageModelV4ToolCallPart(
          toolCallId: 'inline-call',
          toolName: 'inlineTool',
          input: {'ok': true},
        );
        const inlineResult = LanguageModelV4ToolResultPart(
          toolCallId: 'inline-call',
          toolName: 'inlineTool',
          output: ToolResultOutputText('inline result'),
        );
        final controller = _MetadataProbeController(
          messages: const [
            ModelMessage.parts(
              role: ModelMessageRole.assistant,
              parts: [inlineCall, inlineSource],
            ),
          ],
          probeToolCalls: const [inlineCall],
          probeSources: const [inlineSource],
          probeToolResults: const [inlineResult],
        );
        addTearDown(controller.dispose);
        final agent = textAgent('unused');

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: controller, agent: agent)),
        );

        expect(find.text('Inline source'), findsOneWidget);
        expect(find.text('inlineTool'), findsOneWidget);
      },
    );

    testWidgets('uses custom message, error, approval, and status builders', (
      tester,
    ) async {
      final controller = _ApprovalProbeController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'seed'),
        ],
      );
      addTearDown(controller.dispose);
      final approvalDrivenAgent = textAgent('unused');

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold(
            controller: controller,
            agent: approvalDrivenAgent,
            messageBuilder: (context, message, isStreaming) =>
                Text('message:${message.content}:$isStreaming'),
            errorBuilder: (context, chatController, error, onRetry, onDismiss) {
              return Text('error:$error');
            },
            approvalBuilder: (context, chatController, request) {
              return Text('approval:${request.approvalId}');
            },
            statusBuilder: (context, chatController, status) {
              return Text('status:${status.name}');
            },
          ),
        ),
      );

      expect(find.text('message:seed:false'), findsOneWidget);

      controller.showApproval();
      await tester.pump();

      expect(find.text('approval:approval_c1'), findsOneWidget);
      expect(find.text('status:awaitingApproval'), findsOneWidget);
      expect(find.byType(ToolApprovalCard), findsNothing);
      controller.addToolApprovalResponse(
        approvalId: 'approval_c1',
        approved: false,
      );
      await tester.pump();

      final errorAgent = RecordingStreamAgent();
      final errorController = _ErrorProbeController();
      addTearDown(errorController.dispose);

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold(
            controller: errorController,
            agent: errorAgent,
            messageBuilder: (context, message, isStreaming) =>
                Text('message:${message.content}:$isStreaming'),
            errorBuilder: (context, chatController, error, onRetry, onDismiss) {
              return Text('error:$error');
            },
            approvalBuilder: (context, chatController, request) {
              return Text('approval:${request.approvalId}');
            },
            statusBuilder: (context, chatController, status) {
              return Text('status:${status.name}');
            },
          ),
        ),
      );
      errorController.showError(StateError('bad'));
      await tester.pump();

      expect(find.textContaining('error:Bad state: bad'), findsOneWidget);
      expect(find.byType(ChatErrorView), findsNothing);
    });

    testWidgets(
      'responds to controller swaps and ignores old controller changes',
      (tester) async {
        final firstController = ChatController(
          initialMessages: const [
            ModelMessage(role: ModelMessageRole.user, content: 'first'),
          ],
        );
        final secondController = ChatController(
          initialMessages: const [
            ModelMessage(role: ModelMessageRole.user, content: 'second'),
          ],
        );
        addTearDown(firstController.dispose);
        addTearDown(secondController.dispose);
        final agent = ToolLoopAgent(model: MockLanguageModelV4());

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: firstController, agent: agent)),
        );
        expect(find.text('first'), findsOneWidget);

        await tester.pumpWidget(
          _wrap(AiChatScaffold(controller: secondController, agent: agent)),
        );
        await tester.pump();

        expect(find.text('second'), findsOneWidget);
        expect(find.text('first'), findsNothing);

        firstController.append(
          const ModelMessage(role: ModelMessageRole.user, content: 'late'),
        );
        await tester.pump();

        expect(find.text('late'), findsNothing);
        expect(find.text('second'), findsOneWidget);
      },
    );
  });
}
