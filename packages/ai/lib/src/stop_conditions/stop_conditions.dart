/// Result snapshot used to evaluate stop conditions.
class StepSnapshot {
  const StepSnapshot({required this.stepCount, this.toolCallNames = const []});

  final int stepCount;
  final List<String> toolCallNames;
}

typedef StopCondition = bool Function(StepSnapshot snapshot);

/// Stop when the total step count reaches [count].
StopCondition stepCountIs(int count) {
  return (snapshot) => snapshot.stepCount >= count;
}

/// Stop when any tool call in the current snapshot matches [toolName].
StopCondition hasToolCall(String toolName) {
  return (snapshot) => snapshot.toolCallNames.contains(toolName);
}
