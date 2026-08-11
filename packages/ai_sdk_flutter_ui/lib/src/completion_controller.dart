import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'frame_notifier.dart';

/// Flutter controller for single-turn completion — mirrors the JS `useCompletion` hook.
///
/// Provides:
/// - [complete] — submit a prompt and stream the response
/// - [stop] — cancel the active stream
/// - [clear] — reset completion state
/// - [isStreaming] — true while actively streaming
class CompletionController extends ChangeNotifier {
  CompletionController({
    required this.agent,
    this.onFinish,
    this.onError,
    FrameNotificationScheduler? notificationScheduler,
  }) : _rootListenable = FrameNotifier(scheduler: notificationScheduler),
       _statusListenable = FrameNotifier(scheduler: notificationScheduler),
       _contentListenable = FrameNotifier(scheduler: notificationScheduler);

  final ToolLoopAgent agent;

  /// Called when completion finishes with the full text.
  final void Function(String text)? onFinish;

  /// Called when an error occurs.
  final void Function(Object error)? onError;

  final FrameNotifier _rootListenable;
  final FrameNotifier _statusListenable;
  final FrameNotifier _contentListenable;

  /// Notifies when loading/streaming/error state changes.
  Listenable get statusListenable => _statusListenable;

  /// Notifies when [completion] or [lastUsage] changes.
  Listenable get contentListenable => _contentListenable;

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
  int _nextRequestId = 0;
  int? _activeRequestId;
  bool _isDisposed = false;

  bool _isCurrentRequest(int requestId) =>
      !_isDisposed && _activeRequestId == requestId;

  void _notifyTerminalListeners({required bool statusChanged}) {
    if (_isDisposed) return;
    _rootListenable.notifyImmediately();
    if (statusChanged) _statusListenable.notifyImmediately();
    if (_contentListenable.hasPendingNotification) {
      _contentListenable.notifyImmediately();
    }
  }

  void _notifyListenersSafely({
    required bool immediate,
    bool status = false,
    bool content = false,
  }) {
    if (_isDisposed) return;
    if (immediate) {
      _rootListenable.notifyImmediately();
      if (status) _statusListenable.notifyImmediately();
      if (content) _contentListenable.notifyImmediately();
      return;
    }

    _rootListenable.notifyInFrame();
    if (status) _statusListenable.notifyInFrame();
    if (content) _contentListenable.notifyInFrame();
  }

  void _cancelActiveRequestSync() {
    _activeRequestId = null;
    _activeAbortSignal?.cancel();
    _activeAbortSignal = null;
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
  }

  Future<void> _cancelActiveRequest() async {
    _activeRequestId = null;
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
    final requestId = ++_nextRequestId;
    final abortSignal = CancellationToken();
    _activeRequestId = requestId;
    _activeAbortSignal = abortSignal;
    _completion = '';
    _error = null;
    _lastUsage = null;
    _isLoading = true;
    _isStreaming = false;
    _notifyListenersSafely(immediate: true, status: true, content: true);

    try {
      final streamResult = await agent.stream(
        prompt: prompt,
        abortSignal: abortSignal,
      );
      if (!_isCurrentRequest(requestId)) return;
      _isStreaming = true;
      _notifyListenersSafely(immediate: true, status: true);

      // The result's `text`/`output` futures reject on a streaming error; we
      // surface errors via [fullStream] instead, so swallow those completions
      // to keep them from becoming unhandled async errors.
      streamResult.text.then((_) {}, onError: (_) {});
      streamResult.output.then((_) {}, onError: (_) {});

      // Streaming errors surface on the full event stream (not the text
      // stream), so watch both: text for content, fullStream for errors.
      _errorSubscription = streamResult.fullStream.listen((event) {
        if (!_isCurrentRequest(requestId)) return;
        if (event is StreamTextErrorEvent) _handleError(event.error, requestId);
      }, onError: (Object err) => _handleError(err, requestId));

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          if (!_isCurrentRequest(requestId)) return;
          _completion += delta;
          _notifyListenersSafely(immediate: false, content: true);
        },
        onDone: () async {
          _activeSubscription = null;
          unawaited(_errorSubscription?.cancel());
          _errorSubscription = null;
          if (!_isCurrentRequest(requestId) || _error != null) return;
          try {
            _lastUsage =
                await streamResult.totalUsage ?? await streamResult.usage;
          } catch (_) {
            // Usage is best-effort.
          }
          if (!_isCurrentRequest(requestId) || _error != null) return;
          _activeRequestId = null;
          _activeAbortSignal = null;
          _isLoading = false;
          _isStreaming = false;
          _notifyListenersSafely(immediate: true, status: true, content: true);
          onFinish?.call(_completion);
        },
        onError: (Object err) => _handleError(err, requestId),
        cancelOnError: true,
      );
    } catch (err) {
      if (!_isCurrentRequest(requestId) || abortSignal.isCancelled) return;
      _handleError(err, requestId);
    }
  }

  void _handleError(Object err, int requestId) {
    if (!_isCurrentRequest(requestId) || _error != null) return;
    _activeRequestId = null;
    _activeAbortSignal = null;
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _error = err;
    _isLoading = false;
    _isStreaming = false;
    _notifyTerminalListeners(statusChanged: true);
    onError?.call(err);
  }

  Future<void> stop() async {
    await _cancelActiveRequest();
    _isLoading = false;
    _isStreaming = false;
    _notifyTerminalListeners(statusChanged: true);
  }

  void clear() {
    _cancelActiveRequestSync();
    _completion = '';
    _error = null;
    _lastUsage = null;
    _isLoading = false;
    _isStreaming = false;
    _notifyListenersSafely(immediate: true, status: true, content: true);
  }

  @override
  void addListener(VoidCallback listener) =>
      _rootListenable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _rootListenable.removeListener(listener);

  @override
  bool get hasListeners => _rootListenable.hasListeners;

  @override
  void dispose() {
    _isDisposed = true;
    _cancelActiveRequestSync();
    _rootListenable.dispose();
    _statusListenable.dispose();
    _contentListenable.dispose();
    super.dispose();
  }
}
