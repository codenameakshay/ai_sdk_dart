import 'dart:js_interop';
import 'dart:typed_data';

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(JSString input, _FetchOptions init);

@JS('AbortSignal.timeout')
external JSObject _timeoutSignal(int milliseconds);

@JS()
extension type _FetchOptions._(JSObject _) implements JSObject {
  external factory _FetchOptions({
    required String redirect,
    required JSObject signal,
  });
}

@JS()
extension type _FetchResponse._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external _Headers get headers;
  external _Body? get body;
}

@JS()
extension type _Body._(JSObject _) implements JSObject {
  external _Reader getReader();
}

@JS()
extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_Chunk> read();
  external JSPromise<JSAny?> cancel();
  external void releaseLock();
}

@JS()
extension type _Chunk._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array get value;
}

@JS()
extension type _Headers._(JSObject _) implements JSObject {
  external String? get(String name);
}

/// Fetches [uri] without redirects; the browser aborts it after [timeout].
Future<Uint8List> fetchImageBytes(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
}) async {
  final response = await _fetch(
    uri.toString().toJS,
    _FetchOptions(
      redirect: 'error',
      signal: _timeoutSignal(timeout.inMilliseconds),
    ),
  ).toDart;
  final reader = response.body?.getReader();
  try {
    if (!response.ok) {
      throw StateError(
        'Image request failed with status ${response.status}: $uri',
      );
    }
    final declared = int.tryParse(response.headers.get('content-length') ?? '');
    final tooLarge = StateError('Image is larger than $maxBytes bytes: $uri');
    if (declared != null && declared > maxBytes) throw tooLarge;
    final bytes = BytesBuilder(copy: false);
    if (reader != null) {
      while (true) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        final data = chunk.value.toDart;
        if (bytes.length + data.length > maxBytes) throw tooLarge;
        bytes.add(data);
      }
    }
    return bytes.takeBytes();
  } finally {
    try {
      await reader?.cancel().toDart;
    } finally {
      reader?.releaseLock();
    }
  }
}
