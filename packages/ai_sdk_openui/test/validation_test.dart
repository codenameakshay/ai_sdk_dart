import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/validation.dart';
import 'package:test/test.dart';

/// Validates [value] against [schema] as component `Card`, at `/p`.
({Object? result, List<String> messages}) check(
  Object? value,
  Object? schema, {
  bool partial = false,
  Set<String> components = const {'Card', 'Row'},
}) {
  final ctx = ValidationContext(partial: partial, componentNames: components);
  final result = validateSchemaValue(value, schema, 'Card', '/p', ctx);
  return (result: result, messages: [for (final e in ctx.errors) e.message]);
}

Map<String, Object?> objectOf(
  Map<String, Object?> props, [
  List<String> required = const [],
]) => {'type': 'object', 'properties': props, 'required': required};

const string = {'type': 'string'};
const number = {'type': 'number'};

void main() {
  group('sentinels and errors', () {
    test('print their names', () {
      expect(invalid.toString(), 'invalid');
      expect(absent.toString(), 'absent');
    });

    test('a ValidationError prints its message', () {
      final ctx = ValidationContext()..currentStatementId = 'root';
      pushIssue(ctx, 'Card', '/title', const TypeMismatch('string', 'number'));
      final error = ctx.errors.single;
      expect(error.toString(), 'field "/title" expects string but got number');
      expect(error.code, ValidationCode.typeMismatch);
      expect(error.code.wire, 'type-mismatch');
      expect(error.component, 'Card');
      expect(error.path, '/title');
      expect(error.statementId, 'root');
      expect(error.isWarning, isFalse);
    });
  });

  group('issue messages', () {
    String message(Issue issue, [String component = 'Card', String path = '']) {
      final ctx = ValidationContext();
      pushIssue(ctx, component, path, issue);
      return ctx.errors.single.message;
    }

    test('missing and null required fields', () {
      expect(
        message(const Missing(present: false), 'Card', '/title'),
        'missing required field "/title"',
      );
      expect(
        message(const Missing(present: true), 'Card', '/title'),
        'required field "/title" cannot be null',
      );
    });

    test('a signature follows the missing field', () {
      expect(
        message(
          const Missing(present: false, signature: 'Card(title*: string)'),
          'Card',
          '/title',
        ),
        'missing required field "/title" — signature: Card(title*: string)',
      );
      expect(
        message(
          const Missing(present: true, signature: 'Card(title*: string)'),
          'Card',
          '/title',
        ),
        'required field "/title" cannot be null — signature: '
        'Card(title*: string)',
      );
    });

    test('an unknown component lists the available ones', () {
      expect(
        message(const UnknownComponent(['Card', 'Row']), 'Foo'),
        'Unknown component "Foo" — not found in catalog or builtins. '
        'Available components: Card, Row',
      );
    });

    test('an unknown component with none available lists nothing', () {
      expect(
        message(const UnknownComponent([]), 'Foo'),
        'Unknown component "Foo" — not found in catalog or builtins',
      );
      expect(
        message(const UnknownComponent(null), 'Foo'),
        'Unknown component "Foo" — not found in catalog or builtins',
      );
    });

    test('an inline Query or Mutation', () {
      expect(
        message(const InlineReserved(), 'Query'),
        'Query() must be declared as a top-level statement, not used inline '
        'as a value',
      );
    });

    test('excess arguments', () {
      expect(
        message(const ExcessArgs(2, 5), 'Card'),
        'Card takes 2 arg(s), got 5 (3 excess dropped)',
      );
    });

    test('an unknown function', () {
      expect(
        message(const UnknownFunction(), 'Nope'),
        'Unknown function "@Nope": not a built-in or action step. The call '
        'evaluates to null',
      );
    });

    test('the three no-root reasons', () {
      expect(
        message(const NoRoot(NoRootReason.notComponent)),
        'root does not evaluate to a component',
      );
      expect(
        message(const NoRoot(NoRootReason.fallback), 'Stack'),
        'No root statement. Rendering the first statement that calls the root '
        'component Stack',
      );
      expect(
        message(const NoRoot(NoRootReason.missing), 'Stack'),
        'No root statement, and no statement calls the root component Stack',
      );
      expect(
        message(const NoRoot(NoRootReason.missing), ''),
        'No root statement',
      );
    });

    test('only the fallback no-root is a warning', () {
      bool warning(NoRootReason r) {
        final ctx = ValidationContext();
        pushIssue(ctx, 'Stack', '', NoRoot(r));
        return ctx.errors.single.isWarning;
      }

      expect(warning(NoRootReason.fallback), isTrue);
      expect(warning(NoRootReason.missing), isFalse);
      expect(warning(NoRootReason.notComponent), isFalse);
    });
  });

  group('schema helpers', () {
    test('schemaDefault reads default, and is absent without one', () {
      expect(schemaDefault({'type': 'number', 'default': 3}), 3);
      expect(schemaDefault({'type': 'string', 'default': null}), isNull);
      expect(schemaDefault({'type': 'number'}), same(absent));
      expect(schemaDefault('text'), same(absent));
      expect(schemaDefault(null), same(absent));
    });

    test('resolveInvalidValue prefers the default, then required-ness', () {
      expect(resolveInvalidValue(true, 'd'), 'd');
      expect(resolveInvalidValue(false, 'd'), 'd');
      expect(resolveInvalidValue(true, absent), same(invalid));
      expect(resolveInvalidValue(false, absent), same(absent));
    });

    test('buildParamsSignature marks required params and shows types', () {
      expect(
        buildParamsSignature('Header', [
          const ParamDef(name: 'title', required: true, schema: string),
          const ParamDef(
            name: 'variant',
            required: false,
            schema: {
              'enum': ['a', 'b'],
            },
          ),
          const ParamDef(
            name: 'child',
            required: false,
            schema: {r'$ref': '#/\$defs/Card'},
          ),
          const ParamDef(
            name: 'n',
            required: false,
            schema: {'type': 'integer'},
          ),
          const ParamDef(
            name: 'tags',
            required: false,
            schema: {'type': 'array'},
          ),
          const ParamDef(name: 'x', required: false, schema: {}),
          const ParamDef(name: 'y', required: true, schema: null),
        ]),
        r'Header(title*: string, variant: "a"|"b", child: Card, n: number, '
        'tags: array, x, y*)',
      );
    });

    test('buildParamsSignature writes a const as its literal', () {
      expect(
        buildParamsSignature('Icon', [
          const ParamDef(
            name: 'kind',
            required: true,
            schema: {'const': 'star'},
          ),
          const ParamDef(name: 'size', required: false, schema: {'const': 2.5}),
        ]),
        'Icon(kind*: "star", size: 2.5)',
      );
    });
  });

  group('a value with no schema to check', () {
    test('passes through unchanged', () {
      expect(check('x', null).result, 'x');
      expect(check('x', 'string').result, 'x');
      expect(check('x', const <Object?>[]).result, 'x');
    });

    test('null and AST values are never checked', () {
      expect(check(null, string).result, isNull);
      const ast = NumNode(1);
      expect(check(ast, string).result, same(ast));
      expect(check(ast, string).messages, isEmpty);
    });
  });

  group('scalar leaves', () {
    test('a value of the right type passes', () {
      expect(check('x', string).result, 'x');
      expect(check('x', string).messages, isEmpty);
      expect(check(2, number).result, 2);
      expect(check(true, {'type': 'boolean'}).result, true);
      expect(check(2, {'type': 'integer'}).result, 2);
    });

    test('a value of the wrong type is invalid', () {
      final r = check(2, string);
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects string but got number']);
    });

    test('a list is called an array and a map an object', () {
      expect(check([1], string).messages, [
        'field "/p" expects string but got array',
      ]);
      expect(check({'a': 1}, number).messages, [
        'field "/p" expects number but got object',
      ]);
    });

    test('an enum accepts members and names the allowed values otherwise', () {
      const schema = {
        'enum': ['a', 'b'],
      };
      expect(check('a', schema).result, 'a');
      final r = check('c', schema);
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects one of ["a", "b"] but got "c"']);
    });

    test('an enum compares numbers by JavaScript strict equality', () {
      const schema = {
        'enum': [1, 2.5],
      };
      expect(check(1, schema).result, 1);
      expect(check(1.0, schema).result, 1.0);
      expect(check(2.5, schema).result, 2.5);
      expect(check(3, schema).messages, [
        'field "/p" expects one of [1, 2.5] but got 3',
      ]);
      expect(check('1', schema).messages, [
        'field "/p" expects one of [1, 2.5] but got "1"',
      ]);
    });

    test('a const behaves as a one-member enum', () {
      const schema = {'const': 'star'};
      expect(check('star', schema).result, 'star');
      final r = check('moon', schema);
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects one of ["star"] but got "moon"']);
    });

    test('an enum skips values that are not strings, numbers or booleans', () {
      const schema = {
        'enum': ['a'],
      };
      expect(check({'x': 1}, schema).messages, isEmpty);
      expect(check([1], schema).messages, isEmpty);
    });

    test('enum membership waits for the rest of a streamed value', () {
      const schema = {
        'enum': ['alpha', 'beta'],
      };
      final r = check('al', schema, partial: true);
      expect(r.result, 'al');
      expect(r.messages, isEmpty);
    });

    test('a scalar type is still checked while streaming', () {
      expect(check(2, string, partial: true).messages, [
        'field "/p" expects string but got number',
      ]);
    });

    test('a schema with no type accepts anything', () {
      expect(check(2, const <String, Object?>{}).result, 2);
      expect(check('x', {'type': 'null'}).result, 'x');
    });
  });

  group('component slots', () {
    test('an element where a string is expected is invalid', () {
      final el = ElementNode(
        typeName: 'Row',
        props: const {},
        partial: false,
        hasDynamicProps: false,
      );
      final r = check(el, string);
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects string but got component "Row"']);
    });

    test('an element where an enum is expected names a literal value', () {
      final el = ElementNode(
        typeName: 'Row',
        props: const {},
        partial: false,
        hasDynamicProps: false,
      );
      expect(
        check(el, {
          'enum': ['a'],
        }).messages,
        ['field "/p" expects a literal value but got component "Row"'],
      );
    });

    test(
      'an element is fine where the slot accepts components or anything',
      () {
        final el = ElementNode(
          typeName: 'Row',
          props: const {},
          partial: false,
          hasDynamicProps: false,
        );
        expect(check(el, {r'$ref': '#/\$defs/Card'}).result, same(el));
        expect(check(el, const <String, Object?>{}).result, same(el));
      },
    );

    test('plain data in a single-component slot is invalid', () {
      final r = check('hello', {r'$ref': '#/\$defs/Card'});
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects Card but got string']);
    });

    test('a list and a map are told apart in the message', () {
      const schema = {r'$ref': '#/\$defs/Card'};
      expect(check([1], schema).messages, [
        'field "/p" expects Card but got array',
      ]);
      expect(check({'a': 1}, schema).messages, [
        'field "/p" expects Card but got plain object',
      ]);
      expect(check(2, schema).messages, [
        'field "/p" expects Card but got number',
      ]);
      expect(check(true, schema).messages, [
        'field "/p" expects Card but got boolean',
      ]);
    });

    test('a union of components lists every member', () {
      final r = check('x', {
        'anyOf': [
          {r'$ref': '#/\$defs/Card'},
          {r'$ref': '#/\$defs/Row'},
        ],
      });
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects Card | Row but got string']);
      expect(
        check('x', {
          'oneOf': [
            {r'$ref': '#/\$defs/Card'},
          ],
        }).messages,
        ['field "/p" expects Card but got string'],
      );
    });

    test('a union with a plain member accepts plain data', () {
      expect(
        check('x', {
          'anyOf': [
            {r'$ref': '#/\$defs/Card'},
            string,
          ],
        }).result,
        'x',
      );
    });

    test('a ref to something that is not a component accepts plain data', () {
      expect(check('x', {r'$ref': '#/\$defs/Other'}).result, 'x');
      expect(
        check('x', {r'$ref': '#/\$defs/Card'}, components: {}).result,
        'x',
      );
    });
  });

  group('objects', () {
    final schema = objectOf(
      {
        'name': string,
        'age': number,
        'tag': {'type': 'string', 'default': 'none'},
      },
      ['name'],
    );

    test('a conforming object comes back as is', () {
      final value = {'name': 'a', 'age': 3};
      expect(check(value, schema).result, same(value));
    });

    test('a non-object is invalid', () {
      expect(check('x', schema).messages, [
        'field "/p" expects object but got string',
      ]);
      expect(check([1], schema).messages, [
        'field "/p" expects object but got array',
      ]);
    });

    test('a missing required key is reported with its path', () {
      final r = check(<String, Object?>{'age': 1}, schema);
      expect(r.result, same(invalid));
      expect(r.messages, ['missing required field "/p/name"']);
    });

    test('a null required key is reported as null', () {
      final r = check(<String, Object?>{'name': null}, schema);
      expect(r.result, same(invalid));
      expect(r.messages, ['required field "/p/name" cannot be null']);
    });

    test('a required key with a default fills in silently', () {
      final withDefault = objectOf(
        {
          'name': {'type': 'string', 'default': 'anon'},
        },
        ['name'],
      );
      final missing = check(<String, Object?>{}, withDefault);
      expect(missing.result, {'name': 'anon'});
      expect(missing.messages, isEmpty);
      final nulled = check(<String, Object?>{'name': null}, withDefault);
      expect(nulled.result, {'name': 'anon'});
      expect(nulled.messages, isEmpty);
    });

    test('required keys are not checked while streaming', () {
      final value = <String, Object?>{'age': 1};
      final r = check(value, schema, partial: true);
      expect(r.result, same(value));
      expect(r.messages, isEmpty);
    });

    test('a wrong optional property is dropped', () {
      final r = check(<String, Object?>{'name': 'a', 'age': 'x'}, schema);
      expect(r.result, {'name': 'a'});
      expect(r.messages, ['field "/p/age" expects number but got string']);
    });

    test('a wrong property with a default takes the default', () {
      final r = check(<String, Object?>{'name': 'a', 'tag': 5}, schema);
      expect(r.result, {'name': 'a', 'tag': 'none'});
      expect(r.messages, ['field "/p/tag" expects string but got number']);
    });

    test('a wrong required property makes the object invalid', () {
      final r = check(<String, Object?>{'name': 5, 'age': 'x'}, schema);
      expect(r.result, same(invalid));
      expect(r.messages, [
        'field "/p/name" expects string but got number',
        'field "/p/age" expects number but got string',
      ]);
    });

    test('keys the schema does not declare are kept', () {
      final r = check(<String, Object?>{'name': 'a', 'extra': 1}, schema);
      expect(r.result, {'name': 'a', 'extra': 1});
    });

    test('a nested invalid object is pruned when optional', () {
      final nested = objectOf({
        'inner': objectOf({'n': number}, ['n']),
      });
      final r = check(<String, Object?>{
        'inner': <String, Object?>{'n': 'x'},
      }, nested);
      expect(r.result, <String, Object?>{});
      expect(r.messages, ['field "/p/inner/n" expects number but got string']);
    });

    test('a nested invalid object invalidates a required parent', () {
      final nested = objectOf(
        {
          'inner': objectOf({'n': number}, ['n']),
        },
        ['inner'],
      );
      final r = check(<String, Object?>{
        'inner': <String, Object?>{'n': 'x'},
      }, nested);
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p/inner/n" expects number but got string']);
    });

    test('an object with no properties or required list accepts any map', () {
      final value = <String, Object?>{'a': 1};
      expect(check(value, {'type': 'object'}).result, same(value));
    });
  });

  group('arrays', () {
    const schema = {'type': 'array', 'items': number};

    test('a non-array is invalid', () {
      final r = check('x', schema);
      expect(r.result, same(invalid));
      expect(r.messages, ['field "/p" expects array but got string']);
      expect(check({'a': 1}, schema).messages, [
        'field "/p" expects array but got object',
      ]);
    });

    test('a conforming array comes back as is', () {
      final value = <Object?>[1, 2];
      expect(check(value, schema).result, same(value));
    });

    test('invalid items are pruned and keep their original index', () {
      final r = check(<Object?>[1, 'a', 2, 'b'], schema);
      expect(r.result, [1, 2]);
      expect(r.messages, [
        'field "/p/1" expects number but got string',
        'field "/p/3" expects number but got string',
      ]);
    });

    test('items with a default are repaired, not pruned', () {
      final r = check(
        <Object?>[
          <String, Object?>{'name': null},
          <String, Object?>{'name': 'b'},
        ],
        {
          'type': 'array',
          'items': objectOf(
            {
              'name': {'type': 'string', 'default': 'anon'},
            },
            ['name'],
          ),
        },
      );
      expect(r.result, [
        {'name': 'anon'},
        {'name': 'b'},
      ]);
      expect(r.messages, isEmpty);
    });

    test('an array with no items schema accepts any elements', () {
      final value = <Object?>[1, 'a'];
      expect(check(value, {'type': 'array'}).result, same(value));
    });
  });
}
