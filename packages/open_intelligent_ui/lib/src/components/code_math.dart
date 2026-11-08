import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme.dart';
import '../view.dart';
import 'glyph.dart';

String _str(Object? value) => value == null ? '' : jsString(value);

/// `Code(code, language?)`: a code block with a copy button.
Widget buildCode(BuildContext context, OpenUiNode node) => _CodeBlock(
  code: _str(node.props['code']),
  language: _str(node.props['language']),
  copy: node.copy,
);

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.code,
    required this.language,
    required this.copy,
  });
  final String code;
  final String language;
  final Future<void> Function(String text) copy;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await widget.copy(widget.code);
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final head = TextStyle(fontSize: 12, color: theme.muted);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(OpenUiTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language.isEmpty ? 'code' : widget.language,
                    style: head,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Copy code',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Glyph(
                            _copied ? 'check' : 'copy',
                            size: 14,
                            color: theme.muted,
                          ),
                          const SizedBox(width: 5),
                          Text(_copied ? 'Copied' : 'Copy', style: head),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: theme.monoFontFamily,
                fontSize: 13,
                height: 1.6,
                color: theme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
