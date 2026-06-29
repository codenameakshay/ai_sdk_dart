import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';

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

  StreamSubscription<String>? _activeSubscription;
  StreamSubscription<StreamTextEvent>? _errorSubscription;

  /// Submit [prompt] and stream the completion.
  Future<void> complete(String prompt) async {
    _completion = '';
    _error = null;
    _isLoading = true;
    _isStreaming = false;
    notifyListeners();

    try {
      final streamResult = await agent.stream(prompt: prompt);
      _isStreaming = true;
      notifyListeners();

      // The result's `text`/`output` futures reject on a streaming error; we
      // surface errors via [fullStream] instead, so swallow those completions
      // to keep them from becoming unhandled async errors.
      streamResult.text.then((_) {}, onError: (_) {});
      streamResult.output.then((_) {}, onError: (_) {});

      // Streaming errors surface on the full event stream (not the text
      // stream), so watch both: text for content, fullStream for errors.
      _errorSubscription = streamResult.fullStream.listen((event) {
        if (event is StreamTextErrorEvent) _handleError(event.error);
      }, onError: _handleError);

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          _completion += delta;
          notifyListeners();
        },
        onDone: () {
          unawaited(_errorSubscription?.cancel());
          _errorSubscription = null;
          if (_error != null) return; // an error already terminated us
          _isLoading = false;
          _isStreaming = false;
          notifyListeners();
          onFinish?.call(_completion);
        },
        onError: _handleError,
        cancelOnError: true,
      );
    } catch (err) {
      _handleError(err);
    }
  }

  void _handleError(Object err) {
    if (_error != null) return; // first error wins
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _error = err;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
    onError?.call(err);
  }

  Future<void> stop() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    await _errorSubscription?.cancel();
    _errorSubscription = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  void clear() {
    unawaited(_activeSubscription?.cancel());
    _activeSubscription = null;
    unawaited(_errorSubscription?.cancel());
    _errorSubscription = null;
    _completion = '';
    _error = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }
}
