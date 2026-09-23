import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'streaming_controller_base.dart';

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
class ChatController extends StreamingControllerBase {
  ChatController({
    this.id,
    this.initialMessages = const [],
    this.onFinish,
    this.onError,
    super.notificationScheduler,
  }) : _messages = List<ModelMessage>.from(initialMessages);

  /// Optional identifier for this chat session.
  final String? id;

  final List<ModelMessage> initialMessages;

  /// Called when a generation completes successfully.
  /// Errors from the callback are ignored after state is updated.
  final FutureOr<void> Function(ModelMessage message)? onFinish;

  /// Called when a generation errors.
  /// Errors from the callback are ignored after state is updated.
  final FutureOr<void> Function(Object error)? onError;

  /// Notifies when generation/composer-facing state changes.
  ///
  /// This covers [status], [isLoading], [error], and
  /// [pendingApprovalRequests].
  @override
  Listenable get statusListenable => super.statusListenable;

  /// Notifies when transcript/content state changes.
  ///
  /// This covers [messages], [streamingContent], [streamingReasoning],
  /// [reasoningText], [lastUsage], [lastSources], [lastToolCalls], and
  /// [lastToolResults].
  @override
  Listenable get contentListenable => super.contentListenable;

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
  LanguageModelV4Usage? get lastUsage => _lastUsage;
  LanguageModelV4Usage? _lastUsage;

  /// Source citations gathered from the most recent completed turn.
  List<LanguageModelV4SourcePart> get lastSources =>
      List.unmodifiable(_lastSources);
  List<LanguageModelV4SourcePart> _lastSources = const [];

  /// Tool calls made during the most recent completed turn.
  List<LanguageModelV4ToolCallPart> get lastToolCalls =>
      List.unmodifiable(_lastToolCalls);
  List<LanguageModelV4ToolCallPart> _lastToolCalls = const [];

  /// Tool results produced during the most recent completed turn.
  List<LanguageModelV4ToolResultPart> get lastToolResults =>
      List.unmodifiable(_lastToolResults);
  List<LanguageModelV4ToolResultPart> _lastToolResults = const [];

  /// Tool-approval requests awaiting a decision. Non-empty only while
  /// [status] is [ChatStatus.awaitingApproval]. Render each with
  /// `ToolApprovalCard` and answer via [addToolApprovalResponse].
  List<LanguageModelV4ToolApprovalRequestPart> get pendingApprovalRequests =>
      List.unmodifiable(_pendingApprovalRequests);
  List<LanguageModelV4ToolApprovalRequestPart> _pendingApprovalRequests =
      const [];

  final StringBuffer _streamBuffer = StringBuffer();
  StreamSubscription<String>? _activeSubscription;
  StreamSubscription<StreamTextEvent>? _errorSubscription;
  CancellationToken? _activeAbortSignal;
  ToolLoopAgent? _lastAgent;

  // Pending tool-approval responses indexed by approvalId.
  final Map<String, LanguageModelV4ToolApprovalResponse> _pendingApprovals = {};
  ToolApprovalReplay? _pendingApprovalReplay;

  void _cancelActiveRequestSync() {
    activeRequestId = null;
    _activeAbortSignal?.cancel();
    _activeAbortSignal = null;
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _streamBuffer.clear();
    _streamingReasoning = '';
  }

