// Verification checks for package:ai_sdk_telemetry.
// See features/ai_sdk_telemetry.md.
//
// An app wires OtlpHttpMetricSink into TelemetrySettings.metricSink, runs
// generateText or streamText, and the sink POSTs OTLP/HTTP JSON gauges to a
// collector. Each check starts a fixture collector with ctx.server and, where
// real SDK calls matter, a second fixture server that plays the model API.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_telemetry/ai_sdk_telemetry.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_telemetry';

/// One exported OTLP data point.
class _Point {
  _Point(this.value, this.attributes, this.timeUnixNano);
  final double value;
  final Map<String, Object?> attributes;
  final String timeUnixNano;
}

/// What a collector received, flattened from one OTLP request body.
class _Export {
  _Export(this.resource, this.scope, this.metrics);
  final Map<String, Object?> resource;
  final String? scope;

  /// Metric name to its data points.
  final Map<String, List<_Point>> metrics;
}

Object? _anyValue(Map value) {
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('boolValue')) return value['boolValue'];
  if (value.containsKey('intValue')) return 'int:${value['intValue']}';
  if (value.containsKey('doubleValue')) return value['doubleValue'];
  if (value.containsKey('arrayValue')) {
    return [
      for (final v in (value['arrayValue'] as Map)['values'] as List)
        _anyValue(v as Map),
    ];
  }
  return 'unknown:$value';
}

Map<String, Object?> _attributeMap(Object? list) => {
  for (final a in (list as List? ?? const []))
    (a as Map)['key'] as String: _anyValue(a['value'] as Map),
};

_Export _parse(FixtureRequest request) {
  final root = request.jsonObject;
  final resourceMetrics = (root['resourceMetrics'] as List).single as Map;
  final scopeMetrics = (resourceMetrics['scopeMetrics'] as List).single as Map;
  final metrics = <String, List<_Point>>{};
  for (final metric in scopeMetrics['metrics'] as List) {
    final map = metric as Map;
    final gauge = map['gauge'] as Map;
    metrics[map['name'] as String] = [
      for (final p in gauge['dataPoints'] as List)
        _Point(
          ((p as Map)['asDouble'] as num).toDouble(),
          _attributeMap(p['attributes']),
          p['timeUnixNano'] as String,
        ),
    ];
  }
  return _Export(
    _attributeMap((resourceMetrics['resource'] as Map)['attributes']),
    (scopeMetrics['scope'] as Map)['name'] as String?,
    metrics,
  );
}

/// Every metric name and its points across all POSTs the collector received.
Map<String, List<_Point>> _allMetrics(FixtureServer collector) {
  final merged = <String, List<_Point>>{};
  for (final request in collector.requests) {
    _parse(request).metrics.forEach(
      (name, points) => merged.putIfAbsent(name, () => []).addAll(points),
    );
  }
  return merged;
}

/// A collector whose response status the check can change.
class _Collector {
  int status = 200;
  Duration? stall;
}

Future<FixtureServer> _collector(CheckContext ctx, _Collector control) =>
    ctx.server((request) async {
      final stall = control.stall;
      if (stall != null) await Future<void>.delayed(stall);
      return FixtureResponse.json(<String, Object?>{}, status: control.status);
    });

OtlpHttpMetricSink _sink(
  FixtureServer collector, {
  Map<String, String> headers = const {},
  Map<String, Object?> resourceAttributes = const {},
  int maxBufferSize = 128,
  int batchSize = 32,
  int maxPayloadBytes = 64 * 1024,
  int maxAttributes = 64,
  Object? Function(String key, Object? value)? redactAttribute,
  void Function(Object error, [StackTrace? stackTrace])? onDiagnostic,
}) => OtlpHttpMetricSink(
  endpoint: Uri.parse(collector.url('/v1/metrics')),
  headers: headers,
  resourceAttributes: resourceAttributes,
  maxBufferSize: maxBufferSize,
  batchSize: batchSize,
  maxPayloadBytes: maxPayloadBytes,
  maxAttributes: maxAttributes,
  redactAttribute: redactAttribute,
  onDiagnostic: onDiagnostic,
);

