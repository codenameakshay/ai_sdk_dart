import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('uploads bytes as multipart and returns a namespaced reference', () async {
    FormData? form;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        form = request.data as FormData;
        return ResponseBody.fromString(
          '{"id":"file-1","bytes":3,"created_at":1700000000,"filename":"a.txt","purpose":"assistants"}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    final file =
        await OpenAIFiles(
          client: dio,
          headers: () async => {'Authorization': 'Bearer test'},
          baseUrl: 'https://api.openai.test/v1',
        ).upload(
          OpenAIFileUpload(
            filename: 'a.txt',
            purpose: 'assistants',
            mediaType: 'text/plain',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        );
    expect(file.id.namespace, 'openai');
    expect(file.id.id, 'file-1');
    expect(form!.fields.map((field) => field.key), contains('purpose'));
    expect(form!.files.single.key, 'file');
    expect(form!.files.single.value.filename, 'a.txt');
  });

  test('requires a known length for stream uploads', () {
    expect(
      () => OpenAIFileUpload(
        filename: 'a.jsonl',
        purpose: 'batch',
        stream: Stream.value(const [1, 2, 3]),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('uploads a known-length stream with expiry metadata', () async {
    FormData? form;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        form = request.data as FormData;
        return ResponseBody.fromString(
          '{"id":"file-stream","bytes":3,"created_at":1700000000,'
          '"expires_at":1700003600,"filename":"a.jsonl",'
          '"purpose":"batch","status":"processed"}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    final file =
        await OpenAIFiles(
          client: dio,
          headers: () async => const {},
          baseUrl: 'https://api.openai.test/v1',
        ).upload(
          OpenAIFileUpload(
            filename: 'a.jsonl',
            purpose: 'batch',
            stream: Stream<List<int>>.value([1, 2, 3]),
            length: 3,
            expiresAfter: const OpenAIFileExpiry(seconds: 3600),
          ),
        );

    expect(
      file.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1700003600 * 1000, isUtc: true),
    );
    expect(file.status, 'processed');
    final fields = {for (final field in form!.fields) field.key: field.value};
    expect(fields, containsPair('purpose', 'batch'));
    expect(fields, containsPair('expires_after[anchor]', 'created_at'));
    expect(fields, containsPair('expires_after[seconds]', '3600'));
    expect(form!.files.single.value.filename, 'a.jsonl');
  });

  test('rejects invalid file expiry settings', () {
    for (final expiry in [
      const OpenAIFileExpiry(anchor: 'updated_at', seconds: 1),
      const OpenAIFileExpiry(seconds: 0),
      const OpenAIFileExpiry(seconds: 2592001),
    ]) {
      expect(
        () => OpenAIFileUpload(
          filename: 'a.txt',
          purpose: 'assistants',
          bytes: Uint8List.fromList([1]),
          expiresAfter: expiry,
        ).validate(),
        throwsA(isA<OpenAIFileException>()),
      );
    }
  });

  test('validates stream length at runtime', () async {
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
    final files = OpenAIFiles(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
    );
    await expectLater(
      files.upload(
        OpenAIFileUpload(
          filename: 'a.jsonl',
          purpose: 'batch',
          stream: Stream.value(const [1, 2, 3]),
          length: -1,
        ),
      ),
      throwsA(isA<OpenAIFileException>()),
    );
    expect(requests, 0);
  });

  test('rejects a foreign provider reference before HTTP', () async {
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
    final files = OpenAIFiles(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
    );
    await expectLater(
      files.retrieve(
        const DataContentProviderReference(namespace: 'other', id: 'x'),
      ),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  test('serializes an OpenAI reference as Responses file_id', () async {
    Map<String, dynamic>? body;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        body = (request.data as Map).cast<String, dynamic>();
        return ResponseBody.fromString(
          '{"id":"resp-1","status":"completed","output":[]}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    await OpenAIResponsesLanguageModel(
      modelId: 'gpt-6-astra',
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
    ).doGenerate(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.user,
              content: [
                LanguageModelV4FilePart(
                  data: DataContentProviderReference(
                    namespace: 'openai',
                    id: 'file-1',
                  ),
                  mediaType: 'application/pdf',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final input = (body!['input'] as List).single as Map;
    expect((input['content'] as List).single, {
      'type': 'input_file',
      'file_id': 'file-1',
    });
  });

  test('runs upload retrieve download delete against a loopback server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.toString());
      if (request.method == 'POST') {
        final body = await request.fold<List<int>>([], (all, chunk) {
          return all..addAll(chunk);
        });
        expect(utf8.decode(body), contains('purpose'));
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            '{"id":"file-1","bytes":3,"created_at":1700000000,"filename":"a.txt","purpose":"assistants"}',
          );
      } else if (request.method == 'GET' &&
          request.uri.path.endsWith('/content')) {
        request.response.add([1, 2, 3]);
      } else if (request.method == 'GET') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            '{"id":"file-1","bytes":3,"created_at":1700000000,"filename":"a.txt","purpose":"assistants"}',
          );
      } else if (request.method == 'DELETE') {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"id":"file-1","deleted":true}');
      }
      await request.response.close();
    });
    final files = OpenAIFiles(
      client: Dio(),
      headers: () async => const {},
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
    );
    final uploaded = await files.upload(
      OpenAIFileUpload(
        filename: 'a.txt',
        purpose: 'assistants',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    final metadata = await files.retrieve(uploaded.id);
    final downloaded = await files.download(uploaded.id);
    expect(await downloaded.expand((chunk) => chunk).toList(), [1, 2, 3]);
    await files.delete(metadata.id);
    expect(paths, contains('/v1/files'));
    expect(paths.where((path) => path.endsWith('/content')), hasLength(1));
  });

  test('encodes opaque file IDs as one path segment', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requested = Completer<String>();
    server.listen((request) async {
      if (!requested.isCompleted) requested.complete(request.uri.toString());
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          '{"id":"file/x?y","bytes":0,"created_at":1700000000,"filename":"x","purpose":"a"}',
        );
      await request.response.close();
    });
    final files = OpenAIFiles(
      client: Dio(),
      headers: () async => const {},
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
    );
    await files.retrieve(
      const DataContentProviderReference(namespace: 'openai', id: 'file/x?y'),
    );
    expect(await requested.future, contains('file%2Fx%3Fy'));
  });

  test('upload cancellation closes the peer socket', () async {
    final server = await _SilentServer.start();
    addTearDown(server.close);
    final signal = _TestSignal();
    final files = OpenAIFiles(
      client: Dio(),
      headers: () async => const {},
      baseUrl: server.endpoint.toString(),
    );
    final pending = files.upload(
      OpenAIFileUpload(
        filename: 'large.bin',
        purpose: 'assistants',
        bytes: Uint8List(1024 * 1024),
      ),
      abortSignal: signal,
    );
    await server.requestReceived.future;
    signal.cancel();
    await expectLater(pending, throwsA(isA<Object>()));
    await server.peerClosed.future;
  });

  test('rejects malformed metadata and delete acknowledgements', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        if (request.method == 'DELETE') {
          return ResponseBody.fromString(
            '{"id":"other","deleted":true}',
            200,
            headers: {
              'content-type': ['application/json'],
            },
          );
        }
        return ResponseBody.fromString(
          '{"id":"file-1","created_at":1700000000,"filename":"a.txt","purpose":"assistants"}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
    final files = OpenAIFiles(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
    );
    await expectLater(
      files.retrieve(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
      ),
      throwsA(isA<OpenAIFileException>()),
    );
    await expectLater(
      files.delete(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
      ),
      throwsA(isA<OpenAIFileException>()),
    );
  });

  test(
    'cancelling a downstream download consumer closes the active body',
    () async {
      final server = await _StreamingServer.start();
      addTearDown(server.close);
      final files = OpenAIFiles(
        client: Dio(),
        headers: () async => const {},
        baseUrl: server.endpoint.toString(),
      );
      final body = await files.download(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
      );
      expect(await body.take(1).toList(), [
        <int>[120],
      ]);
      await server.peerClosed.future;
    },
  );

  test(
    'timeout while consuming a download body is typed and closes the peer',
    () async {
      final server = await _StreamingServer.start();
      addTearDown(server.close);
      final files = OpenAIFiles(
        client: Dio(),
        headers: () async => const {},
        baseUrl: server.endpoint.toString(),
      );
      final body = await files.download(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        body.toList(),
        throwsA(isA<OpenAIFileTimeoutException>()),
      );
      await server.peerClosed.future;
    },
  );

  test(
    'caller cancellation before consuming a body is typed and closes peer',
    () async {
      final server = await _StreamingServer.start();
      addTearDown(server.close);
      final signal = _TestSignal();
      final files = OpenAIFiles(
        client: Dio(),
        headers: () async => const {},
        baseUrl: server.endpoint.toString(),
      );
      final body = await files.download(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        abortSignal: signal,
      );
      signal.cancel();
      await expectLater(
        body.toList(),
        throwsA(isA<AiOperationCancelledError>()),
      );
      await server.peerClosed.future;
    },
  );

  test('cancelling an unlistened download closes the peer', () async {
    final server = await _StreamingServer.start();
    addTearDown(server.close);
    final signal = _TestSignal();
    final files = OpenAIFiles(
      client: Dio(),
      headers: () async => const {},
      baseUrl: server.endpoint.toString(),
    );
    await files.download(
      const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
      abortSignal: signal,
    );
    signal.cancel();
    await server.peerClosed.future.timeout(const Duration(seconds: 1));
  });

  test(
    'non-cancellation errors from a download source remain the first error',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter((_) async {
          return ResponseBody(
            Stream<Uint8List>.error(StateError('body failed')),
            200,
            headers: const {},
          );
        });
      final files = OpenAIFiles(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      );
      final body = await files.download(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
      );
      await expectLater(body.toList(), throwsA(isA<StateError>()));
    },
  );

  test('timeout during hung auth does not dispatch HTTP', () async {
    var requests = 0;
    final auth = Completer<Map<String, String>>();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
    final files = OpenAIFiles(
      client: dio,
      headers: () => auth.future,
      baseUrl: 'https://api.openai.test/v1',
    );
    await expectLater(
      files.upload(
        OpenAIFileUpload(
          filename: 'a.txt',
          purpose: 'assistants',
          bytes: Uint8List.fromList([1]),
        ),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<OpenAIFileTimeoutException>()),
    );
    expect(requests, 0);
  });

  test('cancellation during hung auth does not dispatch HTTP', () async {
    var requests = 0;
    final auth = Completer<Map<String, String>>();
    final signal = _TestSignal();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
    final files = OpenAIFiles(
      client: dio,
      headers: () => auth.future,
      baseUrl: 'https://api.openai.test/v1',
    );
    final pending = files.upload(
      OpenAIFileUpload(
        filename: 'a.txt',
        purpose: 'assistants',
        bytes: Uint8List.fromList([1]),
      ),
      abortSignal: signal,
    );
    signal.cancel();
    await expectLater(pending, throwsA(isA<AiOperationCancelledError>()));
    expect(requests, 0);
  });

  test('pre-cancelled operation does not invoke auth or HTTP', () async {
    var authCalls = 0;
    var requests = 0;
    final signal = _TestSignal()..cancel();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return ResponseBody.fromString('{}', 200);
      });
    final files = OpenAIFiles(
      client: dio,
      headers: () async {
        authCalls++;
        return const {};
      },
      baseUrl: 'https://api.openai.test/v1',
    );
    await expectLater(
      files.retrieve(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        abortSignal: signal,
      ),
      throwsA(isA<AiOperationCancelledError>()),
    );
    expect(authCalls, 0);
    expect(requests, 0);
  });

  test('timeout is distinct for upload retrieve download and delete', () async {
    final auth = Completer<Map<String, String>>();
    final files = OpenAIFiles(
      client: Dio(),
      headers: () => auth.future,
      baseUrl: 'https://api.openai.test/v1',
    );
    const ref = DataContentProviderReference(namespace: 'openai', id: 'file-1');
    final operations = <Future<dynamic> Function()>[
      () => files.upload(
        OpenAIFileUpload(
          filename: 'a.txt',
          purpose: 'assistants',
          bytes: Uint8List.fromList([1]),
        ),
        timeout: const Duration(milliseconds: 10),
      ),
      () => files.retrieve(ref, timeout: const Duration(milliseconds: 10)),
      () => files.download(ref, timeout: const Duration(milliseconds: 10)),
      () => files.delete(ref, timeout: const Duration(milliseconds: 10)),
    ];
    for (final operation in operations) {
      await expectLater(
        operation(),
        throwsA(isA<OpenAIFileTimeoutException>()),
      );
    }
  });

  test(
    'strict metadata rejects fractional numbers and non-string status',
    () async {
      for (final payload in [
        {
          'id': 'f',
          'bytes': 1.5,
          'created_at': 1,
          'filename': 'x',
          'purpose': 'p',
        },
        {
          'id': 'f',
          'bytes': 1,
          'created_at': 1.5,
          'filename': 'x',
          'purpose': 'p',
        },
        {
          'id': 'f',
          'bytes': 1,
          'created_at': 1,
          'filename': 'x',
          'purpose': 'p',
          'status': 1,
        },
      ]) {
        expect(
          () => OpenAIFileMetadata.fromJson(payload),
          throwsA(isA<OpenAIFileException>()),
        );
      }
    },
  );

  test('rejects empty provider references at runtime', () async {
    final files = OpenAIFiles(
      client: Dio(),
      headers: () async => const {},
      baseUrl: 'https://example.test/v1',
    );
    await expectLater(
      files.retrieve(
        const DataContentProviderReference(namespace: 'openai', id: ' '),
      ),
      throwsArgumentError,
    );
  });

  test('multipart setup failures still dispose request scope', () async {
    final signal = _TestSignal();
    final files = OpenAIFiles(
      client: Dio(),
      headers: () async => const {},
      baseUrl: 'https://example.test/v1',
    );
    await expectLater(
      files.upload(
        OpenAIFileUpload(
          filename: 'a.txt',
          purpose: 'assistants',
          bytes: Uint8List.fromList([1]),
          mediaType: 'not a media type',
        ),
        abortSignal: signal,
      ),
      throwsA(anything),
    );
    signal.cancel();
  });
}

class _TestSignal implements AbortSignal {
  final _cancelled = Completer<void>();
  @override
  var isCancelled = false;

  @override
  Future<void> get onCancelled => _cancelled.future;

  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    _cancelled.complete();
  }
}

