import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_telemetry/ai_sdk_telemetry.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> payloads;
  Completer<void>? requestStarted;
  Completer<void>? releaseResponse;
  int responseStatus = HttpStatus.ok;

  setUp(() async {
    payloads = [];
    requestStarted = null;
    releaseResponse = null;
    responseStatus = HttpStatus.ok;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      payloads.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      final started = requestStarted;
      if (started != null && !started.isCompleted) {
        started.complete();
      }
      final release = releaseResponse;
      if (release != null) await release.future;
      request.response.statusCode = request.uri.path == '/missing'
          ? HttpStatus.badRequest
          : responseStatus;
      await request.response.close();
    });
  });

  tearDown(() async {
    final release = releaseResponse;
    if (release != null && !release.isCompleted) release.complete();
    await server.close(force: true);
  });

  test('exports typed metrics as OTLP HTTP JSON', () async {
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      resourceAttributes: {'service.name': 'test'},
    );
    sink.record(
      const TelemetryMetric(
        name: 'ai.latency.totalMs',
        value: 12.5,
        attributes: {
          'ai.model.provider': 'fake',
          'ai.operation': 'generateText',
        },
      ),
    );
    await sink.flush();
    expect(payloads, hasLength(1));
    final resourceMetrics = payloads.single['resourceMetrics'] as List;
    final metrics =
        (((resourceMetrics.single as Map)['scopeMetrics'] as List).single
                as Map)['metrics']
            as List;
    expect((metrics.single as Map)['name'], 'ai.latency.totalMs');
    expect((metrics.single as Map)['gauge'], isNotNull);
    expect((metrics.single as Map)['sum'], isNull);
    expect(sink.pendingCount, 0);
    await sink.dispose();
  });

  test('redacts attributes before export', () async {
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      redactAttribute: (key, value) => key == 'secret' ? '[REDACTED]' : value,
    );
    sink.record(
      const TelemetryMetric(
        name: 'ai.metric',
        value: 1,
        attributes: {'secret': 'token'},
      ),
    );
    await sink.flush();
    final metrics =
        (((payloads.single['resourceMetrics'] as List).single
                        as Map)['scopeMetrics']
                    as List)
                .single
            as Map;
    final dataPoint =
        ((((metrics['metrics'] as List).single as Map)['gauge']
                        as Map)['dataPoints']
                    as List)
                .single
            as Map;
    expect(
      dataPoint['attributes'],
      contains(
        predicate<Map>(
          (attribute) => attribute['value']['stringValue'] == '[REDACTED]',
        ),
      ),
    );
    await sink.dispose();
  });

  test('bounds buffering and omits unsupported values', () async {
    final diagnostics = <Object>[];
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      maxBufferSize: 2,
      batchSize: 2,
      onDiagnostic: (error, [_]) => diagnostics.add(error),
    );
    sink.record(
      TelemetryMetric(name: 'old', value: 1, attributes: {'bad': Object()}),
    );
    sink.record(const TelemetryMetric(name: 'new', value: 2));
    sink.record(const TelemetryMetric(name: 'latest', value: 3));
    sink.record(const TelemetryMetric(name: 'invalid', value: double.nan));
    expect(sink.pendingCount, lessThanOrEqualTo(2));
    expect(diagnostics, isNotEmpty);
    await sink.flush();
    await sink.dispose();
  });

  test('export errors are diagnosed and leave metrics queued', () async {
    final diagnostics = <Object>[];
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/missing'),
      onDiagnostic: (error, [_]) => diagnostics.add(error),
    );
    sink.record(const TelemetryMetric(name: 'ai.failure', value: 1));
    await expectLater(sink.flush(), throwsA(isA<HttpException>()));
    expect(diagnostics, isNotEmpty);
    expect(sink.pendingCount, 1);
    await sink.dispose();
  });

  test('detaches an in-flight batch before records arrive', () async {
    requestStarted = Completer<void>();
    releaseResponse = Completer<void>();
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      maxBufferSize: 3,
      batchSize: 1,
    );
    sink.record(const TelemetryMetric(name: 'first', value: 1));
    await requestStarted!.future;
    sink.record(const TelemetryMetric(name: 'second', value: 2));
    sink.record(const TelemetryMetric(name: 'third', value: 3));
    sink.record(const TelemetryMetric(name: 'fourth', value: 4));
    expect(sink.pendingCount, 3);
    releaseResponse!.complete();
    await sink.flush();
    expect(payloads, hasLength(3));
    expect(payloads.map((payload) => _firstMetricName(payload)), [
      'first',
      'third',
      'fourth',
    ]);
    await sink.dispose();
  });

  test('deadline aborts a stalled response and preserves the batch', () async {
    requestStarted = Completer<void>();
    releaseResponse = Completer<void>();
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
    );
    sink.record(const TelemetryMetric(name: 'stalled', value: 1));
    final flushing = sink.flush(deadline: const Duration(milliseconds: 30));
    await requestStarted!.future;
    await expectLater(flushing, throwsA(isA<TimeoutException>()));
    expect(sink.pendingCount, 1);
    await sink.dispose(deadline: const Duration(milliseconds: 30));
  });

  test(
    'expired flush deadline restores a batch before opening a request',
    () async {
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      );
      sink.record(const TelemetryMetric(name: 'expired', value: 1));
      await expectLater(
        sink.flush(deadline: const Duration(microseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      expect(sink.pendingCount, 1);
      expect(payloads, isEmpty);
      await sink.dispose();
    },
  );

  test('restores a failed detached batch ahead of newer records', () async {
    requestStarted = Completer<void>();
    releaseResponse = Completer<void>();
    responseStatus = HttpStatus.badRequest;
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      maxBufferSize: 3,
      batchSize: 1,
    );
    sink.record(const TelemetryMetric(name: 'first', value: 1));
    await requestStarted!.future;
    sink.record(const TelemetryMetric(name: 'second', value: 2));
    sink.record(const TelemetryMetric(name: 'third', value: 3));
    releaseResponse!.complete();
    await expectLater(sink.flush(), throwsA(isA<HttpException>()));
    expect(sink.pendingCount, 3);
    responseStatus = HttpStatus.ok;
    await sink.flush();
    expect(_firstMetricName(payloads[1]), 'first');
    await sink.dispose();
  });

  test('dispose closes admission while an export is pending', () async {
    requestStarted = Completer<void>();
    releaseResponse = Completer<void>();
    final diagnostics = <Object>[];
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      onDiagnostic: (error, [_]) => diagnostics.add(error),
    );
    sink.record(const TelemetryMetric(name: 'kept', value: 1));
    final flushing = sink.flush(deadline: const Duration(seconds: 10));
    await requestStarted!.future;
    final disposing = sink.dispose(deadline: const Duration(milliseconds: 30));
    sink.record(const TelemetryMetric(name: 'late', value: 2));
    await disposing;
    await expectLater(flushing, throwsA(anything));
    expect(sink.pendingCount, 1);
    expect(diagnostics, isNotEmpty);
  });

  test(
    'snapshots mutable inputs and omits cyclic or non-finite values',
    () async {
      final values = <Object?>['before'];
      final cyclic = <Object?>[null];
      cyclic[0] = cyclic;
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      );
      sink.record(
        TelemetryMetric(
          name: 'snapshot',
          value: 1,
          attributes: {
            'values': values,
            'cyclic': cyclic,
            'infinite': double.infinity,
          },
        ),
      );
      values[0] = 'after';
      await sink.flush();
      final payload = payloads.single;
      final attrs = _firstDataPointAttributes(payload);
      expect(attrs.any((attribute) => attribute['key'] == 'cyclic'), isFalse);
      expect(attrs.any((attribute) => attribute['key'] == 'infinite'), isFalse);
      final valuesAttribute = attrs.firstWhere(
        (attribute) => attribute['key'] == 'values',
      );
      expect(
        valuesAttribute['value']['arrayValue']['values'][0]['stringValue'],
        'before',
      );
      await sink.dispose();
    },
  );

  test('rejects oversized metrics before retaining their payload', () async {
    final diagnostics = <Object>[];
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      maxPayloadBytes: 256,
      onDiagnostic: (error, [_]) => diagnostics.add(error),
    );
    sink.record(
      TelemetryMetric(
        name: 'oversized',
        value: 1,
        attributes: {'large': 'x' * 2000},
      ),
    );
    expect(sink.pendingCount, 0);
    expect(diagnostics, isNotEmpty);
    await sink.dispose();
  });

  test('rejects invalid production bounds and deadlines', () async {
    expect(
      () => OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        maxBufferSize: 0,
      ),
      throwsArgumentError,
    );
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
    );
    expect(() => sink.flush(deadline: Duration.zero), throwsArgumentError);
    await sink.dispose();
  });

  test('rejects invalid endpoints and batch bounds', () {
    expect(
      () => OtlpHttpMetricSink(endpoint: Uri.parse('fixture.test/metrics')),
      throwsArgumentError,
    );
    expect(
      () => OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        maxBufferSize: 1,
        batchSize: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        maxAttributes: 0,
      ),
      throwsArgumentError,
    );
  });

  test(
    'record after dispose is diagnosed and flush remains harmless',
    () async {
      final diagnostics = <Object>[];
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        onDiagnostic: (error, [_]) => diagnostics.add(error),
      );
      await sink.dispose();
      sink.record(const TelemetryMetric(name: 'late', value: 1));
      await sink.flush();
      await sink.dispose();
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, isA<StateError>());
    },
  );

  test('concurrent flushes share one in-flight operation', () async {
    requestStarted = Completer<void>();
    releaseResponse = Completer<void>();
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      batchSize: 1,
    );
    sink.record(const TelemetryMetric(name: 'one', value: 1));
    await requestStarted!.future;
    final first = sink.flush();
    final second = sink.flush();
    expect(identical(first, second), isTrue);
    releaseResponse!.complete();
    await first;
    await sink.dispose();
  });

  test(
    'drops newest metric when only an in-flight batch fills the buffer',
    () async {
      requestStarted = Completer<void>();
      releaseResponse = Completer<void>();
      final diagnostics = <Object>[];
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        maxBufferSize: 1,
        batchSize: 1,
        onDiagnostic: (error, [_]) => diagnostics.add(error),
      );
      sink.record(const TelemetryMetric(name: 'first', value: 1));
      await requestStarted!.future;
      sink.record(const TelemetryMetric(name: 'dropped', value: 2));
      expect(sink.pendingCount, 1);
      expect(diagnostics, contains(isA<StateError>()));
      releaseResponse!.complete();
      await sink.flush();
      await sink.dispose();
    },
  );

  test(
    'limits nested OTLP attribute values and diagnoses the omission',
    () async {
      final diagnostics = <Object>[];
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        maxListLength: 1,
        onDiagnostic: (error, [_]) => diagnostics.add(error),
      );
      sink.record(
        const TelemetryMetric(
          name: 'nested',
          value: 1,
          attributes: {
            'value': [
              ['nested'],
            ],
          },
        ),
      );
      await sink.flush();
      final attributes = _firstDataPointAttributes(payloads.single);
      expect(attributes, isEmpty);
      expect(diagnostics, contains(isA<StateError>()));
      await sink.dispose();
    },
  );

  test('bounds attributes and contains diagnostic callback failures', () async {
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
      maxAttributes: 1,
      maxListLength: 1,
      redactAttribute: (key, value) {
        if (key == 'bad') throw StateError('redactor failed');
        return value;
      },
      onDiagnostic: (error, [_]) => throw StateError('diagnostic failed'),
    );
    sink.record(
      const TelemetryMetric(
        name: 'bounded',
        value: 1,
        attributes: {
          'bad': 'omitted',
          'list': [1, 2],
          'kept': true,
        },
      ),
    );
    await sink.flush();
    expect(_firstDataPointAttributes(payloads.single), isEmpty);
    await sink.dispose();
  });

  test(
    'valid observations split into payloads within the byte limit',
    () async {
      final splitServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => splitServer.close(force: true));
      final sizes = <int>[];
      final received = <Object?>[];
      splitServer.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        sizes.add(bytes.length);
        final payload = jsonDecode(utf8.decode(bytes)) as Map;
        final resource = (payload['resourceMetrics'] as List).single as Map;
        final scope = (resource['scopeMetrics'] as List).single as Map;
        received.addAll(scope['metrics'] as List);
        await request.response.close();
      });
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${splitServer.port}/v1/metrics'),
        maxPayloadBytes: 800,
        batchSize: 4,
      );
      addTearDown(sink.dispose);
      for (var index = 0; index < 3; index++) {
        sink.record(TelemetryMetric(name: '${'x' * 200}$index', value: index));
      }
      expect(sink.pendingCount, 3);
      await sink.flush();
      expect(received, hasLength(3));
      expect(sizes, everyElement(lessThanOrEqualTo(800)));
      expect(sink.pendingCount, 0);
    },
  );

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
      final identityServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      identityServer.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.statusCode = requests.length == 1 ? 503 : 200;
        await request.response.close();
      });
      var redactions = 0;
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse(
          'http://127.0.0.1:${identityServer.port}/v1/metrics',
        ),
        redactAttribute: (key, value) {
          redactions++;
          return '[redacted-$redactions]';
        },
      );
      addTearDown(() async {
        await sink.dispose();
        await identityServer.close(force: true);
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
    final identityServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    identityServer.listen((request) async {
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      await request.response.close();
    });
    final diagnostics = <Object>[];
    var redactions = 0;
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${identityServer.port}/v1/metrics'),
      redactAttribute: (key, value) {
        redactions++;
        if (key == 'bad') throw StateError('cannot redact');
        return 'sanitized-$value';
      },
      onDiagnostic: (error, [_]) => diagnostics.add(error),
    );
    addTearDown(() async {
      await sink.dispose();
      await identityServer.close(force: true);
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
    final attributes = _firstDataPointAttributes(requests.single);
    expect(attributes, hasLength(1));
    expect((attributes.single as Map)['key'], 'good');
    expect(
      ((attributes.single as Map)['value'] as Map)['stringValue'],
      'sanitized-value',
    );
  });

  test('same metric names share one OTLP metric with ordered points', () async {
    final requests = <Map<String, dynamic>>[];
    final identityServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    identityServer.listen((request) async {
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      await request.response.close();
    });
    final sink = OtlpHttpMetricSink(
      endpoint: Uri.parse('http://127.0.0.1:${identityServer.port}/v1/metrics'),
      batchSize: 3,
    );
    addTearDown(() async {
      await sink.dispose();
      await identityServer.close(force: true);
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
}

String _firstMetricName(Map<String, dynamic> payload) {
  return (_metrics(payload).single as Map)['name'] as String;
}

List<Object?> _metrics(Map<String, dynamic> payload) {
  final resourceMetrics = payload['resourceMetrics'] as List;
  final scopeMetrics = (resourceMetrics.single as Map)['scopeMetrics'] as List;
  return ((scopeMetrics.single as Map)['metrics'] as List).cast<Object?>();
}

List<Map<String, dynamic>> _firstDataPointAttributes(
  Map<String, dynamic> payload,
) {
  final gauge = (_metrics(payload).single as Map)['gauge'] as Map;
  final points = gauge['dataPoints'] as List;
  final attributes = (points.single as Map)['attributes'] as List;
  return attributes
      .map((attribute) => (attribute as Map).cast<String, dynamic>())
      .toList(growable: false);
}
