import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Snapshot of the current step state for [StopCondition] evaluation.
///
/// Contains [stepCount], [toolCallNames], and [finishReason].
class StepSnapshot {
  const StepSnapshot({
    required this.stepCount,
    this.toolCallNames = const [],
    this.finishReason,
  });

  /// Number of steps completed so far (1-indexed).
  final int stepCount;

  /// Names of tool calls made in the most recent step.
  final List<String> toolCallNames;

  /// The finish reason from the most recent model response.
  final LanguageModelV3FinishReason? finishReason;
}

/// Function that returns true when multi-step generation should stop.
///
/// Passed to [generateText] / [streamText] via `stopWhen` or `stopConditions`.
typedef StopCondition = bool Function(StepSnapshot snapshot);

// ---------------------------------------------------------------------------
// Built-in stop condition factories
// ---------------------------------------------------------------------------

/// Never stop — run as many steps as [maxSteps] allows.
///
/// Use this to let `maxSteps` be the sole limit without any additional
/// stop conditions.
///
/// ```dart
/// await generateText(
///   model: model,
///   prompt: 'Help me',
///   maxSteps: 20,
///   stopWhen: never,
/// );
/// ```
const StopCondition never = _never;
bool _never(StepSnapshot _) => false;

/// Stop when the total step count reaches [count].
///
/// Mirrors `stepCountIs` from the JS AI SDK v6.
///
/// ```dart
/// stopWhen: stepCountIs(5)
/// ```
StopCondition stepCountIs(int count) {
  return (snapshot) => snapshot.stepCount >= count;
}

/// Stop when any tool call in the current snapshot matches [toolName].
///
/// Mirrors `hasToolCall` from the JS AI SDK v6.
///
/// ```dart
/// stopWhen: hasToolCall('finalize')
/// ```
StopCondition hasToolCall(String toolName) {
  return (snapshot) => snapshot.toolCallNames.contains(toolName);
}

/// Stop when the model finish reason matches [reason].
///
/// Mirrors `hasFinishReason` from the JS AI SDK v6.
///
/// ```dart
/// stopWhen: hasFinishReason(LanguageModelV3FinishReason.stop)
/// ```
StopCondition hasFinishReason(LanguageModelV3FinishReason reason) {
  return (snapshot) => snapshot.finishReason == reason;
}

/// Stop when at least one of the supplied conditions is satisfied.
///
/// Convenience combinator for readable multi-condition configurations:
///
/// ```dart
/// stopWhen: stopWhenAny([stepCountIs(10), hasToolCall('done')])
/// ```
StopCondition stopWhenAny(List<StopCondition> conditions) {
  return (snapshot) => conditions.any((c) => c(snapshot));
}

/// Stop when all of the supplied conditions are satisfied.
///
/// ```dart
/// stopWhen: stopWhenAll([hasFinishReason(LanguageModelV3FinishReason.stop), stepCountIs(3)])
/// ```
StopCondition stopWhenAll(List<StopCondition> conditions) {
  return (snapshot) => conditions.every((c) => c(snapshot));
}
