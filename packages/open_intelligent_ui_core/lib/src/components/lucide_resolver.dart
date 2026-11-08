import 'package:flutter/widgets.dart';

import 'glyph.dart';
import 'lucide_icons.dart';

/// lucide-react 0.562.0's icons, by name or alias, drawn as lucide-react draws
/// them. Pass it as `OpenUiServices(icons: lucideIconResolver)`.
Widget? lucideIconResolver(
  String name,
  double size,
  Color color,
  double strokeWidth,
) {
  final d = lucideIcons[lucideAliases[name] ?? name];
  return d == null
      ? null
      : OutlineGlyph(
          stroke: d.$1,
          fill: d.$2,
          size: size,
          color: color,
          strokeWidth: strokeWidth,
        );
}
