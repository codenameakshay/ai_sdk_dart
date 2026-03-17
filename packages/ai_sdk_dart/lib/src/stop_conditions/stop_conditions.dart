/// Snapshot of the current step state for [StopCondition] evaluation.
///
/// Contains [stepCount] and [toolCallNames].
class StepSnapshot {
  const StepSnapshot({required this.stepCount, this.toolCallNames = const []});

  final int stepCount;
  final List<String> toolCallNames;
}

/// Function that returns true when multi-step generation should stop.
typedef StopCondition = bool Function(StepSnapshot snapshot);

/// Stop when the total step count reaches [count].
///
/// Mirrors `stepCountIs` from the JS AI SDK v6.
StopCondition stepCountIs(int count) {
  return (snapshot) => snapshot.stepCount >= count;
}

/// Stop when any tool call in the current snapshot matches [toolName].
///
/// Mirrors `hasToolCall` from the JS AI SDK v6.
StopCondition hasToolCall(String toolName) {
  return (snapshot) => snapshot.toolCallNames.contains(toolName);
}
