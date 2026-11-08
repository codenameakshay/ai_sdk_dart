import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:ai_sdk_openui/src/lang/validation.dart';
import 'package:ai_sdk_openui/src/runtime/errors.dart';
import 'package:ai_sdk_openui/src/runtime/mcp.dart';
import 'package:test/test.dart';

void main() {
  test('toJson keeps the lang-core wire shape and toString is the message', () {
    const error = OpenUiError(
      source: OpenUiErrorSource.query,
      code: OpenUiErrorCode.toolError,
      message: 'm',
    );
    expect(error.toJson(), {
      'source': 'query',
      'code': 'tool-error',
      'message': 'm',
    });
    expect(error.toString(), 'm');
  });

  test('toJson marks a warning with severity', () {
    const error = OpenUiError(
      source: OpenUiErrorSource.parser,
      code: OpenUiErrorCode.noRoot,
      message: 'm',
      isWarning: true,
    );
    expect(error.toJson()['severity'], 'warning');
  });

  test('the codes carry the 15 lang-core wire strings in order', () {
    expect(OpenUiErrorCode.values.map((c) => c.wire), [
      'missing-required',
      'null-required',
      'unknown-component',
      'inline-reserved',
      'excess-args',
      'type-mismatch',
      'unknown-function',
      'no-root',
      'runtime-error',
      'render-error',
      'parse-exception',
      'parse-failed',
      'tool-not-found',
      'tool-error',
      'mcp-error',
    ]);
  });

  test('errorMessage gives the message of each kind of throwable', () {
    expect(errorMessage('boom'), 'boom');
    expect(errorMessage(Exception('down')), 'down');
    expect(errorMessage(StateError('kaboom')), 'kaboom');
    expect(errorMessage(ArgumentError('bad')), 'bad');
    expect(errorMessage(UnsupportedError('u')), 'u');
    expect(errorMessage(const FormatException('fmt')), 'fmt');
    expect(errorMessage(const McpToolError('x')), 'MCP tool error: x');
    expect(errorMessage(42), '42');
  });

  test(
    'enrichErrors lists the available components for an unknown component',
    () {
      final error = enrichErrors(
        const [
          ValidationError(
            code: ValidationCode.unknownComponent,
            component: 'Foo',
            path: '',
            message: 'Unknown component "Foo"',
            statementId: 'root',
          ),
        ],
        const {},
        const ['Card', 'Text'],
      ).single;
      expect(error.toJson(), {
        'source': 'parser',
        'code': 'unknown-component',
        'message': 'Unknown component "Foo"',
        'statementId': 'root',
        'component': 'Foo',
        'hint': 'Available components: Card, Text',
      });
    },
  );

  test('enrichErrors gives no hint for an unknown component without names', () {
    final error = enrichErrors(
      const [
        ValidationError(
          code: ValidationCode.unknownComponent,
          component: 'Foo',
          path: '',
          message: 'Unknown component "Foo"',
          statementId: 'root',
        ),
      ],
      const {},
      const [],
    ).single;
    expect(error.toJson().containsKey('hint'), isFalse);
  });

  test('enrichErrors gives the signature for a missing required prop', () {
    final schema = {
      r'$defs': {
        'Card': {
          'properties': {'title': {}, 'subtitle': {}},
          'required': ['title'],
        },
      },
    };
    final error = enrichErrors(
      const [
        ValidationError(
          code: ValidationCode.missingRequired,
          component: 'Card',
          path: '/title',
          message: 'Missing title',
        ),
      ],
      schema,
      const [],
    ).single;
    expect(error.hint, 'Signature: Card(title*, subtitle) — * marks required');
    expect(error.path, '/title');
  });

  test(
    'enrichErrors gives no hint for a null required prop without a definition',
    () {
      final error = enrichErrors(
        const [
          ValidationError(
            code: ValidationCode.nullRequired,
            component: 'Upper',
            path: '/s',
            message: 'Null s',
          ),
        ],
        {
          r'$defs': {
            'Card': {'properties': {}},
          },
        },
        const [],
      ).single;
      expect(error.hint, isNull);
    },
  );

  test(
    'enrichErrors tells the model to declare an inline reserved component',
    () {
      final error = enrichErrors(
        const [
          ValidationError(
            code: ValidationCode.inlineReserved,
            component: 'Query',
            path: '',
            message: 'Query inline',
          ),
        ],
        const {},
        const [],
      ).single;
      expect(
        error.hint,
        'Declare as a top-level statement: myVar = Query(...)',
      );
    },
  );

  test('enrichErrors keeps a no-root warning as a warning without a hint', () {
    final error = enrichErrors(
      const [
        ValidationError(
          code: ValidationCode.noRoot,
          component: '',
          path: '',
          message: 'No root',
          isWarning: true,
        ),
      ],
      const {},
      const ['Card'],
    ).single;
    expect(error.isWarning, isTrue);
    expect(error.hint, isNull);
  });

  test('enrichErrors reports an unknown component found by the parser', () {
    final json = <String, Object?>{
      'properties': {'Card': {}, 'Stack': {}},
      r'$defs': {
        'Card': {
          'properties': {
            'title': {'type': 'string'},
            'subtitle': {'type': 'string'},
          },
          'required': ['title'],
        },
        'Stack': {
          'properties': {
            'children': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/Card'},
            },
          },
        },
      },
    };
    final r = parseProgram(
      'root = Stack([Nope()])',
      CompiledSchema.fromJsonSchema(json),
      rootName: 'Stack',
    );
    final errors = enrichErrors(r.meta.errors, json, const ['Card', 'Stack']);
    expect(errors, hasLength(1));
    expect(errors.single.code, OpenUiErrorCode.unknownComponent);
    expect(errors.single.component, 'Nope');
    expect(errors.single.hint, 'Available components: Card, Stack');
  });
}
