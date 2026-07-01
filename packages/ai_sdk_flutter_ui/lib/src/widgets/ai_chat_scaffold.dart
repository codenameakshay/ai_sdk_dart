import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';
import 'chat_composer.dart';
import 'chat_message_list.dart';
import 'scroll_to_bottom_button.dart';

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
    required this.controller,
    required this.agent,
    this.messageBuilder,
    this.onAttach,
    this.hintText = 'Message…',
    this.emptyState,
    this.listPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  /// The chat controller backing the conversation.
  final ChatController controller;

  /// The agent used to generate responses.
  final ToolLoopAgent agent;

  /// Optional custom row builder forwarded to [ChatMessageList].
  final ChatMessageBuilder? messageBuilder;

  /// Optional attachment callback forwarded to [ChatComposer].
  final VoidCallback? onAttach;

  /// Placeholder text for the composer.
  final String hintText;

  /// Widget shown when the conversation is empty.
  final Widget? emptyState;

  /// Padding around the message list.
  final EdgeInsetsGeometry listPadding;

  @override
  State<AiChatScaffold> createState() => _AiChatScaffoldState();
}

class _AiChatScaffoldState extends State<AiChatScaffold> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
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
                controller: widget.controller,
                messageBuilder: widget.messageBuilder,
                padding: widget.listPadding,
                scrollController: _scrollController,
                emptyState: widget.emptyState,
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: ScrollToBottomButton(controller: _scrollController),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            return ChatComposer(
              isLoading: widget.controller.isLoading,
              hintText: widget.hintText,
              onAttach: widget.onAttach,
              onStop: widget.controller.stop,
              onSend: (text) => widget.controller.sendMessage(
                agent: widget.agent,
                text: text,
              ),
            );
          },
        ),
      ],
    );
  }
}
