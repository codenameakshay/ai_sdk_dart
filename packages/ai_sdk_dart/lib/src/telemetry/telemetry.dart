/// Telemetry configuration and interfaces for the AI SDK Dart.
///
/// Mirrors `experimental_telemetry` from the JS AI SDK v6.
///
/// Usage with a custom recorder:
/// ```dart
/// final result = await generateText(
///   model: model,
///   prompt: 'Hello',
///   telemetry: TelemetrySettings(
///     isEnabled: true,
///     functionId: 'my-chat-function',
///     metadata: {'userId': 'user-123', 'sessionId': 'sess-456'},
///     recorder: MyTelemetryRecorder(),
///   ),
/// );
/// ```
library;

/// An attribute value acceptable in telemetry metadata.
///
/// Mirrors the OpenTelemetry `AttributeValue` type.
typedef TelemetryAttributeValue = Object?; // String | num | bool | List

/// Stable, content-free attribute names emitted by core generation spans.
///
/// Integrations should use these keys instead of matching recorder-specific
/// strings. Values describe execution and accounting only; prompts, outputs,
/// tool arguments, and response bodies remain opt-in through
/// [TelemetrySettings].
abstract final class AiTelemetryKeys {
  static const modelProvider = 'ai.model.provider';
  static const modelId = 'ai.model.id';
  static const stepIndex = 'ai.step.index';
  static const stepCount = 'ai.step.count';
  static const toolName = 'ai.tool.name';
  static const firstTokenMs = 'ai.latency.firstTokenMs';
  static const retryCount = 'ai.retry.count';
  static const queueWaitMs = 'ai.queue.waitMs';
  static const cancelled = 'ai.cancelled';
  static const promptTokens = 'ai.usage.promptTokens';
  static const completionTokens = 'ai.usage.completionTokens';
  static const cacheReadTokens = 'ai.cache.readTokens';
  static const cacheWriteTokens = 'ai.cache.writeTokens';
  static const operation = 'ai.operation';
  static const operationStatus = 'ai.operation.status';
}

/// Content-free metric names emitted by core operations.
abstract final class AiTelemetryMetrics {
  static const firstMeaningfulMs = 'ai.latency.firstMeaningfulMs';
  static const totalMs = 'ai.latency.totalMs';
  static const retryCount = 'ai.retry.count';
  static const toolCount = 'ai.tool.count';
  static const stepCount = 'ai.step.count';
  static const cancelled = 'ai.cancelled';
  static const success = 'ai.operation.success';
  static const failure = 'ai.operation.failure';
  static const usageKnown = 'ai.usage.known';
}

/// A single content-free operation measurement.
class TelemetryMetric {
  const TelemetryMetric({
    required this.name,
    required this.value,
    this.attributes = const {},
  });

  final String name;
  final num value;
  final Map<String, TelemetryAttributeValue> attributes;
}

/// Optional metrics exporter seam. Implementations may bridge OpenTelemetry
/// or another backend without adding a dependency to the core package.
abstract interface class TelemetryMetricSink {
  void record(TelemetryMetric metric);
}

/// Adapts metric events to an optional application exporter.
class CallbackTelemetryMetricSink implements TelemetryMetricSink {
  const CallbackTelemetryMetricSink(this.callback);
  final void Function(TelemetryMetric metric) callback;

  @override
  void record(TelemetryMetric metric) => callback(metric);
}

/// A lightweight telemetry span returned by [TelemetryRecorder.startSpan].
///
/// Implement this interface to integrate with any tracing backend.
abstract interface class TelemetrySpan {
  /// Set a string attribute on the span.
  void setAttribute(String key, TelemetryAttributeValue value);

  /// Record an exception or error event.
  void recordException(Object error, {StackTrace? stackTrace});

  /// End the span; optionally mark it as failed with [error].
  void end({Object? error});
}

/// Hook interface for tracing AI SDK calls.
///
/// Implement this to bridge into OpenTelemetry, Sentry, Datadog, or any
/// custom telemetry backend.  Passed via [TelemetrySettings.recorder].
abstract interface class TelemetryRecorder {
  /// Called at the start of a generation call.
  ///
  /// [name] is the span name (e.g. `'ai.generateText'`).
  /// [attributes] contains the initial set of attributes.
  /// Returns a [TelemetrySpan] that will be ended when the call finishes.
  TelemetrySpan startSpan(
    String name, {
    Map<String, TelemetryAttributeValue> attributes,
  });
}

/// Settings that enable telemetry recording for a generation call.
///
/// Pass to `telemetry` on [generateText] or [streamText].
///
/// All fields are optional except [isEnabled] (defaults to `false`).
///
/// Example:
/// ```dart
/// TelemetrySettings(
///   isEnabled: true,
///   functionId: 'chat-completion',
///   metadata: {'userId': 'abc', 'plan': 'pro'},
/// )
/// ```
class TelemetrySettings {
  const TelemetrySettings({
    this.isEnabled = false,
    this.functionId,
    this.metadata = const {},
    this.recorder,
    this.metricSink,
    this.captureInputs = false,
    this.captureOutputs = false,
    this.captureExceptionDetails = false,
    this.redactAttribute,
    this.onDiagnostic,
  });

  /// Whether telemetry is enabled for this call.
  final bool isEnabled;

  /// An identifier for the span / function being traced.
  ///
  /// Appears as the `ai.telemetry.functionId` attribute.
  final String? functionId;

  /// Arbitrary key/value pairs added to every span for this call.
  ///
  /// Values must be JSON-compatible scalars or lists.
  final Map<String, TelemetryAttributeValue> metadata;

