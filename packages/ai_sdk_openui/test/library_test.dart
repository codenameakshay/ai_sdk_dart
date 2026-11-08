import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props, [this.description = '']);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  final String description;
}

final _missing = {'body': S.ref('Missing')};

final _card = _Spec('Card', {
  'title': S.string(),
  'count': S.number().optional(),
}, 'A card');

OpenUiLibrary _library({
  List<FunctionSpec> functions = const [],
  List<ActionSpec> actions = const [],
}) => OpenUiLibrary(
  root: _card,
  components: [_card],
  functions: functions,
  actions: actions,
);

FunctionSpec _fn(String name, [Map<String, Schema>? params]) => FunctionSpec(
  name,
  description: 'd',
  params: params ?? {'n': S.number()},
  fn: (a) => a['n'],
);

void main() {
  group('a library rejects names that cannot work', () {
    test('a root outside the component list', () {
      expect(
        () => OpenUiLibrary(root: const _Spec('Page', {}), components: [_card]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Root component "Page" is not in components.',
          ),
        ),
      );
    });

    test('a function named like a built-in', () {
      expect(
        () => _library(functions: [_fn('Count')]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '"Count" collides with a built-in, component, function or action.',
          ),
        ),
      );
    });

    test('a function named like a component', () {
      expect(
        () => _library(functions: [_fn('Card')]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '"Card" collides with a built-in, component, function or action.',
          ),
        ),
      );
    });

    test('an action named like a function', () {
      expect(
        () => _library(
          functions: [_fn('Copy')],
          actions: [ActionSpec('Copy', description: 'd', params: {})],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '"Copy" collides with a built-in, component, function or action.',
          ),
        ),
      );
    });

    test('a function named like Query', () {
      expect(
        () => _library(functions: [_fn('Query')]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the JSON schema rejects references that cannot resolve', () {
    test('a prop that references a missing component', () {
      final lib = OpenUiLibrary(
        root: _Spec('Page', _missing),
        components: [_Spec('Page', _missing)],
      );
      expect(
        lib.toJsonSchema,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'No component "Missing" to reference.',
          ),
        ),
      );
    });

    test('a function param that references a component', () {
      final lib = _library(
        functions: [
          _fn('Show', {'card': S.ref('Card')}),
        ],
      );
      expect(
        lib.toJsonSchema,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Call schemas cannot reference "Card".',
          ),
        ),
      );
    });
  });

  group('parse reports what a server needs', () {
    final lib = _library();

    test('a clean program', () {
      final report = lib.parse('root = Card("hi", 2)');
      expect(report.isClean, isTrue);
      expect(report.hasRoot, isTrue);
      expect(report.errors, isEmpty);
      expect(report.warnings, isEmpty);
      expect(report.unresolved, isEmpty);
      expect(report.orphaned, isEmpty);
    });

    test('a missing root statement falls back with a warning', () {
      final report = lib.parse('page = Card("hi")');
      expect(report.hasRoot, isTrue);
      expect(report.errors, isEmpty);
      expect(report.warnings, [
        'No root statement. Rendering the first statement that calls the root component Card',
      ]);
      expect(report.isClean, isFalse);
    });

    test('an unreferenced statement is orphaned', () {
      final report = lib.parse('root = Card("hi")\nextra = Card("x")');
      expect(report.orphaned, ['extra']);
      expect(report.isClean, isFalse);
    });

    test('no program at all has no root', () {
      final report = lib.parse('');
      expect(report.hasRoot, isFalse);
      expect(report.isClean, isFalse);
    });
  });
}
