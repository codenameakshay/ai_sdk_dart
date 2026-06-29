import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Status of the chat controller.
enum ChatStatus {
  /// Idle; no generation in progress.
  ready,

  /// Request submitted; waiting for first token.
  submitted,

  /// Actively streaming response.
  streaming,

  /// The turn paused waiting on one or more tool-approval decisions. Supply
  /// them via [ChatController.addToolApprovalResponse]; once every pending
  /// request is answered the turn resumes automatically.
  awaitingApproval,

  /// An error occurred.
  error,
}

/// Flutter controller for chat interfaces — mirrors the JS `useChat` hook.
///
/// Provides:
/// - [sendMessage] — submit a new user turn and stream the response
/// - [append] — add a message without triggering a new generation
/// - [reload] / [regenerate] — re-run the last assistant turn
/// - [stop] — cancel the active stream
/// - [clearError] — clear the current error state
/// - [addToolApprovalResponse] — inject a tool approval decision mid-stream
/// - Optimistic assistant message during streaming via [streamingContent]
/// - [isLoading] — true while submitted or streaming
class ChatController extends ChangeNotifier {
  ChatController({
    this.id,
    this.initialMessages = const [],
    this.onFinish,
    this.onError,
  }) : _messages = List<ModelMessage>.from(initialMessages);

  /// Optional identifier for this chat session.
  final String? id;

  final List<ModelMessage> initialMessages;

  /// Called when a generation completes successfully.
  final void Function(ModelMessage message)? onFinish;

  /// Called when a generation errors.
  final void Function(Object error)? onError;

  final List<ModelMessage> _messages;

  List<ModelMessage> get messages => List.unmodifiable(_messages);

  ChatStatus _status = ChatStatus.ready;
  ChatStatus get status => _status;

  /// True while the controller is submitted or actively streaming.
  /// Mirrors the `isLoading` property of the JS `useChat` hook.
  bool get isLoading =>
      _status == ChatStatus.submitted || _status == ChatStatus.streaming;

  /// True while the assistant response is actively streaming.
  ///
  /// Provided for consistency with [CompletionController] and
  /// [ObjectStreamController], which both expose an `isStreaming` flag.
  /// Equivalent to `status == ChatStatus.streaming`.
  bool get isStreaming => _status == ChatStatus.streaming;

  Object? _error;
  Object? get error => _error;

  /// Live content of the currently-streaming assistant message.
  /// Empty string when not streaming.
  String get streamingContent => _streamBuffer.toString();

  /// Live reasoning ("thinking") text for the in-flight turn, accumulated from
  /// the model's reasoning deltas. Empty when there is none. Pair it with
  /// `ReasoningView`.
  String get streamingReasoning => _streamingReasoning;
  String _streamingReasoning = '';

  /// Final reasoning text of the most recent completed turn.
  String get reasoningText => _reasoningText;
  String _reasoningText = '';

  /// Token usage reported by the most recent completed turn, if any.
  LanguageModelV3Usage? get lastUsage => _lastUsage;
  LanguageModelV3Usage? _lastUsage;

  /// Source citations gathered from the most recent completed turn.
  List<LanguageModelV3SourcePart> get lastSources =>
      List.unmodifiable(_lastSources);
  List<LanguageModelV3SourcePart> _lastSources = const [];

  /// Tool calls made during the most recent completed turn.
  List<LanguageModelV3ToolCallPart> get lastToolCalls =>
      List.unmodifiable(_lastToolCalls);
  List<LanguageModelV3ToolCallPart> _lastToolCalls = const [];

  /// Tool results produced during the most recent completed turn.
  List<LanguageModelV3ToolResultPart> get lastToolResults =>
      List.unmodifiable(_lastToolResults);
  List<LanguageModelV3ToolResultPart> _lastToolResults = const [];

