import 'dart:async';

import 'package:flutter/foundation.dart';

/// Flutter controller for streaming structured objects — mirrors `useObject` hook.
///
/// Provides:
/// - [bind] — attach to an object stream (partial values emitted as they arrive)
/// - [stop] — cancel the active stream
/// - [reset] — clear current value and error
class ObjectStreamController<T> extends ChangeNotifier {
  ObjectStreamController({this.onFinish, this.onError});

  /// Called when the stream completes with the final value.
  final void Function(T? value)? onFinish;

  /// Called when an error occurs.
  final void Function(Object error)? onError;

  T? _value;
  T? get value => _value;

  Object? _error;
  Object? get error => _error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  StreamSubscription<T>? _subscription;

  Future<void> bind(Stream<T> stream) async {
    await _subscription?.cancel();
    _value = null;
    _error = null;
    _isLoading = true;
    _isStreaming = false;
    notifyListeners();

    _subscription = stream.listen(
      (event) {
        _value = event;
        _isStreaming = true;
        notifyListeners();
      },
      onDone: () {
        _isLoading = false;
        _isStreaming = false;
        notifyListeners();
        onFinish?.call(_value);
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
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  void reset() {
    _value = null;
    _error = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
