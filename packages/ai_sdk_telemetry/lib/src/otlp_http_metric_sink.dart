import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ai_sdk_dart/ai_sdk_dart.dart';

/// Sends AI SDK content-free metric observations to an OTLP/HTTP JSON
/// endpoint. This adapter supports native Dart platforms with `dart:io`.
/// It does not provide a browser transport.
class OtlpHttpMetricSink implements TelemetryMetricSink {
  OtlpHttpMetricSink({
    required this.endpoint,
    Map<String, String> headers = const {},
    Map<String, Object?> resourceAttributes = const {},
    this.scopeName = 'ai_sdk_dart',
    this.maxBufferSize = 128,
    this.batchSize = 32,
    this.maxPayloadBytes = 64 * 1024,
    this.maxAttributes = 64,
    this.maxListLength = 64,
    this.redactAttribute,
    this.onDiagnostic,
    HttpClient? client,
  }) : headers = Map.unmodifiable(Map<String, String>.from(headers)),
       _client = client ?? HttpClient(),
       _ownsClient = client == null {
    if (!endpoint.hasScheme ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
        endpoint.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Must be an HTTP(S) URI.',
      );
    }
    if (maxBufferSize <= 0 ||
        batchSize <= 0 ||
        maxPayloadBytes <= 0 ||
        maxAttributes <= 0 ||
        maxListLength <= 0) {
      throw ArgumentError('Exporter bounds must be positive.');
    }
    if (batchSize > maxBufferSize) {
      throw ArgumentError.value(
        batchSize,
        'batchSize',
        'Cannot exceed maxBufferSize.',
      );
    }
    this.resourceAttributes = Map.unmodifiable(
      _sanitizeAttributes(
        resourceAttributes,
        maxEntries: maxAttributes,
        maxListLength: maxListLength,
        redactAttribute: redactAttribute,
        onDiagnostic: _diagnose,
      ),
    );
  }

  final Uri endpoint;
  final Map<String, String> headers;
  late final Map<String, Object?> resourceAttributes;
  final String scopeName;
  final int maxBufferSize;
  final int batchSize;
  final int maxPayloadBytes;
  final int maxAttributes;
  final int maxListLength;
  final Object? Function(String key, Object? value)? redactAttribute;
  final void Function(Object error, [StackTrace? stackTrace])? onDiagnostic;

  /// An injected client remains owned by the caller and is never closed by
  /// this sink. When omitted, the sink owns its client and may replace it
  /// after a connection timeout so a later flush can recover.
  HttpClient _client;
  final bool _ownsClient;
  final List<_MetricObservation> _buffer = <_MetricObservation>[];
  List<_MetricObservation> _inFlightBatch = const [];
  Future<void>? _flushInFlight;
  HttpClientRequest? _activeRequest;
  Future<void>? _disposeFuture;
  Stopwatch? _disposeClock;
  Duration? _disposeBudget;
  bool _disposing = false;
  bool _disposed = false;

  int get pendingCount => _buffer.length + _inFlightBatch.length;

  @override
  void record(TelemetryMetric metric) {
    if (_disposing || _disposed) {
      _diagnose(
        StateError('Cannot record after telemetry sink disposal has started.'),
      );
      return;
    }
    if (metric.name.trim().isEmpty || !metric.value.isFinite) {
      _diagnose(
        ArgumentError('Metric names must be non-empty and values finite.'),
      );
      return;
    }
    final snapshot = _MetricObservation(
      recordedAtNanos: _nowNanos(),
      metric: TelemetryMetric(
        name: metric.name,
        value: metric.value,
        attributes: Map.unmodifiable(
          _sanitizeAttributes(
            metric.attributes,
            maxEntries: maxAttributes,
            maxListLength: maxListLength,
            redactAttribute: redactAttribute,
            onDiagnostic: _diagnose,
          ),
        ),
      ),
    );
    try {
      if (utf8.encode(jsonEncode(_payload([snapshot]))).length >
          maxPayloadBytes) {
        _diagnose(StateError('OTLP metric exceeds maxPayloadBytes.'));
        return;
      }
    } catch (error, stackTrace) {
      _diagnose(error, stackTrace);
      return;
    }
    if (_buffer.length + _inFlightBatch.length >= maxBufferSize) {
      if (_buffer.isEmpty) {
        _diagnose(
          StateError('OTLP metric buffer is full; dropped the newest metric.'),
        );
        return;
      }
      _buffer.removeAt(0);
      _diagnose(
        StateError('OTLP metric buffer is full; dropped the oldest metric.'),
      );
    }
    _buffer.add(snapshot);
    if (_buffer.length >= batchSize) {
      unawaited(
        flush().catchError((Object error, StackTrace stackTrace) {
          _diagnose(error, stackTrace);
        }),
      );
    }
  }

  Future<void> flush({Duration deadline = const Duration(seconds: 10)}) {
    _validateDeadline(deadline);
    if (_disposed) return Future.value();
    final current = _flushInFlight;
    if (current != null) return current;
    final operation = _flushLoop(deadline);
    _flushInFlight = operation.whenComplete(() => _flushInFlight = null);
    return _flushInFlight!;
  }

  Future<void> dispose({Duration deadline = const Duration(seconds: 10)}) {
    _validateDeadline(deadline);
    if (_disposed) return Future.value();
    return _disposeFuture ??= _dispose(deadline);
  }

  Future<void> _dispose(Duration deadline) async {
    _disposing = true;
    _disposeClock = Stopwatch()..start();
    _disposeBudget = deadline;
    try {
      await flush(deadline: deadline).timeout(
        deadline,
        onTimeout: () {
          final error = TimeoutException(
            'OTLP dispose deadline exceeded.',
            deadline,
          );
          _activeRequest?.abort(error);
          if (_ownsClient) _client.close(force: true);
          throw error;
        },
      );
    } catch (error, stackTrace) {
      _diagnose(error, stackTrace);
    } finally {
      _disposed = true;
      if (_ownsClient) _client.close(force: true);
    }
  }

  Future<void> _flushLoop(Duration deadline) async {
    final started = Stopwatch()..start();
    while (_buffer.isNotEmpty) {
      final batch = _takeBatch();
      final remaining = _remaining(deadline - started.elapsed);
      if (remaining <= Duration.zero) {
        _inFlightBatch = const [];
        _restoreBatch(batch);
        throw TimeoutException(
          'OTLP metric export deadline exceeded.',
          deadline,
        );
      }
      try {
        await _send(batch, remaining);
        _inFlightBatch = const [];
      } catch (error, stackTrace) {
        _inFlightBatch = const [];
        _restoreBatch(batch);
        _diagnose(error, stackTrace);
        rethrow;
      }
    }
  }

  List<_MetricObservation> _takeBatch() {
    var count = math.min(batchSize, _buffer.length);
    while (count > 1 &&
        utf8.encode(jsonEncode(_payload(_buffer.sublist(0, count)))).length >
            maxPayloadBytes) {
      count--;
    }
    final batch = _buffer.sublist(0, count).toList(growable: false);
    _buffer.removeRange(0, count);
    _inFlightBatch = batch;
    return batch;
  }

  void _restoreBatch(List<_MetricObservation> batch) {
    final overflow = _buffer.length + batch.length - maxBufferSize;
    if (overflow > 0) {
      _diagnose(
        StateError('OTLP metric buffer is full; dropped newer metrics.'),
      );
      _buffer.removeRange(_buffer.length - overflow, _buffer.length);
    }
    _buffer.insertAll(0, batch);
  }

  Duration _remaining(Duration operationRemaining) {
    if (_disposeClock == null || _disposeBudget == null) {
      return operationRemaining;
    }
    final disposalRemaining = _disposeBudget! - _disposeClock!.elapsed;
    return operationRemaining < disposalRemaining
        ? operationRemaining
        : disposalRemaining;
  }

  Future<void> _send(List<_MetricObservation> metrics, Duration timeout) {
    final timeoutError = TimeoutException(
      'OTLP export deadline exceeded.',
      timeout,
    );
    HttpClientRequest? request;
    var expired = false;
    Future<void> send() async {
      final payloadBytes = utf8.encode(jsonEncode(_payload(metrics)));
      if (payloadBytes.length > maxPayloadBytes) {
        throw StateError('OTLP metric payload exceeds maxPayloadBytes.');
      }
      final connected = await _client.postUrl(endpoint);
      request = connected;
      if (expired) {
        connected.abort(timeoutError);
        return;
      }
      _activeRequest = connected;
      try {
        connected.headers.contentType = ContentType.json;
        headers.forEach(connected.headers.set);
        connected.add(payloadBytes);
        final response = await connected.close();
        await response.drain<void>();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'OTLP metrics endpoint returned ${response.statusCode}.',
            uri: endpoint,
          );
        }
      } finally {
        if (identical(_activeRequest, connected)) _activeRequest = null;
      }
    }

    return send().timeout(
      timeout,
      onTimeout: () {
        expired = true;
        if (request case final connected?) {
          connected.abort(timeoutError);
        } else if (_ownsClient) {
          final staleClient = _client;
          _client = HttpClient();
          staleClient.close(force: true);
        }
        throw timeoutError;
      },
    );
  }

  Map<String, Object?> _payload(List<_MetricObservation> observations) => {
    'resourceMetrics': [
      {
        'resource': {'attributes': _attributes(resourceAttributes)},
        'scopeMetrics': [
          {
            'scope': {'name': scopeName},
            'metrics': _groupMetrics(observations),
          },
        ],
      },
    ],
  };

  List<Map<String, Object?>> _groupMetrics(
    List<_MetricObservation> observations,
  ) {
    final grouped = <String, List<_MetricObservation>>{};
    for (final observation in observations) {
      grouped.putIfAbsent(observation.metric.name, () => []).add(observation);
    }
    return [
      for (final entry in grouped.entries)
        {
          'name': entry.key,
          'gauge': {
            'dataPoints': [
              for (final observation in entry.value) _dataPoint(observation),
            ],
          },
        },
    ];
  }

  Map<String, Object?> _dataPoint(_MetricObservation observation) => {
    'asDouble': observation.metric.value.toDouble(),
    'timeUnixNano': '${observation.recordedAtNanos}',
    'attributes': _attributes(observation.metric.attributes),
  };

  List<Map<String, Object?>> _attributes(Map<String, Object?> attributes) {
    final result = <Map<String, Object?>>[];
    for (final entry in attributes.entries) {
      if (result.length >= maxAttributes) {
        _diagnose(StateError('OTLP metric attribute limit exceeded.'));
        break;
      }
      final encoded = _value(entry.value, seen: Set<Object>.identity());
      if (encoded != null) result.add({'key': entry.key, 'value': encoded});
    }
    return result;
  }

  Map<String, Object?>? _value(
    Object? value, {
    required Set<Object> seen,
    int depth = 0,
  }) {
    if (depth > maxListLength) {
      _diagnose(StateError('OTLP metric attribute nesting limit exceeded.'));
      return null;
    }
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'boolValue': value};
    if (value is int) return {'intValue': '$value'};
    if (value is double) return value.isFinite ? {'doubleValue': value} : null;
    if (value is num) {
      final converted = value.toDouble();
      return converted.isFinite ? {'doubleValue': converted} : null;
    }
    if (value is List) {
      if (!seen.add(value)) {
        _diagnose(StateError('Cyclic OTLP metric attribute omitted.'));
        return null;
      }
      try {
        if (value.length > maxListLength) {
          _diagnose(StateError('OTLP metric attribute list limit exceeded.'));
          return null;
        }
        final values = <Map<String, Object?>>[];
        for (final item in value) {
          final encoded = _value(item, seen: seen, depth: depth + 1);
          if (encoded == null) return null;
          values.add(encoded);
        }
        return {
          'arrayValue': {'values': values},
        };
      } finally {
        seen.remove(value);
      }
    }
    return null;
  }

  void _validateDeadline(Duration deadline) {
    if (deadline <= Duration.zero) {
      throw ArgumentError.value(deadline, 'deadline', 'Must be positive.');
    }
  }

  void _diagnose(Object error, [StackTrace? stackTrace]) {
    try {
      onDiagnostic?.call(error, stackTrace);
    } catch (_) {}
  }
}

