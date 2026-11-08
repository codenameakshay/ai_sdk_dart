import 'package:flutter/widgets.dart';

import 'lucide_names.dart';

/// "MapPin", "map_pin" and "map pin" all mean the lucide icon "map-pin".
int? lucideCodepoint(Object? value) {
  if (value is! String) return null;
  final name = value
      .trim()
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .toLowerCase();
  return lucideCodepoints[name];
}

/// Whether [value] names a lucide icon.
bool isLucideIcon(Object? value) => lucideCodepoint(value) != null;

/// A lucide icon by name. Unknown names render nothing.
class Glyph extends StatelessWidget {
  const Glyph(this.name, {super.key, this.size = 18, this.color});
  final Object? name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cp = lucideCodepoint(name);
    if (cp == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Text(
          String.fromCharCode(cp),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'IuiLucide',
            package: 'open_intelligent_ui',
            fontSize: size,
            height: 1,
            color: color ?? DefaultTextStyle.of(context).style.color,
          ),
        ),
      ),
    );
  }
}
