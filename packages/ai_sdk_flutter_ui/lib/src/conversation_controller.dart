import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';

import 'chat_controller.dart';

/// A UI-owned seam for conversation-backed chat implementations.
///
/// Adapters own conversion at the backend boundary. Restoring a snapshot only
/// decodes data; it never calls a tool or a provider.
abstract interface class ConversationBackend {
  Conversation get conversation;
  Stream<Conversation> get changes;
  Future<void> send(String text);
  Future<void> interrupt();
  Future<void> restore(Map<String, dynamic> encoded);
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  });
  Future<void> dispose();
}

/// Describes whether a failed conversation turn can be retried safely.
enum ConversationRetryAvailability {
  available,
  noFailedTurn,
  pendingApproval,
  unsafe,
  unsupported,
}

class ConversationRetryInfo {
  const ConversationRetryInfo(this.availability, {this.reason});

  final ConversationRetryAvailability availability;
  final String? reason;

  bool get isAvailable =>
      availability == ConversationRetryAvailability.available;
}

/// Optional retry capability for conversation backends.
///
/// Keeping this separate from [ConversationBackend] preserves source
/// compatibility for custom backends that do not know how to retry a turn.
abstract interface class ConversationRetryBackend {
  ConversationRetryInfo get retryInfo;
  Future<void> retryLastTurn();
}

class ConversationRetryError implements Exception {
  ConversationRetryError(this.message);
  final String message;
  @override
  String toString() => message;
}

class RetryUnsafeError extends ConversationRetryError {
  RetryUnsafeError(super.message);
}

class RetryUnsupportedError extends ConversationRetryError {
  RetryUnsupportedError(super.message);
}

/// A small controller bridge usable by widgets that need typed snapshots.
class ConversationController {
  ConversationController(this.backend, {this.disposeBackend = true}) {
    _subscription = backend.changes.listen((value) {
      _conversation = value;
      _listeners.add(null);
    });
  }

  final ConversationBackend backend;

  /// Whether this controller owns and disposes [backend]. Set false when a
  /// provider or another lifecycle scope owns the backend.
  final bool disposeBackend;
  late Conversation _conversation = backend.conversation;
  final _listeners = StreamController<void>.broadcast();
  late final StreamSubscription<Conversation> _subscription;
  bool _disposed = false;

  Conversation get conversation => _conversation;
  Stream<void> get changes => _listeners.stream;

  Future<void> send(String text) => backend.send(text);
  ConversationRetryInfo get retryInfo => backend is ConversationRetryBackend
      ? (backend as ConversationRetryBackend).retryInfo
      : const ConversationRetryInfo(
          ConversationRetryAvailability.unsupported,
          reason: 'This conversation backend does not support retry.',
        );
  Future<void> retryLastTurn() {
    final retry = backend;
    if (retry is ConversationRetryBackend) {
      return (retry as ConversationRetryBackend).retryLastTurn();
    }
    return Future.error(
      RetryUnsupportedError(
        'This conversation backend does not support retry.',
      ),
    );
  }

  Future<void> interrupt() => backend.interrupt();
  Future<void> restore(Map<String, dynamic> encoded) =>
      backend.restore(encoded);
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) => backend.respondToApproval(
    approvalId: approvalId,
    approved: approved,
    reason: reason,
  );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final cancelSubscription = _subscription.cancel();
    final disposeOwnedBackend = disposeBackend
        ? backend.dispose()
        : Future<void>.value();
    await Future.wait([cancelSubscription, disposeOwnedBackend]);
    await _listeners.close();
  }
}

/// A [ChatController] view over a persisted [ConversationController].
///
/// This adapter lets the existing message list, composer, approval cards and
/// accessibility behavior render local and remote conversation backends using
/// the same widgets. It owns the subscription to [conversationController]; the
/// underlying controller is disposed when [disposeConversationController] is
/// true.
class ConversationChatController extends ChatController {
  ConversationChatController(
    this.conversationController, {
    this.disposeConversationController = true,
    super.notificationScheduler,
  }) : super() {
    _conversationSubscription = conversationController.changes.listen((_) {
      _snapshot = conversationController.conversation;
      _awaitingBackendSnapshot = false;
      _failureDismissed = false;
      _refreshFromSnapshot();
    });
    _refreshFromSnapshot();
  }

  final ConversationController conversationController;
  final bool disposeConversationController;
  late Conversation _snapshot = conversationController.conversation;
  late final StreamSubscription<void> _conversationSubscription;
  bool _sending = false;
  int _operationGeneration = 0;
  bool _awaitingBackendSnapshot = false;
  bool _failureDismissed = false;
  Object? _conversationError;
  ChatStatus _conversationStatus = ChatStatus.ready;

  @override
  List<ModelMessage> get messages => [
    for (final message in _snapshot.messages) _toModelMessage(message),
  ];

  @override
  ChatStatus get status => _conversationStatus;

  @override
  bool get isLoading =>
      _conversationStatus == ChatStatus.submitted ||
      _conversationStatus == ChatStatus.streaming;

  @override
  bool get isStreaming => _conversationStatus == ChatStatus.streaming;

  @override
  Object? get error => _conversationError;

  @override
  String get streamingContent => '';

  @override
  List<LanguageModelV4ToolApprovalRequestPart> get pendingApprovalRequests =>
      _pendingApprovals();

  ConversationRetryInfo get retryInfo => conversationController.retryInfo;

  /// Sends through the backend. [agent] is accepted for source compatibility
  /// with [ChatController] but is intentionally ignored by this adapter.
  @override
  Future<void> sendMessage({
    required ToolLoopAgent agent,
    required String text,
  }) => sendText(text);

  /// Sends text through the conversation backend without a model agent.
  Future<void> sendText(String text) async {
    final generation = ++_operationGeneration;
    _sending = true;
    _awaitingBackendSnapshot = true;
    _failureDismissed = false;
    _conversationError = null;
    _conversationStatus = ChatStatus.submitted;
    notifyListenersSafely(immediate: true, status: true, content: true);
    try {
      await conversationController.send(text);
    } catch (error) {
      if (generation != _operationGeneration || isDisposed) return;
      _conversationError = error;
      _conversationStatus = ChatStatus.error;
      notifyListenersSafely(immediate: true, status: true, content: true);
    } finally {
      if (generation == _operationGeneration && !isDisposed) {
        _sending = false;
        _refreshFromSnapshot();
      }
    }
  }

  @override
  Future<void> stop() async {
    ++_operationGeneration;
    _sending = false;
    _awaitingBackendSnapshot = false;
    await conversationController.interrupt();
    if (!isDisposed) _refreshFromSnapshot();
  }

  @override
  void addToolApprovalResponse({
    required String approvalId,
    required bool approved,
    String? reason,
  }) {
    final generation = _operationGeneration;
    unawaited(
      conversationController
          .respondToApproval(
            approvalId: approvalId,
            approved: approved,
            reason: reason,
          )
          .catchError((error) {
            if (generation != _operationGeneration || isDisposed) return;
            _conversationError = error;
            _conversationStatus = ChatStatus.error;
            notifyListenersSafely(immediate: true, status: true);
          }),
    );
  }

  @override
  void clearError() {
    if (_conversationError == null) return;
    _conversationError = null;
    _failureDismissed = true;
    _refreshFromSnapshot();
  }

  @override
  Future<void> reload({ToolLoopAgent? agent}) async {
    final generation = ++_operationGeneration;
    _sending = true;
    _awaitingBackendSnapshot = true;
    _failureDismissed = false;
    _conversationError = null;
    _conversationStatus = ChatStatus.submitted;
    notifyListenersSafely(immediate: true, status: true, content: true);
    try {
      await conversationController.retryLastTurn();
    } catch (error) {
      if (generation != _operationGeneration || isDisposed) return;
      _conversationError = error;
      _conversationStatus = ChatStatus.error;
      notifyListenersSafely(immediate: true, status: true, content: true);
    } finally {
      if (generation == _operationGeneration && !isDisposed) {
        _sending = false;
        _refreshFromSnapshot();
      }
    }
  }

