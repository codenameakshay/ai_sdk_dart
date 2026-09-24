import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('Files timeout during headers releases the caller observer', () async {
    final signal = _CountingSignal();
    addTearDown(signal.close);
    final client = Dio()..httpClientAdapter = _FilesAdapter();
    addTearDown(() => client.close(force: true));
    final headers = Completer<Map<String, String>>();
    final files = OpenAIFiles(
      client: client,
      headers: () => headers.future,
      baseUrl: 'https://api.openai.test/v1',
    );
    await expectLater(
      files.retrieve(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        abortSignal: signal,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<OpenAIFileTimeoutException>()),
    );
    expect(signal.active, 0);
    expect(signal.futureObservations, 0);
    expect(signal.attached, greaterThan(0));
    headers.complete(const {});
  });

  test(
    'Files cancellation during registration skips headers and detaches',
    () async {
      final signal = _CountingSignal()..cancelOnSubscribe = true;
      addTearDown(signal.close);
      final client = Dio()..httpClientAdapter = _FilesAdapter();
      addTearDown(() => client.close(force: true));
      var headerCalls = 0;
      final files = OpenAIFiles(
        client: client,
        headers: () async {
          headerCalls++;
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
      expect(headerCalls, 0);
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.attached, greaterThan(0));
    },
  );

  test('Files requests detach observers after success and failure', () async {
    final signal = _CountingSignal();
    addTearDown(signal.close);
    final adapter = _FilesAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    addTearDown(() => client.close(force: true));
    final files = OpenAIFiles(
      client: client,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
    );
    const reference = DataContentProviderReference(
      namespace: 'openai',
      id: 'file-1',
    );

    for (final operation in <Future<void> Function()>[
      () async => files.retrieve(reference, abortSignal: signal),
      () async => files.delete(reference, abortSignal: signal),
      () async => files.upload(
        OpenAIFileUpload(
          filename: 'input.txt',
          purpose: 'assistants',
          bytes: Uint8List.fromList([1]),
        ),
        abortSignal: signal,
      ),
    ]) {
      await operation();
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.attached, greaterThan(0));
      expect(signal.detached, signal.attached);
    }

    adapter.fail = true;
    for (final operation in <Future<void> Function()>[
      () async => files.retrieve(reference, abortSignal: signal),
      () async => files.delete(reference, abortSignal: signal),
      () async => files.upload(
        OpenAIFileUpload(
          filename: 'input.txt',
          purpose: 'assistants',
          bytes: Uint8List.fromList([1]),
        ),
        abortSignal: signal,
      ),
    ]) {
      await expectLater(operation(), throwsA(isA<AiApiCallError>()));
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.detached, signal.attached);
    }
  });

  test('Batch requests detach observers after success and failure', () async {
    final signal = _CountingSignal();
    addTearDown(signal.close);
    final adapter = _BatchAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    addTearDown(() => client.close(force: true));
    final batches = OpenAIBatches(
      client: client,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
      files: OpenAIFiles(
        client: client,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      ),
    );

    for (final operation in <Future<void> Function()>[
      () async => batches.get('batch-1', abortSignal: signal),
      () async => batches.list(abortSignal: signal),
      () async => batches.cancel('batch-1', abortSignal: signal),
      () async => batches.create(const [
        OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
      ], abortSignal: signal),
    ]) {
      await operation();
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.attached, greaterThan(0));
      expect(signal.detached, signal.attached);
    }

    adapter.fail = true;
    for (final operation in <Future<void> Function()>[
      () async => batches.get('batch-1', abortSignal: signal),
      () async => batches.list(abortSignal: signal),
      () async => batches.cancel('batch-1', abortSignal: signal),
      () async => batches.create(const [
        OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
      ], abortSignal: signal),
    ]) {
      await expectLater(operation(), throwsA(anything));
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.detached, signal.attached);
    }
  });

  test(
    'File download detaches observers on completion and source error',
    () async {
      final signal = _CountingSignal();
      addTearDown(signal.close);
      final adapter = _DownloadAdapter();
      final client = Dio()..httpClientAdapter = adapter;
      addTearDown(() => client.close(force: true));
      final files = OpenAIFiles(
        client: client,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      );
      const reference = DataContentProviderReference(
        namespace: 'openai',
        id: 'file-1',
      );

      final completed = await files.download(reference, abortSignal: signal);
      await completed.toList();
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.attached, greaterThan(0));
      expect(signal.detached, signal.attached);

      adapter.fail = true;
      final failed = await files.download(reference, abortSignal: signal);
      await expectLater(failed.toList(), throwsA(isA<StateError>()));
      expect(signal.active, 0);
      expect(signal.futureObservations, 0);
      expect(signal.detached, signal.attached);
    },
  );

  test('File download detaches observer when consumer cancels', () async {
    final signal = _CountingSignal();
    addTearDown(signal.close);
    final client = Dio()..httpClientAdapter = _DownloadAdapter(twoChunks: true);
    addTearDown(() => client.close(force: true));
    final files = OpenAIFiles(
      client: client,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1',
    );
    final stream = await files.download(
      const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
      abortSignal: signal,
    );
    await stream.take(1).toList();
    expect(signal.active, 0);
    expect(signal.futureObservations, 0);
    expect(signal.attached, greaterThan(0));
    expect(signal.detached, signal.attached);
  });

  test(
    'File download detaches observer when caller cancels before listen',
    () async {
      final signal = _CountingSignal();
      addTearDown(signal.close);
      final client = Dio()..httpClientAdapter = _DownloadAdapter();
      addTearDown(() => client.close(force: true));
      final files = OpenAIFiles(
        client: client,
        headers: () async => const {},
        baseUrl: 'https://api.openai.test/v1',
      );
      await files.download(
        const DataContentProviderReference(namespace: 'openai', id: 'file-1'),
        abortSignal: signal,
      );
      signal.cancel();
      await signal.waitForNoActiveObservers();
      expect(signal.futureObservations, 0);
      expect(signal.attached, greaterThan(0));
      expect(signal.detached, signal.attached);
    },
  );
}

