import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:advanced_app/config.dart';
import 'package:advanced_app/pages/conversation_page.dart';
import 'package:advanced_app/pages/completion_page.dart';
import 'package:advanced_app/pages/embeddings_page.dart';
import 'package:advanced_app/pages/object_stream_page.dart';
import 'package:advanced_app/pages/image_gen_page.dart';
import 'package:advanced_app/pages/provider_chat_page.dart';
import 'package:advanced_app/pages/tts_page.dart';
import 'package:advanced_app/pages/responses_page.dart';
import 'package:advanced_app/pages/tools_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final page in <String, Widget>{
    'tools chat': const ToolsChatPage(),
    'conversation': const ConversationPage(),
    'embeddings': const EmbeddingsPage(),
    'object stream': const ObjectStreamPage(),
    'responses': const ResponsesPage(),
    'provider chat': const ProviderChatPage(),
    'completion': const CompletionPage(),
    'image generation': const ImageGenPage(),
    'text to speech': const TtsPage(),
  }.entries) {
    testWidgets(
      '${page.key} closes its provider connection when removed',
      (tester) async {
        if (page.key == 'text to speech') {
          final channels = <String>{
            'xyz.luan/audioplayers.global',
            'xyz.luan/audioplayers.global/events',
            'xyz.luan/audioplayers',
          };
          final messenger = tester.binding.defaultBinaryMessenger;
          Future<void> mock(String name) async {
            messenger.setMockMethodCallHandler(MethodChannel(name), (
              call,
            ) async {
              if (call.method == 'create') {
                final events =
                    'xyz.luan/audioplayers/events/${call.arguments['playerId']}';
                channels.add(events);
                await mock(events);
              }
              return null;
            });
          }

          for (final name in channels.toList()) {
            await mock(name);
          }
          addTearDown(() {
            for (final name in channels) {
              messenger.setMockMethodCallHandler(MethodChannel(name), null);
            }
          });
        }
        await _withHttpClient(tester, page.value, (client) async {
          final send = find.byKey(const ValueKey('chat-composer-send'));
          if (send.evaluate().isNotEmpty) {
            await tester.enterText(
              find.byKey(const ValueKey('chat-composer-field')),
              'Hello',
            );
            await tester.tap(send);
          } else {
            if (page.key == 'completion' || page.key == 'image generation') {
              await tester.enterText(find.byType(TextField).first, 'Hello');
            }
            await tester.tap(
              find.text(switch (page.key) {
                'embeddings' => 'Compare',
                'object stream' || 'image generation' => 'Generate',
                'completion' => 'Generate',
                'text to speech' => 'Speak',
                _ => 'Ask',
              }),
            );
          }
          await _waitForRequest(tester, client);
          expect(client.requests, hasLength(1));
          await tester.pumpWidget(const SizedBox());
          expect(client.closed, isTrue);
          await Future<void>.delayed(Duration.zero);
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      },
      skip:
          openAiApiKey.isEmpty &&
          {
            'embeddings',
            'responses',
            'completion',
            'image generation',
            'text to speech',
          }.contains(page.key),
    );
  }

  for (final action in ['Compare', 'Run batch embed']) {
    testWidgets(
      'embeddings keeps the provider fixed during $action',
      (tester) async {
        await _withHttpClient(tester, const EmbeddingsPage(), (client) async {
          await tester.ensureVisible(find.text(action));
          await tester.tap(find.text(action));
          await _waitForRequest(tester, client);
          expect(client.requests, isNotEmpty);
          final selector = tester.widget<SegmentedButton<String>>(
            find.byType(SegmentedButton<String>),
          );
          expect(selector.onSelectionChanged, isNull);
        });
      },
      skip: openAiApiKey.isEmpty,
    );
  }

  testWidgets(
    'embeddings starts one comparison for repeated submit',
    (tester) async {
      await _withHttpClient(tester, const EmbeddingsPage(), (client) async {
        final submit = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Compare'))
            .onPressed!;
        submit();
        submit();
        await _waitForRequest(tester, client);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(client.requests, hasLength(1));
        expect(jsonDecode(client.requests.single.body)['input'], [
          'A cat sits on a mat.',
        ]);
      });
    },
    skip: openAiApiKey.isEmpty,
  );

  for (final provider in ['OpenAI', 'Anthropic', 'Google']) {
    testWidgets(
      'responses sends supported reasoning settings for $provider',
      (tester) async {
        await _withHttpClient(tester, const ResponsesPage(), (client) async {
          await tester.tap(find.text(provider));
          await tester.tap(find.text('Ask'));
          await _waitForRequest(tester, client);
          expect(client.requests, hasLength(1));
          final request = client.requests.single;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          switch (provider) {
            case 'OpenAI':
              expect(body['model'], 'gpt-6-luna');
              expect(body['reasoning'], {'effort': 'medium'});
            case 'Anthropic':
              expect(body['model'], 'claude-fable-5-1');
              expect(body['thinking'], {'type': 'adaptive'});
              expect(body['output_config'], {'effort': 'medium'});
            case 'Google':
              expect(request.uri.path, contains('models/gemini-3.8-flash:'));
              expect(body['generationConfig']['thinkingConfig'], {
                'thinkingLevel': 'medium',
              });
          }
        });
      },
      skip: switch (provider) {
        'OpenAI' => openAiApiKey.isEmpty,
        'Anthropic' => anthropicApiKey.isEmpty,
        _ => googleApiKey.isEmpty,
      },
    );
  }
}

Future<void> _withHttpClient(
  WidgetTester tester,
  Widget page,
  Future<void> Function(_PendingHttpClient) run,
) async {
  final client = _PendingHttpClient();
  await tester.runAsync(() async {
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(MaterialApp(home: page));
      try {
        await run(client);
      } finally {
        await tester.pumpWidget(const SizedBox());
        client.close(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }, createHttpClient: (_) => client);
  });
}

Future<void> _waitForRequest(
  WidgetTester tester,
  _PendingHttpClient client,
) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
    if (client.requests.isNotEmpty && client.requests.last.body.isNotEmpty) {
      return;
    }
  }
}

class _PendingHttpClient extends Fake implements HttpClient {
  final requests = <_PendingRequest>[];
  bool closed = false;

  @override
  set idleTimeout(Duration value) {}
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Duration? get connectionTimeout => null;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    final request = _PendingRequest(uri);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    for (final request in requests) {
      request.abort();
    }
  }
}

class _PendingRequest extends Fake implements HttpClientRequest {
  _PendingRequest(this.uri);
  @override
  final Uri uri;
  String body = '';
  final _response = Completer<HttpClientResponse>();

  @override
  HttpHeaders get headers => _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  set maxRedirects(int value) {}
  @override
  set persistentConnection(bool value) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    body = utf8.decode(await stream.expand((chunk) => chunk).toList());
  }

  @override
  Future<HttpClientResponse> close() => _response.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    if (!_response.isCompleted) {
      _response.completeError(const SocketException('Closed'));
    }
  }
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
