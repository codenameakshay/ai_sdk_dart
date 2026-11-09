import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

final _withoutChart = intelligentUi.extend(
  const LibraryExtension(removeComponents: ['Chart']),
);

const _withChart = 'root = Col([Text("a"), Chart("bar", [1, 2])])';

const _nested =
    'root = Col([@Each(@Range(0, 10000), "i", @Each(@Range(0, 10000), "j", Text("x")))])';

OpenUiSession _settled(
  OpenUiLibrary library,
  String program, [
  ValidationPolicy policy = const ValidationPolicy(),
]) => OpenUiSession(library, policy: policy)..update(program, streaming: false);

List<String> _codes(OpenUiSession session) => [
  for (final e in session.errors) e.code.wire,
];

void main() {
  group('unknown components', () {
    test('are dropped by default and reported', () {
      final session = _settled(_withoutChart, _withChart);
      addTearDown(session.dispose);

      expect(session.root!.props.elements('children'), hasLength(1));
      expect(_codes(session), ['unknown-component']);
    });

    test('fail the whole answer under a fail policy', () {
      final session = _settled(
        _withoutChart,
        _withChart,
        const ValidationPolicy(unknownComponents: UnknownComponentPolicy.fail),
      );
      addTearDown(session.dispose);

      expect(session.root, isNull);
      expect(session.errors.single.code, OpenUiErrorCode.unknownComponent);
      expect(session.errors.single.isWarning, isFalse);
    });

    test('a fail policy keeps an answer without unknown components', () {
      final session = _settled(
        _withoutChart,
        'root = Col([Text("a")])',
        const ValidationPolicy(unknownComponents: UnknownComponentPolicy.fail),
      );
      addTearDown(session.dispose);

      expect(session.root!.typeName, 'Col');
      expect(session.errors, isEmpty);
    });
  });

  group('the node cap', () {
    test('stops @Each from expanding past it', () {
      const policy = ValidationPolicy(maxNodes: 24);
      expect(intelligentUi.validate(_nested, policy: policy).ok, isTrue);

      final watch = Stopwatch()..start();
      final session = _settled(intelligentUi, _nested, policy);
      addTearDown(session.dispose);

      expect(session.root, isNull);
      expect(session.errors.single.toJson(), {
        'source': 'runtime',
        'code': 'too-many-nodes',
        'message': 'The answer builds more than 24 components; the limit is 24',
        'statementId': 'root',
      });
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('stops nested @Each over plain values too', () {
      const program =
          'root = Col([Text(@Join(@Each(@Range(0, 10000), "i", @Each(@Range(0, 10000), "j", "x")), ""))])';
      final watch = Stopwatch()..start();
      final session = _settled(
        intelligentUi,
        program,
        const ValidationPolicy(maxNodes: 24),
      );
      addTearDown(session.dispose);

      expect(session.root, isNull);
      expect(session.errors.single.code, OpenUiErrorCode.tooManyNodes);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('counts written and expanded components together', () {
      const program =
          'root = Col([Text("a"), @Each(@Range(0, 3), "i", Text("x"))])';

      final fits = _settled(
        intelligentUi,
        program,
        const ValidationPolicy(maxNodes: 5),
      );
      addTearDown(fits.dispose);
      expect(fits.root!.props.elements('children'), hasLength(4));
      expect(fits.errors, isEmpty);

      final over = _settled(
        intelligentUi,
        program,
        const ValidationPolicy(maxNodes: 4),
      );
      addTearDown(over.dispose);
      expect(over.root, isNull);
      expect(_codes(over), ['too-many-nodes']);
    });

    test('counts components written without expressions', () {
      final session = _settled(
        intelligentUi,
        'root = Col([Text("a"), Text("b")])',
        const ValidationPolicy(maxNodes: 2),
      );
      addTearDown(session.dispose);

      expect(session.root, isNull);
      expect(_codes(session), ['too-many-nodes']);
    });

    test('does not count data objects as components', () {
      final session = _settled(
        intelligentUi,
        'root = Col([Chart("bar", [{m: "a", v: 1}, {m: "b", v: 2}])])',
        const ValidationPolicy(maxNodes: 2),
      );
      addTearDown(session.dispose);

      expect(session.root!.props.elements('children').single.typeName, 'Chart');
      expect(session.errors, isEmpty);
    });

    test('evaluates again once the answer fits', () {
      final session = _settled(
        intelligentUi,
        _nested,
        const ValidationPolicy(maxNodes: 24),
      )..update('root = Col([Text("a")])', streaming: false);
      addTearDown(session.dispose);

      expect(session.root!.typeName, 'Col');
      expect(session.errors, isEmpty);
    });
  });
}
