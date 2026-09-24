import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('cancellation during late auth does not send a request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    });
    final auth = Completer<Map<String, String>>();
    final authCalled = Completer<void>();
    final token = RemoteCancellationToken();
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
      authHeaders: () {
        if (!authCalled.isCompleted) authCalled.complete();
        return auth.future;
      },
    );
    final pending = transport
        .send(
          Conversation(id: 'c1', messages: const []),
          cancellation: token,
        )
        .toList();
    await authCalled.future;
    token.cancel();
    await expectLater(pending, throwsA(isA<RemoteCancelledException>()));
    auth.complete(const {});
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    await token.dispose();
    transport.dispose();
  });

  test('unlistened send is lazy and dispose prevents startup', () async {
    var authCalls = 0;
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://example.test/chat'),
      authHeaders: () {
        authCalls++;
        return const {};
      },
    );
    final pending = transport.send(Conversation(id: 'c1', messages: const []));
    transport.dispose();
    await expectLater(pending.toList(), throwsA(isA<StateError>()));
    expect(authCalls, 0);
  });

  test('unlistened send does not attach a cancellation observer', () async {
    final token = _TrackedCancellationToken();
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://example.test/chat'),
    );
    transport.send(
      Conversation(id: 'c1', messages: const []),
      cancellation: token,
    );
    expect(token.activeListeners, 0);
    await token.dispose();
    transport.dispose();
  });

  test('cancellation before listen skips auth and dispatch', () async {
    var authCalls = 0;
    final token = RemoteCancellationToken();
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://example.test/chat'),
      authHeaders: () {
        authCalls++;
        return const {};
      },
    );
    final pending = transport.send(
      Conversation(id: 'c1', messages: const []),
      cancellation: token,
    );
    token.cancel();
    expect(await pending.toList(), isEmpty);
    expect(authCalls, 0);
    await token.dispose();
    transport.dispose();
  });

  test('dispose during late auth cancels without sending a request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    });
    final auth = Completer<Map<String, String>>();
    final authCalled = Completer<void>();
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
      authHeaders: () {
        if (!authCalled.isCompleted) authCalled.complete();
        return auth.future;
      },
    );
    final pending = transport
        .send(Conversation(id: 'c1', messages: const []))
        .toList();
    await authCalled.future;
    transport.dispose();
    await expectLater(pending, throwsA(isA<RemoteCancelledException>()));
    auth.complete(const {});
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
  });

  test('cancellation closes a socket waiting for response headers', () async {
    final server = await _RawSocketServer.start();
    addTearDown(server.close);
    final token = RemoteCancellationToken();
    final transport = RemoteConversationTransport(endpoint: server.endpoint);
    final pending = transport
        .send(
          Conversation(id: 'c1', messages: const []),
          cancellation: token,
        )
        .toList();
    await server.requestReceived.future;
    token.cancel();
    await expectLater(pending, throwsA(isA<RemoteCancelledException>()));
    await server.peerClosed.future;
    await token.dispose();
    transport.dispose();
  });

  test(
    'peer EOF while waiting for response headers settles the send',
    () async {
      final server = await _RawSocketServer.start(closeAfterRequest: true);
      addTearDown(server.close);
      final transport = RemoteConversationTransport(endpoint: server.endpoint);
      final pending = transport
          .send(Conversation(id: 'c1', messages: const []))
          .toList();
      await server.requestReceived.future;
      await expectLater(pending, throwsA(isA<Exception>()));
      await server.peerClosed.future;
      transport.dispose();
    },
  );

  test('stream cancellation closes an active silent SSE socket', () async {
    final server = await _RawSocketServer.start(sendSseHeaders: true);
    addTearDown(server.close);
    final transport = RemoteConversationTransport(endpoint: server.endpoint);
    final firstSnapshot = Completer<Conversation>();
    final subscription = transport
        .send(Conversation(id: 'c1', messages: const []))
        .listen((snapshot) {
          if (!firstSnapshot.isCompleted) firstSnapshot.complete(snapshot);
        });
    await firstSnapshot.future;
    await subscription.cancel();
    await server.peerClosed.future;
    transport.dispose();
  });

  test(
    'pausing downstream pauses and resuming downstream resumes the source',
    () async {
      var pauses = 0;
      var resumes = 0;
      final source = StreamController<List<int>>(
        onPause: () => pauses++,
        onResume: () => resumes++,
      );
      final client = _ControlledClient(source.stream);
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://example.test/chat'),
        client: client,
      );
      final first = Completer<void>();
      final done = Completer<void>();
      final subscription = transport
          .send(Conversation(id: 'c1', messages: const []))
          .listen((_) {
            if (!first.isCompleted) first.complete();
          }, onDone: done.complete);
      source.add(utf8.encode('data: {"type":"start","messageId":"a"}\n\n'));
      await first.future;
      subscription.pause();
      await Future<void>.delayed(Duration.zero);
      expect(pauses, greaterThanOrEqualTo(1));
      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(resumes, greaterThanOrEqualTo(1));
      source.add(
        utf8.encode(
          'data: {"type":"finish"}\n\n'
          'data: [DONE]\n\n',
        ),
      );
      await done.future;
      await source.close();
      transport.dispose();
    },
  );

  test(
    'detaches the caller token observer after each completed send',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
        request.response.write(
          'data: {"type":"start","messageId":"a"}\n\n'
          'data: {"type":"finish"}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      final token = _TrackedCancellationToken();
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
      );
      for (var i = 0; i < 100; i++) {
        await transport
            .send(
              Conversation(id: 'c1', messages: const []),
              cancellation: token,
            )
            .toList();
        expect(token.activeListeners, 0);
      }
      await token.dispose();
      transport.dispose();
    },
  );

  test('requires the exact text/event-stream media type', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..headers.set('content-type', 'text/event-streamish')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
      await request.response.close();
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
    );
    await expectLater(
      transport.send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<RemoteProtocolException>()),
    );
    transport.dispose();
  });
}

