import 'dart:convert';

import 'package:flutter/material.dart';

/// Pretty-prints [value] as indented JSON, falling back to [Object.toString]
/// when it isn't JSON-encodable.
///
/// Not part of the public API.
String prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

/// A monospace, rounded block used to render pretty-printed JSON.
///
/// Not part of the public API.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.text,
    this.background,
    this.foreground,
    this.padding = const EdgeInsets.all(10),
  });

  final String text;
  final Color? background;
  final Color? foreground;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectionArea(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
            color: foreground ?? scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
