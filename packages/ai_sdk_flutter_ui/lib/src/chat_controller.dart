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

  Object? _error;
  Object? get error => _error;

  /// Live content of the currently-streaming assistant message.
  /// Empty string when not streaming.
  String get streamingContent => _streamBuffer.toString();

  final StringBuffer _streamBuffer = StringBuffer();
  StreamSubscription<String>? _activeSubscription;
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
    );
    notifyListeners();
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

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          _streamBuffer.write(delta);
          notifyListeners();
        },
        onDone: () {
          final assistantMessage = ModelMessage(
            role: ModelMessageRole.assistant,
            content: _streamBuffer.toString(),
          );
          _messages.add(assistantMessage);
          _streamBuffer.clear();
          _status = ChatStatus.ready;
          notifyListeners();
          onFinish?.call(assistantMessage);
        },
        onError: (Object err) {
          _error = err;
          _streamBuffer.clear();
          _status = ChatStatus.error;
          notifyListeners();
          onError?.call(err);
        },
        cancelOnError: true,
      );
    } catch (err) {
      _error = err;
      _streamBuffer.clear();
      _status = ChatStatus.error;
      notifyListeners();
      onError?.call(err);
    }
  }

  /// Cancel the active stream.
  Future<void> stop() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    if (_streamBuffer.isNotEmpty) {
      _messages.add(
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: _streamBuffer.toString(),
        ),
      );
      _streamBuffer.clear();
    }
    _status = ChatStatus.ready;
    notifyListeners();
  }

  /// Remove all messages and reset to initial state.
  void clear() {
    _messages
      ..clear()
      ..addAll(initialMessages);
    _streamBuffer.clear();
    _pendingApprovals.clear();
    _status = ChatStatus.ready;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    super.dispose();
  }
}
