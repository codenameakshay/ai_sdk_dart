import 'dart:convert';

import '../lang/js.dart';

/// Thrown when an MCP tool result has `isError: true` (lang-core `McpToolError`).
final class McpToolError implements Exception {
  const McpToolError(this.toolErrorText);

  final String toolErrorText;

  String get message =>
      'MCP tool error: ${toolErrorText.isEmpty ? 'Unknown error' : toolErrorText}';

  @override
  String toString() => message;
}

/// lang-core `extractToolResult`: the data of an MCP `callTool` result: `structuredContent`,
/// else the text content parsed as JSON, else the text.
Object? extractToolResult(Map<String, Object?> result) {
  final content = result['content'] is List
      ? result['content'] as List
      : const <Object?>[];
  final texts = [
    for (final c in content)
      if (c is Map && c['type'] == 'text')
        if (c['text'] == null) '' else Js.string(c['text']),
  ];
  if (Js.truthy(result['isError'])) {
    final errorText = texts.join('\n');
    throw McpToolError(errorText.isEmpty ? 'Unknown error' : errorText);
  }
  if (result['structuredContent'] != null) return result['structuredContent'];
  if (texts.isEmpty) return null;
  final text = texts.join();
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}