  void _refreshFromSnapshot() {
    if (isDisposed) return;
    final assistant = _lastAssistantForCurrentTurn();
    if (_conversationError != null) {
      _conversationStatus = ChatStatus.error;
    } else if (_sending && (_awaitingBackendSnapshot || assistant == null)) {
      _conversationStatus = ChatStatus.submitted;
    } else {
      _conversationStatus = switch (assistant?.status) {
        ConversationMessageStatus.streaming => ChatStatus.streaming,
        ConversationMessageStatus.pendingApproval =>
          ChatStatus.awaitingApproval,
        ConversationMessageStatus.failed => () {
          if (!_failureDismissed) {
            _conversationError ??= StateError('Conversation request failed.');
          }
          return ChatStatus.error;
        }(),
        _ => ChatStatus.ready,
      };
    }
    notifyListenersSafely(immediate: true, status: true, content: true);
  }

  ConversationMessage? _lastAssistant() {
    for (final message in _snapshot.messages.reversed) {
      if (message.role == ConversationRole.assistant) return message;
    }
    return null;
  }

  ConversationMessage? _lastAssistantForCurrentTurn() {
    var lastUserIndex = -1;
    for (var i = 0; i < _snapshot.messages.length; i++) {
      if (_snapshot.messages[i].role == ConversationRole.user) {
        lastUserIndex = i;
      }
    }
    for (var i = _snapshot.messages.length - 1; i > lastUserIndex; i--) {
      final message = _snapshot.messages[i];
      if (message.role == ConversationRole.assistant) return message;
    }
    return null;
  }

  List<LanguageModelV4ToolApprovalRequestPart> _pendingApprovals() {
    final assistant = _lastAssistant();
    if (assistant == null) return const [];
    final calls = {
      for (final part in assistant.parts.whereType<ToolCallPart>())
        part.callId: part,
    };
    final requests = <LanguageModelV4ToolApprovalRequestPart>[];
    for (final approval in assistant.parts.whereType<ApprovalPart>()) {
      final call = calls[approval.callId];
      if (approval.status != ApprovalStatus.pending || call == null) continue;
      requests.add(
        LanguageModelV4ToolApprovalRequestPart(
          approvalId: approval.approvalId ?? approval.id,
          toolCall: LanguageModelV4ToolCallPart(
            toolCallId: call.callId,
            toolName: call.name,
            input: call.arguments,
          ),
          argumentsFingerprint: approval.argumentsFingerprint,
          policyRevision: approval.policyVersion,
        ),
      );
    }
    return requests;
  }

  @override
  void dispose() {
    ++_operationGeneration;
    _sending = false;
    unawaited(_conversationSubscription.cancel());
    super.dispose();
    if (disposeConversationController) {
      unawaited(conversationController.dispose());
    }
  }
}

