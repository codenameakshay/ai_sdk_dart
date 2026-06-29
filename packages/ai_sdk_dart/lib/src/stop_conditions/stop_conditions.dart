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

// ---------------------------------------------------------------------------
// Tool-loop run policy (shared by generateText and streamText)
//
// These helpers concentrate the multi-step loop policy that was previously
// duplicated across both core functions — the duplication that let the same
// `stopWhen` / `maxSteps` bug exist in both. Keeping it here makes the policy
// the single test surface.
// ---------------------------------------------------------------------------

/// Resolves the `stopWhen` union (`StopCondition | List<StopCondition> | null`)
/// and merges it with the explicit [stopConditions] into one effective list.
List<StopCondition> resolveStopConditions(
  Object? stopWhen,
  List<StopCondition> stopConditions,
) {
  final fromStopWhen = switch (stopWhen) {
    null => const <StopCondition>[],
    final StopCondition fn => [fn],
    final List<Object?> lst => lst.whereType<StopCondition>().toList(),
    _ => const <StopCondition>[],
  };
  return [...fromStopWhen, ...stopConditions];
}

/// Whether `stopWhen` supplied at least one condition. When it does, it governs
/// termination and `maxSteps` is ignored (see [resolveStepBudget]).
bool stopWhenIsSet(Object? stopWhen) => switch (stopWhen) {
  null => false,
  StopCondition() => true,
  final List<Object?> lst => lst.whereType<StopCondition>().isNotEmpty,
  _ => false,
};

/// Safety cap on tool-loop steps when `stopWhen` governs termination — guards
/// against a stop condition that never trips.
const int stopWhenStepSafetyCap = 1000;

/// The maximum number of tool-loop steps to run.
///
/// Without tools there is never more than one step. When `stopWhen` is set it
/// governs termination and [maxSteps] is ignored (a high safety cap guards
/// runaway loops). Otherwise [maxSteps] (with any `stopConditions`) bounds it.
int resolveStepBudget({
  required bool hasTools,
  required Object? stopWhen,
  required int maxSteps,
}) {
  if (!hasTools) return 1;
  if (stopWhenIsSet(stopWhen)) return stopWhenStepSafetyCap;
  return maxSteps < 1 ? 1 : maxSteps;
}

/// Whether the tool loop should stop after the current step: no further tool
/// results to feed back, a pending approval request, or a satisfied condition.
bool shouldStopAfterStep({
  required bool toolResultsEmpty,
  required bool hasApprovalRequests,
  required StepSnapshot snapshot,
  required List<StopCondition> conditions,
}) =>
    toolResultsEmpty ||
    hasApprovalRequests ||
    conditions.any((condition) => condition(snapshot));