OpenAICompatibleChatLanguageModel _model(
  CheckContext ctx,
  FixtureServer server,
) {
  final baseUrl = server.url('/v1');
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  ctx.onCleanup(() async => dio.close(force: true));
  return OpenAICompatibleChatLanguageModel(
    modelId: 'verify-model',
    config: OpenAICompatibleConfig(
      provider: 'verify-compat',
      baseUrl: baseUrl,
      client: dio,
      headers: () => {'Authorization': 'Bearer verify-key'},
    ),
  );
}

Map<String, Object?> _completion({String content = 'Hello.'}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': 'stop',
    },
  ],
  'usage': {'prompt_tokens': 11, 'completion_tokens': 7, 'total_tokens': 18},
};

Map<String, Object?> _chunk(Map<String, Object?> delta, {String? finish}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

void _expectHasMetric(
  CheckContext ctx,
  Map<String, List<_Point>> metrics,
  String name,
) {
  ctx.expect(
    metrics.containsKey(name),
    'metric $name not exported; got ${metrics.keys.toList()}',
  );
}

final checks = PackageChecks(_package, [
  Check(
    id: 'generate-text-metrics',
    feature: 'otlp-export',
    description:
        'After a real generateText call with telemetry enabled, flush POSTs '
        'OTLP JSON to /v1/metrics with the SDK metric names, gauge values, '
        'model and operation attributes, custom headers and resource '
        'attributes.',
    run: (ctx) async {
      final control = _Collector();
      final collector = await _collector(ctx, control);
      final modelServer = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'Hello metrics.')),
      );
      final sink = _sink(
        collector,
        headers: {'Authorization': 'Bearer collector-key'},
        resourceAttributes: {'service.name': 'verify-app', 'service.build': 7},
      );
      ctx.onCleanup(sink.dispose);
      final result = await generateText(
        model: _model(ctx, modelServer),
        prompt: 'Say hello.',
        maxRetries: 0,
        telemetry: TelemetrySettings(
          isEnabled: true,
          functionId: 'verify-fn',
          metadata: {'tenant': 'acme'},
          metricSink: sink,
        ),
      );
      ctx.expectEquals(result.text, 'Hello metrics.', 'generateText text');
      ctx.expectEquals(collector.requests.length, 0, 'export before flush');
      ctx.observe('pendingBeforeFlush', sink.pendingCount);
      await sink.flush();
      ctx.expectEquals(sink.pendingCount, 0, 'pending after flush');
      final request = ctx.singleRequest(collector, '/v1/metrics');
      ctx.expectEquals(request.method, 'POST', 'method');
      ctx.expect(
        (request.headers['content-type'] ?? '').startsWith('application/json'),
        'content-type: ${request.headers['content-type']}',
      );
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer collector-key',
        'collector auth header',
      );
      final export = _parse(request);
      ctx.observe('metricNames', export.metrics.keys.toList());
      ctx.expectEquals(export.scope, 'ai_sdk_dart', 'scope name');
      ctx.expectEquals(
        export.resource['service.name'],
        'verify-app',
        'service',
      );
      ctx.expectEquals(
        export.resource['service.build'],
        'int:7',
        'int resource attribute',
      );
      for (final name in [
        AiTelemetryMetrics.totalMs,
        AiTelemetryMetrics.stepCount,
        AiTelemetryMetrics.toolCount,
        AiTelemetryMetrics.retryCount,
        AiTelemetryMetrics.usageKnown,
        AiTelemetryMetrics.success,
      ]) {
        _expectHasMetric(ctx, export.metrics, name);
      }
      ctx.expectEquals(
        export.metrics[AiTelemetryMetrics.success]!.single.value,
        1.0,
        'ai.operation.success value',
      );
      ctx.expectEquals(
        export.metrics[AiTelemetryMetrics.stepCount]!.single.value,
        1.0,
        'ai.step.count value',
      );
      ctx.expectEquals(
        export.metrics[AiTelemetryMetrics.toolCount]!.single.value,
        0.0,
        'ai.tool.count value',
      );
      ctx.expectEquals(
        export.metrics[AiTelemetryMetrics.usageKnown]!.single.value,
        1.0,
        'ai.usage.known value',
      );
      final total = export.metrics[AiTelemetryMetrics.totalMs]!.single;
      ctx.expect(total.value >= 0, 'total latency is negative');
      ctx.expectEquals(
        total.attributes[AiTelemetryKeys.operationStatus],
        'success',
        'status attribute on totalMs',
      );
      ctx.expectEquals(
        total.attributes[AiTelemetryKeys.modelProvider],
        'verify-compat',
        'ai.model.provider',
      );
      ctx.expectEquals(
        total.attributes[AiTelemetryKeys.modelId],
        'verify-model',
        'ai.model.id',
      );
      ctx.expectEquals(
        total.attributes[AiTelemetryKeys.operation],
        'generateText',
        'ai.operation',
      );
      ctx.expectEquals(
        total.attributes['tenant'],
        'acme',
        'metadata attribute',
      );
      ctx.expectEquals(
        total.attributes['ai.metric.name'],
        AiTelemetryMetrics.totalMs,
        'ai.metric.name attribute',
      );
      ctx.expect(
        RegExp(r'^\d{19}$').hasMatch(total.timeUnixNano),
        'timeUnixNano is not a 19-digit nano string: ${total.timeUnixNano}',
      );
      final wire = request.bodyText;
      ctx.expect(
        !wire.contains('Say hello.') && !wire.contains('Hello metrics.'),
        'prompt or output leaked into the metrics payload',
      );
      ctx.expect(!wire.contains('"sum"'), 'counters must not be exported');
    },
  ),
  Check(
    id: 'stream-text-metrics',
    feature: 'otlp-export',
    description:
        'A streamText call exports the same content-free gauges with '
        'ai.operation=streamText once the stream has finished.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final modelServer = await ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          _chunk({'content': 'Streaming '}),
          _chunk({'content': 'metrics.'}),
          _chunk({}, finish: 'stop'),
        ], done: true),
      );
      final sink = _sink(collector);
      ctx.onCleanup(sink.dispose);
      final result = await streamText(
        model: _model(ctx, modelServer),
        prompt: 'Stream something.',
        maxRetries: 0,
        telemetry: TelemetrySettings(isEnabled: true, metricSink: sink),
      );
      final text = await result.text;
      ctx.expectEquals(text, 'Streaming metrics.', 'streamed text');
      // The terminal metrics land a moment after the text future resolves.
      Map<String, List<_Point>> metrics = {};
      for (var i = 0; i < 100; i++) {
        await sink.flush();
        metrics = _allMetrics(collector);
        if (metrics.containsKey(AiTelemetryMetrics.success)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      ctx.observe('metricNames', metrics.keys.toList());
      ctx.note(
        'streamText records its terminal metrics after result.text resolves, '
        'so the check flushes until ai.operation.success arrives.',
      );
      for (final name in [
        AiTelemetryMetrics.firstMeaningfulMs,
        AiTelemetryMetrics.totalMs,
        AiTelemetryMetrics.success,
        AiTelemetryMetrics.stepCount,
      ]) {
        _expectHasMetric(ctx, metrics, name);
      }
      ctx.expectEquals(
        metrics[AiTelemetryMetrics.success]!.single.attributes[AiTelemetryKeys
            .operation],
        'streamText',
        'ai.operation',
      );
      ctx.expectEquals(
        metrics[AiTelemetryMetrics.success]!.single.value,
        1.0,
        'success value',
      );
    },
  ),
  Check(
    id: 'failed-call-metrics',
    feature: 'otlp-export',
    description:
        'A generateText call that fails at the provider exports '
        'ai.operation.failure and a totalMs point with status failure.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final modelServer = await ctx.server(
        (_) => FixtureResponse.json({
          'error': {'message': 'Incorrect API key provided.'},
        }, status: 401),
      );
      final sink = _sink(collector);
      ctx.onCleanup(sink.dispose);
      await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: _model(ctx, modelServer),
          prompt: 'hi',
          maxRetries: 0,
          telemetry: TelemetrySettings(isEnabled: true, metricSink: sink),
        ),
        'generateText',
      );
      await sink.flush();
      final metrics = _allMetrics(collector);
      ctx.observe('metricNames', metrics.keys.toList());
      _expectHasMetric(ctx, metrics, AiTelemetryMetrics.failure);
      ctx.expectEquals(
        metrics[AiTelemetryMetrics.failure]!.single.value,
        1.0,
        'failure value',
      );
      ctx.expectEquals(
        metrics[AiTelemetryMetrics.totalMs]!.single.attributes[AiTelemetryKeys
            .operationStatus],
        'failure',
        'status on totalMs',
      );
      ctx.expect(
        !metrics.containsKey(AiTelemetryMetrics.success),
        'success metric exported for a failed call',
      );
    },
  ),
  Check(
    id: 'disabled-telemetry-exports-nothing',
    feature: 'otlp-export',
    description:
        'With TelemetrySettings.isEnabled false the sink receives nothing, '
        'so a flush makes no request.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final modelServer = await ctx.server(
        (_) => FixtureResponse.json(_completion()),
      );
      final sink = _sink(collector);
      ctx.onCleanup(sink.dispose);
      await generateText(
        model: _model(ctx, modelServer),
        prompt: 'hi',
        maxRetries: 0,
        telemetry: TelemetrySettings(isEnabled: false, metricSink: sink),
      );
      ctx.expectEquals(sink.pendingCount, 0, 'pending metrics');
      await sink.flush();
      ctx.expectEquals(collector.requests.length, 0, 'collector requests');
    },
  ),
  Check(
    id: 'attribute-encoding',
    feature: 'otlp-attributes',
    description:
        'Attributes export as typed OTLP values (string, bool, int, double, '
        'list); unsupported, cyclic and non-finite values are omitted with a '
        'diagnostic; maxAttributes bounds each data point.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final diagnostics = <String>[];
      final cycle = <Object?>[];
      cycle.add(cycle);
      final sink = _sink(
        collector,
        maxAttributes: 6,
        onDiagnostic: (error, [_]) => diagnostics.add('$error'),
      );
      ctx.onCleanup(sink.dispose);
      sink.record(
        TelemetryMetric(
          name: 'verify.attributes',
          value: 2.5,
          attributes: {
            'a.string': 'text',
            'b.bool': true,
            'c.int': 42,
            'd.double': 1.25,
            'e.list': ['x', 2, false],
            'f.object': Object(),
            'g.nan': double.nan,
            'h.cycle': cycle,
            'i.over.limit': 'dropped by maxAttributes',
          },
        ),
      );
      await sink.flush();
      final point = _parse(
        ctx.singleRequest(collector, '/v1/metrics'),
      ).metrics['verify.attributes']!.single;
      ctx.observe('attributes', point.attributes);
      ctx.observe('diagnostics', diagnostics);
      ctx.expectEquals(point.value, 2.5, 'asDouble value');
      ctx.expectEquals(point.attributes['a.string'], 'text', 'string');
      ctx.expectEquals(point.attributes['b.bool'], true, 'bool');
      ctx.expectEquals(point.attributes['c.int'], 'int:42', 'int');
      ctx.expectEquals(point.attributes['d.double'], 1.25, 'double');
      ctx.expectEquals(point.attributes['e.list'], [
        'x',
        'int:2',
        false,
      ], 'list');
      for (final key in ['f.object', 'g.nan', 'h.cycle', 'i.over.limit']) {
        ctx.expect(
          !point.attributes.containsKey(key),
          'attribute $key should not be exported',
        );
      }
      final raw = ctx.singleRequest(collector, '/v1/metrics').bodyText;
      ctx.expect(raw.contains('"intValue":"42"'), 'intValue is not a string');
      ctx.expect(raw.contains('"asDouble":2.5'), 'asDouble missing');
    },
  ),
  Check(
    id: 'redaction-before-export',
    feature: 'otlp-redaction',
    description:
        'redactAttribute rewrites metric and resource attribute values once, '
        'before they are retained, so the collector never sees the original.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final seenKeys = <String>[];
      final sink = _sink(
        collector,
        resourceAttributes: {'service.name': 'app', 'api.token': 'rt-secret'},
        redactAttribute: (key, value) {
          seenKeys.add(key);
          return key.contains('token') || key == 'user.email'
              ? '[REDACTED]'
              : value;
        },
      );
      ctx.onCleanup(sink.dispose);
      sink.record(
        const TelemetryMetric(
          name: 'verify.redact',
          value: 1,
          attributes: {
            'user.email': 'a@example.test',
            'plan': 'pro',
            'api.token': 'tok-123',
          },
        ),
      );
      await sink.flush();
      final request = ctx.singleRequest(collector, '/v1/metrics');
      final export = _parse(request);
      final point = export.metrics['verify.redact']!.single;
      ctx.observe('seenKeys', seenKeys);
      ctx.observe('pointAttributes', point.attributes);
      ctx.expectEquals(point.attributes['user.email'], '[REDACTED]', 'email');
      ctx.expectEquals(point.attributes['api.token'], '[REDACTED]', 'token');
      ctx.expectEquals(point.attributes['plan'], 'pro', 'plan');
      ctx.expectEquals(export.resource['api.token'], '[REDACTED]', 'resource');
      ctx.expectEquals(export.resource['service.name'], 'app', 'service');
      for (final secret in ['a@example.test', 'tok-123', 'rt-secret']) {
        ctx.expect(!request.bodyText.contains(secret), 'payload leaks $secret');
      }
    },
  ),
  Check(
    id: 'batching-and-grouping',
    feature: 'otlp-batching',
    description:
        'Observations with one name share one OTLP metric with several data '
        'points, and reaching batchSize exports without an explicit flush.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final sink = _sink(collector, batchSize: 3, maxBufferSize: 10);
      ctx.onCleanup(sink.dispose);
      sink.record(const TelemetryMetric(name: 'verify.group', value: 1));
      sink.record(const TelemetryMetric(name: 'verify.other', value: 9));
      ctx.expectEquals(collector.requests.length, 0, 'requests below batch');
      sink.record(const TelemetryMetric(name: 'verify.group', value: 2));
      // The third record reaches batchSize and starts an export on its own.
      for (var i = 0; i < 100 && collector.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final request = ctx.singleRequest(collector, '/v1/metrics');
      final export = _parse(request);
      ctx.observe('metrics', {
        for (final e in export.metrics.entries)
          e.key: [for (final p in e.value) p.value],
      });
      ctx.expectEquals(
        [for (final p in export.metrics['verify.group']!) p.value],
        [1.0, 2.0],
        'grouped data points in record order',
      );
      ctx.expectEquals(
        export.metrics['verify.other']!.single.value,
        9.0,
        'other',
      );
      ctx.expectEquals(export.metrics.length, 2, 'distinct metrics');
      await sink.flush();
      ctx.expectEquals(sink.pendingCount, 0, 'pending after export');
      ctx.expectEquals(collector.requests.length, 1, 'no extra requests');
    },
  ),
  Check(
    id: 'collector-5xx-retains-and-recovers',
    feature: 'otlp-failure',
    description:
        'A 503 from the collector makes flush throw HttpException, reports a '
        'diagnostic and keeps the metrics; after the collector recovers, a '
        'later flush delivers them with their original timestamps.',
    run: (ctx) async {
      final control = _Collector()..status = 503;
      final collector = await _collector(ctx, control);
      final diagnostics = <String>[];
      final sink = _sink(
        collector,
        onDiagnostic: (error, [_]) => diagnostics.add('$error'),
      );
      ctx.onCleanup(sink.dispose);
      sink.record(const TelemetryMetric(name: 'verify.retained', value: 5));
      final error = await ctx.expectThrows<HttpException>(
        () => sink.flush(),
        'flush against 503',
      );
      ctx.expect(error.message.contains('503'), 'message lacks 503: $error');
      ctx.expectEquals(sink.pendingCount, 1, 'pending after failed flush');
      ctx.expect(
        diagnostics.any((d) => d.contains('503')),
        'no 503 diagnostic in $diagnostics',
      );
      ctx.observe('diagnostics', diagnostics);
      final firstTime = _parse(
        collector.requests.single,
      ).metrics['verify.retained']!.single.timeUnixNano;
      control.status = 200;
      await sink.flush();
      ctx.expectEquals(sink.pendingCount, 0, 'pending after recovery');
      ctx.expectEquals(collector.requests.length, 2, 'attempts');
      final retried = _parse(
        collector.requests.last,
      ).metrics['verify.retained']!.single;
      ctx.expectEquals(retried.value, 5.0, 'retried value');
      ctx.expectEquals(
        retried.timeUnixNano,
        firstTime,
        'retry keeps the original observation time',
      );
    },
  ),
  Check(
    id: 'generation-survives-collector-failure',
    feature: 'otlp-failure',
    description:
        'generateText still returns its result when the collector answers '
        '500 on the automatic export; the failure reaches onDiagnostic only.',
    run: (ctx) async {
      final control = _Collector()..status = 500;
      final collector = await _collector(ctx, control);
      final modelServer = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'Still fine.')),
      );
      final diagnostics = <String>[];
      // batchSize 1 makes every recorded metric start an export immediately.
      final sink = _sink(
        collector,
        batchSize: 1,
        onDiagnostic: (error, [_]) => diagnostics.add('$error'),
      );
      ctx.onCleanup(sink.dispose);
      final result = await generateText(
        model: _model(ctx, modelServer),
        prompt: 'hi',
        maxRetries: 0,
        telemetry: TelemetrySettings(isEnabled: true, metricSink: sink),
      );
      ctx.expectEquals(result.text, 'Still fine.', 'generation result');
      for (var i = 0; i < 100 && diagnostics.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      ctx.observe('diagnostics', diagnostics);
      ctx.observe('collectorRequests', collector.requests.length);
      ctx.expect(collector.requests.isNotEmpty, 'collector was not contacted');
      ctx.expect(
        diagnostics.any((d) => d.contains('500')),
        'no 500 diagnostic in $diagnostics',
      );
      ctx.expect(sink.pendingCount > 0, 'failed metrics were not retained');
    },
  ),
  Check(
    id: 'buffer-and-payload-bounds',
    feature: 'otlp-bounds',
    description:
        'A full buffer drops the oldest metric with a diagnostic, and a '
        'metric above maxPayloadBytes is rejected before it is queued.',
    run: (ctx) async {
      final collector = await _collector(ctx, _Collector());
      final diagnostics = <String>[];
      final sink = _sink(
        collector,
        maxBufferSize: 2,
        batchSize: 2,
        maxPayloadBytes: 2048,
        onDiagnostic: (error, [_]) => diagnostics.add('$error'),
      );
      ctx.onCleanup(sink.dispose);
      sink.record(const TelemetryMetric(name: 'verify.m1', value: 1));
      sink.record(
        TelemetryMetric(
          name: 'verify.huge',
          value: 1,
          attributes: {'blob': 'x' * 5000},
        ),
      );
      ctx.expectEquals(sink.pendingCount, 1, 'oversize metric was queued');
      sink.record(const TelemetryMetric(name: 'verify.m2', value: 2));
      // m1 and m2 now fill batchSize 2; stop the auto export from racing the
      // next records by waiting for it to land.
      for (var i = 0; i < 100 && collector.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      ctx.observe('diagnostics', diagnostics);
      ctx.expect(
        diagnostics.any((d) => d.contains('maxPayloadBytes')),
        'no payload-bound diagnostic in $diagnostics',
      );
      ctx.expectEquals(
        _allMetrics(collector).keys.toList()..sort(),
        ['verify.m1', 'verify.m2'],
        'only bounded metrics exported',
      );
      // Overflow: hold the collector so the buffer cannot drain.
      final control = _Collector()..status = 500;
      final stuck = await _collector(ctx, control);
      final overflowDiagnostics = <String>[];
      final small = _sink(
        stuck,
        maxBufferSize: 2,
        batchSize: 2,
        onDiagnostic: (error, [_]) => overflowDiagnostics.add('$error'),
      );
      ctx.onCleanup(small.dispose);
      for (var i = 0; i < 2; i++) {
        small.record(TelemetryMetric(name: 'verify.o$i', value: i));
      }
      for (var i = 0; i < 100 && stuck.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      for (var i = 2; i < 5; i++) {
        small.record(TelemetryMetric(name: 'verify.o$i', value: i));
      }
      ctx.observe('overflowDiagnostics', overflowDiagnostics);
      ctx.expect(
        overflowDiagnostics.any((d) => d.contains('buffer is full')),
        'no buffer-full diagnostic in $overflowDiagnostics',
      );
      ctx.expect(small.pendingCount <= 2, 'buffer exceeded maxBufferSize');
    },
  ),
  Check(
    id: 'deadline-and-dispose',
    feature: 'otlp-lifecycle',
    description:
        'A stalled collector makes flush fail with TimeoutException at the '
        'deadline and keeps the batch; dispose makes a final delivery, then '
        'refuses new records with a diagnostic.',
    run: (ctx) async {
      final control = _Collector()..stall = const Duration(milliseconds: 600);
      final collector = await _collector(ctx, control);
      final diagnostics = <String>[];
      final sink = _sink(
        collector,
        onDiagnostic: (error, [_]) => diagnostics.add('$error'),
      );
      sink.record(const TelemetryMetric(name: 'verify.slow', value: 1));
      final stopwatch = Stopwatch()..start();
      await ctx.expectThrows<TimeoutException>(
        () => sink.flush(deadline: const Duration(milliseconds: 80)),
        'flush with a stalled collector',
      );
      ctx.observe('flushElapsedMs', stopwatch.elapsedMilliseconds);
      ctx.expect(
        stopwatch.elapsedMilliseconds < 500,
        'flush ignored its deadline: ${stopwatch.elapsedMilliseconds} ms',
      );
      ctx.expectEquals(sink.pendingCount, 1, 'batch kept after timeout');
      control.stall = null;
      await sink.dispose();
      ctx.expect(
        collector.requests.length >= 2,
        'dispose did not attempt a final delivery',
      );
      ctx.expectEquals(sink.pendingCount, 0, 'pending after dispose');
      final last = _parse(collector.requests.last);
      ctx.expect(
        last.metrics.containsKey('verify.slow'),
        'final delivery lacks the retained metric',
      );
      sink.record(const TelemetryMetric(name: 'verify.late', value: 1));
      ctx.expectEquals(sink.pendingCount, 0, 'record after dispose queued');
      ctx.expect(
        diagnostics.any((d) => d.contains('after telemetry sink disposal')),
        'no post-dispose diagnostic in $diagnostics',
      );
      await sink.flush();
      await sink.dispose();
    },
  ),
  Check(
    id: 'constructor-validation',
    feature: 'otlp-bounds',
    description:
        'The constructor rejects non-HTTP endpoints, non-positive bounds and '
        'batchSize above maxBufferSize; flush rejects a non-positive deadline.',
    run: (ctx) async {
      OtlpHttpMetricSink build({
        String endpoint = 'http://127.0.0.1:1/v1/metrics',
        int maxBufferSize = 128,
        int batchSize = 32,
        int maxPayloadBytes = 1024,
        int maxAttributes = 4,
        int maxListLength = 4,
      }) => OtlpHttpMetricSink(
        endpoint: Uri.parse(endpoint),
        maxBufferSize: maxBufferSize,
        batchSize: batchSize,
        maxPayloadBytes: maxPayloadBytes,
        maxAttributes: maxAttributes,
        maxListLength: maxListLength,
      );
      final cases = <String, OtlpHttpMetricSink Function()>{
        'ftp endpoint': () => build(endpoint: 'ftp://example.test/m'),
        'relative endpoint': () => build(endpoint: '/v1/metrics'),
        'maxBufferSize 0': () => build(maxBufferSize: 0),
        'batchSize 0': () => build(batchSize: 0),
        'maxPayloadBytes 0': () => build(maxPayloadBytes: 0),
        'maxAttributes 0': () => build(maxAttributes: 0),
        'maxListLength 0': () => build(maxListLength: 0),
        'batchSize above buffer': () => build(maxBufferSize: 4, batchSize: 8),
      };
      for (final entry in cases.entries) {
        await ctx.expectThrows<ArgumentError>(
          () async => entry.value(),
          entry.key,
        );
      }
      final sink = build();
      ctx.onCleanup(sink.dispose);
      await ctx.expectThrows<ArgumentError>(
        () async => sink.flush(deadline: Duration.zero),
        'zero flush deadline',
      );
      await ctx.expectThrows<ArgumentError>(
        () async => sink.dispose(deadline: const Duration(seconds: -1)),
        'negative dispose deadline',
      );
      ctx.expectEquals(
        jsonEncode(sink.endpoint.toString()),
        '"http://127.0.0.1:1/v1/metrics"',
        'endpoint',
      );
    },
  ),
]);
