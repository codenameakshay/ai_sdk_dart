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
