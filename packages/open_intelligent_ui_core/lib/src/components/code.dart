import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../localizations.dart';
import '../theme.dart';
import '../view.dart';
import 'controls.dart' show Press;
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
    final head = TextStyle(
      fontSize: theme.fontSizeOf('Code.head', 12),
      color: theme.muted,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(theme.radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 8, 6),
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
                  container: true,
                  button: true,
                  label: OpenUiLocalizations.of(context).copyCode,
                  excludeSemantics: true,
                  child: Press(
                    radius: theme.radii.sm,
                    onTap: (_) => _copy(),
                    builder: (hovered, pressed) {
                      final color = hovered ? theme.ink : theme.muted;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hovered ? theme.hover : null,
                          borderRadius: BorderRadius.circular(theme.radii.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Glyph(
                              _copied ? 'check' : 'copy',
                              size: 14,
                              color: color,
                              strokeWidth: 2,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _copied
                                  ? OpenUiLocalizations.of(context).copied
                                  : OpenUiLocalizations.of(context).copy,
                              style: head.copyWith(color: color),
                            ),
                          ],
                        ),
                      );
                    },
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
                fontSize: theme.fontSizeOf('Code', 13),
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