/// Local adapter around [ToolLoopAgent].
class LocalConversationBackend
    implements ConversationBackend, ConversationRetryBackend {
  LocalConversationBackend({
    required ToolLoopAgent agent,
    required Conversation initial,
  }) : _agent = agent,
       _conversation = initial;

  final ToolLoopAgent _agent;
  Conversation _conversation;
  final _changes = StreamController<Conversation>.broadcast();
  CancellationToken? _cancellation;
  CancellationToken? _resumeCancellation;
  bool _disposed = false;
  int _epoch = 0;
  List<ConversationPart> _liveParts = [];
  String? _liveMessageId;
  final _streamPartIds = <String, String>{};
  ToolApprovalReplay? _pendingReplay;
  bool _restoredBindingInvalid = false;
  final _pendingApprovalRequests =
      <String, LanguageModelV4ToolApprovalRequestPart>{};
  final _pendingApprovalResponses =
      <String, LanguageModelV4ToolApprovalResponse>{};
  Future<void>? _resumeInFlight;

  @override
  Conversation get conversation => _conversation;
  @override
  Stream<Conversation> get changes => _changes.stream;

  @override
  ConversationRetryInfo get retryInfo =>
      _retryInfoForConversation(_conversation);

  @override
  Future<void> retryLastTurn() async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    final pair = _retryPair(_conversation);
    if (pair == null) {
      throw RetryUnsafeError(
        'Retry requires the latest turn to end with a failed assistant response.',
      );
    }
    final assistant = pair.$2;
    final hasUnsafePart = assistant.parts.any(
      (part) =>
          part is ToolCallPart ||
          part is ToolResultPart ||
          part is ApprovalPart ||
          part is UnknownPart,
    );
    if (hasUnsafePart) {
      throw RetryUnsafeError(
        'This turn may have executed a tool or provider action and cannot be retried safely. Send a new request or recover the turn explicitly.',
      );
    }

    await interrupt();
    final epoch = ++_epoch;
    final cancellation = CancellationToken();
    _cancellation = cancellation;
    _conversation = Conversation(
      id: _conversation.id,
      messages: [
        for (final message in _conversation.messages)
          if (message.id != assistant.id) message,
      ],
      metadata: _conversation.metadata,
      extra: _conversation.extra,
    );
    _liveMessageId = assistant.id;
    _liveParts = [];
    _streamPartIds.clear();
    _pendingReplay = null;
    _pendingApprovalRequests.clear();
    _pendingApprovalResponses.clear();
    _publishLive(ConversationMessageStatus.streaming);
    try {
      final result = await _agent.stream(
        messages: _toModelMessages(_conversation),
        abortSignal: cancellation,
      );
      await for (final event in result.stream) {
        if (_disposed || epoch != _epoch) return;
        _applyLocalEvent(event, epoch);
      }
      if (_disposed || epoch != _epoch) return;
      final steps = await result.steps;
      _mergeStepToolCalls(steps);
      final approvals = [
        for (final step in steps) ...step.toolApprovalRequests,
      ];
      if (approvals.isNotEmpty) {
        _pendingReplay = ToolApprovalReplay(
          messages: [for (final step in steps) ..._replayMessagesForStep(step)],
          requests: approvals,
        );
        _pendingApprovalRequests
          ..clear()
          ..addEntries(approvals.map((r) => MapEntry(r.approvalId, r)));
        _liveParts.addAll([
          for (final request in approvals)
            ApprovalPart(
              id: 'approval-${request.approvalId}',
              approvalId: request.approvalId,
              callId: request.toolCall.toolCallId,
              toolName: request.toolCall.toolName,
              argumentsFingerprint: request.argumentsFingerprint,
              policyVersion: request.policyRevision,
              status: ApprovalStatus.pending,
            ),
        ]);
        _publishLive(ConversationMessageStatus.pendingApproval);
        return;
      }
      _publishLive(ConversationMessageStatus.complete);
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _publishLive(ConversationMessageStatus.failed);
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  void _publish(Conversation value) {
    if (_disposed) return;
    _conversation = value;
    _changes.add(value);
  }

  @override
  Future<void> send(String text) async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    await interrupt();
    final epoch = ++_epoch;
    final userId = _freshId(_conversation, 'message');
    final user = ConversationMessage(
      id: userId,
      role: ConversationRole.user,
      parts: [TextPart(id: _freshId(_conversation, 'part'), text: text)],
    );
    _publish(
      Conversation(
        id: _conversation.id,
        messages: [..._conversation.messages, user],
        metadata: _conversation.metadata,
        extra: _conversation.extra,
      ),
    );
    final cancellation = CancellationToken();
    _cancellation = cancellation;
    _liveParts = [];
    _streamPartIds.clear();
    _liveMessageId = _freshId(_conversation, 'message');
    try {
      final result = await _agent.stream(
        messages: _toModelMessages(_conversation),
        abortSignal: cancellation,
      );
      await for (final event in result.stream) {
        if (_disposed || epoch != _epoch) return;
        _applyLocalEvent(event, epoch);
      }
      if (_disposed || epoch != _epoch) return;
      final steps = await result.steps;
      _mergeStepToolCalls(steps);
      final approvals = [
        for (final step in steps) ...step.toolApprovalRequests,
      ];
      if (approvals.isNotEmpty) {
        _pendingReplay = ToolApprovalReplay(
          messages: [for (final step in steps) ..._replayMessagesForStep(step)],
          requests: approvals,
        );
        _pendingApprovalRequests
          ..clear()
          ..addEntries(approvals.map((r) => MapEntry(r.approvalId, r)));
        _liveParts.addAll([
          for (final request in approvals)
            ApprovalPart(
              id: 'approval-${request.approvalId}',
              approvalId: request.approvalId,
              callId: request.toolCall.toolCallId,
              toolName: request.toolCall.toolName,
              argumentsFingerprint: request.argumentsFingerprint,
              policyVersion: request.policyRevision,
              status: ApprovalStatus.pending,
            ),
        ]);
        _publishLive(ConversationMessageStatus.pendingApproval);
        return;
      }
      _publishLive(ConversationMessageStatus.complete);
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _publishLive(ConversationMessageStatus.failed);
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  /// The public stream event reports tool input separately from the provider
  /// tool-call content. Reconcile the finished step so provider-only fields
  /// survive in the persisted conversation and can be replayed later.
  void _mergeStepToolCalls(Iterable<GenerateTextStep> steps) {
    for (final call in steps.expand((step) => step.toolCalls)) {
      final index = _liveParts.indexWhere(
        (part) => part is ToolCallPart && part.callId == call.toolCallId,
      );
      final id = index >= 0
          ? (_liveParts[index] as ToolCallPart).id
          : 'tool-${call.toolCallId}';
      final replacement = ToolCallPart(
        id: id,
        callId: call.toolCallId,
        name: call.toolName,
        arguments: call.input is Map
            ? (call.input as Map).cast<String, dynamic>()
            : const {},
        providerOptions: call.providerOptions ?? const {},
        providerExecuted: call.providerExecuted,
      );
      if (index >= 0) {
        _liveParts[index] = replacement;
      } else {
        _liveParts.add(replacement);
      }
    }
  }

  String _freshLivePartId(String prefix) {
    final used = <String>{
      for (final message in _conversation.messages) ...[
        message.id,
        ...message.parts.map((part) => part.id),
      ],
      ..._liveParts.map((part) => part.id),
    };
    for (var index = 0; ; index++) {
      final candidate = '$prefix-$index';
      if (used.add(candidate)) return candidate;
    }
  }

  @override
  Future<void> interrupt() async {
    _epoch++;
    _cancellation?.cancel();
    _cancellation = null;
    _resumeCancellation?.cancel();
    _resumeCancellation = null;
    if (_liveMessageId != null && !_disposed) {
      _publishLive(ConversationMessageStatus.interrupted);
    }
  }

  void _publishLive(ConversationMessageStatus status) {
    final id = _liveMessageId;
    if (id == null || _disposed) return;
    _publish(
      Conversation(
        id: _conversation.id,
        messages: [
          ..._conversation.messages.where((m) => m.id != id),
          ConversationMessage(
            id: id,
            role: ConversationRole.assistant,
            status: status,
            parts: List.of(_liveParts),
          ),
        ],
        metadata: _conversation.metadata,
        extra: _conversation.extra,
      ),
    );
  }

  void _applyLocalEvent(StreamTextEvent event, int epoch) {
    if (event case StreamTextTextStartEvent(
      :final id,
      :final providerMetadata,
    )) {
      final stable = _streamPartIds[id] = _freshLivePartId('text');
      _liveParts.add(
        TextPart(
          id: stable,
          text: '',
          providerOptions: _mergeProviderMetadata(const {}, providerMetadata),
        ),
      );
    } else if (event case StreamTextTextDeltaEvent(
      :final id,
      :final delta,
      :final providerMetadata,
    )) {
      final i = _liveParts.indexWhere((p) => p.id == _streamPartIds[id]);
      if (i >= 0) {
        final part = _liveParts[i];
        if (part case final TextPart textPart) {
          _liveParts[i] = TextPart(
            id: textPart.id,
            text: textPart.text + delta,
            providerOptions: _mergeProviderMetadata(
              textPart.providerOptions,
              providerMetadata,
            ),
          );
        }
      }
    } else if (event case StreamTextTextEndEvent(
      :final id,
      :final providerMetadata,
    )) {
      final i = _liveParts.indexWhere((p) => p.id == _streamPartIds[id]);
      if (i >= 0) {
        final part = _liveParts[i];
        if (part case final TextPart textPart) {
          _liveParts[i] = TextPart(
            id: textPart.id,
            text: textPart.text,
            providerOptions: _mergeProviderMetadata(
              textPart.providerOptions,
              providerMetadata,
            ),
          );
        }
      }
    } else if (event case StreamTextReasoningStartEvent(
      :final id,
      :final providerMetadata,
    )) {
      final stable = _streamPartIds[id] = _freshLivePartId('reasoning');
      _liveParts.add(
        ReasoningPart(
          id: stable,
          text: '',
          metadata: _mergeProviderMetadata(const {}, providerMetadata),
          providerOptions: _mergeProviderMetadata(const {}, providerMetadata),
        ),
      );
    } else if (event case StreamTextReasoningDeltaEvent(
      :final id,
      :final delta,
      :final providerMetadata,
    )) {
      final i = _liveParts.indexWhere((p) => p.id == _streamPartIds[id]);
      if (i >= 0) {
        final part = _liveParts[i];
        if (part case final ReasoningPart reasoningPart) {
          _liveParts[i] = ReasoningPart(
            id: reasoningPart.id,
            text: reasoningPart.text + delta,
            metadata: _mergeProviderMetadata(
              reasoningPart.metadata,
              providerMetadata,
            ),
            providerOptions: _mergeProviderMetadata(
              reasoningPart.providerOptions,
              providerMetadata,
            ),
          );
        }
      }
    } else if (event case StreamTextReasoningEndEvent(
      :final id,
      :final providerMetadata,
      :final signature,
    )) {
      final i = _liveParts.indexWhere((p) => p.id == _streamPartIds[id]);
      if (i >= 0) {
        final part = _liveParts[i];
        if (part case final ReasoningPart reasoningPart) {
          _liveParts[i] = ReasoningPart(
            id: reasoningPart.id,
            text: reasoningPart.text,
            signature: signature,
            metadata: _mergeProviderMetadata(
              reasoningPart.metadata,
              providerMetadata,
            ),
            providerOptions: _mergeProviderMetadata(
              reasoningPart.providerOptions,
              providerMetadata,
            ),
          );
        }
      }
    } else if (event case StreamTextToolInputStartEvent(
      :final toolCallId,
      :final toolName,
    )) {
      final existing = _liveParts.indexWhere(
        (part) => part is ToolCallPart && part.callId == toolCallId,
      );
      if (existing < 0) {
        _liveParts.add(
          ToolCallPart(
            id: 'tool-$toolCallId',
            callId: toolCallId,
            name: toolName,
            arguments: const {},
          ),
        );
      }
    } else if (event case StreamTextToolInputEndEvent(
      :final toolCallId,
      :final toolName,
      :final input,
    )) {
      final i = _liveParts.indexWhere((p) => p.id == 'tool-$toolCallId');
      final args = input is Map
          ? input.cast<String, dynamic>()
          : const <String, dynamic>{};
      final part = ToolCallPart(
        id: 'tool-$toolCallId',
        callId: toolCallId,
        name: toolName,
        arguments: args,
      );
      if (i >= 0) {
        _liveParts[i] = part;
      } else {
        _liveParts.add(part);
      }
    } else if (event case StreamTextToolResultEvent(
      :final toolResult,
      :final preliminary,
    )) {
      final denied = toolResult.output;
      _liveParts.add(
        ToolResultPart(
          id: 'result-${toolResult.toolCallId}-${_liveParts.length}',
          callId: toolResult.toolCallId,
          output: _toolOutput(toolResult.output),
          isError: toolResult.isError,
          toolName: toolResult.toolName,
          outputKind: _toolOutputKind(toolResult.output),
          preliminary: preliminary,
          isDynamic: toolResult.isDynamic,
          providerOptions: toolResult.providerOptions ?? const {},
          executionDeniedReason: denied is ToolResultOutputExecutionDenied
              ? denied.reason
              : null,
          executionDeniedApprovalId: denied is ToolResultOutputExecutionDenied
              ? denied.approvalId
              : null,
        ),
      );
    } else if (event case StreamTextToolErrorEvent(
      :final toolCallId,
      :final toolName,
      :final error,
    )) {
      final isText = error is String;
      _liveParts.add(
        ToolResultPart(
          id: 'error-$toolCallId-${_liveParts.length}',
          callId: toolCallId,
          toolName: toolName,
          output: _freezeJsonValue(error),
          isError: true,
          outputKind: isText ? 'error_text' : 'error_json',
        ),
      );
    } else if (event case StreamTextSourceEvent(:final source)) {
      _liveParts.add(
        SourcePart(
          id: source.id,
          uri: source.url,
          title: source.title,
          providerMetadata: source.providerMetadata ?? const {},
        ),
      );
    } else if (event case StreamTextDocumentSourceEvent(:final source)) {
      _liveParts.add(
        DocumentSourcePart(
          id: source.id,
          mediaType: source.mediaType,
          title: source.title,
          name: source.filename,
          providerMetadata: source.providerMetadata ?? const {},
        ),
      );
    } else if (event case StreamTextFileEvent(:final file)) {
      final data = file.data;
      _liveParts.add(
        FilePart(
          id: _freshLivePartId('file'),
          uri: switch (data) {
            DataContentUrl(:final url) => url.toString(),
            _ => null,
          },
          data: switch (data) {
            DataContentBytes(:final bytes) => ConversationFileBytes(bytes),
            DataContentBase64(:final base64) => ConversationFileBytes(
              Uint8List.fromList(base64Decode(base64)),
            ),
            DataContentProviderReference(:final namespace, :final id) =>
              ConversationFileProviderReference(namespace: namespace, id: id),
            DataContentUrl() => null,
          },
          mimeType: file.mediaType,
          name: file.filename,
          providerOptions: file.providerOptions ?? const {},
        ),
      );
    } else if (event case StreamTextReasoningFileEvent(:final file)) {
      final data = file.data;
      _liveParts.add(
        ReasoningFilePart(
          id: _freshLivePartId('reasoning-file'),
          uri: switch (data) {
            DataContentUrl(:final url) => url.toString(),
            _ => null,
          },
          data: switch (data) {
            DataContentBytes(:final bytes) => ConversationFileBytes(bytes),
            DataContentBase64(:final base64) => ConversationFileBytes(
              Uint8List.fromList(base64Decode(base64)),
            ),
            DataContentProviderReference(:final namespace, :final id) =>
              ConversationFileProviderReference(namespace: namespace, id: id),
            DataContentUrl() => null,
          },
          mimeType: file.mediaType,
          name: file.filename,
          providerOptions: file.providerOptions ?? const {},
        ),
      );
    } else if (event case StreamTextOpaqueEvent(:final opaque)) {
      final id = _freshLivePartId('opaque');
      _liveParts.add(
        UnknownPart(
          id: id,
          type: 'opaque',
          raw: {
            'id': id,
            'type': 'opaque',
            'provider': opaque.provider,
            'raw': _freezeJsonValue(opaque.raw),
          },
        ),
      );
    }
    _publishLive(ConversationMessageStatus.streaming);
  }

  @override
  Future<void> restore(Map<String, dynamic> encoded) async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    await interrupt();
    // ConversationCodec.decode is intentionally pure. No agent call occurs.
    final restored = ConversationCodec.decode(encoded);
    _restorePendingApproval(restored);
    _publish(restored);
  }

  void _restorePendingApproval(Conversation restored) {
    _pendingReplay = null;
    _restoredBindingInvalid = false;
    _pendingApprovalRequests.clear();
    _pendingApprovalResponses.clear();
    final pending = [
      for (final message in restored.messages)
        if (message.status == ConversationMessageStatus.pendingApproval)
          (message, message.parts.whereType<ApprovalPart>().toList()),
    ];
    if (pending.isEmpty) {
      _liveMessageId = null;
      _liveParts = [];
      return;
    }
    final entry = pending.last;
    final message = entry.$1;
    final approvals = entry.$2;
    final calls = {
      for (final part in message.parts.whereType<ToolCallPart>())
        part.callId: part,
    };
    final requests = <LanguageModelV4ToolApprovalRequestPart>[];
    for (final approval in approvals) {
      final call = calls[approval.callId];
      if (call == null) continue;
      final request = LanguageModelV4ToolApprovalRequestPart(
        approvalId: approval.approvalId ?? approval.id,
        toolCall: LanguageModelV4ToolCallPart(
          toolCallId: call.callId,
          toolName: call.name,
          input: call.arguments,
          providerOptions: call.providerOptions.isEmpty
              ? null
              : call.providerOptions,
          providerExecuted: call.providerExecuted,
        ),
        argumentsFingerprint: approval.argumentsFingerprint,
        policyRevision: approval.policyVersion,
      );
      requests.add(request);
      if ((approval.toolName != null && approval.toolName != call.name) ||
          (approval.argumentsFingerprint != null &&
              approval.argumentsFingerprint !=
                  _argumentsFingerprint(call.arguments))) {
        _restoredBindingInvalid = true;
      }
      _pendingApprovalRequests[request.approvalId] = request;
      if (approval.status != ApprovalStatus.pending) {
        _pendingApprovalResponses[request.approvalId] =
            LanguageModelV4ToolApprovalResponse(
              approvalId: request.approvalId,
              approved: approval.status == ApprovalStatus.approved,
              toolCallId: request.toolCall.toolCallId,
              toolName: request.toolCall.toolName,
              argumentsFingerprint: request.argumentsFingerprint,
              policyRevision: request.policyRevision,
            );
      }
    }
    if (requests.isEmpty) return;
    _liveMessageId = message.id;
    _liveParts = List.of(message.parts);
    _pendingReplay = ToolApprovalReplay(
      messages: _modelMessagesForSnapshot(message),
      requests: requests,
    );
  }

  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    final request = _pendingApprovalRequests[approvalId];
    if (request == null || _pendingApprovalResponses.containsKey(approvalId)) {
      return;
    }
    final response = LanguageModelV4ToolApprovalResponse(
      approvalId: approvalId,
      approved: approved,
      reason: reason,
      toolCallId: request.toolCall.toolCallId,
      toolName: request.toolCall.toolName,
      argumentsFingerprint: request.argumentsFingerprint,
      policyRevision: request.policyRevision,
    );
    _pendingApprovalResponses[approvalId] = response;
    _setApproval(approvalId, approved);
    if (_pendingApprovalResponses.length == _pendingApprovalRequests.length) {
      final replay = _pendingReplay;
      if (replay != null && _resumeInFlight == null) {
        final future = _resumeApproval(replay);
        _resumeInFlight = future;
        unawaited(
          future.whenComplete(() {
            if (identical(_resumeInFlight, future)) _resumeInFlight = null;
          }),
        );
      }
    }
  }

  Future<void> _resumeApproval(ToolApprovalReplay replay) async {
    final epoch = _epoch;
    final cancellation = CancellationToken();
    _resumeCancellation = cancellation;
    try {
      if (_restoredBindingInvalid) {
        throw ToolApprovalRenewalRequiredError(requests: replay.requests);
      }
      final result = await _agent.resume(
        replay: replay,
        // The pending assistant snapshot contains client-only ApprovalParts;
        // replay supplies the provider-facing assistant/tool messages.
        messages: _toModelMessages(
          Conversation(
            id: _conversation.id,
            messages: [
              for (final message in _conversation.messages)
                if (message.id != _liveMessageId) message,
            ],
            metadata: _conversation.metadata,
            extra: _conversation.extra,
          ),
        ),
        toolApprovalResponses: _pendingApprovalResponses.values.toList(),
        abortSignal: cancellation,
      );
      await for (final event in result.stream) {
        if (_disposed || epoch != _epoch) return;
        _applyLocalEvent(event, epoch);
      }
      final resumedSteps = await result.steps;
      if (_disposed || epoch != _epoch) return;
      _mergeStepToolCalls(resumedSteps);
      final approvals = [
        for (final step in resumedSteps) ...step.toolApprovalRequests,
      ];
      final priorApprovalIds = replay.requests
          .map((request) => request.approvalId)
          .toSet();
      final priorCallIds = replay.requests
          .map((request) => request.toolCall.toolCallId)
          .toSet();
      final freshApprovals = approvals
          .where(
            (request) =>
                !priorApprovalIds.contains(request.approvalId) &&
                !priorCallIds.contains(request.toolCall.toolCallId),
          )
          .toList();
      if (freshApprovals.isNotEmpty) {
        _pendingReplay = ToolApprovalReplay(
          messages: [
            for (final step in resumedSteps) ..._replayMessagesForStep(step),
          ],
          requests: freshApprovals,
        );
        _pendingApprovalRequests
          ..clear()
          ..addEntries(
            freshApprovals.map(
              (request) => MapEntry(request.approvalId, request),
            ),
          );
        _pendingApprovalResponses.clear();
        final approvalIds = freshApprovals
            .map((request) => request.approvalId)
            .toSet();
        _liveParts.removeWhere(
          (part) =>
              part is ApprovalPart && approvalIds.contains(part.approvalId),
        );
        _liveParts.addAll([
          for (final request in approvals)
            ApprovalPart(
              id: 'approval-${request.approvalId}',
              approvalId: request.approvalId,
              callId: request.toolCall.toolCallId,
              toolName: request.toolCall.toolName,
              argumentsFingerprint: request.argumentsFingerprint,
              policyVersion: request.policyRevision,
              status: ApprovalStatus.pending,
            ),
        ]);
        _publishLive(ConversationMessageStatus.pendingApproval);
        return;
      }
      if (!_disposed && epoch == _epoch) {
        _publishLive(ConversationMessageStatus.complete);
        _pendingReplay = null;
        _pendingApprovalRequests.clear();
        _pendingApprovalResponses.clear();
      }
    } on ToolApprovalRenewalRequiredError catch (error) {
      if (_disposed || epoch != _epoch) return;
      _restoredBindingInvalid = false;
      final renewedRequests = [
        for (final request in error.requests)
          LanguageModelV4ToolApprovalRequestPart(
            approvalId: request.approvalId,
            toolCall: request.toolCall,
            argumentsFingerprint: _argumentsFingerprint(request.toolCall.input),
            policyRevision: _agent.approvalPolicyRevision,
          ),
      ];
      _pendingReplay = ToolApprovalReplay(
        messages: replay.messages,
        requests: renewedRequests,
      );
      _pendingApprovalRequests
        ..clear()
        ..addEntries(
          renewedRequests.map(
            (request) => MapEntry(request.approvalId, request),
          ),
        );
      _pendingApprovalResponses.clear();
      _resetApprovalPartsToPending(renewedRequests);
      _publishLive(ConversationMessageStatus.pendingApproval);
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        _publishLive(ConversationMessageStatus.failed);
      }
    } finally {
      if (identical(_resumeCancellation, cancellation)) {
        _resumeCancellation = null;
      }
    }
  }

  void _resetApprovalPartsToPending(
    List<LanguageModelV4ToolApprovalRequestPart> requests,
  ) {
    final byId = {for (final request in requests) request.approvalId: request};
    _liveParts = [
      for (final part in _liveParts)
        if (part case final ApprovalPart approval)
          (() {
            final request = byId[approval.approvalId];
            return ApprovalPart(
              id: approval.id,
              callId: request?.toolCall.toolCallId ?? approval.callId,
              status: ApprovalStatus.pending,
              approvalId: approval.approvalId,
              toolName: request?.toolCall.toolName ?? approval.toolName,
              argumentsFingerprint:
                  request?.argumentsFingerprint ??
                  approval.argumentsFingerprint,
              policyVersion: request?.policyRevision ?? approval.policyVersion,
              metadata: approval.metadata,
            );
          })()
        else
          part,
    ];
  }

  List<ModelMessage> _modelMessagesForSnapshot(ConversationMessage message) {
    final result = <ModelMessage>[];
    var assistantParts = <LanguageModelV4ContentPart>[];
    var toolParts = <LanguageModelV4ContentPart>[];

    void flushAssistant() {
      if (assistantParts.isEmpty) return;
      result.add(
        ModelMessage.parts(
          role: ModelMessageRole.assistant,
          parts: List.of(assistantParts),
        ),
      );
      assistantParts = [];
    }

    void flushTools() {
      if (toolParts.isEmpty) return;
      result.add(
        ModelMessage.parts(
          role: ModelMessageRole.tool,
          parts: List.of(toolParts),
        ),
      );
      toolParts = [];
    }

    for (final part in message.parts) {
      final converted = _toProviderPart(part);
      if (converted == null) continue;
      if (part is ToolResultPart) {
        flushAssistant();
        toolParts.add(converted);
      } else {
        flushTools();
        assistantParts.add(converted);
      }
    }
    flushTools();
    flushAssistant();
    return result;
  }

  Iterable<ModelMessage> _replayMessagesForStep(GenerateTextStep step) sync* {
    final parts = step.content
        .where((part) => part is! LanguageModelV4ToolApprovalRequestPart)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      yield ModelMessage.parts(role: ModelMessageRole.assistant, parts: parts);
    }
    if (step.toolResults.isNotEmpty) {
      yield ModelMessage.parts(
        role: ModelMessageRole.tool,
        parts: step.toolResults,
      );
    }
  }

  void _setApproval(String approvalId, bool approved) {
    final target = 'approval-$approvalId';
    final messages = [
      for (final message in _conversation.messages)
        (() {
          final parts = [
            for (final part in message.parts)
              if (part case final ApprovalPart approval
                  when approval.id == target)
                ApprovalPart(
                  id: approval.id,
                  callId: approval.callId,
                  status: approved
                      ? ApprovalStatus.approved
                      : ApprovalStatus.rejected,
                  approvalId: approval.approvalId,
                  toolName: approval.toolName,
                  argumentsFingerprint: approval.argumentsFingerprint,
                  policyVersion: approval.policyVersion,
                  metadata: approval.metadata,
                )
              else
                part,
          ];
          final hasPending = parts.any(
            (part) =>
                part is ApprovalPart && part.status == ApprovalStatus.pending,
          );
          return ConversationMessage(
            id: message.id,
            role: message.role,
            status: hasPending
                ? ConversationMessageStatus.pendingApproval
                : (message.status == ConversationMessageStatus.pendingApproval
                      ? ConversationMessageStatus.streaming
                      : message.status),
            metadata: message.metadata,
            extra: message.extra,
            parts: parts,
          );
        })(),
    ];
    final updated = Conversation(
      id: _conversation.id,
      messages: messages,
      metadata: _conversation.metadata,
      extra: _conversation.extra,
    );
    _publish(updated);
    final liveMessage = _liveMessageId == null
        ? null
        : updated.messages.where((message) => message.id == _liveMessageId);
    if (liveMessage != null && liveMessage.isNotEmpty) {
      _liveParts = List.of(liveMessage.first.parts);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await interrupt();
    await _changes.close();
  }
}

