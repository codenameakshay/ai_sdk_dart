import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test('pre-cancelled Responses skips auth (stream=$streaming)', () async {
      var authCalls = 0;
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final model = OpenAIResponsesLanguageModel(
        modelId: 'gpt-5',
        client: dio,
        headers: () async {
          authCalls++;
          return const {};
        },
        baseUrl: 'http://responses.test',
      );
      final signal = _Signal()..cancel();
      final options = _options(abortSignal: signal);
      await expectLater(
        streaming ? model.doStream(options) : model.doGenerate(options),
        throwsA(isA<AiOperationCancelledError>()),
      );
      expect(authCalls, 0);
    });
  }

  test(
    'consumer cancellation cancels the underlying response stream',
    () async {
      final source = StreamController<Uint8List>();
      final cancelled = Completer<void>();
      source.onCancel = () {
        if (!cancelled.isCompleted) cancelled.complete();
      };
      final dio = Dio()
        ..httpClientAdapter = _StreamAdapter(() {
          return ResponseBody(
            source.stream,
            HttpStatus.ok,
            headers: {
              'content-type': ['text/event-stream'],
            },
          );
        });
      final model = OpenAIResponsesLanguageModel(
        modelId: 'gpt-5',
        client: dio,
        headers: () async => const {},
        baseUrl: 'http://responses.test',
      );
      final result = await model.doStream(_options());
      final firstEvent = Completer<void>();
      final subscription = result.stream.listen((part) {
        if (part is StreamPartTextDelta && !firstEvent.isCompleted) {
          firstEvent.complete();
        }
      });
      source.add(
        Uint8List.fromList(
          'data: {"type":"response.output_text.delta",'
                  '"delta":"hello","item_id":"text-1"}\n\n'
              .codeUnits,
        ),
      );
      await firstEvent.future;
      await subscription.cancel();
      await cancelled.future.timeout(const Duration(seconds: 1));
    },
  );

  test('caller cancellation aborts Responses startup', () async {
    final server = await _RawSocketServer.start();
    addTearDown(server.close);

    final signal = _Signal();
    final future = _model(
      server.endpoint,
    ).doStream(_options(abortSignal: signal));
    await server.requestReceived.future;
    signal.cancel();
    await expectLater(future, throwsA(anything));
    await server.peerClosed.future;
  });

  test('caller cancellation closes an active Responses SSE socket', () async {
    final server = await _RawSocketServer.start(sendSseHeaders: true);
    addTearDown(server.close);
    final signal = _Signal();
    final result = await _model(
      server.endpoint,
    ).doStream(_options(abortSignal: signal));
    final firstEvent = Completer<void>();
    final subscription = result.stream.listen((part) {
      if (part is StreamPartTextDelta && !firstEvent.isCompleted) {
        firstEvent.complete();
      }
    });
    await firstEvent.future;
    signal.cancel();
    await server.peerClosed.future;
    await subscription.cancel();
  });

  test(
    'cancellation races stalled headers without dispatching generate',
    () async {
      final auth = Completer<Map<String, String>>();
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = _ResponseAdapter(() {
          requests++;
          return ResponseBody.fromString('{}', HttpStatus.ok);
        });
      final model = OpenAIResponsesLanguageModel(
        modelId: 'gpt-5',
        client: dio,
        headers: () => auth.future,
        baseUrl: 'http://responses.test',
      );
      final signal = _Signal();
      final pending = model.doGenerate(_options(abortSignal: signal));
      signal.cancel();
      await expectLater(pending, throwsA(isA<AiOperationCancelledError>()));
      auth.complete(const {});
      await Future<void>.delayed(Duration.zero);
      expect(requests, 0);
    },
  );

  test(
    'cancellation races stalled headers without dispatching stream',
    () async {
      final auth = Completer<Map<String, String>>();
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = _ResponseAdapter(() {
          requests++;
          return ResponseBody.fromString('', HttpStatus.ok);
        });
      final model = OpenAIResponsesLanguageModel(
        modelId: 'gpt-5',
        client: dio,
        headers: () => auth.future,
        baseUrl: 'http://responses.test',
      );
      final signal = _Signal();
      final pending = model.doStream(_options(abortSignal: signal));
      signal.cancel();
      await expectLater(pending, throwsA(isA<AiOperationCancelledError>()));
      auth.complete(const {});
      await Future<void>.delayed(Duration.zero);
      expect(requests, 0);
    },
  );
}

OpenAIResponsesLanguageModel _model(Uri endpoint) {
  final dio = Dio(BaseOptions(baseUrl: endpoint.toString()));
  return OpenAIResponsesLanguageModel(
    modelId: 'gpt-5',
    client: dio,
    headers: () async => const {},
    baseUrl: dio.options.baseUrl,
  );
}

class _RawSocketServer {
  _RawSocketServer(this._server, this._sendSseHeaders);

  final ServerSocket _server;
  final bool _sendSseHeaders;
  final requestReceived = Completer<void>();
  final peerClosed = Completer<void>();
  final _sockets = <Socket>[];

  Uri get endpoint =>
      Uri.parse('http://${_server.address.host}:${_server.port}');

  static Future<_RawSocketServer> start({bool sendSseHeaders = false}) async {
    final server = _RawSocketServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      sendSseHeaders,
    );
    server._server.listen(server._handleSocket);
    return server;
  }

  void _handleSocket(Socket socket) {
    _sockets.add(socket);
    socket.listen(
      (_) {
        if (!requestReceived.isCompleted) requestReceived.complete();
        if (_sendSseHeaders) {
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: text/event-stream\r\n'
              'Connection: keep-alive\r\n\r\n'
              'data: {"type":"response.output_text.delta",'
              '"delta":"hello","item_id":"text-1"}\r\n\r\n',
            ),
          );
        }
      },
      onDone: () {
        if (!peerClosed.isCompleted) peerClosed.complete();
      },
      onError: (_) {
        if (!peerClosed.isCompleted) peerClosed.complete();
      },
    );
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

LanguageModelV4CallOptions _options({AbortSignal? abortSignal}) =>
    LanguageModelV4CallOptions(
      prompt: LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.user,
            content: [LanguageModelV4TextPart(text: 'hello')],
          ),
        ],
      ),
      abortSignal: abortSignal,
    );

class _Signal implements AbortSignal {
  final _cancelled = Completer<void>();
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get onCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }
}

class _StreamAdapter implements HttpClientAdapter {
  _StreamAdapter(this.factory);
  final ResponseBody Function() factory;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => factory();

  @override
  void close({bool force = false}) {}
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.factory);
  final ResponseBody Function() factory;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => factory();

  @override
  void close({bool force = false}) {}
}
