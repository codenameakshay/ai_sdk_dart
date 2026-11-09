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
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS()
extension type _Headers._(JSObject _) implements JSObject {
  external String? get(String name);
}

/// Fetches [uri] without redirects; the browser aborts it after [timeout].
// ponytail: a body without Content-Length is read whole before the size check;
// stream it through a reader if memory on web matters.
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
  if (!response.ok) {
    throw StateError(
      'Image request failed with status ${response.status}: $uri',
    );
  }
  final declared = int.tryParse(response.headers.get('content-length') ?? '');
  if (declared != null && declared > maxBytes) {
    throw StateError('Image is larger than $maxBytes bytes: $uri');
  }
  final buffer = (await response.arrayBuffer().toDart).toDart;
  if (buffer.lengthInBytes > maxBytes) {
    throw StateError('Image is larger than $maxBytes bytes: $uri');
  }
  return Uint8List.fromList(buffer.asUint8List());
}