/// Adapter for a server-owned conversation stream.
class RemoteConversationBackend
    implements ConversationBackend, ConversationRetryBackend {
  RemoteConversationBackend({
    required RemoteConversationTransport transport,
    required Conversation initial,
  }) : _transport = transport,
       _conversation = initial;

  final RemoteConversationTransport _transport;
  Conversation _conversation;
  final _changes = StreamController<Conversation>.broadcast();
  RemoteCancellationToken? _cancellation;
  RemoteCancellationToken? _resumeCancellation;
  bool _disposed = false;
  int _epoch = 0;
  final _approvalBindings = <String, ApprovalPart>{};
  final _approvalRoundIds = <String>{};
  final _approvalResponses = <String>{};
  Future<void>? _resumeInFlight;

  @override
  Conversation get conversation => _conversation;
  @override
  Stream<Conversation> get changes => _changes.stream;

  @override
  ConversationRetryInfo get retryInfo => const ConversationRetryInfo(
    ConversationRetryAvailability.unsupported,
    reason:
        'Remote retry requires an explicit server idempotency and assistant identity contract.',
  );

  @override
  Future<void> retryLastTurn() => Future.error(
    RetryUnsupportedError(
      'Remote retry is unavailable until the transport establishes an explicit server idempotency and assistant identity contract.',
    ),
  );

  @override
  Future<void> send(String text) async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    await interrupt();
    final epoch = ++_epoch;
    final userId = _freshId(_conversation, 'message');
    final message = ConversationMessage(
      id: userId,
      role: ConversationRole.user,
      parts: [TextPart(id: _freshId(_conversation, 'part'), text: text)],
    );
    _conversation = Conversation(
      id: _conversation.id,
      messages: [..._conversation.messages, message],
      metadata: _conversation.metadata,
      extra: _conversation.extra,
    );
    _clearApprovalRound();
    final cancellation = RemoteCancellationToken();
    _cancellation = cancellation;
    try {
      await for (final value in _transport.send(
        _conversation,
        cancellation: cancellation,
      )) {
        if (_disposed || epoch != _epoch) return;
        _accept(value);
      }
    } catch (error) {
      if (!_disposed && epoch == _epoch) {
        _setLastAssistantStatusForLatestTurn(ConversationMessageStatus.failed);
        rethrow;
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
      await cancellation.dispose();
    }
  }

  @override
  Future<void> interrupt() async {
    _epoch++;
    _cancellation?.cancel();
    _cancellation = null;
    _resumeCancellation?.cancel();
    _resumeCancellation = null;
  }

  @override
  Future<void> restore(Map<String, dynamic> encoded) async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    await interrupt();
    _conversation = ConversationCodec.decode(encoded);
    _restoreApprovalRound();
    _changes.add(_conversation);
  }

  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async {
    if (_disposed) throw StateError('Conversation backend is disposed');
    final binding = _approvalBindings[approvalId];
    if (binding == null ||
        binding.status != ApprovalStatus.pending ||
        !_approvalRoundIds.contains(approvalId) ||
        _approvalResponses.contains(approvalId)) {
      return;
    }
    final updated = ApprovalPart(
      id: binding.id,
      callId: binding.callId,
      status: approved ? ApprovalStatus.approved : ApprovalStatus.rejected,
      approvalId: binding.approvalId,
      toolName: binding.toolName,
      argumentsFingerprint: binding.argumentsFingerprint,
      policyVersion: binding.policyVersion,
      metadata: binding.metadata,
      extra: {
        ...binding.extra,
        ...?(reason == null ? null : {'reason': reason}),
      },
    );
    _approvalBindings[approvalId] = updated;
    _approvalResponses.add(approvalId);
    _updateApprovalPart(updated);
    if (_approvalResponses.length != _approvalRoundIds.length) return;

    final inFlight = _resumeInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final resume = _resumeConversation();
    _resumeInFlight = resume;
    try {
      await resume;
    } finally {
      if (identical(_resumeInFlight, resume)) _resumeInFlight = null;
    }
  }

  void _accept(Conversation value) {
    if (_disposed) return;
    _conversation = value;
    _syncApprovalRoundFromConversation();
    _changes.add(value);
  }

  void _restoreApprovalRound() {
    _clearApprovalRound();
    _syncApprovalRoundFromConversation();
  }

  void _clearApprovalRound() {
    _approvalBindings.clear();
    _approvalRoundIds.clear();
    _approvalResponses.clear();
  }

  void _syncApprovalRoundFromConversation() {
    final pending = <String, ApprovalPart>{};
    for (final message in _conversation.messages) {
      for (final part in message.parts.whereType<ApprovalPart>()) {
        if (part.status == ApprovalStatus.pending) {
          pending[_approvalId(part)] = part;
        }
      }
    }
    if (pending.isEmpty) {
      _clearApprovalRound();
      return;
    }
    if (pending.keys.toSet().containsAll(_approvalRoundIds) &&
        _approvalRoundIds.containsAll(pending.keys)) {
      _approvalBindings
        ..clear()
        ..addAll(pending);
      return;
    }
    _approvalBindings
      ..clear()
      ..addAll(pending);
    _approvalRoundIds
      ..clear()
      ..addAll(pending.keys);
    _approvalResponses.clear();
  }

  void _updateApprovalPart(ApprovalPart replacement) {
    final messages = [
      for (final message in _conversation.messages)
        (() {
          final parts = [
            for (final part in message.parts)
              if (part is ApprovalPart &&
                  _approvalId(part) == _approvalId(replacement))
                replacement
              else
                part,
          ];
          final hasPending = parts.any(
            (part) =>
                part is ApprovalPart && part.status == ApprovalStatus.pending,
          );
          return ConversationMessage(
            id: message.id,
            role: message.role,
            status: message.status == ConversationMessageStatus.pendingApproval
                ? (hasPending
                      ? ConversationMessageStatus.pendingApproval
                      : ConversationMessageStatus.streaming)
                : message.status,
            metadata: message.metadata,
            extra: message.extra,
            parts: parts,
          );
        })(),
    ];
    _conversation = Conversation(
      id: _conversation.id,
      messages: messages,
      metadata: _conversation.metadata,
      extra: _conversation.extra,
    );
    _changes.add(_conversation);
  }

  Future<void> _resumeConversation() async {
    final epoch = _epoch;
    final cancellation = RemoteCancellationToken();
    _resumeCancellation = cancellation;
    try {
      await for (final value in _transport.send(
        _conversation,
        cancellation: cancellation,
      )) {
        if (_disposed || epoch != _epoch) return;
        _accept(value);
      }
    } catch (error) {
      if (!_disposed && epoch == _epoch) {
        _setLastAssistantStatusForLatestTurn(ConversationMessageStatus.failed);
        rethrow;
      }
    } finally {
      if (identical(_resumeCancellation, cancellation)) {
        _resumeCancellation = null;
      }
      await cancellation.dispose();
      if (!_disposed && epoch == _epoch) {
        _syncApprovalRoundFromConversation();
      }
    }
  }

  void _setLastAssistantStatusForLatestTurn(ConversationMessageStatus status) {
    final lastUser = _conversation.messages.lastIndexWhere(
      (message) => message.role == ConversationRole.user,
    );
    if (lastUser < 0) return;
    final index = _conversation.messages.indexWhere(
      (message) =>
          message.role == ConversationRole.assistant &&
          _conversation.messages.indexOf(message) > lastUser,
    );
    if (index < 0) return;
    final current = _conversation.messages[index];
    _setAssistantStatus(current.id, status);
  }

  void _setAssistantStatus(String id, ConversationMessageStatus status) {
    final index = _conversation.messages.indexWhere(
      (message) =>
          message.id == id && message.role == ConversationRole.assistant,
    );
    if (index < 0) return;
    final messages = [..._conversation.messages];
    final current = messages[index];
    messages[index] = ConversationMessage(
      id: current.id,
      role: current.role,
      status: status,
      parts: current.parts,
      metadata: current.metadata,
      extra: current.extra,
    );
    _conversation = Conversation(
      id: _conversation.id,
      messages: messages,
      metadata: _conversation.metadata,
      extra: _conversation.extra,
    );
    _changes.add(_conversation);
  }

  static String _approvalId(ApprovalPart approval) =>
      approval.approvalId ?? approval.id;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await interrupt();
    _transport.dispose();
    await _changes.close();
  }
}

