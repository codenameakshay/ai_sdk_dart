import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/src/components/flex_row.dart';

const _a = Key('a');
const _b = Key('b');

Widget _box(Key key, double width, double height) =>
    SizedBox(key: key, width: width, height: height);

/// A square that fills whatever width it is given, so its height follows it.
Widget _square(Key key, double width) =>
    SizedBox(key: key, width: width, child: const AspectRatio(aspectRatio: 1));

Future<void> _pump(WidgetTester tester, FlexRow row, {double width = 400}) =>
    tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: row),
      ),
    );

RenderFlexRow _render(WidgetTester tester) =>
    tester.renderObject<RenderFlexRow>(find.byType(FlexRow));

Offset _at(WidgetTester tester, Key key) => tester.getTopLeft(find.byKey(key));

void main() {
  testWidgets('percentage flex basis keeps natural width in an unbounded row', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: FlexRow(
            children: [
              FlexRowItem(grow: 1, zeroBasis: true, child: _box(_a, 120, 20)),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(_a)), const Size(120, 20));
  });

  group('FlexRowItem', () {
    testWidgets('outside a FlexRow it reports FlexRow as the expected parent', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(children: [FlexRowItem(child: _box(_a, 10, 10))]),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('FlexRow'));
    });
  });

  group('FlexRow updates', () {
    testWidgets('a new gap moves the later children', (tester) async {
      await _pump(
        tester,
        FlexRow(children: [_box(_a, 100, 20), _box(_b, 50, 20)]),
      );
      expect(_at(tester, _b).dx, 100);
      await _pump(
        tester,
        FlexRow(gap: 10, children: [_box(_a, 100, 20), _box(_b, 50, 20)]),
      );
      expect(_at(tester, _b).dx, 110);
    });

    testWidgets('a new justify spreads the free space', (tester) async {
      await _pump(
        tester,
        FlexRow(children: [_box(_a, 100, 20), _box(_b, 50, 20)]),
      );
      expect(_at(tester, _a).dx, 0);
      await _pump(
        tester,
        FlexRow(
          justify: FlexJustify.center,
          children: [_box(_a, 100, 20), _box(_b, 50, 20)],
        ),
      );
      expect(_at(tester, _a).dx, 125);
      await _pump(
        tester,
        FlexRow(
          justify: FlexJustify.between,
          children: [_box(_a, 100, 20), _box(_b, 50, 20)],
        ),
      );
      expect(_at(tester, _b).dx, 350);
    });

    testWidgets('a new align moves children vertically', (tester) async {
      await _pump(
        tester,
        FlexRow(children: [_box(_a, 100, 20), _box(_b, 50, 40)]),
      );
      expect(_at(tester, _a).dy, 10);
      await _pump(
        tester,
        FlexRow(
          align: FlexAlign.end,
          children: [_box(_a, 100, 20), _box(_b, 50, 40)],
        ),
      );
      expect(_at(tester, _a).dy, 20);
      await _pump(
        tester,
        FlexRow(
          align: FlexAlign.start,
          children: [_box(_a, 100, 20), _box(_b, 50, 40)],
        ),
      );
      expect(_at(tester, _a).dy, 0);
    });
  });

  group('FlexRow measuring', () {
    testWidgets('the intrinsic width is the children and gaps added up', (
      tester,
    ) async {
      await _pump(
        tester,
        FlexRow(gap: 10, children: [_box(_a, 100, 20), _box(_b, 50, 40)]),
      );
      final row = _render(tester);
      expect(row.getMinIntrinsicWidth(double.infinity), 0);
      expect(row.getMaxIntrinsicWidth(double.infinity), 160);
    });

    testWidgets('the intrinsic height is the tallest child', (tester) async {
      await _pump(
        tester,
        FlexRow(children: [_box(_a, 100, 20), _box(_b, 50, 40)]),
      );
      final row = _render(tester);
      expect(row.getMinIntrinsicHeight(400), 40);
      expect(row.getMaxIntrinsicHeight(400), 40);
    });

    testWidgets('an IntrinsicWidth parent sizes the row to its children', (
      tester,
    ) async {
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: IntrinsicWidth(
            child: FlexRow(
              gap: 10,
              children: [_box(_a, 100, 20), _box(_b, 50, 40)],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(FlexRow)), const Size(160, 40));
    });

    testWidgets('a dry layout fills the width and takes the tallest child', (
      tester,
    ) async {
      await _pump(
        tester,
        FlexRow(gap: 10, children: [_box(_a, 100, 20), _box(_b, 50, 40)]),
      );
      expect(
        _render(tester).getDryLayout(const BoxConstraints(maxWidth: 300)),
        const Size(300, 40),
      );
    });

    testWidgets('a dry layout shrinks children that do not fit', (
      tester,
    ) async {
      await _pump(
        tester,
        FlexRow(gap: 10, children: [_square(_a, 100), _square(_b, 50)]),
      );
      // 160 wanted in 100: overflow 60 is shared by width, so 60 and 30 wide.
      expect(
        _render(tester).getDryLayout(const BoxConstraints(maxWidth: 100)),
        const Size(100, 60),
      );
      await _pump(
        tester,
        FlexRow(gap: 10, children: [_square(_a, 100), _square(_b, 50)]),
        width: 100,
      );
      expect(tester.getSize(find.byKey(_a)), const Size(60, 60));
      expect(tester.getSize(find.byKey(_b)), const Size(30, 30));
    });

    testWidgets(
      'a dry layout without a width limit is as wide as its children',
      (tester) async {
        await _pump(
          tester,
          FlexRow(gap: 10, children: [_box(_a, 100, 20), _box(_b, 50, 40)]),
        );
        expect(
          _render(tester).getDryLayout(const BoxConstraints()),
          const Size(160, 40),
        );
      },
    );

    testWidgets('a dry layout gives a fixed child its share of the width', (
      tester,
    ) async {
      await _pump(
        tester,
        FlexRow(
          children: [
            FlexRowItem(fixed: (w) => w / 2, child: _square(_a, 10)),
            FlexRowItem(spacer: true, child: const SizedBox.shrink()),
          ],
        ),
      );
      expect(
        _render(tester).getDryLayout(const BoxConstraints(maxWidth: 200)),
        const Size(200, 100),
      );
      expect(tester.getSize(find.byKey(_a)), const Size(200, 200));
    });
  });
}
