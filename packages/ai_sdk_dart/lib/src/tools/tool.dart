import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'schema_validation.dart';

typedef ToolExecutor<INPUT, OUTPUT> =
    Future<OUTPUT> Function(INPUT input, ToolExecutionOptions options);
typedef ToolContextExecutor<INPUT, OUTPUT, CONTEXT> =
    Future<OUTPUT> Function(
      INPUT input,
      CONTEXT context,
      ToolExecutionOptions options,
    );
typedef UntypedToolExecutor =
    Future<Object?> Function(Object? input, ToolExecutionOptions options);

/// Explicit context made available to one tool invocation.
///
/// The wrapper keeps application context out of provider messages and gives
/// integrations a typed boundary for their per-tool value.
class ToolExecutionContext<T> {
  const ToolExecutionContext(this.value);

  final T value;
}

/// A token that signals cancellation of an in-progress operation.
///
/// Passed to tool executors via [ToolExecutionOptions.abortSignal].
/// Long-running tools should check [isCancelled] periodically and exit early
/// when it returns `true`.  The [onCancelled] future completes when the
/// cancellation is requested.
///
/// Mirrors the JS `AbortSignal` concept for the Dart/Flutter world.
class CancellationToken implements ObservableAbortSignal {
  CancellationToken() {
    _completer = Completer<void>();
  }

  late final Completer<void> _completer;
  StreamController<void>? _events;
  bool _isCancelled = false;

  /// Whether this token has been cancelled.
  @override
  bool get isCancelled => _isCancelled;

  /// A future that completes when cancellation is requested.
  @override
  Future<void> get onCancelled => _completer.future;

  /// A cancellable subscription for observers with a shorter lifetime than
  /// this token. Late subscribers receive one event if already cancelled.
  @override
  Stream<void> get cancellationEvents => isCancelled
      ? Stream<void>.value(null)
      : (_events ??= StreamController<void>.broadcast(sync: true)).stream;

  /// Cancel the operation.  Idempotent — safe to call multiple times.
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      if (!_completer.isCompleted) _completer.complete();
      if (_events case final events?) {
        events.add(null);
        unawaited(events.close());
      }
    }
  }
}

/// Context passed to tool executors during execution.
///
/// - [toolCallId] — unique ID for this specific tool invocation.
/// - [messages] — conversation history at the point of the tool call
///   (provider-level messages; typed as [LanguageModelV4Message]).
/// - [abortSignal] — [CancellationToken] that fires if the generation is
///   cancelled; check [CancellationToken.isCancelled] in long-running tools.
/// - [runtimeContext] — arbitrary key/value context map threaded from
///   the `runtimeContext` parameter of [generateText]/[streamText].
class ToolExecutionOptions {
  const ToolExecutionOptions({
    this.toolCallId,
    this.messages,
    this.abortSignal,
    this.runtimeContext,
    this.generationContext,
    this.toolContext,
  });

  final String? toolCallId;
  final List<LanguageModelV4Message>? messages;

  /// Cancellation token — non-null when the caller provided an abort signal.
  final CancellationToken? abortSignal;

  /// Caller-supplied context; strongly typed as a string-keyed map.
  final Map<String, Object?>? runtimeContext;

  /// Per-tool context supplied by the generation request. It is not sent to
  /// the provider or included in response history.
  final Object? generationContext;

  /// Typed per-tool context. This is never serialized or sent to a provider.
  final Object? toolContext;
}

typedef ToolNeedsApproval<INPUT> =
    FutureOr<bool> Function(INPUT input, ToolExecutionOptions options);
typedef UntypedToolNeedsApproval =
    FutureOr<bool> Function(Object? input, ToolExecutionOptions options);

/// How the core decides whether a tool call requires user approval.
enum ToolApprovalPolicy {
  /// Execute without asking for approval.
  never,

  /// Evaluate the tool's [Tool.needsApproval] callback for each call.
  conditional,

