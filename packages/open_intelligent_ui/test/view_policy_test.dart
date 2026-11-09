import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart' show ChatController;
import 'package:open_intelligent_ui/chat.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

final class _MoneyRow implements ComponentSpec {
  const _MoneyRow();
  @override
  String get typeName => 'MoneyRow';
  @override
  String get description => 'An amount with a label';
  @override
  Map<String, Schema> get props => {'label': S.string()};
}

final _withMoneyRow = intelligentUi.extend(
  const LibraryExtension(addComponents: [ComponentAddition(_MoneyRow())]),
);

const _nested =
    'root = Col([@Each(@Range(0, 10000), "i", @Each(@Range(0, 10000), "j", Text("x")))])';

Widget _moneyRow(BuildContext context, OpenUiNode node) =>
    Text('row ${node.props.string('label')}');

Future<void> _pump(
  WidgetTester tester,
  OpenUiSession session, {
  OpenUiBuilderLookup builders = openUiCoreBuilders,
  Widget? fallback,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: OpenUiView(
        session: session,
        builders: builders,
        fallback: fallback,
      ),
    ),
  ),
);

void main() {
  testWidgets('a component without a builder reports a render-error', (
    tester,
  ) async {
    final reports = <List<Map<String, Object?>>>[];
    final session = OpenUiSession(
      _withMoneyRow,
      onError: (errors) => reports.add([for (final e in errors) e.toJson()]),
    )..update('root = Col([Text("a"), MoneyRow("rent")])', streaming: false);
    addTearDown(session.dispose);

    await _pump(tester, session);
    await tester.pump();

    expect(find.text('a'), findsOneWidget);
    expect(reports.last, [
      {
        'source': 'runtime',
        'code': 'render-error',
        'message': 'Component MoneyRow render failed: no builder for MoneyRow',
        'component': 'MoneyRow',
      },
    ]);
  });

  testWidgets('a fail policy shows the fallback instead of the answer', (
    tester,
  ) async {
    final session = OpenUiSession(
      intelligentUi.extend(const LibraryExtension(removeComponents: ['Chart'])),
      policy: const ValidationPolicy(
        unknownComponents: UnknownComponentPolicy.fail,
      ),
    )..update('root = Col([Text("a"), Chart("bar", [1])])', streaming: false);
    addTearDown(session.dispose);

    await _pump(tester, session, fallback: const Text('unavailable'));

    expect(find.text('a'), findsNothing);
    expect(find.text('unavailable'), findsOneWidget);
  });

  testWidgets('the fallback stays hidden while the answer renders', (
    tester,
  ) async {
    final session = OpenUiSession(intelligentUi)
      ..update('root = Col([Text("a")])', streaming: false);
    addTearDown(session.dispose);

    await _pump(tester, session, fallback: const Text('unavailable'));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('unavailable'), findsNothing);
  });

  testWidgets('the fallback also replaces OpenUiContent', (tester) async {
    final session = OpenUiSession(
      intelligentUi,
      policy: const ValidationPolicy(maxNodes: 1),
    )..update('root = Col([Text("a")])', streaming: false);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: OpenUiView(
          session: session,
          builders: openUiCoreBuilders,
          fallback: const Text('unavailable'),
          child: const OpenUiContent(),
        ),
      ),
    );

    expect(find.text('unavailable'), findsOneWidget);
  });

  testWidgets('the node cap renders an error, not the expanded tree', (
    tester,
  ) async {
    final errors = <OpenUiError>[];
    final watch = Stopwatch()..start();
    final session = OpenUiSession(
      intelligentUi,
      policy: const ValidationPolicy(maxNodes: 24),
      onError: errors.addAll,
    )..update(_nested, streaming: false);
    addTearDown(session.dispose);

    await _pump(tester, session, fallback: const Text('too big'));

    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(find.text('x'), findsNothing);
    expect(find.text('too big'), findsOneWidget);
    expect(errors.single.code, OpenUiErrorCode.tooManyNodes);
  });

  group('intelligentUiFor with a host library', () {
    test('rejects a host component the lookup cannot build', () {
      expect(
        () => intelligentUiFor(openUiCoreBuilders, library: _withMoneyRow),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'has no builder for MoneyRow',
          ),
        ),
      );
    });

    test('OpenUiChat rejects a host component it cannot build', () {
      final controller = ChatController();
      addTearDown(controller.dispose);
      expect(
        () => OpenUiChat(
          controller: controller,
          send: (_) async {},
          library: _withMoneyRow,
          builders: openUiCoreBuilders,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'has no builder for MoneyRow',
          ),
        ),
      );
    });

    test('keeps host components and omits unbuildable built-ins', () {
      final library = intelligentUiFor(
        composeBuilders([
          {'MoneyRow': _moneyRow},
        ]),
        library: _withMoneyRow,
      );

      expect(library.components.containsKey('MoneyRow'), isTrue);
      expect(library.components.containsKey('Text'), isTrue);
      expect(library.components.containsKey('Map'), isFalse);
      expect(library.components.containsKey('MapMarker'), isFalse);
      expect(library.components.containsKey('Math'), isFalse);
    });

    test('returns the host library when every component can build', () {
      final library = intelligentUi.extend(
        const LibraryExtension(removeComponents: ['Map', 'MapMarker']),
      );
      OpenUiBuilder? lookup(String typeName) => _moneyRow;

      expect(
        identical(intelligentUiFor(lookup, library: library), library),
        isTrue,
      );
    });

    test('requires a builder for the host library root', () {
      expect(
        () => intelligentUiFor(
          (name) => name == 'Col' ? null : _moneyRow,
          library: _withMoneyRow,
        ),
        throwsArgumentError,
      );
    });
  });
}
