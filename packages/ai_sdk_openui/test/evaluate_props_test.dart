import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:ai_sdk_openui/src/runtime/errors.dart';
import 'package:ai_sdk_openui/src/runtime/evaluator.dart';
import 'package:test/test.dart';

final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'action': actionSchema.optional(),
  };
}

final _lib = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  functions: [
    FunctionSpec(
      'Boom',
      description: 'Throws',
      params: {'n': S.number()},
      fn: (_) => throw StateError('kaboom'),
    ),
  ],
);

EvaluationContext _ctx({
  Object? Function(String)? resolveRef,
  Map<String, Object?> state = const {},
}) {
  final boom =
      ((_lib.toJsonSchema()['functions'] as Map)['Boom'] as Map)['params']
          as Map;
  return EvaluationContext(
    getState: (n) => state[n],
    resolveRef: resolveRef ?? (_) => null,
    functions: {
      'Boom': RuntimeFunction(
        params: boom.cast(),
        fn: _lib.functions.single.fn,
      ),
    },
  );
}

ParseResult _parse(String src) =>
    parseProgram(src, _lib.compiled, rootName: 'Out');

bool _notReactive(String component, String prop) => false;

void main() {
  test(
    'a failing function prop reports it under the prop and leaves it null',
    () {
      final errors = <OpenUiError>[];
      final el = evaluateRoot(
        _parse('root = Out(@Boom(1))'),
        _ctx(),
        _notReactive,
        errors,
      )!;
      expect(el.props['value'], isNull);
      expect(errors.single.toJson(), {
        'source': 'runtime',
        'code': 'runtime-error',
        'message': 'Evaluating prop "value" on Out failed: @Boom threw: kaboom',
        'statementId': 'root',
        'component': 'Out',
        'hint': 'Check the expression used for prop "value"',
      });
    },
  );

  test('a prop that throws keeps the other props', () {
    final errors = <OpenUiError>[];
    final el = evaluateRoot(
      _parse('root = Out(q, @OpenUrl("https://a.b"))\nq = Query("t", {}, {})'),
      _ctx(resolveRef: (_) => throw StateError('ref broke')),
      _notReactive,
      errors,
    )!;
    expect(el.props['value'], isNull);
    final action = el.props['action'] as ActionPlan;
    expect(action.steps.single, isA<OpenUrlStep>());
    expect((action.steps.single as OpenUrlStep).url, 'https://a.b');
    expect(
      errors.single.message,
      'Evaluating prop "value" on Out failed: ref broke',
    );
  });

  test('a nested element reports its error under its own statement', () {
    final errors = <OpenUiError>[];
    final el = evaluateRoot(
      _parse('root = Out(inner)\ninner = Out(@Boom(1))'),
      _ctx(),
      _notReactive,
      errors,
    )!;
    final inner = el.props['value'] as ElementNode;
    expect(inner.props['value'], isNull);
    expect(errors.single.statementId, 'inner');
  });

  test('a root expression that is not a component reports no-root', () {
    final src = 'root = \$big ? Out(1) : 5\n\$big = false';
    final errors = <OpenUiError>[];
    final el = evaluateRoot(
      _parse(src),
      _ctx(state: {r'$big': false}),
      _notReactive,
      errors,
    );
    expect(el, isNull);
    expect(errors.single.toJson(), {
      'source': 'runtime',
      'code': 'no-root',
      'message': 'root does not evaluate to a component',
      'statementId': 'root',
    });
  });

  test('a root expression that picks a component evaluates it', () {
    final src = 'root = \$big ? Out(1) : 5\n\$big = false';
    final errors = <OpenUiError>[];
    final el = evaluateRoot(
      _parse(src),
      _ctx(state: {r'$big': true}),
      _notReactive,
      errors,
    );
    expect(el!.props['value'], 1);
    expect(errors, isEmpty);
  });

  test(
    'a nested object prop keeps its values with lists and elements evaluated',
    () {
      final el = evaluateRoot(
        _parse('root = Out({a: [1], b: inner})\ninner = Out(2)'),
        _ctx(),
        _notReactive,
        <OpenUiError>[],
      )!;
      final map = el.props['value'] as Map;
      expect(map['a'], [1]);
      expect((map['b'] as ElementNode).props['value'], 2);
    },
  );

  test('a program without a root gives no element and no errors', () {
    final errors = <OpenUiError>[];
    final el = evaluateRoot(_parse('x = 5'), _ctx(), _notReactive, errors);
    expect(el, isNull);
    expect(errors, isEmpty);
  });

  test('a binding strips to the current value of its state variable', () {
    expect(
      stripReactiveAssign(
        const ReactiveAssign(r'$x', StateRefNode(r'$value')),
        _ctx(state: {r'$x': 7}),
      ),
      7,
    );
    expect(stripReactiveAssign('a', _ctx()), 'a');
  });

  test(
    'a runtime element is spliced in as a value node that keeps identity',
    () {
      final el = ElementNode(
        typeName: 'Out',
        props: {},
        partial: false,
        hasDynamicProps: false,
      );
      final node = literalAst(el) as ValueNode;
      expect(identical(node.value, el), isTrue);
      expect(
        literalAst({
          'a': [1],
        }),
        isA<ObjNode>(),
      );
    },
  );
}
