import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

String _str(Object? value) => value == null ? '' : jsString(value);

/// `Math(tex, inline?)`: a LaTeX formula. A formula that does not parse
/// shows its source, as KaTeX does with `throwOnError: false`.
Widget buildMath(BuildContext context, OpenUiNode node) {
  final tex = _str(node.props['tex']);
  final inline = node.props.boolean('inline') ?? false;
  final theme = node.theme;
  final base = DefaultTextStyle.of(context).style;
  final formula = Math.tex(
    tex,
    mathStyle: inline ? MathStyle.text : MathStyle.display,
    textStyle: base.copyWith(
      fontSize: (base.fontSize ?? 14) * 1.12,
      color: theme.ink,
    ),
    onErrorFallback: (error) => Text(
      tex,
      style: base.copyWith(
        fontFamily: theme.monoFontFamily,
        color: theme.danger,
      ),
    ),
  );
  if (inline) return formula;
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: formula,
  );
}

extension on OpenUiTheme {
  Color get danger => status['danger']!;
}
