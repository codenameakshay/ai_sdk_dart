import 'dart:async';

class StreamOutcome<T> {
  const StreamOutcome.value(T value)
    : _value = value,
      _error = null,
      _stackTrace = null;

  const StreamOutcome.error(Object error, StackTrace stackTrace)
    : _value = null,
      _error = error,
      _stackTrace = stackTrace;

  final T? _value;
  final Object? _error;
  final StackTrace? _stackTrace;

  T unwrap() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stackTrace!);
    return _value as T;
  }
}

Stream<StreamOutcome<T>> captureStreamErrors<T>(Stream<T> source) =>
    source.transform(
      StreamTransformer<T, StreamOutcome<T>>.fromHandlers(
        handleData: (value, sink) => sink.add(StreamOutcome.value(value)),
        handleError: (Object error, StackTrace stackTrace, sink) =>
            sink.add(StreamOutcome.error(error, stackTrace)),
      ),
    );