class _MetricObservation {
  const _MetricObservation({
    required this.metric,
    required this.recordedAtNanos,
  });

  final TelemetryMetric metric;
  final int recordedAtNanos;
}

int _nowNanos() => DateTime.now().microsecondsSinceEpoch * 1000;

Map<String, Object?> _sanitizeAttributes(
  Map<String, Object?> attributes, {
  required int maxEntries,
  required int maxListLength,
  Object? Function(String key, Object? value)? redactAttribute,
  void Function(Object error, [StackTrace? stackTrace])? onDiagnostic,
}) {
  final seen = Set<Object>.identity();
  final sanitized = <String, Object?>{};
  for (final entry in attributes.entries) {
    if (sanitized.length >= maxEntries) break;
    Object? value;
    try {
      value = redactAttribute == null
          ? entry.value
          : redactAttribute(entry.key, entry.value);
    } catch (error, stackTrace) {
      try {
        onDiagnostic?.call(error, stackTrace);
      } catch (_) {}
      continue;
    }
    sanitized[entry.key] = _snapshotAttributeValue(
      value,
      seen: seen,
      maxListLength: maxListLength,
    );
  }
  return sanitized;
}

Object? _snapshotAttributeValue(
  Object? value, {
  required Set<Object> seen,
  int maxListLength = 64,
  int depth = 0,
}) {
  if (value is String || value is bool || value is int) return value;
  if (value is num) return value.isFinite ? value : null;
  if (value is! List) return null;
  if (depth > maxListLength ||
      value.length > maxListLength ||
      !seen.add(value)) {
    return null;
  }
  try {
    return List.unmodifiable(
      value.map(
        (item) => _snapshotAttributeValue(
          item,
          seen: seen,
          maxListLength: maxListLength,
          depth: depth + 1,
        ),
      ),
    );
  } finally {
    seen.remove(value);
  }
}