class _SilentServer {
  _SilentServer(this._server);
  final ServerSocket _server;
  final requestReceived = Completer<void>();
  final peerClosed = Completer<void>();
  final _sockets = <Socket>[];

  Uri get endpoint =>
      Uri.parse('http://${_server.address.host}:${_server.port}/v1');

  static Future<_SilentServer> start() async {
    final server = _SilentServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._accept);
    return server;
  }

  void _accept(Socket socket) {
    _sockets.add(socket);
    socket.listen(
      (_) {
        if (!requestReceived.isCompleted) requestReceived.complete();
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

class _StreamingServer {
  _StreamingServer(this._server);
  final ServerSocket _server;
  final peerClosed = Completer<void>();
  final _sockets = <Socket>[];

  Uri get endpoint =>
      Uri.parse('http://${_server.address.host}:${_server.port}/v1');

  static Future<_StreamingServer> start() async {
    final server = _StreamingServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._accept);
    return server;
  }

  void _accept(Socket socket) {
    _sockets.add(socket);
    var request = <int>[];
    socket.listen(
      (chunk) {
        request.addAll(chunk);
        if (request.contains(13) && request.contains(10)) {
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n'
            'Transfer-Encoding: chunked\r\n\r\n1\r\nx\r\n',
          );
          request = [];
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

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
