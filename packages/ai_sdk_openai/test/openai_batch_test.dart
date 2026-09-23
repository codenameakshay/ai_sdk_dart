import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('encodes unique responses JSONL and creates a batch', () async {
    final calls = <RequestOptions>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        calls.add(request);
        if (request.method == 'POST' && request.path.endsWith('/files')) {
          return _json({
            'id': 'file-in',
            'bytes': 1,
            'created_at': 1,
            'filename': 'x',
            'purpose': 'batch',
          });
        }
        return _json({'id': 'batch-1', 'status': 'validating'});
      });
    final batches = OpenAIBatches(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
      files: OpenAIFiles(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      ),
    );
    final batch = await batches.create(
      const [
        OpenAIBatchInput(customId: 'a', model: 'gpt-test', input: 'hello'),
        OpenAIBatchInput(customId: 'b', model: 'gpt-test', input: 'world'),
      ],
      metadata: {'source': 'test'},
    );
    expect(batch.status, OpenAIBatchStatus.validating);
    expect(calls, hasLength(2));
    expect((calls.last.data as Map)['endpoint'], '/v1/responses');
    expect((calls.last.data as Map)['metadata'], {'source': 'test'});
  });

  test(
    'applies the total deadline to upload and skips expired submission',
    () async {
      Duration? uploadTimeout;
      final stopwatch = _FakeStopwatch(const Duration(milliseconds: 1));
      var submissions = 0;
      final files = _DelayedFiles((timeout) async {
        uploadTimeout = timeout;
        stopwatch.value = const Duration(milliseconds: 10);
        return OpenAIFileMetadata(
          id: DataContentProviderReference(namespace: 'openai', id: 'file-in'),
          bytes: 1,
          createdAt: DateTime.utc(1970),
          filename: 'batch.jsonl',
          purpose: 'batch',
        );
      });
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          submissions++;
          return _json({'id': 'batch-1', 'status': 'validating'});
        });
      final batches = OpenAIBatches(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
        files: files,
        stopwatchFactory: () => stopwatch,
      );

      await expectLater(
        batches.create(const [
          OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
        ], timeout: const Duration(milliseconds: 10)),
        throwsA(isA<OpenAIBatchSubmissionException>()),
      );
      expect(uploadTimeout, isNotNull);
      expect(uploadTimeout!, lessThan(const Duration(milliseconds: 10)));
      expect(submissions, 0);
    },
  );

  test(
    'rejects an expired pre-upload deadline without invoking upload',
    () async {
      final stopwatch = _FakeStopwatch(const Duration(milliseconds: 10));
      var uploads = 0;
      final files = _DelayedFiles((_) async {
        uploads++;
        throw StateError('upload should not run');
      });
      final batches = OpenAIBatches(
        client: Dio(),
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
        files: files,
        stopwatchFactory: () => stopwatch,
      );
      await expectLater(
        batches.create(const [
          OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
        ], timeout: const Duration(milliseconds: 10)),
        throwsA(isA<OpenAIFileTimeoutException>()),
      );
      expect(uploads, 0);
    },
  );

  test(
    'surfaces post-upload create failure with the uploaded reference',
    () async {
      var submissions = 0;
      final files = _DelayedFiles(
        (_) async => OpenAIFileMetadata(
          id: const DataContentProviderReference(
            namespace: 'openai',
            id: 'file-in',
          ),
          bytes: 1,
          createdAt: DateTime.utc(1970),
          filename: 'batch.jsonl',
          purpose: 'batch',
        ),
      );
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          submissions++;
          return ResponseBody.fromString(
            '{"error":{"message":"rejected"}}',
            400,
            headers: const {
              'content-type': ['application/json'],
            },
          );
        });
      final batches = OpenAIBatches(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
        files: files,
      );

      OpenAIBatchSubmissionException? failure;
      try {
        await batches.create(const [
          OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
        ]);
      } catch (error) {
        failure = error as OpenAIBatchSubmissionException;
      }
      expect(failure, isNotNull);
      expect(failure!.inputFile.id, 'file-in');
      expect(submissions, 1);
    },
  );

  test(
    'cancellation during upload auth does not submit or cancel a batch',
    () async {
      final auth = Completer<Map<String, String>>();
      final signal = _TestAbortSignal();
      final paths = <String>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((request) async {
          paths.add(request.uri.path);
          return _json({
            'id': 'file-in',
            'bytes': 1,
            'created_at': 1,
            'filename': 'batch.jsonl',
            'purpose': 'batch',
          });
        });
      final files = OpenAIFiles(
        client: dio,
        headers: () => auth.future,
        baseUrl: 'https://api.openai.test/v1',
      );
      final batches = OpenAIBatches(
        client: dio,
        headers: () => auth.future,
        baseUrl: 'https://api.openai.test/v1',
        files: files,
      );
      final pending = batches.create(const [
        OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
      ], abortSignal: signal);
      signal.cancel();
      await expectLater(pending, throwsA(isA<AiOperationCancelledError>()));
      auth.complete(const {});
      await Future<void>.delayed(Duration.zero);
      expect(paths, isEmpty);
    },
  );

  test('rejects duplicate IDs and mixed models', () async {
    final batches = OpenAIBatches(
      client: Dio(),
      headers: () async => const {},
      baseUrl: 'https://example.test/v1',
      files: OpenAIFiles(
        client: Dio(),
        headers: () async => const {},
        baseUrl: 'https://example.test/v1',
      ),
    );
    await expectLater(
      batches.create(const [
        OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
        OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
      ]),
      throwsA(isA<OpenAIBatchException>()),
    );
    await expectLater(
      batches.create(const [
        OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
        OpenAIBatchInput(customId: 'b', model: 'n', input: 'x'),
      ]),
      throwsA(isA<OpenAIBatchException>()),
    );
  });

  test('preserves unknown states and separate output/error references', () {
    final batch = OpenAIBatch.fromJson({
      'id': 'b',
      'status': 'future_state',
      'input_file_id': 'in',
      'output_file_id': 'out',
      'error_file_id': 'err',
      'request_counts': {'total': 2, 'completed': 1, 'failed': 1},
    });
    expect(batch.status, OpenAIBatchStatus.unknown);
    expect(batch.rawStatus, 'future_state');
    expect(batch.outputFileId!.id, 'out');
    expect(batch.errorFileId!.id, 'err');
  });

  test('gets lists and explicitly cancels without polling', () async {
    final paths = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        paths.add(request.uri.toString());
        if (request.path.endsWith('/cancel')) {
          return _json({'id': 'b', 'status': 'cancelling'});
        }
        if (request.path.endsWith('/batches')) {
          return _json({
            'data': [
              {'id': 'b', 'status': 'in_progress'},
            ],
            'has_more': false,
          });
        }
        return _json({'id': 'b', 'status': 'completed'});
      });
    final batches = OpenAIBatches(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
      files: OpenAIFiles(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      ),
    );
    expect((await batches.get('b')).status, OpenAIBatchStatus.completed);
    expect(
      (await batches.list(limit: 2)).single.status,
      OpenAIBatchStatus.inProgress,
    );
    expect((await batches.cancel('b')).status, OpenAIBatchStatus.cancelling);
    expect(paths.any((path) => path.endsWith('/v1/batches/b')), isTrue);
    expect(paths.any((path) => path.endsWith('/v1/batches?limit=2')), isTrue);
    expect(paths.any((path) => path.endsWith('/v1/batches/b/cancel')), isTrue);
  });

  test('rejects malformed list items and mismatched get/cancel IDs', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) async {
        if (request.path.endsWith('/cancel')) {
          return _json({'id': 'other', 'status': 'cancelling'});
        }
        if (request.path.endsWith('/batches')) {
          return _json({
            'data': [null],
            'has_more': false,
          });
        }
        return _json({'id': 'other', 'status': 'completed'});
      });
    final batches = OpenAIBatches(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
      files: OpenAIFiles(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      ),
    );
    await expectLater(batches.list(), throwsA(isA<OpenAIBatchException>()));
    await expectLater(batches.get('b'), throwsA(isA<OpenAIBatchException>()));
    await expectLater(
      batches.cancel('b'),
      throwsA(isA<OpenAIBatchException>()),
    );
  });

  test('rejects a paginated list without a last id', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        return _json({'data': <Object>[], 'has_more': true});
      });
    final batches = OpenAIBatches(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
      files: OpenAIFiles(
        client: dio,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      ),
    );

    await expectLater(batches.list(), throwsA(isA<OpenAIBatchException>()));
  });

  test(
    'decodes split UTF8 JSONL in result order and rejects duplicates/truncation',
    () async {
      final rows = [
        jsonEncode({
          'custom_id': 'b',
          'response': {'status_code': 500},
          'error': {'message': 'échec'},
        }),
        jsonEncode({
          'custom_id': 'a',
          'response': {'status_code': 200, 'request_id': 'r'},
        }),
      ];
      final bytes = utf8.encode('${rows.join('\n')}\n');
      final emojiOffset = bytes.indexOf(0xc3);
      final chunks = <List<int>>[
        bytes.sublist(0, emojiOffset + 1),
        bytes.sublist(emojiOffset + 1, emojiOffset + 2),
        bytes.sublist(emojiOffset + 2),
      ];
      final result = await decodeOpenAIBatchResults(
        Stream.fromIterable(chunks),
      ).toList();
      expect(result.map((item) => item.customId), ['b', 'a']);
      expect(result.first.error!['message'], 'échec');
      await expectLater(
        decodeOpenAIBatchResults(
          Stream.value(utf8.encode('{"custom_id":')),
        ).toList(),
        throwsA(isA<OpenAIBatchException>()),
      );
      await expectLater(
        decodeOpenAIBatchResults(
          Stream.fromIterable([
            utf8.encode('${rows.first}\n'),
            utf8.encode('${rows.first}\n'),
          ]),
        ).toList(),
        throwsA(isA<OpenAIBatchException>()),
      );
    },
  );

  test('runs batch lifecycle and result download on loopback', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var uploadBody = '';
    var createBody = <String, dynamic>{};
    server.listen((request) async {
      final path = request.uri.path;
      if (request.method == 'POST' && path.endsWith('/files')) {
        uploadBody = utf8.decode(
          await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
        );
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            '{"id":"file-in","bytes":1,"created_at":1,"filename":"x","purpose":"batch"}',
          );
      } else if (request.method == 'POST' && path.endsWith('/batches')) {
        createBody =
            jsonDecode(
                  utf8.decode(
                    await request.fold<List<int>>(
                      [],
                      (all, chunk) => all..addAll(chunk),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            '{"id":"batch-1","status":"validating","input_file_id":"file-in"}',
          );
      } else if (request.method == 'POST' && path.endsWith('/cancel')) {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"id":"batch-1","status":"cancelling"}');
      } else if (request.method == 'GET' && path.endsWith('/content')) {
        request.response.headers.contentType = ContentType(
          'application',
          'jsonl',
        );
        request.response.add(
          utf8.encode(
            '{"custom_id":"b","response":null,"error":{"message":"échec"}}\n{"custom_id":"a","response":{"status_code":200}}',
          ),
        );
      } else if (request.method == 'GET' && path.endsWith('/batches')) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            '{"data":[{"id":"batch-1","status":"in_progress"}],"has_more":false,"last_id":"batch-1"}',
          );
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            '{"id":"batch-1","status":"completed","output_file_id":"file-out"}',
          );
      }
      await request.response.close();
    });
    final provider = OpenAIProvider(
      apiKey: 'test',
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
    );
    addTearDown(provider.dispose);
    final batches = provider.batches();
    final created = await batches.create(const [
      OpenAIBatchInput(customId: 'a', model: 'gpt-test', input: 'hello 🌍'),
    ]);
    expect(uploadBody, contains('name="purpose"'));
    expect(uploadBody, contains('name="file"'));
    expect(createBody['input_file_id'], 'file-in');
    expect(createBody['endpoint'], '/v1/responses');
    expect((await batches.get(created.id)).status, OpenAIBatchStatus.completed);
    expect((await batches.list()).items, hasLength(1));
    expect(
      (await batches.cancel(created.id)).status,
      OpenAIBatchStatus.cancelling,
    );
    final stream = await provider.files().download(
      const DataContentProviderReference(namespace: 'openai', id: 'file-out'),
    );
    final rows = await decodeOpenAIBatchResults(stream).toList();
    expect(rows.map((row) => row.customId), ['b', 'a']);
    expect(rows.first.statusCode, isNull);
  });
}

ResponseBody _json(Map<String, dynamic> json) => ResponseBody.fromString(
  jsonEncode(json),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

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

class _DelayedFiles extends OpenAIFiles {
  _DelayedFiles(this.uploadHandler)
    : super(
        client: Dio(),
        headers: _emptyHeaders,
        baseUrl: 'https://api.openai.test/v1',
      );

  final Future<OpenAIFileMetadata> Function(Duration? timeout) uploadHandler;

  @override
  Future<OpenAIFileMetadata> upload(
    OpenAIFileUpload upload, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) => uploadHandler(timeout);
}

class _TestAbortSignal implements AbortSignal {
  final _cancelled = Completer<void>();
  @override
  bool isCancelled = false;
  @override
  Future<void> get onCancelled => _cancelled.future;
  void cancel() {
    isCancelled = true;
    _cancelled.complete();
  }
}

class _FakeStopwatch extends Stopwatch {
  _FakeStopwatch(this.value);
  Duration value;
  @override
  Duration get elapsed => value;
  @override
  Stopwatch start() => this;
}

Future<Map<String, String>> _emptyHeaders() async => const {};
