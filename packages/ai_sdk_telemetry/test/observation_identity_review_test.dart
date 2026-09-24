import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_telemetry/ai_sdk_telemetry.dart';
import 'package:test/test.dart';

void main() {
  test('resource attributes retain only sanitized values', () async {
    var redactions = 0;
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://fixture.test/v1/metrics'),
      resourceAttributes: const {'secret': 'private'},
      redactAttribute: (key, value) {
        redactions++;
        return '[redacted]';
      },
    );
    addTearDown(sink.dispose);
    expect(sink.resourceAttributes, {'secret': '[redacted]'});
    expect(redactions, 1);
  });

  test(
    'redaction runs once at admission and retries preserve observation',
    () async {
      final requests = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.statusCode = requests.length == 1 ? 503 : 200;
        await request.response.close();
      });
      var redactions = 0;
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        redactAttribute: (key, value) {
          redactions++;
          return '[redacted-$redactions]';
        },
      );
      addTearDown(() async {
        await sink.dispose();
        await server.close(force: true);
      });
      sink.record(
        const TelemetryMetric(
          name: 'ai.latency.totalMs',
          value: 12,
          attributes: {'secret': 'private'},
        ),
      );
      expect(redactions, 1);
      await expectLater(sink.flush(), throwsA(isA<HttpException>()));
      await sink.flush();
      expect(requests, hasLength(2));
      expect(
        redactions,
        1,
        reason: 'Export and retry must not rerun user redaction',
      );
      expect(
        requests[1],
        requests[0],
        reason:
            'Retries retain the original observation timestamp and redacted data',
      );
    },
  );

  test('redactor failures omit only the failing attribute', () async {
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      await request.response.close();
    });
    final diagnostics = <Object>[];
    var redactions = 0;
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      redactAttribute: (key, value) {
        redactions++;
        if (key == 'bad') throw StateError('cannot redact');
        return 'sanitized-$value';
      },
      onDiagnostic: (error, [_]) => diagnostics.add(error),
    );
    addTearDown(() async {
      await sink.dispose();
      await server.close(force: true);
    });

    sink.record(
      const TelemetryMetric(
        name: 'ai.metric',
        value: 1,
        attributes: {'good': 'value', 'bad': 'secret'},
      ),
    );
    await sink.flush();

    expect(redactions, 2);
    expect(diagnostics, isNotEmpty);
    final payload = requests.single;
    final dataPoint = _dataPoints(payload).single as Map;
    final attributes = dataPoint['attributes'] as List;
    expect(attributes, hasLength(1));
    expect((attributes.single as Map)['key'], 'good');
    expect(
      ((attributes.single as Map)['value'] as Map)['stringValue'],
      'sanitized-value',
    );
  });

  test('same metric names share one OTLP metric with ordered points', () async {
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      await request.response.close();
    });
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      batchSize: 3,
    );
    addTearDown(() async {
      await sink.dispose();
      await server.close(force: true);
    });

    final beforeRecording = DateTime.now().microsecondsSinceEpoch * 1000;
    sink.record(const TelemetryMetric(name: 'same', value: 1));
    sink.record(const TelemetryMetric(name: 'other', value: 2));
    sink.record(const TelemetryMetric(name: 'same', value: 3));
    final afterRecording = DateTime.now().microsecondsSinceEpoch * 1000;
    await sink.flush();

    final metrics = _metrics(requests.single);
    expect(metrics.map((metric) => (metric as Map)['name']), ['same', 'other']);
    final same = metrics.first as Map;
    final points = same['gauge']['dataPoints'] as List;
    expect(points, hasLength(2));
    expect(points.map((point) => (point as Map)['asDouble']), [1.0, 3.0]);
    final timestamps = points
        .map((point) => int.parse((point as Map)['timeUnixNano'] as String))
        .toList();
    expect(
      timestamps,
      everyElement(inInclusiveRange(beforeRecording, afterRecording)),
    );
    expect(timestamps.first, lessThanOrEqualTo(timestamps.last));
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

List<Object?> _metrics(Map<String, dynamic> payload) {
  final resourceMetrics = payload['resourceMetrics'] as List;
  final scopeMetrics = (resourceMetrics.single as Map)['scopeMetrics'] as List;
  return ((scopeMetrics.single as Map)['metrics'] as List).cast<Object?>();
}

List<Object?> _dataPoints(Map<String, dynamic> payload) {
  final metric = _metrics(payload).single as Map;
  return ((metric['gauge'] as Map)['dataPoints'] as List).cast<Object?>();
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
  HttpHeaders get headers => _TestHeaders();

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

class _TestHeaders implements HttpHeaders {
  @override
  set contentType(ContentType? value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
