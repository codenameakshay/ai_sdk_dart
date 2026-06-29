import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

/// A wrap of citation chips, one per [LanguageModelV3SourcePart].
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
  final List<LanguageModelV3SourcePart> sources;

  /// Called when a chip is tapped, with the corresponding source.
  final void Function(LanguageModelV3SourcePart source)? onTap;

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
              ActionChip(
                avatar: Icon(
                  Icons.link_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                label: Text(_chipLabel(source)),
                tooltip: source.url,
                visualDensity: VisualDensity.compact,
                onPressed: onTap == null ? null : () => onTap!(source),
              ),
          ],
        ),
      ],
    );
  }

  static String _chipLabel(LanguageModelV3SourcePart source) {
    final title = source.title;
    if (title != null && title.trim().isNotEmpty) return title;
    return source.url;
  }
}
