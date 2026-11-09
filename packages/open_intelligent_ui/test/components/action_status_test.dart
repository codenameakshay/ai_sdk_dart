import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';

void main() {
  late List<ActionInvocation> calls;
  late Completer<ActionResult>? pending;

  setUp(() {
    calls = [];
    pending = null;
  });

  /// A library whose Pay action waits for the test to complete each call.
  OpenUiLibrary library({String? confirm, bool disable = false}) =>
      intelligentUi.extend(
        LibraryExtension(
          addActions: [
            ActionSpec(
              'Pay',
              description: 'Pays an order',
              params: {'orderId': S.string()},
              confirm: confirm,
              disableAfterSuccess: disable,
              handler: (invocation) {
                calls.add(invocation);
                return (pending = Completer<ActionResult>()).future;
              },
            ),
            ActionSpec('Ping', description: 'Pings', params: {}),
          ],
        ),
      );

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
  }

  Finder glyph(String name) =>
      find.byWidgetPredicate((w) => w is Glyph && w.name == name);

  testWidgets('a Button shows pending, then done, then stays disabled', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Button("Pay", @Pay("o-1"))])',
      library: library(disable: true),
    );
    await tapText(tester, 'Pay');
    expect(calls, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tapText(tester, 'Pay');
    expect(calls, hasLength(1));

    pending!.complete(const ActionSuccess());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(glyph('check'), findsOneWidget);

    await tapText(tester, 'Pay');
    expect(calls, hasLength(1));
  });

  testWidgets(
    'a failed Button shows the message and retries with the same key',
    (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Button("Pay", @Pay("o-1"))])',
        library: library(),
      );
      await tapText(tester, 'Pay');
      pending!.complete(const ActionFailure('Card declined'));
      await tester.pump();
      expect(find.text('Card declined'), findsOneWidget);

      await tapText(tester, 'Pay');
      expect(calls, hasLength(2));
      expect(calls[1].idempotencyKey, calls[0].idempotencyKey);
      expect(calls[0].idempotencyKey, endsWith('-1'));
    },
  );

  testWidgets('a failure without a message shows the fallback text', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Button("Pay", @Pay("o-1"))])',
      library: library(),
    );
    await tapText(tester, 'Pay');
    pending!.complete(const ActionFailure(''));
    await tester.pump();
    expect(find.text(const OpenUiLocalizations().actionFailed), findsOneWidget);
  });

  testWidgets('a confirm Button asks first, and Cancel hides the question', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Button("Pay", @Pay("o-1"))])',
      library: library(confirm: 'Pay this order?'),
    );
    await tapText(tester, 'Pay');
    expect(calls, isEmpty);
    expect(find.text('Pay this order?'), findsOneWidget);

    await tapText(tester, 'Cancel');
    expect(find.text('Pay this order?'), findsNothing);
    expect(calls, isEmpty);

    await tapText(tester, 'Pay');
    await tapText(tester, 'Confirm');
    expect(calls, hasLength(1));
  });

  testWidgets('a changed action resets an open confirmation', (tester) async {
    final lib = intelligentUi.extend(
      LibraryExtension(
        addActions: [
          ActionSpec(
            'Pay',
            description: 'Pays',
            params: {},
            confirm: 'Pay?',
            handler: (invocation) async {
              calls.add(invocation);
              return const ActionSuccess();
            },
          ),
          ActionSpec(
            'Delete',
            description: 'Deletes',
            params: {},
            confirm: 'Delete?',
            handler: (invocation) async {
              calls.add(invocation);
              return const ActionSuccess();
            },
          ),
        ],
      ),
    );
    final pumped = await pumpProgram(
      tester,
      'root = Col([Button("Do", @Pay())])',
      library: lib,
    );
    await tapText(tester, 'Do');
    expect(find.text('Pay?'), findsOneWidget);
    final staleConfirm = tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text('Confirm'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTap!;

    pumped.session.update(
      'root = Col([Button("Do", @Delete())])',
      streaming: false,
    );
    await tester.pump();
    staleConfirm();
    await tester.pump();
    expect(calls, isEmpty);

    expect(find.text('Delete?'), findsNothing);
    await tapText(tester, 'Do');
    await tapText(tester, 'Confirm');
    expect(calls.map((invocation) => invocation.name), ['Delete']);
  });

  testWidgets('IconButton and Pressable ignore taps while pending', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([IconButton("credit-card", @Pay("o-1"), "Pay"), '
      'Pressable([Text("Tile")], @Pay("o-2"))])',
      library: library(),
    );
    await tester.tap(find.byTooltip('Pay'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pay'));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tapText(tester, 'Tile');
    await tapText(tester, 'Tile');
    expect(calls, hasLength(2));
  });

  testWidgets('a pending Pressable is announced disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(
      tester,
      'root = Pressable([Text("Tile")], @Pay("o-1"))',
      library: library(),
    );
    await tapText(tester, 'Tile');

    expect(
      tester.getSemantics(find.text('Tile')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    handle.dispose();
  });

  testWidgets('a successful disabled Pressable is announced disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(
      tester,
      'root = Pressable([Text("Tile")], @Pay("o-1"))',
      library: library(disable: true),
    );
    await tapText(tester, 'Tile');
    pending!.complete(const ActionSuccess());
    await tester.pump();

    expect(
      tester.getSemantics(find.text('Tile')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    handle.dispose();
  });

  testWidgets('a failed IconButton shows the alert glyph', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([IconButton("credit-card", @Pay("o-1"), "Pay")])',
      library: library(),
    );
    await tester.tap(find.byTooltip('Pay'));
    await tester.pump();
    pending!.complete(const ActionFailure('Card declined'));
    await tester.pump();
    expect(glyph('circle-alert'), findsOneWidget);
  });

  testWidgets('an action without a handler still reaches the host', (
    tester,
  ) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([Button("Ping", @Ping())])',
      library: library(),
    );
    await tapText(tester, 'Ping');
    expect(calls, isEmpty);
    expect(pumped.events.single.type, 'Ping');
  });

  testWidgets('two Buttons with the same action and params share one key', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Button("Pay", @Pay("o-1")), Button("Pay again", @Pay("o-1"))])',
      library: library(),
    );
    await tapText(tester, 'Pay');
    pending!.complete(const ActionFailure('no'));
    await tester.pump();
    await tapText(tester, 'Pay again');
    expect(calls, hasLength(2));
    expect(calls[1].idempotencyKey, calls[0].idempotencyKey);
  });

  testWidgets('a finished action survives a restore', (tester) async {
    const program = 'root = Col([Button("Pay", @Pay("o-1"))])';
    final first = await pumpProgram(tester, program, library: library());
    await tapText(tester, 'Pay');
    pending!.complete(const ActionSuccess());
    await tester.pump();
    final saved = first.session.state;

    await pumpProgram(
      tester,
      program,
      library: library(disable: true),
      initialState: saved,
    );
    expect(glyph('check'), findsOneWidget);
    await tapText(tester, 'Pay');
    expect(calls, hasLength(1));
  });

  testWidgets('a write cut off by a restore shows checking until resolved', (
    tester,
  ) async {
    const program = 'root = Col([Button("Pay", @Pay("o-1"))])';
    final first = await pumpProgram(tester, program, library: library());
    await tapText(tester, 'Pay');
    final saved = first.session.state;

    final resolved = Completer<ActionResult>();
    final session = OpenUiSession(
      library(),
      initialState: saved,
      resolveAction: (_) => resolved.future,
    )..update(program, streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiView(session: session, builders: intelligentUiBuilders),
        ),
      ),
    );
    final text = const OpenUiLocalizations();
    expect(find.text(text.checkingAction), findsOneWidget);
    expect(find.text(text.actionFailed), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tapText(tester, 'Pay');
    expect(calls, hasLength(1));

    resolved.complete(const ActionSuccess());
    await tester.pump();
    expect(find.text(text.checkingAction), findsNothing);
    expect(glyph('check'), findsOneWidget);
  });
}