ModelMessage _toModelMessage(ConversationMessage value) {
  final role = switch (value.role) {
    ConversationRole.system => ModelMessageRole.system,
    ConversationRole.user => ModelMessageRole.user,
    ConversationRole.assistant => ModelMessageRole.assistant,
    ConversationRole.tool => ModelMessageRole.tool,
  };
  final parts = _conversationParts(value.parts).toList(growable: false);
  // The existing user bubble renders the plain-text message field. Preserve
  // text-only user turns in that form while keeping rich assistant/tool parts
  // available to their dedicated renderers.
  if (role == ModelMessageRole.user &&
      parts.every((part) => part is LanguageModelV4TextPart)) {
    return ModelMessage(
      role: role,
      content: parts
          .whereType<LanguageModelV4TextPart>()
          .map((part) => part.text)
          .join(),
    );
  }
  return ModelMessage.parts(role: role, parts: parts);
}

Iterable<LanguageModelV4ContentPart> _conversationParts(
  List<ConversationPart> parts,
) sync* {
  for (final part in parts) {
    final converted = _toProviderPart(part);
    if (converted != null) yield converted;
  }
}

LanguageModelV4ContentPart? _toProviderPart(
  ConversationPart part,
) => switch (part) {
  TextPart(:final text, :final providerOptions) => LanguageModelV4TextPart(
    text: text,
    providerOptions: providerOptions.isEmpty ? null : providerOptions,
  ),
  ReasoningPart(:final text, :final signature, :final providerOptions) =>
    LanguageModelV4ReasoningPart(
      text: text,
      signature: signature,
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
    ),
  ImagePart(:final uri, :final data, :final mimeType, :final providerOptions) =>
    LanguageModelV4ImagePart(
      image: _toProviderData(data, uri),
      mediaType: mimeType,
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
    ),
  RedactedReasoningPart(:final data, :final providerOptions) =>
    LanguageModelV4RedactedReasoningPart(
      data: data,
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
    ),
  ToolCallPart(
    :final callId,
    :final name,
    :final arguments,
    :final providerOptions,
    :final providerExecuted,
  ) =>
    LanguageModelV4ToolCallPart(
      toolCallId: callId,
      toolName: name,
      input: arguments,
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
      providerExecuted: providerExecuted,
    ),
  ToolResultPart(
    :final callId,
    :final toolName,
    :final output,
    :final isError,
    :final outputKind,
    :final preliminary,
    :final isDynamic,
    :final providerOptions,
    :final executionDeniedReason,
    :final executionDeniedApprovalId,
  ) =>
    LanguageModelV4ToolResultPart(
      toolCallId: callId,
      toolName: toolName ?? 'unknown',
      output: _toProviderToolOutput(
        outputKind,
        output,
        isError,
        executionDeniedReason,
        executionDeniedApprovalId,
      ),
      isError: isError,
      preliminary: preliminary,
      isDynamic: isDynamic,
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
    ),
  FilePart(
    :final uri,
    :final data,
    :final mimeType,
    :final name,
    :final providerOptions,
  ) =>
    LanguageModelV4FilePart(
      mediaType: mimeType,
      filename: name,
      data: _toProviderData(data, uri),
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
    ),
  ReasoningFilePart(
    :final uri,
    :final data,
    :final mimeType,
    :final name,
    :final providerOptions,
  ) =>
    LanguageModelV4ReasoningFilePart(
      mediaType: mimeType,
      filename: name,
      data: _toProviderData(data, uri),
      providerOptions: providerOptions.isEmpty ? null : providerOptions,
    ),
  SourcePart(:final id, :final uri, :final title, :final providerMetadata) =>
    LanguageModelV4SourcePart(
      id: id,
      url: uri,
      title: title,
      providerMetadata: providerMetadata.isEmpty ? null : providerMetadata,
    ),
  DocumentSourcePart(
    :final id,
    :final mediaType,
    :final title,
    :final name,
    :final providerMetadata,
  ) =>
    LanguageModelV4DocumentSourcePart(
      id: id,
      mediaType: mediaType,
      title: title,
      filename: name,
      providerMetadata: providerMetadata.isEmpty ? null : providerMetadata,
    ),
  UnknownPart(:final raw) => LanguageModelV4OpaquePart(
    provider: raw['provider'] is String
        ? raw['provider'] as String
        : 'conversation',
    raw: raw['raw'] ?? raw,
  ),
  ApprovalPart() => null,
  ConversationPart() => throw UnsupportedError(
    'Cannot replay unsupported conversation part type ${part.type}',
  ),
};

