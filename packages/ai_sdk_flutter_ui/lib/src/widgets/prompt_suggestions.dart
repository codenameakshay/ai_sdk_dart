import 'package:flutter/material.dart';

/// A wrap of tappable prompt-starter chips.
///
/// Ideal for an empty conversation state: surface a few example prompts the
/// user can tap to kick things off. [onSelected] fires with the chosen string —
/// wire it to `ChatController.sendMessage` or your composer.
///
/// Collapses to nothing when [suggestions] is empty. Themed via
/// `Theme.of(context)`; holds no business logic.
///
/// ```dart
/// PromptSuggestions(
///   title: 'Try asking',
///   suggestions: const ['Summarize my notes', 'Plan a trip to Kyoto'],
///   onSelected: (text) => controller.sendMessage(agent: agent, text: text),
/// )
/// ```
class PromptSuggestions extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = this.title;

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
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                label: Text(suggestion),
                onPressed: () => onSelected(suggestion),
              ),
          ],
        ),
      ],
    );
  }
}
