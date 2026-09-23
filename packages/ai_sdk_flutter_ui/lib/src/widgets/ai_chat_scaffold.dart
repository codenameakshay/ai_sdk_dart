import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';
import '../conversation_controller.dart';
import 'assistant_message_view.dart';
import 'chat_composer.dart';
import 'chat_error_view.dart';
import 'chat_message_list.dart';
import 'scroll_to_bottom_button.dart';
import 'tool_approval_card.dart';
import 'ui_strings.dart';

/// Builds the scaffold's inline error state.
typedef ChatScaffoldErrorBuilder =
    Widget Function(
      BuildContext context,
      ChatController controller,
      Object error,
      VoidCallback onRetry,
      VoidCallback onDismiss,
    );

/// Builds one pending tool-approval card for the scaffold.
typedef ChatScaffoldApprovalBuilder =
    Widget Function(
      BuildContext context,
      ChatController controller,
      LanguageModelV4ToolApprovalRequestPart request,
    );

/// Builds the scaffold's status view for non-terminal controller states.
typedef ChatScaffoldStatusBuilder =
    Widget Function(
      BuildContext context,
      ChatController controller,
      ChatStatus status,
    );

/// A drop-in chat screen body: composes [ChatMessageList], a
/// [ScrollToBottomButton], and [ChatComposer] wired to a [ChatController] and a
/// [ToolLoopAgent].
///
/// Sending a message routes through
/// `controller.sendMessage(agent: agent, text: ...)`; the send button morphs to
/// a stop button that cancels the in-flight stream. The transcript renders
/// Claude-style (user bubbles, flush assistant prose) and auto-scrolls; a
/// scroll-to-bottom button appears when the user reads back through history.
/// Everything is driven by the controller's public state, so it rebuilds
/// reactively as tokens arrive.
///
/// Wrap it in your own `Scaffold`/`AppBar`, or drop it straight into a screen:
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Chat')),
///   body: AiChatScaffold(controller: chat, agent: agent),
/// )
/// ```
///
/// This widget owns no business logic; it only adapts the child widgets to the
/// controller + agent.
class AiChatScaffold extends StatefulWidget {
  const AiChatScaffold({
    super.key,
    this.controller,
    this.agent,
    this.conversationController,
    this.messageBuilder,
    this.errorBuilder,
    this.approvalBuilder,
    this.statusBuilder,
    this.onAttach,
    this.hintText,
    this.emptyState,
    this.listPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.disposeConversationController = false,
  }) : assert(
         controller != null && agent != null && conversationController == null,
         'Pass controller and agent, or use AiChatScaffold.conversation.',
       );

  /// Builds the same scaffold from a persisted local or remote conversation.
  ///
  /// The backend remains behind [ConversationController]; this constructor
  /// only adapts its snapshots to the existing widgets and approval cards.
  const AiChatScaffold.conversation({
    super.key,
    required this.conversationController,
    this.messageBuilder,
    this.errorBuilder,
    this.approvalBuilder,
    this.statusBuilder,
    this.onAttach,
    this.hintText,
    this.emptyState,
    this.listPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.disposeConversationController = true,
  }) : controller = null,
       agent = null;

  /// The chat controller backing the conversation.
  final ChatController? controller;

  /// The agent used to generate responses.
  final ToolLoopAgent? agent;

  /// Conversation controller used by [AiChatScaffold.conversation].
  final ConversationController? conversationController;

  /// Whether the conversation adapter should dispose its controller when the
  /// scaffold is removed from the tree.
  final bool disposeConversationController;

  /// Optional custom row builder forwarded to [ChatMessageList].
  final ChatMessageBuilder? messageBuilder;

  /// Optional override for the inline error state.
  final ChatScaffoldErrorBuilder? errorBuilder;

  /// Optional override for each inline tool-approval card.
  final ChatScaffoldApprovalBuilder? approvalBuilder;

  /// Optional override for the scaffold's compact status view.
  final ChatScaffoldStatusBuilder? statusBuilder;

  /// Optional attachment callback forwarded to [ChatComposer].
  final VoidCallback? onAttach;

  /// Placeholder text for the composer.
  final String? hintText;

  /// Widget shown when the conversation is empty.
  final Widget? emptyState;

  /// Padding around the message list.
  final EdgeInsetsGeometry listPadding;

  @override
  State<AiChatScaffold> createState() => _AiChatScaffoldState();
}

class _AiChatScaffoldState extends State<AiChatScaffold> {
  final ScrollController _scrollController = ScrollController();
  ConversationChatController? _conversationAdapter;

  ChatController get _controller => widget.controller ?? _conversationAdapter!;

  @override
  void initState() {
    super.initState();
    _createConversationAdapter();
  }

