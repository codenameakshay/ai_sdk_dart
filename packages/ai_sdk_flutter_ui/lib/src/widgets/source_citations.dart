import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// A wrap of citation chips, one per [LanguageModelV4SourcePart].
///
/// Each chip shows the source's title (falling back to its URL) and, when
/// [onTap] is provided, is tappable so the host app can open the link. The
/// package does not depend on `url_launcher`; wire your own opener via [onTap].
///
/// ```dart
/// SourceCitations(
///   sources: result.sources,
///   onTap: (source) => launchUrl(Uri.parse(source.url)),
/// )
/// ```
class SourceCitations extends StatelessWidget {
  const SourceCitations({
    super.key,
    required this.sources,
    this.onTap,
    this.label = 'Sources',
  });

  /// Source parts to render as chips.
  final List<LanguageModelV4SourcePart> sources;

  /// Called when a chip is tapped, with the corresponding source.
  final void Function(LanguageModelV4SourcePart source)? onTap;

  /// Optional section label shown above the chips. Pass an empty string to hide.
  final String label;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final source in sources)
              Builder(
                builder: (context) {
                  final interactive = onTap != null;
                  final labelText = _chipLabel(source);
                  return Semantics(
                    button: interactive,
                    link: interactive,
                    label: interactive
                        ? 'Open source: $labelText'
                        : 'Source: $labelText',
                    hint: interactive ? source.url : null,
                    onTap: interactive ? () => onTap!(source) : null,
                    child: ExcludeSemantics(
                      child: PressableScale(
                        child: ActionChip(
                          avatar: Icon(
                            Icons.link_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          label: Text(labelText),
                          tooltip: interactive
                              ? 'Open source: $labelText'
                              : 'Source: $labelText',
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onPressed: interactive
                              ? () {
                                  AiHaptics.selection();
                                  onTap!(source);
                                }
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  static String _chipLabel(LanguageModelV4SourcePart source) {
    final title = source.title;
    if (title != null && title.trim().isNotEmpty) return title;
    return source.url;
  }
}
