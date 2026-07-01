import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// A wrap of tappable prompt-starter chips.
///
/// Ideal for an empty conversation state: surface a few example prompts the
/// user can tap to kick things off. [onSelected] fires with the chosen string —
/// wire it to `ChatController.sendMessage` or your composer.
///
/// The chips ease in on a short stagger and answer a press with a subtle scale
/// and a selection haptic. Collapses to nothing when [suggestions] is empty.
///
/// ```dart
/// PromptSuggestions(
///   title: 'Try asking',
///   suggestions: const ['Summarize my notes', 'Plan a trip to Kyoto'],
///   onSelected: (text) => controller.sendMessage(agent: agent, text: text),
/// )
/// ```
class PromptSuggestions extends StatefulWidget {
  const PromptSuggestions({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.title,
    this.spacing = 8,
  });

  /// The prompt strings to render as chips.
  final List<String> suggestions;

  /// Called with the suggestion when a chip is tapped.
  final ValueChanged<String> onSelected;

  /// Optional heading shown above the chips.
  final String? title;

  /// Gap between chips.
  final double spacing;

  @override
  State<PromptSuggestions> createState() => _PromptSuggestionsState();
}

class _PromptSuggestionsState extends State<PromptSuggestions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AiMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = widget.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: widget.spacing,
          runSpacing: widget.spacing,
          children: [
            for (var i = 0; i < widget.suggestions.length; i++)
              _staggered(i, _chip(widget.suggestions[i])),
          ],
        ),
      ],
    );
  }

  Widget _chip(String suggestion) {
    return PressableScale(
      child: ActionChip(
        label: Text(suggestion),
        onPressed: () {
          AiHaptics.selection();
          widget.onSelected(suggestion);
        },
      ),
    );
  }

  Widget _staggered(int index, Widget child) {
    // Cap the staggered count so a long list still finishes promptly.
    final start = (index.clamp(0, 5)) * 0.08;
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: AiMotion.standard),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
        );
      },
      child: child,
    );
  }
}
