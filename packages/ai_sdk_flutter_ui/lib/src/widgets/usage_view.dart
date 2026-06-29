import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

/// A compact row of token-usage stats for a generation.
///
/// Renders one labelled pill per non-null token field of [usage] — input,
/// output, and total. Fields whose count is null are omitted; if every count
/// is null the widget collapses to nothing.
///
/// Feed it `ChatController.lastUsage`, `CompletionController.lastUsage`, or any
/// `LanguageModelV3Usage` from a generation result.
///
/// ```dart
/// final usage = controller.lastUsage;
/// if (usage != null) UsageView(usage: usage)
/// ```
class UsageView extends StatelessWidget {
  const UsageView({super.key, required this.usage, this.spacing = 6});

  /// The token usage to display.
  final LanguageModelV3Usage usage;

  /// Horizontal/vertical gap between the pills.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, int)>[
      if (usage.inputTokens != null) ('Input', usage.inputTokens!),
      if (usage.outputTokens != null) ('Output', usage.outputTokens!),
      if (usage.totalTokens != null) ('Total', usage.totalTokens!),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final (label, count) in entries) _UsagePill(label: label, count: count),
      ],
    );
  }
}

class _UsagePill extends StatelessWidget {
  const _UsagePill({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
