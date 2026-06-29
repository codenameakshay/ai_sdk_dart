import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

/// Renders a tool call — the tool name plus its pretty-printed JSON arguments —
/// and, when supplied, the matching tool result or error.
///
/// Feed it the parts from a streamed/generated turn:
///
/// ```dart
/// ToolCallCard(
///   call: toolCallPart,
///   result: toolResultPart, // optional
/// )
/// ```
///
/// Pure presentation: it reads only the content-part fields and themes via
/// `Theme.of(context)`.
class ToolCallCard extends StatelessWidget {
  const ToolCallCard({super.key, required this.call, this.result});

  /// The tool call to render.
  final LanguageModelV3ToolCallPart call;

  /// Optional result for [call]. When [LanguageModelV3ToolResultPart.isError]
  /// is true, it is rendered in the error color.
  final LanguageModelV3ToolResultPart? result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final result = this.result;
    final isError = result?.isError ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    call.toolName,
                    style: textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CodeBlock(text: _prettyJson(call.input)),
            if (result != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 16,
                    color: isError ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isError ? 'Error' : 'Result',
                    style: textTheme.labelMedium?.copyWith(
                      color: isError ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _CodeBlock(
                text: _stringifyOutput(result.output),
                background: isError ? scheme.errorContainer : null,
                foreground: isError ? scheme.onErrorContainer : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _prettyJson(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  static String _stringifyOutput(LanguageModelV3ToolResultOutput output) {
    if (output is ToolResultOutputText) return output.text;
    if (output is ToolResultOutputContent) {
      return output.parts.map((p) => p.runtimeType).join(', ');
    }
    return output.toString();
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text, this.background, this.foreground});

  final String text;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: foreground ?? scheme.onSurface,
        ),
      ),
    );
  }
}