class _CountingSignal implements ObservableAbortSignal {
  final _events = StreamController<void>.broadcast();
  final _noActiveObservers = <Completer<void>>[];
  var attached = 0;
  var detached = 0;
  var futureObservations = 0;
  var _isCancelled = false;
  var cancelOnSubscribe = false;

  int get active => attached - detached;

  Future<void> waitForNoActiveObservers() {
    if (active == 0) return Future<void>.value();
    final waiter = Completer<void>();
    _noActiveObservers.add(waiter);
    return waiter.future;
  }

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get onCancelled {
    futureObservations++;
    return Completer<void>().future;
  }

  @override
  Stream<void> get cancellationEvents => Stream.multi((controller) {
    attached++;
    final subscription = _events.stream.listen(controller.addSync);
    controller.onCancel = () {
      detached++;
      if (active == 0) {
        for (final waiter in _noActiveObservers) {
          if (!waiter.isCompleted) waiter.complete();
        }
        _noActiveObservers.clear();
      }
      return subscription.cancel();
    };
    if (cancelOnSubscribe) cancel();
  }, isBroadcast: true);

  void cancel() {
    _isCancelled = true;
    _events.add(null);
  }

  Future<void> close() => _events.close();
}

class _FilesAdapter implements HttpClientAdapter {
  var fail = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) return _error();
    if (options.method == 'DELETE') {
      return _json({'id': 'file-1', 'deleted': true});
    }
    return _json({
      'id': 'file-1',
      'bytes': 1,
      'created_at': 1,
      'filename': 'input.txt',
      'purpose': 'assistants',
    });
  }

  @override
  void close({bool force = false}) {}
}

class _BatchAdapter implements HttpClientAdapter {
  var fail = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) return _error();
    if (options.path.endsWith('/files')) {
      return _json({
        'id': 'file-in',
        'bytes': 1,
        'created_at': 1,
        'filename': 'batch.jsonl',
        'purpose': 'batch',
      });
    }
    if (options.path.endsWith('/batches')) {
      if (options.method == 'GET') {
        return _json({
          'data': [
            {'id': 'batch-1', 'status': 'completed'},
          ],
          'has_more': false,
        });
      }
      return _json({'id': 'batch-1', 'status': 'validating'});
    }
    return _json({'id': 'batch-1', 'status': 'cancelling'});
  }

  @override
  void close({bool force = false}) {}
}

class _DownloadAdapter implements HttpClientAdapter {
  _DownloadAdapter({this.twoChunks = false});
  final bool twoChunks;
  var fail = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      return ResponseBody(
        Stream<Uint8List>.error(StateError('body failed')),
        200,
        headers: const {},
      );
    }
    final chunks = <Uint8List>[
      Uint8List.fromList([1]),
      if (twoChunks) Uint8List.fromList([2]),
    ];
    return ResponseBody(Stream.fromIterable(chunks), 200, headers: const {});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> json) => ResponseBody.fromString(
  jsonEncode(json),
  200,
  headers: const {
    'content-type': ['application/json'],
  },
);

ResponseBody _error() => ResponseBody.fromString(
  '{"error":{"message":"fixture failure"}}',
  400,
  headers: const {
    'content-type': ['application/json'],
  },
);