  /// Tool-approval requests awaiting a decision. Non-empty only while
  /// [status] is [ChatStatus.awaitingApproval]. Render each with
  /// `ToolApprovalCard` and answer via [addToolApprovalResponse].
  List<LanguageModelV3ToolApprovalRequestPart> get pendingApprovalRequests =>
      List.unmodifiable(_pendingApprovalRequests);
  List<LanguageModelV3ToolApprovalRequestPart> _pendingApprovalRequests =
      const [];

  final StringBuffer _streamBuffer = StringBuffer();
  StreamSubscription<String>? _activeSubscription;
  StreamSubscription<StreamTextEvent>? _errorSubscription;
  ToolLoopAgent? _lastAgent;

  // Pending tool-approval responses indexed by approvalId.
  final Map<String, LanguageModelV3ToolApprovalResponse> _pendingApprovals = {};

  /// Submit [text] as a user message and stream the assistant response.
  Future<void> sendMessage({
    required ToolLoopAgent agent,
    required String text,
  }) async {
    _lastAgent = agent;
    append(ModelMessage(role: ModelMessageRole.user, content: text));
    await _runGeneration(agent);
  }

  /// Add a [message] to the list without triggering generation.
  void append(ModelMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  /// Re-run generation using the current message list.
  ///
  /// Removes the last assistant message (if any) so the model produces a
  /// fresh response. Requires a prior call to [sendMessage].
  /// Alias: [regenerate].
  Future<void> reload({ToolLoopAgent? agent}) async {
    final effectiveAgent = agent ?? _lastAgent;
    if (effectiveAgent == null) return;

    // Remove trailing assistant message to allow regeneration.
    if (_messages.isNotEmpty &&
        _messages.last.role == ModelMessageRole.assistant) {
      _messages.removeLast();
      notifyListeners();
    }

    await _runGeneration(effectiveAgent);
  }

  /// Alias for [reload] — mirrors the JS `useChat` `regenerate()` method.
  Future<void> regenerate({ToolLoopAgent? agent}) => reload(agent: agent);

  /// Clear the current error and reset [status] to [ChatStatus.ready].
  ///
  /// Mirrors the JS `useChat` `clearError()` method.
  void clearError() {
    if (_status == ChatStatus.error) {
      _error = null;
      _status = ChatStatus.ready;
      notifyListeners();
    }
  }

  /// Inject a tool-approval response for an in-flight approval request.
  ///
  /// The [approvalId] must match the one emitted in the
  /// [StreamTextToolApprovalRequestEvent].  [approved] controls whether the
  /// tool call is executed; [reason] is optional context.
  ///
  /// Mirrors the JS `useChat` `addToolApprovalResponse()` method.
  void addToolApprovalResponse({
    required String approvalId,
    required bool approved,
    String? reason,
  }) {
    _pendingApprovals[approvalId] = LanguageModelV3ToolApprovalResponse(
      approvalId: approvalId,
      approved: approved,
      reason: reason,
    );
    _pendingApprovalRequests = _pendingApprovalRequests
        .where((request) => request.approvalId != approvalId)
        .toList();
    notifyListeners();

    // Once every paused request has a decision, replay the turn with the
    // collected responses so the agent can execute (or skip) the tools.
    if (_status == ChatStatus.awaitingApproval &&
        _pendingApprovalRequests.isEmpty &&
        _lastAgent != null) {
      unawaited(_runGeneration(_lastAgent!));
    }
  }

  /// Returns any pending tool-approval responses and clears the buffer.
  List<LanguageModelV3ToolApprovalResponse> _consumeApprovals() {
    if (_pendingApprovals.isEmpty) return const [];
    final result = _pendingApprovals.values.toList();
    _pendingApprovals.clear();
    return result;
  }

  Future<void> _runGeneration(ToolLoopAgent agent) async {
    _streamBuffer.clear();
    _streamingReasoning = '';
    _reasoningText = '';
    _lastUsage = null;
    _lastSources = const [];
    _lastToolCalls = const [];
    _lastToolResults = const [];
    _pendingApprovalRequests = const [];
    _status = ChatStatus.submitted;
    _error = null;
    notifyListeners();

    try {
      final streamResult = await agent.stream(
        messages: messages,
        toolApprovalResponses: _consumeApprovals(),
      );
      _status = ChatStatus.streaming;
      notifyListeners();

      // The result's `text`/`output` futures reject on a streaming error; we
      // surface errors via [fullStream] instead, so swallow those completions
      // to keep them from becoming unhandled async errors.
      streamResult.text.then((_) {}, onError: (_) {});
      streamResult.output.then((_) {}, onError: (_) {});

      // Streaming errors surface on the full event stream (not the text
      // stream), so watch both: text for content, fullStream for errors and
      // live reasoning deltas.
      _errorSubscription = streamResult.fullStream.listen((event) {
        if (event is StreamTextErrorEvent) {
          _handleError(event.error);
        } else if (event is StreamTextReasoningDeltaEvent) {
          _streamingReasoning += event.delta;
          notifyListeners();
        }
      }, onError: _handleError);

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          _streamBuffer.write(delta);
          notifyListeners();
        },
        onDone: () => unawaited(_finalizeTurn(streamResult)),
        onError: _handleError,
        cancelOnError: true,
      );
    } catch (err) {
      _handleError(err);
    }
  }

  /// Finalize a completed (or approval-paused) turn: capture the turn's
  /// metadata, then either surface pending approval requests or commit the
  /// assistant message.
  Future<void> _finalizeTurn(StreamTextResult streamResult) async {
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;

    // An error event may already have moved us out of streaming.
    if (_status != ChatStatus.streaming) return;

    var approvals = const <LanguageModelV3ToolApprovalRequestPart>[];
    try {
      final steps = await streamResult.steps;
      approvals = [
        for (final step in steps) ...step.toolApprovalRequests,
      ];
      _lastUsage = await streamResult.totalUsage ?? await streamResult.usage;
      _lastSources = await streamResult.sources;
      _lastToolCalls = await streamResult.toolCalls;
      _lastToolResults = await streamResult.toolResults;
      _reasoningText = await streamResult.reasoningText;
    } catch (_) {
      // Metadata is best-effort; a late stream error must not break finalize.
    }

    // A late error may have arrived while awaiting the result futures.
    if (_status != ChatStatus.streaming) return;

    if (approvals.isNotEmpty) {
      _pendingApprovalRequests = approvals;
      _streamBuffer.clear();
      _streamingReasoning = '';
      _status = ChatStatus.awaitingApproval;
      notifyListeners();
      return;
    }

    final assistantMessage = ModelMessage(
      role: ModelMessageRole.assistant,
      content: _streamBuffer.toString(),
    );
    _messages.add(assistantMessage);
    _streamBuffer.clear();
    _streamingReasoning = '';
    _status = ChatStatus.ready;
    notifyListeners();
    onFinish?.call(assistantMessage);
  }

  void _handleError(Object err) {
    if (_status == ChatStatus.error) return; // first error wins
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _error = err;
    _streamBuffer.clear();
    _status = ChatStatus.error;
    notifyListeners();
    onError?.call(err);
  }

  /// Cancel the active stream.
  Future<void> stop() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    await _errorSubscription?.cancel();
    _errorSubscription = null;
    if (_streamBuffer.isNotEmpty) {
      _messages.add(
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: _streamBuffer.toString(),
        ),
      );
      _streamBuffer.clear();
    }
    _streamingReasoning = '';
    _pendingApprovalRequests = const [];
    _status = ChatStatus.ready;
    notifyListeners();
  }

  /// Remove all messages and reset to initial state.
  void clear() {
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _messages
      ..clear()
      ..addAll(initialMessages);
    _streamBuffer.clear();
    _streamingReasoning = '';
    _reasoningText = '';
    _lastUsage = null;
    _lastSources = const [];
    _lastToolCalls = const [];
    _lastToolResults = const [];
    _pendingApprovalRequests = const [];
    _pendingApprovals.clear();
    _status = ChatStatus.ready;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }
}
