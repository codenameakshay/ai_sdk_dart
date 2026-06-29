import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';
import '../theme/ai_motion.dart';
import 'assistant_message_view.dart';
import 'chat_message_bubble.dart';
import 'streaming_text_view.dart';
import 'typing_indicator.dart';

/// Builder signature for customizing how a single message row is rendered.
///
/// [isStreaming] is true only for the optimistic in-flight assistant row (the
/// one backed by [ChatController.streamingContent]).
typedef ChatMessageBuilder =
    Widget Function(
      BuildContext context,
      ModelMessage message,
      bool isStreaming,
    );

/// Renders a [ChatController]'s message history as a natural transcript.
///
/// The default composition is Claude-style: **user** messages are soft,
/// right-aligned bubbles ([ChatMessageBubble]); **assistant** turns render
/// flush (no bubble) via [AssistantMessageView] with a small leading marker, so
/// long answers and rich parts read as prose rather than chat chrome. Before
/// the first token a [TypingIndicator] shows, then cross-fades into the
/// streaming text.
///
/// - Listens to the controller and rebuilds as tokens arrive.
/// - Auto-scrolls to the bottom as new content appears (honors reduced motion).
/// - Newly-arrived messages ease in once; scrolling never replays the entrance.
/// - Accepts an optional [messageBuilder] to fully customize each row, which
///   restores the simpler "one row per message" behavior.
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

  /// Optional custom row builder. When null, the default transcript
  /// composition is used.
  final ChatMessageBuilder? messageBuilder;

  /// Padding around the list.
  final EdgeInsetsGeometry padding;

  /// Optional external scroll controller. When null, an internal one is created
  /// and used for auto-scrolling.
  final ScrollController? scrollController;

  /// Widget shown when there are no messages and nothing is pending.
  final Widget? emptyState;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  late final ScrollController _scrollController =
      widget.scrollController ?? ScrollController();
  bool _ownsScrollController = false;

  /// Message instances already shown, tracked by identity so a row eases in
  /// exactly once (on arrival) and never again when scrolled back into view.
  final Set<ModelMessage> _seen = Set<ModelMessage>.identity();

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
      _seen.clear();
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
      final target = _scrollController.position.maxScrollExtent;
      if (AiMotion.reduced(context)) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: AiMotion.scroll,
          curve: AiMotion.standard,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.messages;
        final streaming = widget.controller.streamingContent;
        final status = widget.controller.status;
        final hasCustomBuilder = widget.messageBuilder != null;

        // A custom builder keeps the simple contract (a pending row only when
        // there is streaming text). The default composition also surfaces a
        // typing indicator before the first token.
        final pendingActive = hasCustomBuilder
            ? streaming.isNotEmpty
            : streaming.isNotEmpty ||
                  status == ChatStatus.submitted ||
                  status == ChatStatus.streaming;

        final itemCount = messages.length + (pendingActive ? 1 : 0);

        if (itemCount == 0 && widget.emptyState != null) {
          return widget.emptyState!;
        }

        // Mark everything seen after this frame, so the rows that are new
        // *this* build animate, and subsequent rebuilds/scrolls don't.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _seen
            ..clear()
            ..addAll(messages);
        });

        return ListView.builder(
          controller: _scrollController,
          padding: widget.padding,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (pendingActive && index == messages.length) {
              return _buildPendingRow(context, streaming);
            }
            final message = messages[index];
            final isNew = !_seen.contains(message);
            final row = _buildRow(context, message);
            return isNew ? AiEntrance(child: row) : row;
          },
        );
      },
    );
  }

  Widget _buildPendingRow(BuildContext context, String streaming) {
    final builder = widget.messageBuilder;
    if (builder != null) {
      final streamingMessage = ModelMessage(
        role: ModelMessageRole.assistant,
        content: streaming,
      );
      return builder(context, streamingMessage, true);
    }

    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(height: 1.5);
    final Widget content = streaming.isEmpty
        ? const TypingIndicator(key: ValueKey('pending-typing'))
        : StreamingTextView(
            key: const ValueKey('pending-text'),
            text: streaming,
            isStreaming: true,
            style: style,
          );

    return AiEntrance(
      key: const ValueKey('pending-row'),
      child: _assistantTurn(
        context,
        AnimatedSwitcher(
          duration: AiMotion.duration(context, AiMotion.quick),
          child: content,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, ModelMessage message) {
    final builder = widget.messageBuilder;
    if (builder != null) return builder(context, message, false);

    if (message.role == ModelMessageRole.user) {
      return ChatMessageBubble(message: message);
    }
    return _assistantTurn(context, AssistantMessageView(message: message));
  }

  /// Flush assistant layout: a small leading marker + the content column.
  Widget _assistantTurn(BuildContext context, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AssistantMarker(),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A minimal, deferential marker that anchors a bubbleless assistant turn.
class _AssistantMarker extends StatelessWidget {
  const _AssistantMarker();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.auto_awesome, size: 15, color: scheme.primary),
    );
  }
}
