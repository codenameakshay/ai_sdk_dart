import 'dart:js_interop';
import 'dart:typed_data';

@JS('fetch')
external JSPromise<_FetchResponse> _fetch(JSString input, _FetchOptions init);

@JS()
extension type _FetchOptions._(JSObject _) implements JSObject {
  external factory _FetchOptions({required String redirect});
}

@JS()
extension type _FetchResponse._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<Uint8List> fetchImageBytes(Uri uri) async {
  final response = await _fetch(
    uri.toString().toJS,
    _FetchOptions(redirect: 'error'),
  ).toDart;
  if (!response.ok) {
    throw StateError(
      'Image request failed with status ${response.status}: $uri',
    );
  }
  final buffer = await response.arrayBuffer().toDart;
  return Uint8List.fromList(buffer.toDart.asUint8List());
}
