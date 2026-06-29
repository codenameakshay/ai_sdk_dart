import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';
import 'chat_message_bubble.dart';

/// Builder signature for customizing how a single message row is rendered.
///
/// [isStreaming] is true only for the optimistic in-flight assistant bubble
/// (the one backed by [ChatController.streamingContent]).
typedef ChatMessageBuilder =
    Widget Function(
      BuildContext context,
      ModelMessage message,
      bool isStreaming,
    );

/// Renders a [ChatController]'s message history plus an optimistic streaming
/// bubble sourced from [ChatController.streamingContent].
///
/// - Listens to the controller and rebuilds as tokens arrive.
/// - Auto-scrolls to the bottom whenever new content appears.
/// - Accepts an optional [messageBuilder] to fully customize each row;
///   defaults to [ChatMessageBubble].
///
/// This widget contains no business logic — it only reads the controller's
/// public state.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.controller,
    this.messageBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.scrollController,
    this.emptyState,
  });

  /// The chat controller whose [ChatController.messages] and
  /// [ChatController.streamingContent] are rendered.
  final ChatController controller;

  /// Optional custom row builder. When null, [ChatMessageBubble] is used.
  final ChatMessageBuilder? messageBuilder;

  /// Padding around the list.
  final EdgeInsetsGeometry padding;

  /// Optional external scroll controller. When null, an internal one is created
  /// and used for auto-scrolling.
  final ScrollController? scrollController;

  /// Widget shown when there are no messages and nothing is streaming.
  final Widget? emptyState;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  late final ScrollController _scrollController =
      widget.scrollController ?? ScrollController();
  bool _ownsScrollController = false;

  @override
  void initState() {
    super.initState();
    _ownsScrollController = widget.scrollController == null;
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  void _onChange() => _scrollToBottom();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.messages;
        final streaming = widget.controller.streamingContent;
        final hasStreaming = streaming.isNotEmpty;
        final itemCount = messages.length + (hasStreaming ? 1 : 0);

        if (itemCount == 0 && widget.emptyState != null) {
          return widget.emptyState!;
        }

        return ListView.builder(
          controller: _scrollController,
          padding: widget.padding,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (hasStreaming && index == messages.length) {
              final streamingMessage = ModelMessage(
                role: ModelMessageRole.assistant,
                content: streaming,
              );
              return _buildRow(context, streamingMessage, true);
            }
            return _buildRow(context, messages[index], false);
          },
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    ModelMessage message,
    bool isStreaming,
  ) {
    final builder = widget.messageBuilder;
    if (builder != null) return builder(context, message, isStreaming);
    return ChatMessageBubble(message: message, isStreaming: isStreaming);
  }
}