  /// Require approval for every call.
  always,
}

typedef ToolApprovalPolicySelector =
    ToolApprovalPolicy? Function(String toolName, Object input);

/// Example input for a tool; helps the model understand expected usage.
class ToolInputExample {
  const ToolInputExample({required this.input});

  final Map<String, dynamic> input;
}

/// A typed schema wrapper for tool inputs/structured outputs.
///
/// Pass any decoder that maps the provider's JSON object to your application
/// type; code generation is optional.
class Schema<T> {
  const Schema({
    required this.jsonSchema,
    required T Function(Map<String, dynamic>) fromJson,
    this.validator,
  }) : _decoder = fromJson;

  const Schema.decoderOnly({
    required this.jsonSchema,
    required T Function(Map<String, dynamic>) fromJson,
  }) : _decoder = fromJson,
       validator = null;

  final Map<String, dynamic> jsonSchema;
  final T Function(Map<String, dynamic>) _decoder;

  /// Optional runtime validation. Without it, the decoder determines acceptance.
  final SchemaValidator? validator;

  T fromJson(Map<String, dynamic> value) {
    final issues =
        validator?.validate(value) ?? const <SchemaValidationIssue>[];
    if (issues.isNotEmpty) throw SchemaValidationException(issues);
    return _decoder(value);
  }
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
    this.approvalPolicy = ToolApprovalPolicy.never,
    this.dynamic = false,
    this.toolContext,
    this.toolContextIsBound = false,
  });

  final String? description;
  final Schema<INPUT> inputSchema;
  final ToolExecutor<INPUT, OUTPUT>? execute;
  final UntypedToolExecutor? executeDynamic;
  final bool? strict;
  final List<ToolInputExample> inputExamples;
  final ToolNeedsApproval<INPUT>? needsApproval;
  final UntypedToolNeedsApproval? needsApprovalDynamic;
  final ToolApprovalPolicy approvalPolicy;
  final bool dynamic;

  /// Explicit application context bound to this tool's executor.
  final Object? toolContext;
  final bool toolContextIsBound;
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
  ToolApprovalPolicy? approvalPolicy,
  Object? toolContext,
  bool toolContextIsBound = false,
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
    approvalPolicy:
        approvalPolicy ??
        (needsApproval == null
            ? ToolApprovalPolicy.never
            : ToolApprovalPolicy.conditional),
    toolContext: toolContext,
    toolContextIsBound: toolContextIsBound || toolContext != null,
  );
}

/// Defines a tool whose executor receives its bound context as a typed value.
///
/// The context is kept out of provider messages and response history. The
/// existing [tool] helper remains source compatible for executors that prefer
/// to read [ToolExecutionOptions.toolContext] directly.
Tool<INPUT, OUTPUT> toolWithContext<INPUT, OUTPUT, CONTEXT>({
  required Schema<INPUT> inputSchema,
  required CONTEXT context,
  required ToolContextExecutor<INPUT, OUTPUT, CONTEXT> execute,
  String? description,
  bool? strict,
  List<ToolInputExample> inputExamples = const [],
  ToolNeedsApproval<INPUT>? needsApproval,
  ToolApprovalPolicy? approvalPolicy,
}) {
  return tool<INPUT, OUTPUT>(
    inputSchema: inputSchema,
    description: description,
    strict: strict,
    inputExamples: inputExamples,
    needsApproval: needsApproval,
    approvalPolicy: approvalPolicy,
    toolContext: context,
    toolContextIsBound: true,
    execute: (input, options) {
      final boundContext = options.toolContext as ToolExecutionContext<Object?>;
      return execute(input, boundContext.value as CONTEXT, options);
    },
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
  ToolApprovalPolicy? approvalPolicy,
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
    approvalPolicy:
        approvalPolicy ??
        (needsApproval == null
            ? ToolApprovalPolicy.never
            : ToolApprovalPolicy.conditional),
    dynamic: true,
  );
}