  @override
  void didUpdateWidget(covariant AiChatScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationController == widget.conversationController) {
      return;
    }
    _conversationAdapter?.dispose();
    _conversationAdapter = null;
    _createConversationAdapter();
  }

  void _createConversationAdapter() {
    final conversation = widget.conversationController;
    if (conversation == null) return;
    _conversationAdapter = ConversationChatController(
      conversation,
      disposeConversationController: widget.disposeConversationController,
    );
  }

  @override
  void dispose() {
    _conversationAdapter?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ChatMessageList(
                controller: _controller,
                messageBuilder: widget.messageBuilder,
                padding: widget.listPadding,
                scrollController: _scrollController,
                emptyState: widget.emptyState,
              ),
              PositionedDirectional(
                end: 12,
                bottom: 12,
                child: ScrollToBottomButton(controller: _scrollController),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: _controller.contentListenable,
          builder: (context, _) {
            final metadata = _buildMetadataFallback(context);
            if (metadata == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: metadata,
            );
          },
        ),
        ListenableBuilder(
          listenable: _controller.statusListenable,
          builder: (context, _) {
            final panels = _buildStatePanels(context);
            if (panels.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < panels.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    panels[i],
                  ],
                ],
              ),
            );
          },
        ),
        ListenableBuilder(
          listenable: _controller.statusListenable,
          builder: (context, _) {
            final awaitingApproval =
                _controller.status == ChatStatus.awaitingApproval;
            return ChatComposer(
              isLoading: _controller.isLoading,
              enabled: !awaitingApproval,
              hintText: widget.hintText,
              onAttach: widget.onAttach,
              onStop: _controller.stop,
              onSend: _sendText,
            );
          },
        ),
      ],
    );
  }

  List<Widget> _buildStatePanels(BuildContext context) {
    final controller = _controller;
    final panels = <Widget>[];

    final error = controller.error;
    if (error != null) {
      panels.add(_buildErrorView(context, error));
    }

    if (controller.status == ChatStatus.awaitingApproval) {
      for (final request in controller.pendingApprovalRequests) {
        panels.add(_buildApprovalView(context, request));
      }
    }

    final statusView = _buildStatusView(context, controller.status);
    if (statusView != null) {
      panels.add(statusView);
    }

    return panels;
  }

  Widget _buildErrorView(BuildContext context, Object error) {
    final builder = widget.errorBuilder;
    if (builder != null) {
      return builder(
        context,
        _controller,
        error,
        _retryLastRequest,
        _controller.clearError,
      );
    }

    return ChatErrorView(
      error: error,
      onRetry: _retryLastRequest,
      onDismiss: _controller.clearError,
    );
  }

  Widget _buildApprovalView(
    BuildContext context,
    LanguageModelV4ToolApprovalRequestPart request,
  ) {
    final builder = widget.approvalBuilder;
    if (builder != null) {
      return builder(context, _controller, request);
    }

    return ToolApprovalCard(
      request: request,
      onApprove: (reason) =>
          _submitApproval(request: request, approved: true, reason: reason),
      onDeny: (reason) =>
          _submitApproval(request: request, approved: false, reason: reason),
    );
  }

  Widget? _buildStatusView(BuildContext context, ChatStatus status) {
    if (status == ChatStatus.ready || status == ChatStatus.error) {
      return null;
    }

    final builder = widget.statusBuilder;
    if (builder != null) {
      return builder(context, _controller, status);
    }

    final strings = AiSdkUiStringsScope.of(context);
    final label = switch (status) {
      ChatStatus.submitted ||
      ChatStatus.streaming => strings.assistantResponding,
      ChatStatus.awaitingApproval => strings.approveToolCall,
      ChatStatus.ready || ChatStatus.error => null,
    };
    if (label == null) return null;

    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(
              status == ChatStatus.awaitingApproval
                  ? Icons.shield_outlined
                  : Icons.auto_awesome,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: style)),
          ],
        ),
      ),
    );
  }

  Widget? _buildMetadataFallback(BuildContext context) {
    if (widget.messageBuilder != null ||
        _controller.status != ChatStatus.ready) {
      return null;
    }

    final assistantMessage = _lastAssistantMessage(_controller.messages);
    if (assistantMessage == null) return null;

    final parts =
        assistantMessage.parts ?? const <LanguageModelV4ContentPart>[];
    final hasInlineSources = parts.any(
      (part) => part is LanguageModelV4SourcePart,
    );
    final hasInlineToolCalls = parts.any(
      (part) => part is LanguageModelV4ToolCallPart,
    );

    final metadataParts = <LanguageModelV4ContentPart>[
      if (!hasInlineToolCalls) ..._controller.lastToolCalls,
      if (!hasInlineSources) ..._controller.lastSources,
    ];
    if (metadataParts.isEmpty) return null;

    return AssistantMessageView(
      message: ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: metadataParts,
      ),
      toolResults: _controller.lastToolResults,
    );
  }

  ModelMessage? _lastAssistantMessage(List<ModelMessage> messages) {
    for (final message in messages.reversed) {
      if (message.role == ModelMessageRole.assistant) return message;
    }
    return null;
  }

  void _submitApproval({
    required LanguageModelV4ToolApprovalRequestPart request,
    required bool approved,
    String? reason,
  }) {
    _controller.addToolApprovalResponse(
      approvalId: request.approvalId,
      approved: approved,
      reason: reason,
    );
  }

  void _retryLastRequest() {
    _controller.reload();
  }

  void _sendText(String text) {
    final adapter = _conversationAdapter;
    if (adapter != null) {
      unawaited(adapter.sendText(text));
      return;
    }
    unawaited(_controller.sendMessage(agent: widget.agent!, text: text));
  }
}