LanguageModelV4DataContent _toProviderData(
  ConversationFileData? data,
  String? uri,
) => switch (data) {
  ConversationFileBytes(:final bytes) => DataContentBytes(bytes),
  ConversationFileProviderReference(:final namespace, :final id) =>
    DataContentProviderReference(namespace: namespace, id: id),
  null => DataContentUrl(Uri.parse(uri!)),
};

LanguageModelV4ToolResultOutput _toProviderToolOutput(
  String? kind,
  Object? output,
  bool isError,
  String? deniedReason,
  String? deniedApprovalId,
) => switch (kind) {
  'text' => ToolResultOutputText(output as String? ?? ''),
  'content' => ToolResultOutputContent(
    (output is List)
        ? [
            for (final item in output)
              if (item is Map) _decodeProviderContentPart(item),
          ]
        : const [],
  ),
  'error_json' => ToolResultOutputErrorJson(output),
  'error_text' => ToolResultOutputErrorText(output as String? ?? ''),
  'execution_denied' => ToolResultOutputExecutionDenied(
    deniedReason ?? 'Tool call execution denied.',
    deniedApprovalId,
  ),
  _ =>
    isError ? ToolResultOutputErrorJson(output) : ToolResultOutputJson(output),
};

LanguageModelV4ContentPart _decodeProviderContentPart(Map item) {
  final type = item['type'];
  if (type == 'text') {
    return LanguageModelV4TextPart(
      text: item['text'] as String,
      providerOptions: _optionalProviderOptions(item['providerOptions']),
    );
  }
  if (type == 'reasoning') {
    return LanguageModelV4ReasoningPart(
      text: item['text'] as String,
      signature: item['signature'] as String?,
      providerOptions: _optionalProviderOptions(item['providerOptions']),
    );
  }
  if (type == 'redacted_reasoning') {
    return LanguageModelV4RedactedReasoningPart(
      data: _decodeBytesData(item['data']),
      providerOptions: _optionalProviderOptions(item['providerOptions']),
    );
  }
  if (type == 'image') {
    return LanguageModelV4ImagePart(
      image: _decodeDataContent(item['data']),
      mediaType: item['mediaType'] as String?,
      providerOptions: _optionalProviderOptions(item['providerOptions']),
    );
  }
  if (type == 'file') {
    return LanguageModelV4FilePart(
      data: _decodeDataContent(item['data']),
      mediaType: item['mediaType'] as String,
      filename: item['filename'] as String?,
      providerOptions: _optionalProviderOptions(item['providerOptions']),
    );
  }
  if (type == 'reasoning_file') {
    return LanguageModelV4ReasoningFilePart(
      data: _decodeDataContent(item['data']),
      mediaType: item['mediaType'] as String,
      filename: item['filename'] as String?,
      providerOptions: _optionalProviderOptions(item['providerOptions']),
    );
  }
  if (type == 'source') {
    return LanguageModelV4SourcePart(
      id: item['id'] as String,
      url: item['url'] as String,
      title: item['title'] as String?,
      providerMetadata: _optionalProviderOptions(item['providerMetadata']),
    );
  }
  if (type == 'source-document') {
    return LanguageModelV4DocumentSourcePart(
      id: item['id'] as String,
      mediaType: item['mediaType'] as String,
      title: item['title'] as String,
      filename: item['filename'] as String?,
      providerMetadata: _optionalProviderOptions(item['providerMetadata']),
    );
  }
  if (type == 'opaque') {
    return LanguageModelV4OpaquePart(
      provider: item['provider'] as String? ?? 'conversation',
      raw: item['raw'],
    );
  }
  throw UnsupportedError('Unknown persisted tool content type $type');
}

