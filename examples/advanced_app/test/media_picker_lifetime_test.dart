import 'dart:async';
import 'dart:io';

import 'package:advanced_app/config.dart';
import 'package:advanced_app/pages/multimodal_page.dart';
import 'package:advanced_app/pages/stt_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final granted in [false, true]) {
    testWidgets(
      'removed recording page ignores permission response $granted',
      (tester) async {
        final permission = Completer<bool>();
        var starts = 0;
        final asked = Completer<void>();
        final disposed = Completer<void>();
        const recorder = MethodChannel('com.llfbandit.record/messages');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          recorder,
          (call) async {
            if (call.method == 'create') {
              final id = (call.arguments as Map)['recorderId'];
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                MethodChannel('com.llfbandit.record/events/$id'),
                (_) async => null,
              );
            }
            if (call.method == 'hasPermission') {
              asked.complete();
              return permission.future;
            }
            if (call.method == 'start') {
              starts++;
            }
            if (call.method == 'dispose') {
              disposed.complete();
            }
            return null;
          },
        );
        try {
          await tester.pumpWidget(const MaterialApp(home: SttPage()));
          final button = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start Recording'),
          );
          final pending = (button.onPressed as dynamic)() as Future<void>;
          for (var i = 0; i < 50 && !asked.isCompleted; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(asked.isCompleted, isTrue);
          await tester.pumpWidget(const SizedBox());
          permission.complete(granted);
          Object? failure;
          var completed = false;
          pending.then<void>(
            (_) {
              completed = true;
            },
            onError: (Object error) {
              failure = error;
              completed = true;
            },
          );
          for (
            var i = 0;
            i < 50 && (!completed || !disposed.isCompleted);
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(completed, isTrue);
          expect(disposed.isCompleted, isTrue);
          expect(failure, isNull);
          expect(starts, 0);
          expect(tester.takeException(), isNull);
        } finally {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            recorder,
            null,
          );
        }
      },
      skip: openAiApiKey.isEmpty,
    );
  }

  for (final label in ['Gallery', 'Camera']) {
    testWidgets('removed multimodal page ignores a late $label image', (
      tester,
    ) async {
      final selected = Completer<String?>();
      final asked = Completer<void>();
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        _,
      ) {
        asked.complete();
        return selected.future;
      });
      try {
        await tester.runAsync(() async {
          await tester.pumpWidget(const MaterialApp(home: MultimodalPage()));
          final button = tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, label),
          );
          final pending = (button.onPressed as dynamic)() as Future<void>;
          for (var i = 0; i < 50 && !asked.isCompleted; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(asked.isCompleted, isTrue);
          await tester.pumpWidget(const SizedBox());
          final file = [
            File('docs/screenshots/adv_04_multimodal.png'),
            File('../../docs/screenshots/adv_04_multimodal.png'),
          ].firstWhere((file) => file.existsSync()).absolute;
          selected.complete(file.path);
          Object? failure;
          var completed = false;
          pending.then<void>(
            (_) {
              completed = true;
            },
            onError: (Object error) {
              failure = error;
              completed = true;
            },
          );
          for (var i = 0; i < 50 && !completed; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(completed, isTrue);
          expect(failure, isNull);
        });
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        );
      }
    });
  }
}
