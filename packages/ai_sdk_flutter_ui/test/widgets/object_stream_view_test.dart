import 'dart:async';

import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ObjectStreamView', () {
    testWidgets('shows a progress indicator while loading, then the value', (
      tester,
    ) async {
      final source = StreamController<Map<String, dynamic>>();
      final controller = ObjectStreamController<Map<String, dynamic>>();
      addTearDown(() {
        controller.dispose();
        source.close();
      });

      await tester.pumpWidget(
        _wrap(ObjectStreamView<Map<String, dynamic>>(controller: controller)),
      );

      unawaited(controller.bind(source.stream));
      await tester.pump(); // isLoading flips true on a microtask
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      source.add({'title': 'Hello'});
      await tester.pump();
      expect(find.textContaining('"title": "Hello"'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders the value through a custom builder when provided', (
      tester,
    ) async {
      final source = StreamController<Map<String, dynamic>>();
      final controller = ObjectStreamController<Map<String, dynamic>>();
      addTearDown(() {
        controller.dispose();
        source.close();
      });

      await tester.pumpWidget(
        _wrap(
          ObjectStreamView<Map<String, dynamic>>(
            controller: controller,
            builder: (context, value, isStreaming) =>
                Text('built:${value['title']}'),
          ),
        ),
      );

      unawaited(controller.bind(source.stream));
      await tester.pump();
      source.add({'title': 'Hi'});
      await tester.pump();

      expect(find.text('built:Hi'), findsOneWidget);
    });

    testWidgets('surfaces a stream error', (tester) async {
      final source = StreamController<Map<String, dynamic>>();
      final controller = ObjectStreamController<Map<String, dynamic>>();
      addTearDown(() {
        controller.dispose();
        source.close();
      });

      await tester.pumpWidget(
        _wrap(ObjectStreamView<Map<String, dynamic>>(controller: controller)),
      );

      unawaited(controller.bind(source.stream));
      await tester.pump();
      source.addError(StateError('stream broke'));
      await tester.pump();

      expect(find.textContaining('stream broke'), findsOneWidget);
    });

    testWidgets('falls back to toString for a non-JSON value', (tester) async {
      final source = StreamController<Object>();
      final controller = ObjectStreamController<Object>();
      addTearDown(() {
        controller.dispose();
        source.close();
      });

      await tester.pumpWidget(
        _wrap(ObjectStreamView<Object>(controller: controller)),
      );

      unawaited(controller.bind(source.stream));
      await tester.pump();
      source.add(_Unencodable());
      await tester.pump();

      expect(find.textContaining('UNENCODABLE'), findsOneWidget);
    });
  });
}

class _Unencodable {
  @override
  String toString() => 'UNENCODABLE';
}
