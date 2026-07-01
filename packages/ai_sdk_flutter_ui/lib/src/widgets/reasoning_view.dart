import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// A collapsible panel for reasoning ("thinking") text.
///
/// Use it to surface a model's chain-of-thought without dominating the
/// conversation. Collapsed by default; tap the header to expand. The disclosure
/// eases open and the chevron rotates; both collapse to instant under reduced
/// motion.
///
/// ```dart
/// ReasoningView(text: result.reasoningText)
/// ```
///
/// Stateful only to track expansion; it holds no business logic and reads no
/// controller.
class ReasoningView extends StatefulWidget {
  const ReasoningView({
    super.key,
    required this.text,
    this.title = 'Reasoning',
    this.initiallyExpanded = false,
  });

  /// The reasoning text to show when expanded.
  final String text;

  /// Header label.
  final String title;

  /// Whether the panel starts expanded.
  final bool initiallyExpanded;

  @override
  State<ReasoningView> createState() => _ReasoningViewState();
}

class _ReasoningViewState extends State<ReasoningView> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    AiHaptics.selection();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final motion = AiMotion.duration(context, AiMotion.base);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: motion,
                    curve: AiMotion.standard,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: motion,
            curve: AiMotion.standard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SelectableText(
                      widget.text,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
