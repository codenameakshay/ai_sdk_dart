import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:test/test.dart';

void main() {
  test('configured JSON limits must be positive', () {
    expect(
      () => validatedJsonSchema<Map<String, dynamic>>(
        schema: {'type': 'object'},
        fromJson: (json) => json,
        maxDepth: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => validatedJsonSchema<Map<String, dynamic>>(
        schema: {'type': 'object'},
        fromJson: (json) => json,
        maxNodes: 0,
      ),
      throwsArgumentError,
    );
  });

  test('value validation rejects nonfinite values before the decoder', () {
    var decoded = false;
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: {'type': 'object'},
      fromJson: (json) {
        decoded = true;
        return json;
      },
    );
    expect(
      () => schema.fromJson({'value': double.infinity}),
      throwsA(isA<SchemaValidationException>()),
    );
    expect(decoded, isFalse);
    expect(schema.validator!.validate({'value': double.nan}), isNotEmpty);
  });

  test('nonfinite numbers and excessive value depth fail safely', () {
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: {'type': 'object'},
      fromJson: (json) => json,
      maxDepth: 3,
    );
    expect(
      () => schema.fromJson({'x': double.nan}),
      throwsA(isA<SchemaValidationException>()),
    );
    expect(
      () => schema.fromJson({
        'a': {
          'b': {
            'c': {'d': 1},
          },
        },
      }),
      throwsA(isA<SchemaValidationException>()),
    );
  });
  test('schema and input snapshots cannot drift after compilation', () {
    final source = <String, dynamic>{
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
    };
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: source,
      fromJson: (json) => json,
    );
    (source['properties'] as Map)['city'] = {'type': 'number'};
    expect(
      () => schema.fromJson({'city': 7}),
      throwsA(isA<SchemaValidationException>()),
    );
    expect(
      () => (schema.jsonSchema['properties'] as Map)['city'] = {},
      throwsUnsupportedError,
    );
  });
  test('cyclic schema fails within the configured bounds', () {
    final source = <String, dynamic>{};
    source['cycle'] = source;
    expect(
      () => validatedJsonSchema<Map<String, dynamic>>(
        schema: source,
        fromJson: (json) => json,
      ),
      throwsFormatException,
    );
  });

  final shape = <String, dynamic>{
    'type': 'object',
    'required': ['city', 'days', 'region'],
    'additionalProperties': false,
    'properties': {
      'city': {
        'type': 'string',
        'enum': ['Paris', 'London'],
      },
      'days': {
        'type': 'array',
        'items': {
          'type': 'object',
          'required': ['temperature'],
          'properties': {
            'temperature': {'type': 'number'},
          },
        },
      },
      'region': {
        'type': ['string', 'null'],
      },
    },
  };
  for (final dialect in [
    'http://json-schema.org/draft-07/schema#',
    'https://json-schema.org/draft/2020-12/schema',
  ]) {
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: {...shape, r'$schema': dialect},
      fromJson: (json) => json,
    );
    test('$dialect validates nested arrays and nullable fields', () {
      expect(
        schema.fromJson({
          'city': 'Paris',
          'days': [
            {'temperature': 12.5},
          ],
          'region': null,
        })['city'],
        'Paris',
      );
    });
    final invalid = <String, Map<String, dynamic>>{
      'scalar type': {'city': 7, 'days': [], 'region': null},
      'enum': {'city': 'unknown', 'days': [], 'region': null},
      'array': {'city': 'Paris', 'days': {}, 'region': null},
      'nested required': {
        'city': 'Paris',
        'days': [{}],
        'region': null,
      },
      'additional property': {
        'city': 'Paris',
        'days': [],
        'region': null,
        'extra': true,
      },
    };
    for (final entry in invalid.entries) {
      test('$dialect rejects ${entry.key}', () {
        expect(
          () => schema.fromJson(entry.value),
          throwsA(isA<SchemaValidationException>()),
        );
      });
    }
  }
  test('local references are resolved without a network client', () {
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: {
        r'$defs': {
          'city': {'type': 'string'},
        },
        'properties': {
          'city': {r'$ref': r'#/$defs/city'},
        },
      },
      fromJson: (json) => json,
    );
    expect(
      () => schema.fromJson({'city': 7}),
      throwsA(isA<SchemaValidationException>()),
    );
  });
  test('external references are refused during construction', () {
    expect(
      () => validatedJsonSchema<Map<String, dynamic>>(
        schema: {r'$ref': 'https://fixture.invalid/schema.json'},
        fromJson: (json) => json,
      ),
      throwsUnsupportedError,
    );
  });
  test('unsupported dialect is rejected instead of silently downgraded', () {
    expect(
      () => validatedJsonSchema<Map<String, dynamic>>(
        schema: {r'$schema': 'https://fixture.invalid/future-schema'},
        fromJson: (json) => json,
      ),
      throwsUnsupportedError,
    );
  });

  test('required field failure precedes decoding and includes a path', () {
    var decoded = false;
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: {
        'type': 'object',
        'required': ['city'],
        'properties': {
          'city': {'type': 'string'},
        },
      },
      fromJson: (json) {
        decoded = true;
        return json;
      },
    );
    expect(
      () => schema.fromJson({}),
      throwsA(isA<SchemaValidationException>()),
    );
    expect(decoded, isFalse);
  });
}
