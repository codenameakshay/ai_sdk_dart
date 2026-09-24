import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:json_schema/json_schema.dart' as js;

/// Compiles a local JSON Schema and validates before decoding tool/final output.
///
/// Supports Draft 7 and 2020-12; absent `$schema` defaults to 2020-12.
/// External references are rejected and never fetched over the network.
Schema<T> validatedJsonSchema<T>({
  required Map<String, dynamic> schema,
  required T Function(Map<String, dynamic>) fromJson,
  int maxDepth = 64,
  int maxNodes = 100000,
}) {
  if (!_withinLimits(schema, maxDepth, maxNodes)) {
    throw const FormatException(
      'JSON Schema exceeds the configured JSON limits.',
    );
  }
  final copy = (jsonDecode(jsonEncode(schema)) as Map).cast<String, dynamic>();
  final validator = JsonSchemaValidator(
    copy,
    maxDepth: maxDepth,
    maxNodes: maxNodes,
  );
  return Schema(
    jsonSchema: _freeze(copy) as Map<String, dynamic>,
    fromJson: fromJson,
    validator: validator,
  );
}

class JsonSchemaValidator implements SchemaValidator {
  JsonSchemaValidator(
    Map<String, dynamic> schema, {
    this.maxDepth = 64,
    this.maxNodes = 100000,
  }) : _schema = _compile(schema, maxDepth, maxNodes);

  final int maxDepth;
  final int maxNodes;

  static js.JsonSchema _compile(
    Map<String, dynamic> schema,
    int maxDepth,
    int maxNodes,
  ) {
    if (!_withinLimits(schema, maxDepth, maxNodes)) {
      throw const FormatException(
        'JSON Schema exceeds the configured JSON limits.',
      );
    }
    return js.JsonSchema.create(
      schema,
      schemaVersion: _version(schema[r'$schema']),
      refProvider: js.RefProvider.sync(
        (ref) => throw UnsupportedError(
          'External JSON Schema references are disabled.',
        ),
      ),
    );
  }

  final js.JsonSchema _schema;

  static js.SchemaVersion _version(Object? declaration) =>
      switch (declaration) {
        null ||
        'https://json-schema.org/draft/2020-12/schema' ||
        'https://json-schema.org/draft/2020-12/schema#' =>
          js.SchemaVersion.draft2020_12,
        'http://json-schema.org/draft-07/schema#' ||
        'https://json-schema.org/draft-07/schema#' => js.SchemaVersion.draft7,
        _ => throw UnsupportedError(
          'Only JSON Schema Draft 7 and 2020-12 are supported.',
        ),
      };

  @override
  List<SchemaValidationIssue> validate(Map<String, dynamic> value) {
    if (!_withinLimits(value, maxDepth, maxNodes)) {
      return const [
        SchemaValidationIssue(
          path: '',
          message:
              'Value exceeds configured JSON limits or contains non-JSON values.',
        ),
      ];
    }
    return _schema
        .validate(value, validateFormats: false)
        .errors
        .map(
          (error) => SchemaValidationIssue(
            path: error.instancePath,
            schemaPath: error.schemaPath,
            message: error.message,
          ),
        )
        .toList(growable: false);
  }
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
    value.map((key, child) => MapEntry(key, _freeze(child))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

bool _withinLimits(Object? value, int maxDepth, int maxNodes) {
  if (maxDepth < 1 || maxNodes < 1) {
    throw ArgumentError('JSON limits must be positive.');
  }
  final pending = <(Object?, int)>[(value, 0)];
  var count = 0;
  while (pending.isNotEmpty) {
    final (current, depth) = pending.removeLast();
    if (++count > maxNodes || depth > maxDepth) return false;
    switch (current) {
      case Map():
        if (current.keys.any((key) => key is! String)) return false;
        for (final child in current.values) {
          pending.add((child, depth + 1));
        }
      case List():
        for (final child in current) {
          pending.add((child, depth + 1));
        }
      case num():
        if (!current.isFinite) return false;
      case null || String() || bool():
        break;
      default:
        return false;
    }
    if (pending.length + count > maxNodes) return false;
  }
  return true;
}
