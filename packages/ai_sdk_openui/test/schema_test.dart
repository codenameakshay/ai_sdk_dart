import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/spec/schema.dart'
    show JsonSchemaEmitter, signature, typeAnnotation;
import 'package:test/test.dart';

Map<String, Object?> _emit(Schema s) => JsonSchemaEmitter(
  (name) => {'type': 'string', 'description': 'body of $name'},
).emit(s);

const _null = {'type': 'null'};

void main() {
  group('nullable schemas emit anyOf with null, as Zod does', () {
    test('a literal', () {
      expect(_emit(S.literal('open').nullable()), {
        'anyOf': [
          {'type': 'string', 'const': 'open'},
          _null,
        ],
      });
    });

    test('an enum', () {
      expect(_emit(S.oneOf(['a', 'b']).nullable()), {
        'anyOf': [
          {
            'type': 'string',
            'enum': ['a', 'b'],
          },
          _null,
        ],
      });
    });

    test('a list', () {
      expect(_emit(S.list(S.number()).nullable()), {
        'anyOf': [
          {
            'type': 'array',
            'items': {'type': 'number'},
          },
          _null,
        ],
      });
    });

    test('an object keeps its required list', () {
      final schema = S.object({'a': S.string(), 'b': S.number().optional()});
      expect(_emit(schema.nullable()), {
        'anyOf': [
          {
            'type': 'object',
            'properties': {
              'a': {'type': 'string'},
              'b': {'type': 'number'},
            },
            'required': ['a'],
            'additionalProperties': false,
          },
          _null,
        ],
      });
    });

    test('a record', () {
      expect(_emit(S.record(S.string(), S.number()).nullable()), {
        'anyOf': [
          {
            'type': 'object',
            'propertyNames': {'type': 'string'},
            'additionalProperties': {'type': 'number'},
          },
          _null,
        ],
      });
    });

    test(r'a component ref points into $defs', () {
      final emitter = JsonSchemaEmitter(
        (name) => {'type': 'object', 'description': name},
      );
      expect(emitter.emit(S.ref('Card').nullable()), {
        'anyOf': [
          {r'$ref': r'#/$defs/Card'},
          _null,
        ],
      });
      expect(emitter.defs, {
        'Card': {'type': 'object', 'description': 'Card'},
      });
    });

    test('a union of plain types', () {
      expect(_emit(S.union([S.string(), S.number()]).nullable()), {
        'anyOf': [
          {
            'type': ['string', 'number'],
          },
          _null,
        ],
      });
    });

    test('any', () {
      expect(_emit(S.any().nullable()), {
        'anyOf': [<String, Object?>{}, _null],
      });
    });

    test('a primitive folds null into its type', () {
      expect(_emit(S.string().nullable()), {
        'type': ['string', 'null'],
      });
    });
  });

  test('a union with a non-primitive member emits anyOf', () {
    expect(_emit(S.union([S.string(), S.list(S.number())])), {
      'anyOf': [
        {'type': 'string'},
        {
          'type': 'array',
          'items': {'type': 'number'},
        },
      ],
    });
  });

  test('a record annotates as Record<K, V> in the prompt', () {
    final sig = signature('Chart', {
      'data': S.list(S.record(S.string(), S.union([S.string(), S.number()]))),
    });
    expect(sig, 'Chart(data: Record<string, string | number>[])');
  });

  test(
    'a default is emitted first and required, and the prompt marks it optional, as Zod does',
    () {
      final params = {
        'name': S.string(),
        'format': S.oneOf(['csv', 'pdf']).withDefault('csv'),
      };
      expect(
        jsonEncode(_emit(S.object(params))),
        '{"type":"object","properties":{"name":{"type":"string"},'
        '"format":{"default":"csv","type":"string","enum":["csv","pdf"]}},'
        '"required":["name","format"],"additionalProperties":false}',
      );
      expect(
        signature('ExportFile', params),
        'ExportFile(name: string, format?: "csv" | "pdf")',
      );
    },
  );

  group('modifiers keep every other flag', () {
    final kinds = <String, Schema>{
      'string': S.string(),
      'any': S.any(),
      'literal': S.literal('x'),
      'enum': S.oneOf(['x', 'y']),
      'list': S.list(S.string()),
      'union': S.union([S.string(), S.number()]),
      'object': S.object({'a': S.string()}),
      'record': S.record(S.string(), S.number()),
      'ref': S.ref('Card'),
      'default': S.string().withDefault('x'),
    };
    for (final MapEntry(:key, :value) in kinds.entries) {
      test(key, () {
        final s = value.optional().nullable().reactive().tag('T');
        expect(
          (s.isOptional, s.isNullable, s.isReactive, s.tagName),
          (true, true, true, 'T'),
        );
        // Each step also leaves the earlier flags in place.
        final t = value.tag('T').reactive().nullable().optional();
        expect(
          (t.isOptional, t.isNullable, t.isReactive, t.tagName),
          (true, true, true, 'T'),
        );
        expect(
          (value.isOptional, value.isNullable, value.isReactive),
          (false, false, false),
          reason: 'modifiers return a copy',
        );
        expect(typeAnnotation(s), r'$binding<T>');
      });
    }
  });
}
