import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat/pages/chat_page.dart';
import 'package:flutter_chat/pages/completion_page.dart';
import 'package:flutter_chat/pages/object_stream_page.dart';

void main() {
  for (final page in <String, Widget>{
    'chat': const ChatPage(),
    'completion': const CompletionPage(),
    'object': const ObjectStreamPage(),
  }.entries) {
    testWidgets(
      '${page.key} closes its owned provider when removed during a request',
      (tester) async {
        final client = _Client();
        await tester.runAsync(() async {
          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(MaterialApp(home: page.value));
            if (page.key == 'chat') {
              await tester.enterText(
                find.byKey(const ValueKey('chat-composer-field')),
                'hello',
              );
              await tester.tap(
                find.byKey(const ValueKey('chat-composer-send')),
              );
            } else {
              if (page.key == 'completion') {
                await tester.enterText(find.byType(TextField).first, 'hello');
              }
              await tester.tap(find.text('Generate'));
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
        });
        client.close(force: true);
        expect(tester.takeException(), isNull);
      },
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
