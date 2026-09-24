/// Validates decoded JSON independently of its conversion to a Dart type.
abstract interface class SchemaValidator {
  List<SchemaValidationIssue> validate(Map<String, dynamic> value);
}

class SchemaValidationIssue {
  const SchemaValidationIssue({
    required this.path,
    required this.message,
    this.schemaPath,
  });

  /// JSON Pointer to the invalid value; the empty string denotes the root.
  final String path;
  final String message;
  final String? schemaPath;
}

class SchemaValidationException implements Exception {
  SchemaValidationException(List<SchemaValidationIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<SchemaValidationIssue> issues;

  @override
  String toString() => 'Schema validation failed (${issues.length} issues).';
}