class _RawSocketServer {
  _RawSocketServer(this._server, this._sendSseHeaders, this._closeAfterRequest);

  final ServerSocket _server;
  final bool _sendSseHeaders;
  final bool _closeAfterRequest;
  final requestReceived = Completer<void>();
  final peerClosed = Completer<void>();
  final _sockets = <Socket>[];

  Uri get endpoint =>
      Uri.parse('http://${_server.address.host}:${_server.port}');

  static Future<_RawSocketServer> start({
    bool sendSseHeaders = false,
    bool closeAfterRequest = false,
  }) async {
    final server = _RawSocketServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      sendSseHeaders,
      closeAfterRequest,
    );
    server._server.listen(server._handleSocket);
    return server;
  }

  void _handleSocket(Socket socket) {
    _sockets.add(socket);
    var announced = false;
    socket.listen(
      (bytes) {
        if (announced) return;
        announced = true;
        requestReceived.complete();
        if (_closeAfterRequest) {
          socket.destroy();
          return;
        }
        if (_sendSseHeaders) {
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: text/event-stream\r\n'
              'X-Vercel-AI-UI-Message-Stream: v1\r\n'
              'Connection: keep-alive\r\n\r\n'
              'data: {"type":"start","messageId":"a"}\r\n\r\n',
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

class _ControlledClient extends http.BaseClient {
  _ControlledClient(this.source);
  final Stream<List<int>> source;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      source,
      200,
      headers: const {
        'content-type': 'text/event-stream',
        'x-vercel-ai-ui-message-stream': 'v1',
      },
      request: request,
    );
  }
}

class _TrackedCancellationToken extends RemoteCancellationToken {
  var activeListeners = 0;
  late final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: () => activeListeners++,
    onCancel: () => activeListeners--,
  );

  @override
  Stream<void> get changes {
    return _changes.stream.transform(
      StreamTransformer<void, void>.fromHandlers(
        handleData: (value, sink) => sink.add(value),
      ),
    );
  }

  @override
  void cancel() {
    super.cancel();
    _changes.add(null);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _changes.close();
  }
}
