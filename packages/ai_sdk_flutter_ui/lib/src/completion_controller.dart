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

      _activeSubscription = streamResult.textStream.listen(
        (delta) {
          _completion += delta;
          notifyListeners();
        },
        onDone: () {
          _isLoading = false;
          _isStreaming = false;
          notifyListeners();
          onFinish?.call(_completion);
        },
        onError: (Object err) {
          _error = err;
          _isLoading = false;
          _isStreaming = false;
          notifyListeners();
          onError?.call(err);
        },
        cancelOnError: true,
      );
    } catch (err) {
      _error = err;
      _isLoading = false;
      _isStreaming = false;
      notifyListeners();
      onError?.call(err);
    }
  }

  Future<void> stop() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  void clear() {
    _completion = '';
    _error = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    super.dispose();
  }
}
