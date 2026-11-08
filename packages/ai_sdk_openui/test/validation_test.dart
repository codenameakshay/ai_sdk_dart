import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/parser.dart';
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

  // Ported from lang-core 1.0.0 parser/__tests__/materialize.validation.test.ts,
  // case for case. Each component's first arg is the schema under test.
  group('lang-core materialize validation cases', () {
    Map<String, Object?> box(
      Map<String, Object?> properties, [
      List<String> required = const [],
    ]) => {'properties': properties, 'required': required};
    final schema = CompiledSchema.fromJsonSchema({
      r'$defs': {
        'ObjBox': box({
          'info': {
            'type': 'object',
            'properties': {'author': string, 'views': number},
            'required': ['author'],
          },
        }),
        'ArrBox': box({
          'rows': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {'label': string, 'value': number},
              'required': ['label'],
            },
          },
        }),
        'TagBox': box({
          'tags': {'type': 'array', 'items': string},
        }),
        'EnumBox': box({
          'status': {
            'enum': ['active', 'inactive'],
          },
        }),
        'AnyBox': box({
          'combo': {
            'anyOf': [string, number],
          },
        }),
        'ScalarBox': box({
          'title': string,
          'count': number,
          'flag': {'type': 'boolean'},
        }),
        'ListBox': box({
          'children': {'type': 'array'},
        }),
        'CardBox': box({'text': string}),
        'ReqScalar': box({'title': string}, ['title']),
        'DefBox': box(
          {
            'theme': {'type': 'string', 'default': 'dark'},
          },
          ['theme'],
        ),
        'SlotBox': box({
          'children': {
            'type': 'array',
            'items': {
              'anyOf': [
                {r'$ref': r'#/$defs/CardBox'},
              ],
            },
          },
        }),
        'ChartBox': box(
          {
            'labels': {'type': 'array', 'items': string},
            'variant': {
              'enum': ['grouped', 'stacked'],
            },
          },
          ['labels'],
        ),
        'NestDefBox': box({
          'cfg': {
            'type': 'object',
            'properties': {
              'mode': {
                'enum': ['fast', 'slow'],
                'default': 'fast',
              },
              'retries': {'type': 'number', 'default': 3},
            },
            'required': ['mode'],
          },
        }),
      },
    });
    ParseResult parse(String src) => parseProgram(src, schema);
    List<ValidationError> errorsFor(String src) => parse(src).meta.errors;
    List<ValidationError> directErrors(
      Object? value,
      Object? s, {
      bool partial = false,
    }) {
      final ctx = ValidationContext(partial: partial);
      validateSchemaValue(value, s, 'X', '/p', ctx);
      return ctx.errors;
    }

    String codePath(ValidationError e) => '${e.code.wire}:${e.path}';

    test(
      'accepts valid values and reports violations with JSON-pointer paths and distinct codes',
      () {
        expect(
          errorsFor('root = ObjBox({ author: "ann", views: 3 })'),
          isEmpty,
        );
        final leaf = errorsFor(
          'root = ObjBox({ author: "ann", views: "lots" })',
        ).first;
        expect(
          [leaf.code.wire, leaf.component, leaf.path],
          ['type-mismatch', 'ObjBox', '/info/views'],
        );
        expect(
          errorsFor('root = ArrBox([{ label: "a", value: "x" }])').first.path,
          '/rows/0/value',
        );
        expect(
          codePath(errorsFor('root = ObjBox({ views: 3 })').first),
          'missing-required:/info/author',
        );
        expect(
          codePath(
            errorsFor('root = ObjBox({ author: null, views: 3 })').first,
          ),
          'null-required:/info/author',
        );
      },
    );

    test(
      'reports container-shape mismatches and accumulates independent errors',
      () {
        expect(
          errorsFor('root = ObjBox("hello")').first.message,
          contains('expects object but got string'),
        );
        expect(
          errorsFor('root = TagBox(42)').first.message,
          contains('expects array but got number'),
        );
        expect(
          errorsFor(r'root = ScalarBox({ a: $x })').first.message,
          contains('expects string but got object'),
        );
        expect(
          errorsFor(
            'root = ArrBox([{ label: 1 }, { value: "x" }])',
          ).map(codePath).toList()..sort(),
          [
            'missing-required:/rows/1/label',
            'type-mismatch:/rows/0/label',
            'type-mismatch:/rows/1/value',
          ],
        );
        expect(
          errorsFor(
            'root = ScalarBox(1, 1, true, "extra")',
          ).map((e) => e.code.wire).toList()..sort(),
          ['excess-args', 'type-mismatch'],
        );
      },
    );

    test('messages are self-sufficient and attributed to the defining statement', () {
      expect(
        errorsFor('root = ReqScalar()').first.message,
        'missing required field "/title" — signature: ReqScalar(title*: string)',
      );
      expect(
        errorsFor('root = ChartBox(null, "grouped")').first.message,
        'required field "/labels" cannot be null — signature: ChartBox(labels*: array, variant: "grouped"|"stacked")',
      );
      expect(
        errorsFor('root = Nope()').first.message,
        contains('Available components: ObjBox, ArrBox'),
      );
      final inner = errorsFor(
        'root = ListBox([inner])\ninner = ObjBox({ author: "ann", views: "lots" })',
      ).first;
      expect([inner.component, inner.statementId], ['ObjBox', 'inner']);
    });

    test(
      'prunes invalid values on optional edges and array items; the component survives',
      () {
        expect(
          parse(
            'root = ObjBox({ author: "ann", views: "lots" })',
          ).root!.props['info'],
          {'author': 'ann'},
        );
        final top = parse('root = ScalarBox(5)');
        expect(top.root, isNotNull);
        expect(top.root!.props.containsKey('title'), isFalse);
        expect(
          parse('root = ObjBox({ views: 3 })').root!.props.containsKey('info'),
          isFalse,
        );
        expect(parse('root = TagBox(["a", 2, "c"])').root!.props['tags'], [
          'a',
          'c',
        ]);
        expect(
          parse(
            'root = ArrBox([{ label: "a", value: 1 }, { value: 2 }])',
          ).root!.props['rows'],
          [
            {'label': 'a', 'value': 1},
          ],
        );
      },
    );

    test(
      'propagates through required edges: parent pruned at an optional edge, or component dropped',
      () {
        final nested = parse(
          'root = ObjBox({ author: { first: "a" }, views: 3 })',
        );
        expect(nested.root, isNotNull);
        expect(nested.root!.props.containsKey('info'), isFalse);
        expect(parse('root = ReqScalar(5)').root, isNull);
      },
    );

    test(
      'substitutes schema defaults at every edge; absent or null required keys fill silently',
      () {
        final def = parse('root = DefBox(5)');
        expect(def.root!.props['theme'], 'dark');
        expect(def.meta.errors, hasLength(1));
        expect(parse('root = DefBox()').meta.errors, isEmpty);
        final opt = parse('root = NestDefBox({ mode: "warp", retries: 1 })');
        expect(opt.root!.props['cfg'], {'mode': 'fast', 'retries': 1});
        expect(codePath(opt.meta.errors.first), 'type-mismatch:/cfg/mode');
        expect(
          parse(
            'root = NestDefBox({ mode: "slow", retries: "many" })',
          ).root!.props['cfg'],
          {'mode': 'slow', 'retries': 3},
        );
        final absent = parse('root = NestDefBox({ retries: 2 })');
        expect(absent.root!.props['cfg'], {'mode': 'fast', 'retries': 2});
        expect(absent.meta.errors, isEmpty);
        final nulled = parse('root = NestDefBox({ mode: null, retries: 2 })');
        expect(nulled.root!.props['cfg'], {'mode': 'fast', 'retries': 2});
        expect(nulled.meta.errors, isEmpty);
      },
    );

    test(
      'elements in data slots follow the edge rule: drop on required, prune on optional or items',
      () {
        final dropped = parse('root = ChartBox(CardBox("x"), "grouped")');
        expect(dropped.root, isNull);
        expect(
          dropped.meta.errors.first.message,
          contains('expects array but got component "CardBox"'),
        );
        final pruned = parse('root = ChartBox(["a"], CardBox("x"))');
        expect(pruned.root!.props.containsKey('variant'), isFalse);
        expect(
          pruned.meta.errors.first.message,
          contains('expects a literal value but got component'),
        );
        expect(
          parse('root = TagBox(["a", CardBox("x"), "b"])').root!.props['tags'],
          ['a', 'b'],
        );
      },
    );

    test(
      "component slots accept any component; a misplaced component's own args still validate",
      () {
        final slot = parse(
          'root = SlotBox([CardBox("hi"), EnumBox("active")])',
        );
        expect(slot.meta.errors, isEmpty);
        expect(slot.root!.props['children'], hasLength(2));
        final errors = errorsFor('root = ObjBox({ author: CardBox(9) })');
        expect(errors, hasLength(2));
        expect(
          errors.firstWhere((e) => e.component == 'CardBox').path,
          '/text',
        );
        expect(
          errors.firstWhere((e) => e.component == 'ObjBox').path,
          '/info/author',
        );
      },
    );

    test(
      'data in a component slot is a type-mismatch and is pruned, also through a reference',
      () {
        final inline = parse(
          'root = SlotBox([CardBox("hi"), { text: "a" }, "b", 3, [CardBox("x")]])',
        );
        expect(inline.root!.props['children'], hasLength(1));
        expect(
          [for (final e in inline.meta.errors) e.message],
          [
            'field "/children/1" expects CardBox but got plain object',
            'field "/children/2" expects CardBox but got string',
            'field "/children/3" expects CardBox but got number',
            'field "/children/4" expects CardBox but got array',
          ],
        );
        final viaRef = parse('root = SlotBox(items)\nitems = [{ text: "a" }]');
        expect(viaRef.root!.props['children'], isEmpty);
        expect(codePath(viaRef.meta.errors.first), 'type-mismatch:/children/0');
      },
    );

    test(r'a $ref to a non-component def is not a component slot', () {
      final tree = CompiledSchema.fromJsonSchema({
        'properties': {'Tree': <String, Object?>{}},
        r'$defs': {
          'Tree': {
            'properties': {
              'node': {r'$ref': r'#/$defs/__schema0'},
            },
            'required': ['node'],
          },
          '__schema0': {
            'type': 'object',
            'properties': {'label': string},
          },
        },
      });
      final r = parseProgram('root = Tree({ label: "a" })', tree);
      expect(r.meta.errors, isEmpty);
      expect(r.root!.props['node'], {'label': 'a'});
    });

    test(
      'skips dynamic values, composites, null or omitted args, and extra keys',
      () {
        expect(errorsFor(r'root = TagBox(["a", $x])'), isEmpty);
        expect(
          errorsFor('root = ObjBox({ author: "a", views: Sum([1, 2]) })'),
          isEmpty,
        );
        expect(errorsFor('root = AnyBox({ anything: true })'), isEmpty);
        expect(errorsFor('root = ObjBox(null)'), isEmpty);
        expect(errorsFor('root = ObjBox()'), isEmpty);
        expect(errorsFor('root = ObjBox({ author: "a", bonus: 99 })'), isEmpty);
        expect(errorsFor('root = ListBox([1, "a", true])'), isEmpty);
      },
    );

    test(
      'skips malformed or uncheckable schemas and applies the documented leaf edges',
      () {
        expect(directErrors(5, null), isEmpty);
        expect(directErrors(5, 'string'), isEmpty);
        expect(directErrors(5, {r'$ref': r'#/$defs/Thing'}), isEmpty);
        expect(
          directErrors(5, {
            'oneOf': [string],
          }),
          isEmpty,
        );
        expect(
          directErrors(
            [5],
            {
              'type': 'array',
              'items': [string],
            },
          ),
          isEmpty,
        );
        expect(directErrors('x', {'type': 'date'}), isEmpty);
        expect(
          directErrors(<String, Object?>{}, {
            'type': 'object',
            'required': 'author',
          }),
          isEmpty,
        );
        expect(
          directErrors(<String, Object?>{}, {
            'type': 'object',
            'required': ['a'],
          }).first.code,
          ValidationCode.missingRequired,
        );
        expect(directErrors(1.5, {'type': 'integer'}), isEmpty);
        expect(directErrors('3', {'type': 'integer'}), hasLength(1));
        expect(
          directErrors('loose', {'const': 'fixed'}).first.message,
          contains('one of ["fixed"]'),
        );
        expect(
          directErrors(
            {'a': 1},
            {
              'enum': ['active'],
            },
          ),
          isEmpty,
        );
      },
    );

    test(
      'defers required-key and enum checks while partial, then reports them on completion',
      () {
        final req = StreamParser(schema);
        expect(req.push('root = ObjBox({ views: 3 ').meta.errors, isEmpty);
        final missing = req.push('})\n').meta.errors.first;
        expect(
          [codePath(missing), missing.statementId],
          ['missing-required:/info/author', 'root'],
        );
        final en = StreamParser(schema);
        expect(en.push('root = EnumBox("bogus" ').meta.errors, isEmpty);
        expect(en.push(')\n').meta.errors.first.path, '/status');
      },
    );

    test(
      'keeps scalar type checks on mid-stream; only structure and enums defer',
      () {
        final res = StreamParser(
          schema,
        ).push('root = ObjBox({ author: "a", views: "lots" ');
        expect(res.meta.incomplete, isTrue);
        expect(
          res.meta.errors
              .firstWhere((e) => e.code == ValidationCode.typeMismatch)
              .path,
          '/info/views',
        );
        expect(
          directErrors(<String, Object?>{}, {
            'type': 'object',
            'required': ['a'],
          }, partial: true),
          isEmpty,
        );
        expect(
          directErrors('act', {
            'enum': ['active'],
          }, partial: true),
          isEmpty,
        );
        expect(directErrors(5, string, partial: true), hasLength(1));
      },
    );
  });
}
