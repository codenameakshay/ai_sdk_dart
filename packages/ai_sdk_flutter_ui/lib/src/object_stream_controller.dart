import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'frame_notifier.dart';

/// Flutter controller for streaming structured objects — mirrors `useObject` hook.
///
/// Two ways to drive it:
///
/// - **Ergonomic** (useObject-style): supply a [model] and [schema] up front,
///   then call [submit] with a prompt. Internally runs
///   `streamText(... output: Output.object(schema:))` and binds the
///   partial-output stream for you.
///
/// - **Flexible**: build any `Stream<T>` of partial values yourself and pass it
///   to [bind] (e.g. from a custom `streamText`/`streamObject` call or a
///   non-AI source).
///
/// Provides:
/// - [submit] — run a prompt against the configured [model]/[schema]
/// - [bind] — attach to an arbitrary object stream
/// - [stop] — cancel the active stream
/// - [clear] / [reset] — clear current value and error
/// - [isLoading] — true while loading or streaming
class ObjectStreamController<T> extends ChangeNotifier {
  ObjectStreamController({
    this.id,
    this.model,
    this.schema,
    T? initialValue,
    this.onFinish,
    this.onError,
    FrameNotificationScheduler? notificationScheduler,
  }) : _rootListenable = FrameNotifier(scheduler: notificationScheduler),
       _statusListenable = FrameNotifier(scheduler: notificationScheduler),
       _contentListenable = FrameNotifier(scheduler: notificationScheduler),
       _value = initialValue;

  /// Optional identifier for this controller.
  final String? id;

  /// Model used by [submit]. Required only when calling [submit];
  /// [bind] works without it.
  final LanguageModelV4? model;

  /// Schema describing the structured output for [submit]. Required only when
  /// calling [submit]; [bind] works without it.
  final Schema<T>? schema;

  /// Called when the stream completes with the final value.
  final void Function(T? value)? onFinish;

  /// Called when an error occurs.
  final void Function(Object error)? onError;

  final FrameNotifier _rootListenable;
  final FrameNotifier _statusListenable;
  final FrameNotifier _contentListenable;

  /// Notifies when loading/streaming/error state changes.
  Listenable get statusListenable => _statusListenable;

  /// Notifies when [value] changes.
  Listenable get contentListenable => _contentListenable;

  T? _value;
  T? get value => _value;

  Object? _error;
  Object? get error => _error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  StreamSubscription<T>? _subscription;
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
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  Future<void> _cancelActiveRequest() async {
    _activeRequestId = null;
    _activeAbortSignal?.cancel();
    _activeAbortSignal = null;
    await _subscription?.cancel();
    _subscription = null;
  }

  int _beginRequest({required bool clearValue}) {
    _cancelActiveRequestSync();
    final requestId = ++_nextRequestId;
    _activeRequestId = requestId;
    _activeAbortSignal = CancellationToken();
    if (clearValue) _value = null;
    _error = null;
    _isLoading = true;
    _isStreaming = false;
    _notifyListenersSafely(immediate: true, status: true, content: clearValue);
    return requestId;
  }

  void _listenToStream(Stream<T> stream, int requestId) {
    _subscription = stream.listen(
      (event) {
        if (!_isCurrentRequest(requestId)) return;
        final wasStreaming = _isStreaming;
        _value = event;
        _isStreaming = true;
        _notifyListenersSafely(
          immediate: wasStreaming ? false : true,
          status: !wasStreaming,
          content: true,
        );
      },
      onDone: () {
        if (!_isCurrentRequest(requestId)) return;
        _activeRequestId = null;
        _activeAbortSignal = null;
        _subscription = null;
        _isLoading = false;
        _isStreaming = false;
        _notifyListenersSafely(immediate: true, status: true, content: true);
        onFinish?.call(_value);
      },
      onError: (Object err) {
        if (!_isCurrentRequest(requestId)) return;
        _activeRequestId = null;
        _activeAbortSignal = null;
        _subscription = null;
        _error = err;
        _isLoading = false;
        _isStreaming = false;
        _notifyTerminalListeners(statusChanged: true);
        onError?.call(err);
      },
      cancelOnError: true,
    );
  }

  /// Run [prompt] against the configured [model] and [schema], streaming
  /// partial structured values into [value] as they arrive.
  ///
  /// This is the useObject-style convenience: it runs
  /// `streamText(model:, prompt:, output: Output.object(schema:))` and binds
  /// the resulting `partialOutputStream` for you.
  ///
  /// Throws a [StateError] if [model] or [schema] were not provided to the
  /// constructor. For full control over the request, build the stream yourself
  /// and call [bind] instead.
  Future<void> submit(String prompt) async {
    final model = this.model;
    final schema = this.schema;
    if (model == null || schema == null) {
      throw StateError(
        'ObjectStreamController.submit requires both `model` and `schema` to '
        'be provided to the constructor. Either pass them, or build the '
        'stream yourself and call bind().',
      );
    }

    final requestId = _beginRequest(clearValue: true);
    final abortSignal = _activeAbortSignal!;

    try {
      final result = await streamText<T>(
        model: model,
        prompt: prompt,
        output: Output.object(schema: schema),
        abortSignal: abortSignal,
      );
      if (!_isCurrentRequest(requestId)) return;
      _listenToStream(
        result.partialOutputStream.map((value) => value as T),
        requestId,
      );
    } catch (err) {
      if (!_isCurrentRequest(requestId) || abortSignal.isCancelled) return;
      _activeRequestId = null;
      _activeAbortSignal = null;
      _error = err;
      _isLoading = false;
      _isStreaming = false;
      _notifyTerminalListeners(statusChanged: true);
      onError?.call(err);
    }
  }

  /// Attach to [stream]; emits partial values as they arrive.
  Future<void> bind(Stream<T> stream) async {
    final requestId = _beginRequest(clearValue: true);
    _listenToStream(stream, requestId);
  }

  Future<void> stop() async {
    await _cancelActiveRequest();
    _isLoading = false;
    _isStreaming = false;
    _notifyTerminalListeners(statusChanged: true);
  }

  /// Clear the current value and error.
  ///
  /// Mirrors the JS `experimental_useObject` `clear()` method.
  void clear() {
    _cancelActiveRequestSync();
    _value = null;
    _error = null;
    _isLoading = false;
    _isStreaming = false;
    _notifyListenersSafely(immediate: true, status: true, content: true);
  }

  /// Alias for [clear] — kept for backward compatibility.
  void reset() => clear();

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
