import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Flutter controller for single-turn completion — mirrors the JS `useCompletion` hook.
///
/// Provides:
/// - [complete] — submit a prompt and stream the response
/// - [stop] — cancel the active stream
/// - [clear] — reset completion state
/// - [isStreaming] — true while actively streaming
class CompletionController extends ChangeNotifier {
  CompletionController({required this.agent, this.onFinish, this.onError});

  final ToolLoopAgent agent;

  /// Called when completion finishes with the full text.
  final void Function(String text)? onFinish;

  /// Called when an error occurs.
  final void Function(Object error)? onError;

  String _completion = '';
  String get completion => _completion;

  Object? _error;
  Object? get error => _error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  /// Token usage reported by the most recent completion, if any.
  LanguageModelV3Usage? get lastUsage => _lastUsage;
  LanguageModelV3Usage? _lastUsage;

  StreamSubscription<String>? _activeSubscription;
  StreamSubscription<StreamTextEvent>? _errorSubscription;
  CancellationToken? _activeAbortSignal;
  int _nextRequestId = 0;
  int? _activeRequestId;
  bool _isDisposed = false;

  bool _isCurrentRequest(int requestId) =>
      !_isDisposed && _activeRequestId == requestId;

  void _notifyListenersSafely() {
    if (!_isDisposed) notifyListeners();
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
    _notifyListenersSafely();

    try {
      final streamResult = await agent.stream(
        prompt: prompt,
        abortSignal: abortSignal,
      );
      if (!_isCurrentRequest(requestId)) return;
      _isStreaming = true;
      _notifyListenersSafely();

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
          _notifyListenersSafely();
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
          _notifyListenersSafely();
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
    _notifyListenersSafely();
    onError?.call(err);
  }

  Future<void> stop() async {
    await _cancelActiveRequest();
    _isLoading = false;
    _isStreaming = false;
    _notifyListenersSafely();
  }

  void clear() {
    _cancelActiveRequestSync();
    _completion = '';
    _error = null;
    _lastUsage = null;
    _isLoading = false;
    _isStreaming = false;
    _notifyListenersSafely();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelActiveRequestSync();
    super.dispose();
  }
}
