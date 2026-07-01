import 'package:ai_sdk_flutter_ui/src/theme/ai_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Wraps [child] so reduced motion is forced on via [MediaQuery].
Widget _reduced(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('AiHaptics', () {
    // Capture platform-channel method calls so we can both run the haptic code
    // path and assert whether a haptic was actually requested per platform.
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    bool hapticRequested() =>
        calls.any((c) => c.method == 'HapticFeedback.vibrate');

    testWidgets('light() and selection() fire on mobile platforms', (
      tester,
    ) async {
      // Reset the override before the test body ends so the binding's
      // debug-var invariant check passes.
      try {
        for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
          debugDefaultTargetPlatformOverride = platform;
          calls.clear();
          AiHaptics.light();
          await tester.pump();
          expect(hapticRequested(), isTrue, reason: 'light on $platform');

          calls.clear();
          AiHaptics.selection();
          await tester.pump();
          expect(hapticRequested(), isTrue, reason: 'selection on $platform');
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('is a no-op on desktop / non-haptic platforms', (tester) async {
      // Covers the fuchsia/linux/macOS/windows switch arms that return false.
      try {
        for (final platform in [
          TargetPlatform.fuchsia,
          TargetPlatform.linux,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        ]) {
          debugDefaultTargetPlatformOverride = platform;
          calls.clear();
          AiHaptics.light();
          AiHaptics.selection();
          await tester.pump();
          expect(hapticRequested(), isFalse, reason: 'no haptic on $platform');
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('PressableScale', () {
    // The pressable's scale Transform is the one that wraps the keyed child.
    const childKey = ValueKey('pressable-child');

    double currentScale(WidgetTester tester) {
      final transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byKey(childKey),
              matching: find.byType(Transform),
            )
            .first,
      );
      return transform.transform.getMaxScaleOnAxis();
    }

    testWidgets('wraps its child in a Listener + scale transform at rest', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PressableScale(
            child: ColoredBox(
              key: childKey,
              color: Color(0xFF000000),
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      // The animated path builds a Listener + a scale Transform around the
      // child; at rest the scale is 1.0.
      expect(
        find.descendant(
          of: find.byType(PressableScale),
          matching: find.byType(Listener),
        ),
        findsOneWidget,
      );
      expect(currentScale(tester), closeTo(1.0, 0.001));
    });

    testWidgets('collapses to a plain child under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _reduced(const PressableScale(child: Text('x'))),
      );
      // Under reduced motion there is no Listener / Transform — just the child.
      expect(
        find.descendant(
          of: find.byType(PressableScale),
          matching: find.byType(Listener),
        ),
        findsNothing,
      );
      expect(find.text('x'), findsOneWidget);
    });
  });

  group('AiEntrance', () {
    testWidgets('appears instantly (fully opaque) under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _reduced(
          const AiEntrance(child: Text('arrived')),
        ),
      );
      // didChangeDependencies sets the controller to its end value (1) without
      // ticking, so the child is already fully visible on the first frame.
      await tester.pump();

      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AiEntrance),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 1.0);
      expect(find.text('arrived'), findsOneWidget);
    });

    testWidgets('animates from transparent to opaque with motion enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AiEntrance(child: Text('arrived')),
        ),
      );

      Opacity opacity() => tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AiEntrance),
          matching: find.byType(Opacity),
        ),
      );

      // First frame of the forward animation: not yet fully opaque.
      await tester.pump();
      expect(opacity().opacity, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(opacity().opacity, 1.0);
    });
  });

  group('AiMotion.duration', () {
    testWidgets('collapses to zero under reduced motion', (tester) async {
      late Duration normal;
      late Duration collapsed;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              normal = AiMotion.duration(context, AiMotion.quick);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        _reduced(
          Builder(
            builder: (context) {
              collapsed = AiMotion.duration(context, AiMotion.quick);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(normal, AiMotion.quick);
      expect(collapsed, Duration.zero);
    });
  });
}
