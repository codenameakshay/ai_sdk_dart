import 'dart:async';
import 'dart:io';

import 'package:advanced_app/config.dart';
import 'package:advanced_app/pages/multimodal_page.dart';
import 'package:advanced_app/pages/stt_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final speech in [false, true]) {
    testWidgets(
      '${speech ? "transcription" : "multimodal"} closes its owned provider when removed',
      (tester) async {
        final client = _Client();
        await tester.runAsync(() async {
          final file = [
            File('docs/screenshots/adv_04_multimodal.png'),
            File('../../docs/screenshots/adv_04_multimodal.png'),
          ].firstWhere((file) => file.existsSync()).absolute;
          const picker = MethodChannel('plugins.flutter.io/image_picker');
          const recorder = MethodChannel('com.llfbandit.record/messages');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            (_) async => file.path,
          );
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
              return switch (call.method) {
                'hasPermission' => true,
                'stop' => file.path,
                _ => null,
              };
            },
          );
          try {
            await HttpOverrides.runZoned(() async {
              await tester.pumpWidget(
                MaterialApp(
                  home: speech ? const SttPage() : const MultimodalPage(),
                ),
              );
              await tester.pump();
              if (speech) {
                await tester.tap(find.text('Start Recording'));
                for (
                  var i = 0;
                  i < 50 && find.text('Stop & Transcribe').evaluate().isEmpty;
                  i++
                ) {
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                  await tester.pump();
                }
                await tester.tap(find.text('Stop & Transcribe'));
              } else {
                await tester.tap(find.text('Gallery'));
                for (
                  var i = 0;
                  i < 50 &&
                      tester
                              .widget<FilledButton>(
                                find.widgetWithText(FilledButton, 'Analyze'),
                              )
                              .onPressed ==
                          null;
                  i++
                ) {
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                  await tester.pump();
                }
                await tester.enterText(
                  find.byType(TextField),
                  'What is shown?',
                );
                await tester.tap(find.text('Analyze'));
              }
              for (var i = 0; i < 50 && client.requests.isEmpty; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                await tester.pump();
              }
              expect(client.requests, hasLength(1));
              await tester.pumpWidget(const SizedBox());
              await Future<void>.delayed(const Duration(milliseconds: 20));
              expect(client.closes, 1);
              expect(client.requests.single.aborted, isTrue);
            }, createHttpClient: (_) => client);
          } finally {
            client.close(force: true);
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              picker,
              null,
            );
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              recorder,
              null,
            );
          }
        });
        expect(tester.takeException(), isNull);
      },
      skip: openAiApiKey.isEmpty,
    );
  }
}

class _Client extends Fake implements HttpClient {
  final requests = <_Request>[];
  var closes = 0;
  @override
  set idleTimeout(Duration value) {}
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Duration? get connectionTimeout => null;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    final request = _Request();
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {
    closes++;
    for (final request in requests) {
      request.abort();
    }
  }
}

class _Request extends Fake implements HttpClientRequest {
  _Request() {
    _response.future.ignore();
  }

  final _response = Completer<HttpClientResponse>();
  var aborted = false;
  @override
  HttpHeaders get headers => _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  set maxRedirects(int value) {}
  @override
  set persistentConnection(bool value) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async =>
      await stream.drain<void>();
  @override
  Future<HttpClientResponse> close() => _response.future;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
    if (!_response.isCompleted) {
      _response.completeError(const SocketException('closed'));
    }
  }
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
