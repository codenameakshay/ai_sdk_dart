import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/src/components/play.dart' show Flashcard;

import '../support/pump.dart';

void main() {
  testWidgets(
    'flashcard faces mount once and retain their state across flips',
    (tester) async {
      final mounts = [0, 0];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Flashcard(
              front: _CounterFace(onMount: () => mounts[0]++),
              back: _CounterFace(onMount: () => mounts[1]++),
              hint: 'Flip',
            ),
          ),
        ),
      );
      expect(mounts, [1, 1]);
      await tester.tap(find.text('Count 0'));
      await tester.pump();
      expect(find.text('Count 1'), findsOneWidget);
      await tester.tapAt(
        tester.getTopLeft(find.byType(Flashcard)) + const Offset(10, 10),
      );
      await tester.pumpAndSettle();
      expect(find.text('Count 0'), findsOneWidget);
      await tester.tapAt(
        tester.getTopLeft(find.byType(Flashcard)) + const Offset(10, 10),
      );
      await tester.pumpAndSettle();
      expect(find.text('Count 1'), findsOneWidget);
      expect(mounts, [1, 1]);
    },
  );

  testWidgets('a flashcard keeps the taller face height on both sides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answer = List.filled(12, 'a long answer').join(' ');
    await pumpProgram(tester, 'root = Col([Flashcard("Hi", "$answer")])');
    final front = tester.getSize(find.byType(Flashcard)).height;
    expect(front, greaterThan(168));
    final frontFace = find
        .ancestor(of: find.text('Hi'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(frontFace).height, front);

    await tester.tap(find.byType(Flashcard));
    await tester.pumpAndSettle();
    expect(find.text('Hi'), findsNothing);
    expect(tester.getSize(find.byType(Flashcard)).height, front);
  });
}

class _CounterFace extends StatefulWidget {
  const _CounterFace({required this.onMount});
  final VoidCallback onMount;

  @override
  State<_CounterFace> createState() => _CounterFaceState();
}

class _CounterFaceState extends State<_CounterFace> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _count++),
    child: Text('Count $_count'),
  );
}