  /// Pluggable recorder that receives tracing lifecycle events.
  ///
  /// If `null` and [isEnabled] is `true`, a no-op recorder is used so that
  /// integrating a real backend is opt-in.
  final TelemetryRecorder? recorder;

  /// Optional content-free metrics exporter.
  final TelemetryMetricSink? metricSink;

  /// Opts in to prompt, request body, and tool input attributes.
  final bool captureInputs;

  /// Opts in to generated text, response body, and tool output attributes.
  final bool captureOutputs;

  /// Opts in to exception messages and details. Type and code are retained by
  /// default while secret-bearing messages remain excluded.
  final bool captureExceptionDetails;

  /// Redacts or transforms an attribute before it reaches the recorder.
  final TelemetryAttributeValue? Function(
    String key,
    TelemetryAttributeValue value,
  )?
  redactAttribute;

  /// Receives exporter/recorder failures without affecting generation.
  final void Function(Object error)? onDiagnostic;
}

void recordTelemetryMetric(
  TelemetrySettings? settings,
  TelemetryMetric metric,
) {
  try {
    if (settings?.isEnabled == true) {
      final attributes = <String, TelemetryAttributeValue>{
        ...settings!.metadata,
        ...metric.attributes,
        'ai.metric.name': metric.name,
      };
      final filtered = _filterTelemetryAttributes(settings, attributes);
      settings.metricSink?.record(
        TelemetryMetric(
          name: metric.name,
          value: metric.value,
          attributes: filtered,
        ),
      );
    }
  } catch (error) {
    settings?.onDiagnostic?.call(error);
  }
}

// ---------------------------------------------------------------------------
// No-op implementations used internally when no real recorder is wired up.
// ---------------------------------------------------------------------------

class _NoOpSpan implements TelemetrySpan {
  const _NoOpSpan();

  @override
  void setAttribute(String key, TelemetryAttributeValue value) {}

  @override
  void recordException(Object error, {StackTrace? stackTrace}) {}

  @override
  void end({Object? error}) {}
}

// ---------------------------------------------------------------------------
// Internal helpers used by generateText / streamText
// ---------------------------------------------------------------------------

/// Start a telemetry span for a generation call.
///
/// Returns a no-op span if telemetry is disabled or no recorder is provided.
TelemetrySpan startTelemetrySpan(
  TelemetrySettings? settings, {
  required String spanName,
  required Map<String, TelemetryAttributeValue> attributes,
}) {
  if (settings == null || !settings.isEnabled) return const _NoOpSpan();

  final recorder = settings.recorder;
  if (recorder == null) return const _NoOpSpan();
  final allAttributes = {
    if (settings.functionId != null)
      'ai.telemetry.functionId': settings.functionId,
    ...settings.metadata,
    ...attributes,
  };

  final filtered = _filterTelemetryAttributes(settings, allAttributes);
  try {
    return _SafeTelemetrySpan(
      recorder.startSpan(spanName, attributes: filtered),
      settings: settings,
    );
  } catch (error) {
    settings.onDiagnostic?.call(error);
    return const _NoOpSpan();
  }
}

class _SafeTelemetrySpan implements TelemetrySpan {
  _SafeTelemetrySpan(this._inner, {required this.settings});
  final TelemetrySpan _inner;
  final TelemetrySettings settings;

  @override
  void setAttribute(String key, TelemetryAttributeValue value) {
    try {
      final filtered = _filterTelemetryAttributes(settings, {key: value});
      if (filtered.containsKey(key)) {
        _inner.setAttribute(key, filtered[key]);
      }
    } catch (error) {
      settings.onDiagnostic?.call(error);
    }
  }

  @override
  void recordException(Object error, {StackTrace? stackTrace}) {
    try {
      _inner.recordException(
        settings.captureExceptionDetails ? error : _TelemetryErrorType(error),
        stackTrace: settings.captureExceptionDetails ? stackTrace : null,
      );
    } catch (error) {
      settings.onDiagnostic?.call(error);
    }
  }

  @override
  void end({Object? error}) {
    try {
      _inner.end(
        error: error == null
            ? null
            : (settings.captureExceptionDetails
                  ? error
                  : _TelemetryErrorType(error)),
      );
    } catch (error) {
      settings.onDiagnostic?.call(error);
    }
  }
}

Map<String, TelemetryAttributeValue> _filterTelemetryAttributes(
  TelemetrySettings settings,
  Map<String, TelemetryAttributeValue> attributes,
) {
  final filtered = <String, TelemetryAttributeValue>{};
  for (final entry in attributes.entries) {
    final key = entry.key.toLowerCase();
    final isInput = _hasContentPrefix(key, const [
      'ai.prompt',
      'ai.request.body',
      'ai.tool.input',
    ]);
    final isOutput = _hasContentPrefix(key, const [
      'ai.output',
      'ai.response.body',
      'ai.tool.output',
    ]);
    if ((isInput && !settings.captureInputs) ||
        (isOutput && !settings.captureOutputs)) {
      continue;
    }
    if (settings.redactAttribute == null) {
      filtered[entry.key] = entry.value;
      continue;
    }
    try {
      final redacted = settings.redactAttribute!(entry.key, entry.value);
      if (redacted != null) filtered[entry.key] = redacted;
    } catch (_) {}
  }
  return filtered;
}

bool _hasContentPrefix(String key, List<String> prefixes) {
  for (final prefix in prefixes) {
    if (key == prefix || key.startsWith('$prefix.')) return true;
  }
  return false;
}

class _TelemetryErrorType {
  _TelemetryErrorType(Object error) : type = error.runtimeType.toString();
  final String type;

  @override
  String toString() => type;
}
