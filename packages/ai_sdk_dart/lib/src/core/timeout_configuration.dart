class TimeoutConfiguration {
  const TimeoutConfiguration({
    this.total,
    this.step,
    this.firstChunk,
    this.chunk,
    this.tool,
    this.tools = const {},
  });

  final Duration? total;
  final Duration? step;
  final Duration? firstChunk;
  final Duration? chunk;
  final Duration? tool;
  final Map<String, Duration> tools;

  Duration? toolTimeoutFor(String toolName) => tools[toolName] ?? tool;
}
