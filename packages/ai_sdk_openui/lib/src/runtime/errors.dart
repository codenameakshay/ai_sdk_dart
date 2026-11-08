import '../lang/validation.dart';
import 'mcp.dart';

/// lang-core `OpenUIErrorSource`.
enum OpenUiErrorSource { parser, runtime, query, mutation }

/// lang-core `OpenUIErrorCode`; [wire] is the JS string.
enum OpenUiErrorCode {
  missingRequired('missing-required'),
  nullRequired('null-required'),
  unknownComponent('unknown-component'),
  inlineReserved('inline-reserved'),
  excessArgs('excess-args'),
  typeMismatch('type-mismatch'),
  unknownFunction('unknown-function'),
  noRoot('no-root'),
  boundOnly('bound-only'),
  runtimeError('runtime-error'),
  renderError('render-error'),
  parseException('parse-exception'),
  parseFailed('parse-failed'),
  toolNotFound('tool-not-found'),
  toolError('tool-error'),
  mcpError('mcp-error');

  const OpenUiErrorCode(this.wire);
  final String wire;
}

/// lang-core `OpenUIError`: a structured error an LLM correction loop can act on.
final class OpenUiError {
  const OpenUiError({
    required this.source,
    required this.code,
    required this.message,
    this.statementId,
    this.component,
    this.path,
    this.toolName,
    this.hint,
    this.isWarning = false,
  });

  final OpenUiErrorSource source;
  final OpenUiErrorCode code;
  final String message;
  final String? statementId;
  final String? component;
  final String? path;
  final String? toolName;
  final String? hint;

  /// lang-core `severity: "warning"`: the program still renders.
  final bool isWarning;

  /// The lang-core JSON shape; null fields are omitted.
  Map<String, Object?> toJson() => {
    'source': source.name,
    'code': code.wire,
    'message': message,
    'statementId': ?statementId,
    'component': ?component,
    'path': ?path,
    'toolName': ?toolName,
    'hint': ?hint,
    if (isWarning) 'severity': 'warning',
  };

  @override
  String toString() => message;
}

/// JavaScript `err instanceof Error ? err.message : String(err)` for Dart throwables.
String errorMessage(Object error) => switch (error) {
  String() => error,
  McpToolError(:final message) => message,
  StateError(:final message) => message,
  ArgumentError(:final Object message) => '$message',
  UnsupportedError(:final String message) => message,
  FormatException(:final message) => message,
  _ => '$error'.replaceFirst(RegExp(r'^Exception: '), ''),
};

/// lang-core `enrichErrors`: parser validation errors as [OpenUiError]s with fix hints.
List<OpenUiError> enrichErrors(
  List<ValidationError> validationErrors,
  Map<String, Object?> schema,
  List<String> componentNames,
) => [
  for (final ve in validationErrors)
    OpenUiError(
      source: OpenUiErrorSource.parser,
      code: OpenUiErrorCode.values.byName(ve.code.name),
      message: ve.message,
      component: ve.component,
      path: ve.path.isEmpty ? null : ve.path,
      statementId: ve.statementId,
      isWarning: ve.isWarning,
      hint: _parserHint(ve, schema, componentNames),
    ),
];

String? _parserHint(
  ValidationError ve,
  Map<String, Object?> schema,
  List<String> componentNames,
) {
  final code = ve.code;
  if (code == ValidationCode.unknownComponent && componentNames.isNotEmpty) {
    return 'Available components: ${componentNames.join(', ')}';
  }
  if (code == ValidationCode.missingRequired ||
      code == ValidationCode.nullRequired) {
    final defs = schema[r'$defs'];
    return _signatureHint(
      ve.component,
      defs is Map ? defs[ve.component] : null,
    );
  }
  if (code == ValidationCode.inlineReserved) {
    return 'Declare as a top-level statement: myVar = ${ve.component}(...)';
  }
  return null;
}

/// Builds `Signature: Card(title*, subtitle) — * marks required` from a JSON Schema entry.
String? _signatureHint(String name, Object? def) {
  if (def is! Map || def['properties'] is! Map) return null;
  final keys = (def['properties'] as Map).keys;
  final required = def['required'] as List? ?? const [];
  final params = [for (final k in keys) required.contains(k) ? '$k*' : '$k'];
  return 'Signature: $name(${params.join(', ')}) — * marks required';
}
