import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

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
  }) : _value = initialValue;

  /// Optional identifier for this controller.
  final String? id;

  /// Model used by [submit]. Required only when calling [submit];
  /// [bind] works without it.
  final LanguageModelV3? model;

  /// Schema describing the structured output for [submit]. Required only when
  /// calling [submit]; [bind] works without it.
  final Schema<T>? schema;

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

    final result = await streamText<T>(
      model: model,
      prompt: prompt,
      output: Output.object(schema: schema),
    );

    await bind(result.partialOutputStream.map((value) => value as T));
  }

  /// Attach to [stream]; emits partial values as they arrive.
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

  /// Clear the current value and error.
  ///
  /// Mirrors the JS `experimental_useObject` `clear()` method.
  void clear() {
    _value = null;
    _error = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  /// Alias for [clear] — kept for backward compatibility.
  void reset() => clear();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
