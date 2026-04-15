/// Telemetry configuration and interfaces for the AI SDK Dart.
///
/// Mirrors `experimental_telemetry` from the JS AI SDK v6.
///
/// Usage with a custom recorder:
/// ```dart
/// final result = await generateText(
///   model: model,
///   prompt: 'Hello',
///   experimentalTelemetry: TelemetrySettings(
///     isEnabled: true,
///     functionId: 'my-chat-function',
///     metadata: {'userId': 'user-123', 'sessionId': 'sess-456'},
///     recorder: MyTelemetryRecorder(),
///   ),
/// );
/// ```

/// An attribute value acceptable in telemetry metadata.
///
/// Mirrors the OpenTelemetry `AttributeValue` type.
typedef TelemetryAttributeValue = Object?; // String | num | bool | List

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
/// Pass to `experimentalTelemetry` on [generateText] or [streamText].
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

class _NoOpRecorder implements TelemetryRecorder {
  const _NoOpRecorder();

  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) =>
      const _NoOpSpan();
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

  final recorder = settings.recorder ?? const _NoOpRecorder();
  final allAttributes = {
    if (settings.functionId != null)
      'ai.telemetry.functionId': settings.functionId,
    ...settings.metadata,
    ...attributes,
  };

  return recorder.startSpan(spanName, attributes: allAttributes);
}
