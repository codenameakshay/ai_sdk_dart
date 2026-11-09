import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/components/controls.dart'
    show IuiButton;

const _program =
    'root = Col([@Each(\$debts, "d", Button("Settle", @Settle(d.id)))])';

void main() {
  late List<ActionInvocation> calls;

  setUp(() => calls = []);

  OpenUiLibrary library() => intelligentUi.extend(
    LibraryExtension(
      addActions: [
        ActionSpec(
          'Settle',
          description: 'Settles a debt',
          params: {'id': S.string()},
          disableAfterSuccess: true,
          handler: (invocation) async {
            calls.add(invocation);
            return const ActionSuccess();
          },
        ),
      ],
    ),
  );

  Future<OpenUiSession> pump(
    WidgetTester tester,
    List<String> ids, {
    String scope = 'message-1',
    Map<String, Object?> initialState = const {},
  }) async {
    final session = OpenUiSession(
      library(),
      records: [
        BoundRecord('debts', [
          for (final id in ids) {'id': id},
        ]),
      ],
      initialState: initialState,
      actionScope: scope,
    )..update(_program, streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiView(
            key: UniqueKey(),
            session: session,
            builders: intelligentUiBuilders,
          ),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  Finder settle(int index) => find.text('Settle').at(index);

  bool enabled(WidgetTester tester, int index) =>
      tester
          .widgetList<IuiButton>(find.byType(IuiButton))
          .elementAt(index)
          .onTap !=
      null;

  testWidgets('a settled item stays settled when the list around it grows', (
    tester,
  ) async {
    final first = await pump(tester, ['d1', 'd2']);
    await tester.tap(settle(0));
    await tester.pumpAndSettle();
    expect(calls.single.params, {'id': 'd1'});
    final key = calls.single.idempotencyKey;

    await pump(tester, ['d0', 'd1', 'd2'], initialState: first.state);
    expect(
      [for (var i = 0; i < 3; i++) enabled(tester, i)],
      [true, false, true],
    );
    await tester.tap(settle(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.idempotencyKey, key);
  });

  testWidgets('two items in one list get different keys', (tester) async {
    await pump(tester, ['d1', 'd2']);
    await tester.tap(settle(0));
    await tester.tap(settle(1));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.params['id']), ['d1', 'd2']);
    expect(calls[0].idempotencyKey, isNot(calls[1].idempotencyKey));
  });

  testWidgets('the same item in two messages gets different keys', (
    tester,
  ) async {
    await pump(tester, ['d1'], scope: 'message-1');
    await tester.tap(settle(0));
    await tester.pumpAndSettle();
    await pump(tester, ['d1'], scope: 'message-2');
    await tester.tap(settle(0));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls[0].idempotencyKey, isNot(calls[1].idempotencyKey));
  });
}