Map<String, dynamic>? _optionalProviderOptions(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw UnsupportedError('Provider metadata/options must be an object');
  }
  return value.cast<String, dynamic>();
}

Uint8List _decodeBytesData(Object? value) {
  if (value is! Map || value['kind'] != 'bytes' || value['base64'] is! String) {
    throw UnsupportedError('Persisted bytes are invalid');
  }
  return Uint8List.fromList(base64Decode(value['base64'] as String));
}

LanguageModelV4DataContent _decodeDataContent(Object? value) {
  if (value is! Map) {
    throw UnsupportedError('Persisted data content is invalid');
  }
  return switch (value['kind']) {
    'bytes' => DataContentBytes(
      Uint8List.fromList(base64Decode(value['base64'] as String)),
    ),
    'base64' => DataContentBase64(value['base64'] as String),
    'url' => DataContentUrl(Uri.parse(value['url'] as String)),
    'provider_reference' => DataContentProviderReference(
      namespace: value['namespace'] as String,
      id: value['id'] as String,
    ),
    _ => throw UnsupportedError('Unknown persisted data content kind'),
  };
}

List<ModelMessage> _toModelMessages(Conversation value) => [
  for (final message in value.messages)
    ModelMessage.parts(
      role: switch (message.role) {
        ConversationRole.system => ModelMessageRole.system,
        ConversationRole.user => ModelMessageRole.user,
        ConversationRole.assistant => ModelMessageRole.assistant,
        ConversationRole.tool => ModelMessageRole.tool,
      },
      parts: [..._providerPartsForReplay(message.parts)],
    ),
];

