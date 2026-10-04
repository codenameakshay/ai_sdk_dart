import 'dart:async';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_telemetry/ai_sdk_telemetry.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('dispose bounds an existing stalled connection', () {
    fakeAsync((clock) {
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://fixture.test/v1/metrics'),
        client: _Client(),
      );
      sink.record(const TelemetryMetric(name: 'duration', value: 1));
      unawaited(sink.flush().catchError((Object _) {}));
      clock.flushMicrotasks();
      var disposed = false;
      sink
          .dispose(deadline: const Duration(seconds: 1))
          .then<void>((_) => disposed = true);
      clock.elapse(const Duration(seconds: 1));
      expect(disposed, isTrue);
      clock.elapse(const Duration(seconds: 10));
    });
  });

  test('connection setup and response share one export deadline', () {
    fakeAsync((clock) {
      final client = _Client();
      final request = _Request();
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://fixture.test/v1/metrics'),
        client: client,
      );
      sink.record(const TelemetryMetric(name: 'duration', value: 1));
      Object? error;
      var settled = false;
      sink
          .flush(deadline: const Duration(seconds: 3))
          .then<void>(
            (_) => settled = true,
            onError: (Object value) {
              error = value;
              settled = true;
            },
          );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      client.connected.complete(request);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(settled, isTrue);
      expect(error, isA<TimeoutException>());
      expect(request.aborted, isTrue);
      request.response.completeError(StateError('closed'));
      unawaited(sink.dispose(deadline: const Duration(seconds: 1)));
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
    });
  });

  test(
    'connection timeout leaves an injected client usable for retry',
    () async {
      final client = _RecoveringClient();
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://fixture.test/v1/metrics'),
        client: client,
      );
      addTearDown(sink.dispose);
      sink.record(const TelemetryMetric(name: 'retryable', value: 1));

      await expectLater(
        sink.flush(deadline: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.closed, isFalse);
      await sink.flush(deadline: const Duration(seconds: 1));
      expect(client.calls, 2);
      expect(sink.pendingCount, 0);
      client.firstConnection.complete(_ImmediateRequest());
      await sink.dispose();
      expect(
        client.closed,
        isFalse,
        reason: 'Injected HttpClient ownership remains with the caller.',
      );
    },
  );
}

class _Client implements HttpClient {
  final connected = Completer<HttpClientRequest>();
  @override
  Future<HttpClientRequest> postUrl(Uri url) => connected.future;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  final response = Completer<HttpClientResponse>();
  bool aborted = false;
  @override
  HttpHeaders get headers => _Headers();
  @override
  void add(List<int> data) {}
  @override
  Future<HttpClientResponse> close() => response.future;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) => aborted = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  set contentType(ContentType? value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveringClient implements HttpClient {
  final firstConnection = Completer<HttpClientRequest>();
  var calls = 0;
  var closed = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    calls++;
    if (calls == 1) return firstConnection.future;
    return Future<HttpClientRequest>.value(_ImmediateRequest());
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImmediateRequest implements HttpClientRequest {
  @override
  HttpHeaders get headers => _Headers();

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() =>
      Future<HttpClientResponse>.value(_SuccessfulResponse());

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SuccessfulResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  Future<T> drain<T>([T? futureValue]) => Future<T>.value(futureValue);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
