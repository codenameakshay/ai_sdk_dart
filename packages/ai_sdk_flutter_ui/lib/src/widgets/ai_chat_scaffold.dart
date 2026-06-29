import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';
import 'chat_composer.dart';
import 'chat_message_list.dart';

/// A drop-in chat screen body: composes [ChatMessageList] and [ChatComposer]
/// wired to a [ChatController] and a [ToolLoopAgent].
///
/// Sending a message routes through
/// `controller.sendMessage(agent: agent, text: ...)`; the stop button cancels
/// the in-flight stream. Everything is driven by the controller's public state,
/// so it rebuilds reactively as tokens arrive.
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
/// This widget owns no business logic; it only adapts the two child widgets to
/// the controller + agent.
class AiChatScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ChatMessageList(
            controller: controller,
            messageBuilder: messageBuilder,
            padding: listPadding,
            emptyState: emptyState,
          ),
        ),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return ChatComposer(
              isLoading: controller.isLoading,
              hintText: hintText,
              onAttach: onAttach,
              onStop: controller.stop,
              onSend: (text) =>
                  controller.sendMessage(agent: agent, text: text),
            );
          },
        ),
      ],
    );
  }
}
