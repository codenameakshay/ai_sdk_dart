import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

typedef ToolExecutor<INPUT, OUTPUT> =
    Future<OUTPUT> Function(INPUT input, ToolExecutionOptions options);
typedef UntypedToolExecutor =
    Future<Object?> Function(Object? input, ToolExecutionOptions options);

/// A token that signals cancellation of an in-progress operation.
///
/// Passed to tool executors via [ToolExecutionOptions.abortSignal].
/// Long-running tools should check [isCancelled] periodically and exit early
/// when it returns `true`.  The [onCancelled] future completes when the
/// cancellation is requested.
///
/// Mirrors the JS `AbortSignal` concept for the Dart/Flutter world.
class CancellationToken {
  CancellationToken() {
    _completer = Completer<void>();
  }

  late final Completer<void> _completer;
  bool _isCancelled = false;

  /// Whether this token has been cancelled.
  bool get isCancelled => _isCancelled;

  /// A future that completes when cancellation is requested.
  Future<void> get onCancelled => _completer.future;

  /// Cancel the operation.  Idempotent — safe to call multiple times.
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      if (!_completer.isCompleted) _completer.complete();
    }
  }
}

/// Context passed to tool executors during execution.
///
/// - [toolCallId] — unique ID for this specific tool invocation.
/// - [messages] — conversation history at the point of the tool call
///   (provider-level messages; typed as [LanguageModelV3Message]).
/// - [abortSignal] — [CancellationToken] that fires if the generation is
///   cancelled; check [CancellationToken.isCancelled] in long-running tools.
/// - [experimentalContext] — arbitrary key/value context map threaded from
///   the `experimentalContext` parameter of [generateText]/[streamText].
class ToolExecutionOptions {
  const ToolExecutionOptions({
    this.toolCallId,
    this.messages,
    this.abortSignal,
    this.experimentalContext,
  });

  final String? toolCallId;
  final List<LanguageModelV3Message>? messages;

  /// Cancellation token — non-null when the caller provided an abort signal.
  final CancellationToken? abortSignal;

  /// Caller-supplied context; strongly typed as a string-keyed map.
  final Map<String, Object?>? experimentalContext;
}

typedef ToolNeedsApproval<INPUT> =
    FutureOr<bool> Function(INPUT input, ToolExecutionOptions options);
typedef UntypedToolNeedsApproval =
    FutureOr<bool> Function(Object? input, ToolExecutionOptions options);

/// Example input for a tool; helps the model understand expected usage.
class ToolInputExample {
  const ToolInputExample({required this.input});

  final Map<String, dynamic> input;
}

/// A typed schema wrapper for tool inputs/structured outputs.
///
/// This is intentionally codegen-friendly: your input class can be generated
/// with `json_serializable` and wired using its generated `fromJson`.
class Schema<T> {
  const Schema({required this.jsonSchema, required this.fromJson});

  final Map<String, dynamic> jsonSchema;
  final T Function(Map<String, dynamic>) fromJson;
}

/// Core typed tool definition for [generateText] and [streamText].
///
/// Defines [inputSchema], [description], [execute], [strict], [inputExamples],
/// and [needsApproval]. Mirrors the tool API from the JS AI SDK v6.
class Tool<INPUT, OUTPUT> {
  const Tool({
    required this.inputSchema,
    this.description,
    this.execute,
    this.executeDynamic,
    this.strict,
    this.inputExamples = const [],
    this.needsApproval,
    this.needsApprovalDynamic,
    this.requiresApproval = false,
    this.dynamic = false,
  });

  final String? description;
  final Schema<INPUT> inputSchema;
  final ToolExecutor<INPUT, OUTPUT>? execute;
  final UntypedToolExecutor? executeDynamic;
  final bool? strict;
  final List<ToolInputExample> inputExamples;
  final ToolNeedsApproval<INPUT>? needsApproval;
  final UntypedToolNeedsApproval? needsApprovalDynamic;
  final bool requiresApproval;
  final bool dynamic;
}

/// Map of tool names to tools; used by [generateText] and [streamText].
typedef ToolSet = Map<String, Tool<dynamic, dynamic>>;

/// Helper to define typed tools with better type inference.
///
/// Example:
/// ```dart
/// final weatherTool = tool(
///   inputSchema: Schema(jsonSchema: {...}, fromJson: ...),
///   description: 'Get the weather',
///   execute: (input, options) async => {...},
/// );
/// ```
Tool<INPUT, OUTPUT> tool<INPUT, OUTPUT>({
  required Schema<INPUT> inputSchema,
  String? description,
  ToolExecutor<INPUT, OUTPUT>? execute,
  bool? strict,
  List<ToolInputExample> inputExamples = const [],
  ToolNeedsApproval<INPUT>? needsApproval,
}) {
  return Tool<INPUT, OUTPUT>(
    inputSchema: inputSchema,
    description: description,
    execute: execute,
    executeDynamic: execute == null
        ? null
        : (input, options) => execute(input as INPUT, options),
    strict: strict,
    inputExamples: inputExamples,
    needsApproval: needsApproval,
    needsApprovalDynamic: needsApproval == null
        ? null
        : (input, options) => needsApproval(input as INPUT, options),
    requiresApproval: needsApproval != null,
  );
}

/// Creates a [Schema] from a JSON schema map without deserialization.
///
/// Use when you need to pass a schema to [generateText]/[streamText] output
/// or [tool] but don't need typed deserialization — the raw JSON map is returned.
/// Mirrors `jsonSchema()` from the JS AI SDK v6.
Schema<Map<String, dynamic>> jsonSchema(Map<String, dynamic> schema) {
  return Schema<Map<String, dynamic>>(
    jsonSchema: schema,
    fromJson: (json) => json,
  );
}

/// Defines a tool with runtime-unknown input (accepts any JSON object).
///
/// Use when the tool input structure is not known at compile time.
/// Mirrors `dynamicTool` from the JS AI SDK v6.
Tool<Object?, OUTPUT> dynamicTool<OUTPUT>({
  String? description,
  ToolExecutor<Object?, OUTPUT>? execute,
  bool? strict,
  List<ToolInputExample> inputExamples = const [],
  ToolNeedsApproval<Object?>? needsApproval,
}) {
  return Tool<Object?, OUTPUT>(
    inputSchema: Schema<Object?>(
      jsonSchema: const {'type': 'object'},
      fromJson: (json) => json,
    ),
    description: description,
    execute: execute,
    executeDynamic: execute,
    strict: strict,
    inputExamples: inputExamples,
    needsApproval: needsApproval,
    needsApprovalDynamic: needsApproval,
    requiresApproval: needsApproval != null,
    dynamic: true,
  );
}
