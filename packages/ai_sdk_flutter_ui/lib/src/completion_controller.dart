import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'streaming_controller_base.dart';

/// Flutter controller for single-turn completion — mirrors the JS `useCompletion` hook.
///
/// Provides:
/// - [complete] — submit a prompt and stream the response
/// - [stop] — cancel the active stream
/// - [clear] — reset completion state
/// - [isStreaming] — true while actively streaming
class CompletionController extends StreamingControllerBase {
  CompletionController({
    required this.agent,
    this.onFinish,
    this.onError,
    super.notificationScheduler,
  });

  final ToolLoopAgent agent;

  /// Called when completion finishes with the full text.
  /// Errors from the callback are ignored after state is updated.
  final FutureOr<void> Function(String text)? onFinish;

  /// Called when an error occurs.
  /// Errors from the callback are ignored after state is updated.
  final FutureOr<void> Function(Object error)? onError;

  /// Notifies when loading/streaming/error state changes.
  @override
  Listenable get statusListenable => super.statusListenable;

  /// Notifies when [completion] or [lastUsage] changes.
  @override
  Listenable get contentListenable => super.contentListenable;

  String _completion = '';
  String get completion => _completion;

  Object? _error;
  Object? get error => _error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  /// Token usage reported by the most recent completion, if any.
  LanguageModelV4Usage? get lastUsage => _lastUsage;
  LanguageModelV4Usage? _lastUsage;

  StreamSubscription<String>? _activeSubscription;
  StreamSubscription<StreamTextEvent>? _errorSubscription;
  CancellationToken? _activeAbortSignal;

  void _cancelActiveRequestSync() {
    activeRequestId = null;
    _activeAbortSignal?.cancel();
    _activeAbortSignal = null;
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
  }

  Future<void> _cancelActiveRequest() async {
    activeRequestId = null;
    _activeAbortSignal?.cancel();
    _activeAbortSignal = null;
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    await _errorSubscription?.cancel();
    _errorSubscription = null;
  }

  /// Submit [prompt] and stream the completion.
  Future<void> complete(String prompt) async {
    _cancelActiveRequestSync();
    final requestId = ++nextRequestId;
    final abortSignal = CancellationToken();
    activeRequestId = requestId;
    _activeAbortSignal = abortSignal;
    _completion = '';
    _error = null;
    _lastUsage = null;
    _isLoading = true;
    _isStreaming = false;
    notifyListenersSafely(immediate: true, status: true, content: true);

    try {
      final streamResult = await agent.stream(
        prompt: prompt,
        abortSignal: abortSignal,
      );
      if (!isCurrentRequest(requestId)) return;
      _isStreaming = true;
      notifyListenersSafely(immediate: true, status: true);

      // The result's `text`/`output` futures reject on a streaming error; we
      // surface errors via [fullStream] instead, so swallow those completions
      // to keep them from becoming unhandled async errors.
      streamResult.text.then((_) {}, onError: (_) {});
      streamResult.output.then((_) {}, onError: (_) {});

      // Streaming errors surface on the full event stream (not the text
      // stream), so watch both: text for content, fullStream for errors.
      _errorSubscription = streamResult.fullStream.listen((event) {
        if (!isCurrentRequest(requestId)) return;
        if (event is StreamTextErrorEvent) _handleError(event.error, requestId);
      }, onError: (Object err) => _handleError(err, requestId));

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          if (!isCurrentRequest(requestId)) return;
          _completion += delta;
          notifyListenersSafely(immediate: false, content: true);
        },
        onDone: () async {
          _activeSubscription = null;
          unawaited(_errorSubscription?.cancel());
          _errorSubscription = null;
          if (!isCurrentRequest(requestId) || _error != null) return;
          try {
            _lastUsage =
                await streamResult.totalUsage ?? await streamResult.usage;
          } catch (_) {
            // Usage is best-effort.
          }
          if (!isCurrentRequest(requestId) || _error != null) return;
          activeRequestId = null;
          _activeAbortSignal = null;
          _isLoading = false;
          _isStreaming = false;
          notifyListenersSafely(immediate: true, status: true, content: true);
          try {
            final result = onFinish?.call(_completion);
            if (result is Future<void>) unawaited(result.catchError((_) {}));
          } catch (_) {}
        },
        onError: (Object err) => _handleError(err, requestId),
        cancelOnError: true,
      );
    } catch (err) {
      if (!isCurrentRequest(requestId) || abortSignal.isCancelled) return;
      _handleError(err, requestId);
    }
  }

  void _handleError(Object err, int requestId) {
    if (!isCurrentRequest(requestId) || _error != null) return;
    activeRequestId = null;
    _activeAbortSignal = null;
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _error = err;
    _isLoading = false;
    _isStreaming = false;
    notifyTerminalListeners(statusChanged: true);
    try {
      final result = onError?.call(err);
      if (result is Future<void>) unawaited(result.catchError((_) {}));
    } catch (_) {}
  }

  Future<void> stop() async {
    await _cancelActiveRequest();
    _isLoading = false;
    _isStreaming = false;
    notifyTerminalListeners(statusChanged: true);
  }

  void clear() {
    _cancelActiveRequestSync();
    _completion = '';
    _error = null;
    _lastUsage = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListenersSafely(immediate: true, status: true, content: true);
  }

  @override
  void dispose() {
    isDisposed = true;
    _cancelActiveRequestSync();
    super.dispose();
  }
}