List<LanguageModelV4ContentPart> _providerPartsForReplay(
  Iterable<ConversationPart> parts,
) {
  final result = <LanguageModelV4ContentPart>[];
  for (final part in parts) {
    if (part is ApprovalPart) continue;
    final converted = _toProviderPart(part);
    if (converted != null) result.add(converted);
  }
  return result;
}

Map<String, dynamic> _mergeProviderMetadata(
  Map<String, dynamic> current,
  Map<String, dynamic>? update,
) {
  if (update == null || update.isEmpty) return current;
  final merged = <String, dynamic>{...current};
  for (final entry in update.entries) {
    final existing = merged[entry.key];
    merged[entry.key] = existing is Map && entry.value is Map
        ? <String, dynamic>{
            ...existing.cast<String, dynamic>(),
            ...entry.value.cast<String, dynamic>(),
          }
        : entry.value;
  }
  return merged;
}

String _toolOutputKind(LanguageModelV4ToolResultOutput output) =>
    switch (output) {
      ToolResultOutputText() => 'text',
      ToolResultOutputContent() => 'content',
      ToolResultOutputJson() => 'json',
      ToolResultOutputErrorJson() => 'error_json',
      ToolResultOutputErrorText() => 'error_text',
      ToolResultOutputExecutionDenied() => 'execution_denied',
    };

Object? _toolOutput(LanguageModelV4ToolResultOutput output) => switch (output) {
  ToolResultOutputText(:final text) => text,
  ToolResultOutputContent(:final parts) => [
    for (var i = 0; i < parts.length; i++)
      _encodeProviderContentPart(parts[i], 'tool-output-$i'),
  ],
  ToolResultOutputJson(:final value) => value,
  ToolResultOutputErrorJson(:final value) => value,
  ToolResultOutputErrorText(:final text) => text,
  ToolResultOutputExecutionDenied() => null,
};

Map<String, dynamic> _encodeProviderContentPart(
  LanguageModelV4ContentPart part,
  String id,
) => switch (part) {
  LanguageModelV4TextPart(:final text, :final providerOptions) => {
    'id': id,
    'type': 'text',
    'text': text,
    ...?providerOptions == null ? null : {'providerOptions': providerOptions},
  },
  LanguageModelV4ReasoningPart(
    :final text,
    :final signature,
    :final providerOptions,
  ) =>
    {
      'id': id,
      'type': 'reasoning',
      'text': text,
      ...?signature == null ? null : {'signature': signature},
      ...?providerOptions == null ? null : {'providerOptions': providerOptions},
    },
  LanguageModelV4RedactedReasoningPart(:final data, :final providerOptions) => {
    'id': id,
    'type': 'redacted_reasoning',
    'data': _encodeDataContent(DataContentBytes(data)),
    ...?providerOptions == null ? null : {'providerOptions': providerOptions},
  },
  LanguageModelV4ImagePart(
    :final image,
    :final mediaType,
    :final providerOptions,
  ) =>
    {
      'id': id,
      'type': 'image',
      'data': _encodeDataContent(image),
      ...?mediaType == null ? null : {'mediaType': mediaType},
      ...?providerOptions == null ? null : {'providerOptions': providerOptions},
    },
  LanguageModelV4FilePart(
    :final data,
    :final mediaType,
    :final filename,
    :final providerOptions,
  ) =>
    {
      'id': id,
      'type': 'file',
      'data': _encodeDataContent(data),
      'mediaType': mediaType,
      ...?filename == null ? null : {'filename': filename},
      ...?providerOptions == null ? null : {'providerOptions': providerOptions},
    },
  LanguageModelV4ReasoningFilePart(
    :final data,
    :final mediaType,
    :final filename,
    :final providerOptions,
  ) =>
    {
      'id': id,
      'type': 'reasoning_file',
      'data': _encodeDataContent(data),
      'mediaType': mediaType,
      ...?filename == null ? null : {'filename': filename},
      ...?providerOptions == null ? null : {'providerOptions': providerOptions},
    },
  LanguageModelV4SourcePart(
    :final id,
    :final url,
    :final title,
    :final providerMetadata,
  ) =>
    {
      'id': id,
      'type': 'source',
      'url': url,
      ...?title == null ? null : {'title': title},
      ...?providerMetadata == null
          ? null
          : {'providerMetadata': providerMetadata},
    },
  LanguageModelV4DocumentSourcePart(
    :final id,
    :final mediaType,
    :final title,
    :final filename,
    :final providerMetadata,
  ) =>
    {
      'id': id,
      'type': 'source-document',
      'mediaType': mediaType,
      'title': title,
      ...?filename == null ? null : {'filename': filename},
      ...?providerMetadata == null
          ? null
          : {'providerMetadata': providerMetadata},
    },
  LanguageModelV4OpaquePart(:final provider, :final raw) => {
    'id': id,
    'type': 'opaque',
    'provider': provider,
    'raw': _freezeJsonValue(raw),
  },
  _ => throw UnsupportedError(
    'Cannot persist tool content part ${part.runtimeType} without a wire form',
  ),
};

Object _encodeDataContent(LanguageModelV4DataContent data) => switch (data) {
  DataContentBytes(:final bytes) => {
    'kind': 'bytes',
    'base64': base64Encode(bytes),
  },
  DataContentBase64(:final base64) => {'kind': 'base64', 'base64': base64},
  DataContentUrl(:final url) => {'kind': 'url', 'url': url.toString()},
  DataContentProviderReference(:final namespace, :final id) => {
    'kind': 'provider_reference',
    'namespace': namespace,
    'id': id,
  },
};

Object? _freezeJsonValue(Object? value) => switch (value) {
  null || String() || bool() || num() => value,
  Uint8List(:final length) => {
    'kind': 'bytes',
    'base64': base64Encode(value),
    'length': length,
  },
  List() => [for (final item in value) _freezeJsonValue(item)],
  Map() => {
    for (final entry in value.entries)
      entry.key.toString(): _freezeJsonValue(entry.value),
  },
  _ => throw UnsupportedError(
    'Cannot persist opaque provider value of type ${value.runtimeType}',
  ),
};

(ConversationMessage, ConversationMessage)? _retryPair(Conversation value) {
  final messages = value.messages;
  for (var i = messages.length - 1; i > 0; i--) {
    final assistant = messages[i];
    if (assistant.role != ConversationRole.assistant ||
        assistant.status != ConversationMessageStatus.failed) {
      continue;
    }
    if (i != messages.length - 1) return null;
    final user = messages[i - 1];
    if (user.role == ConversationRole.user) return (user, assistant);
    return null;
  }
  return null;
}

ConversationRetryInfo _retryInfoForConversation(Conversation value) {
  final pair = _retryPair(value);
  if (pair == null) {
    final pending = value.messages.any(
      (message) => message.status == ConversationMessageStatus.pendingApproval,
    );
    return pending
        ? const ConversationRetryInfo(
            ConversationRetryAvailability.pendingApproval,
            reason: 'Respond to the pending tool approval to continue.',
          )
        : const ConversationRetryInfo(
            ConversationRetryAvailability.noFailedTurn,
            reason: 'There is no failed assistant turn to retry.',
          );
  }
  if (pair.$2.parts.any(
    (part) =>
        part is ToolCallPart ||
        part is ToolResultPart ||
        part is ApprovalPart ||
        part is UnknownPart,
  )) {
    return const ConversationRetryInfo(
      ConversationRetryAvailability.unsafe,
      reason:
          'This turn may have executed a tool or provider action and cannot be retried safely.',
    );
  }
  return const ConversationRetryInfo(ConversationRetryAvailability.available);
}

String _argumentsFingerprint(Object input) => jsonEncode(_canonicalJson(input));

Object? _canonicalJson(Object? value) => switch (value) {
  Map map => {
    for (final key in map.keys.map((key) => key.toString()).toList()..sort())
      key: _canonicalJson(map[key]),
  },
  List() => [for (final item in value) _canonicalJson(item)],
  _ => value,
};

String _freshId(Conversation value, String prefix) {
  final used = <String>{};
  for (final message in value.messages) {
    used.add(message.id);
    used.addAll(message.parts.map((part) => part.id));
  }
  for (var i = 1; ; i++) {
    final id = '$prefix-$i';
    if (!used.contains(id)) return id;
  }
}