  Future<void> _cancelActiveRequest({bool commitPartial = false}) async {
    activeRequestId = null;
    _activeAbortSignal?.cancel();
    _activeAbortSignal = null;
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    await _errorSubscription?.cancel();
    _errorSubscription = null;
    if (commitPartial && _streamBuffer.isNotEmpty) {
      _messages.add(
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: _streamBuffer.toString(),
        ),
      );
    }
    _streamBuffer.clear();
    _streamingReasoning = '';
  }

  void _discardApprovalState() {
    _pendingApprovalRequests = const [];
    _pendingApprovals.clear();
    _pendingApprovalReplay = null;
  }

  /// Submit [text] as a user message and stream the assistant response.
  Future<void> sendMessage({
    required ToolLoopAgent agent,
    required String text,
  }) async {
    _lastAgent = agent;
    _discardApprovalState();
    append(ModelMessage(role: ModelMessageRole.user, content: text));
    await _runGeneration(agent);
  }

  /// Add a [message] to the list without triggering generation.
  void append(ModelMessage message) {
    _messages.add(message);
    notifyListenersSafely(immediate: true, content: true);
  }

  /// Re-run generation using the current message list.
  ///
  /// Removes the last assistant message (if any) so the model produces a
  /// fresh response. Requires a prior call to [sendMessage].
  /// Alias: [regenerate].
  Future<void> reload({ToolLoopAgent? agent}) async {
    final effectiveAgent = agent ?? _lastAgent;
    if (effectiveAgent == null) return;
    _discardApprovalState();

    // Remove trailing assistant message to allow regeneration.
    if (_messages.isNotEmpty &&
        _messages.last.role == ModelMessageRole.assistant) {
      _messages.removeLast();
      notifyListenersSafely(immediate: true, content: true);
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
      notifyListenersSafely(immediate: true, status: true);
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
    final request = _pendingApprovalRequests
        .cast<LanguageModelV4ToolApprovalRequestPart?>()
        .firstWhere(
          (value) => value?.approvalId == approvalId,
          orElse: () => null,
        );
    _pendingApprovals[approvalId] = LanguageModelV4ToolApprovalResponse(
      approvalId: approvalId,
      approved: approved,
      reason: reason,
      toolCallId: request?.toolCall.toolCallId,
      toolName: request?.toolCall.toolName,
      argumentsFingerprint: request?.argumentsFingerprint,
      policyRevision: request?.policyRevision,
    );
    _pendingApprovalRequests = _pendingApprovalRequests
        .where((request) => request.approvalId != approvalId)
        .toList();
    notifyListenersSafely(immediate: true, status: true);

    // Once every paused request has a decision, replay the turn with the
    // collected responses so the agent can execute (or skip) the tools.
    if (_status == ChatStatus.awaitingApproval &&
        _pendingApprovalRequests.isEmpty &&
        _lastAgent != null) {
      unawaited(_runGeneration(_lastAgent!, consumeApprovals: true));
    }
  }

  /// Returns any pending tool-approval responses and clears the buffer.
  List<LanguageModelV4ToolApprovalResponse> _consumeApprovals() {
    if (_pendingApprovals.isEmpty) return const [];
    final result = _pendingApprovals.values.toList();
    _pendingApprovals.clear();
    return result;
  }

  Future<void> _runGeneration(
    ToolLoopAgent agent, {
    bool consumeApprovals = false,
  }) async {
    final approvalReplay = consumeApprovals ? _pendingApprovalReplay : null;
    _cancelActiveRequestSync();
    final requestId = ++nextRequestId;
    final abortSignal = CancellationToken();
    activeRequestId = requestId;
    _activeAbortSignal = abortSignal;
    _streamBuffer.clear();
    _streamingReasoning = '';
    _pendingApprovalRequests = const [];
    if (consumeApprovals) _pendingApprovalReplay = null;
    if (!consumeApprovals) {
      _reasoningText = '';
      _lastUsage = null;
      _lastSources = const [];
      _lastToolCalls = const [];
      _lastToolResults = const [];
    }
    _status = ChatStatus.submitted;
    _error = null;
    notifyListenersSafely(immediate: true, status: true, content: true);

    try {
      final List<LanguageModelV4ToolApprovalResponse> approvals =
          consumeApprovals ? _consumeApprovals() : const [];
      final streamResult = approvalReplay == null
          ? await agent.stream(
              messages: messages,
              toolApprovalResponses: approvals,
              abortSignal: abortSignal,
            )
          : await agent.resume(
              replay: approvalReplay,
              messages: messages,
              toolApprovalResponses: approvals,
              abortSignal: abortSignal,
            );
      if (!isCurrentRequest(requestId)) return;
      _status = ChatStatus.streaming;
      notifyListenersSafely(immediate: true, status: true);

      // The result's `text`/`output` futures reject on a streaming error; we
      // surface errors via [fullStream] instead, so swallow those completions
      // to keep them from becoming unhandled async errors.
      streamResult.text.then((_) {}, onError: (_) {});
      streamResult.output.then((_) {}, onError: (_) {});

      // Streaming errors surface on the full event stream (not the text
      // stream), so watch both: text for content, fullStream for errors and
      // live reasoning deltas.
      _errorSubscription = streamResult.stream.listen((event) {
        if (!isCurrentRequest(requestId)) return;
        if (event is StreamTextErrorEvent) {
          _handleError(event.error, requestId);
        } else if (event is StreamTextReasoningDeltaEvent) {
          _streamingReasoning += event.delta;
          notifyListenersSafely(immediate: false, content: true);
        }
      }, onError: (Object err) => _handleError(err, requestId));

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          if (!isCurrentRequest(requestId)) return;
          _streamBuffer.write(delta);
          notifyListenersSafely(immediate: false, content: true);
        },
        onDone: () => unawaited(
          _finalizeTurn(
            streamResult,
            requestId,
            mergeMetadata: consumeApprovals,
            approvalReplay: approvalReplay,
          ),
        ),
        onError: (Object err) => _handleError(err, requestId),
        cancelOnError: true,
      );
    } catch (err) {
      if (!isCurrentRequest(requestId) || abortSignal.isCancelled) return;
      _handleError(err, requestId);
    }
  }

  /// Finalize a completed (or approval-paused) turn: capture the turn's
  /// metadata, then either surface pending approval requests or commit the
  /// assistant message.
  Iterable<ModelMessage> _replayMessagesForStep(GenerateTextStep step) sync* {
    final assistantParts = step.content
        .where((part) => part is! LanguageModelV4ToolApprovalRequestPart)
        .toList(growable: false);
    if (assistantParts.isNotEmpty) {
      yield ModelMessage.parts(
        role: ModelMessageRole.assistant,
        parts: assistantParts,
      );
    }
    if (step.toolResults.isNotEmpty) {
      yield ModelMessage.parts(
        role: ModelMessageRole.tool,
        parts: step.toolResults,
      );
    }
  }

  Future<void> _finalizeTurn(
    StreamTextResult streamResult,
    int requestId, {
    required bool mergeMetadata,
    ToolApprovalReplay? approvalReplay,
  }) async {
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;

    // An error event may already have moved us out of streaming.
    if (!isCurrentRequest(requestId) || _status != ChatStatus.streaming) {
      return;
    }

    var approvals = const <LanguageModelV4ToolApprovalRequestPart>[];
    var steps = const <GenerateTextStep>[];
    LanguageModelV4Usage? usage;
    List<LanguageModelV4SourcePart> sources = const [];
    List<LanguageModelV4ToolCallPart> toolCalls = const [];
    List<LanguageModelV4ToolResultPart> toolResults = const [];
    String reasoningText = '';
    try {
      steps = await streamResult.steps;
      approvals = [for (final step in steps) ...step.toolApprovalRequests];
      usage = await streamResult.totalUsage ?? await streamResult.usage;
      sources = await streamResult.sources;
      toolCalls = await streamResult.toolCalls;
      toolResults = await streamResult.toolResults;
      reasoningText = await streamResult.reasoningText;
    } catch (_) {
      // Metadata is best-effort; a late stream error must not break finalize.
    }

    // A late error may have arrived while awaiting the result futures.
    if (!isCurrentRequest(requestId) || _status != ChatStatus.streaming) {
      return;
    }

    activeRequestId = null;
    _activeAbortSignal = null;
    _lastUsage = usage ?? _lastUsage;
    _lastSources = mergeMetadata
        ? _mergeById(_lastSources, sources, (s) => '${s.id}|${s.url}')
        : sources;
    _lastToolCalls = mergeMetadata
        ? _mergeById(_lastToolCalls, toolCalls, (c) => c.toolCallId)
        : toolCalls;
    _lastToolResults = mergeMetadata
        ? _mergeById(_lastToolResults, toolResults, (r) => r.toolCallId)
        : toolResults;
    if (reasoningText.isNotEmpty || !mergeMetadata) {
      _reasoningText = reasoningText;
    }

    if (approvals.isNotEmpty) {
      _pendingApprovalReplay = ToolApprovalReplay(
        messages: [
          ...?approvalReplay?.messages,
          for (final step in steps) ..._replayMessagesForStep(step),
        ],
        requests: approvals,
      );
      _pendingApprovalRequests = approvals;
      _streamBuffer.clear();
      _streamingReasoning = '';
      _status = ChatStatus.awaitingApproval;
      notifyListenersSafely(immediate: true, status: true, content: true);
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
    notifyListenersSafely(immediate: true, status: true, content: true);
    try {
      final result = onFinish?.call(assistantMessage);
      if (result is Future<void>) unawaited(result.catchError((_) {}));
    } catch (_) {}
  }

  /// Merges [previous] and [current] by the key returned from [keyOf],
  /// preferring the [current] entry for any id present in both.
  List<T> _mergeById<T>(
    List<T> previous,
    List<T> current,
    Object Function(T) keyOf,
  ) {
    if (previous.isEmpty) return current;
    if (current.isEmpty) return previous;

    final merged = <Object, T>{};
    for (final item in previous) {
      merged[keyOf(item)] = item;
    }
    for (final item in current) {
      merged[keyOf(item)] = item;
    }
    return merged.values.toList(growable: false);
  }

  void _handleError(Object err, int requestId) {
    if (!isCurrentRequest(requestId) || _status == ChatStatus.error) return;
    activeRequestId = null;
    _activeAbortSignal = null;
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _error = err;
    _streamBuffer.clear();
    _streamingReasoning = '';
    _status = ChatStatus.error;
    notifyListenersSafely(immediate: true, status: true, content: true);
    try {
      final result = onError?.call(err);
      if (result is Future<void>) unawaited(result.catchError((_) {}));
    } catch (_) {}
  }

  /// Cancel the active stream.
  Future<void> stop() async {
    await _cancelActiveRequest(commitPartial: true);
    _discardApprovalState();
    _status = ChatStatus.ready;
    notifyListenersSafely(immediate: true, status: true, content: true);
  }

  /// Remove all messages and reset to initial state.
  void clear() {
    _cancelActiveRequestSync();
    _messages
      ..clear()
      ..addAll(initialMessages);
    _reasoningText = '';
    _lastUsage = null;
    _lastSources = const [];
    _lastToolCalls = const [];
    _lastToolResults = const [];
    _discardApprovalState();
    _status = ChatStatus.ready;
    _error = null;
    notifyListenersSafely(immediate: true, status: true, content: true);
  }

  @override
  void dispose() {
    isDisposed = true;
    _cancelActiveRequestSync();
    super.dispose();
  }
}
