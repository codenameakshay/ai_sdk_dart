@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui_core/src/image_fetch_web.dart';

@JS('eval')
external JSAny? _eval(JSString source);

void main() {
  setUp(() => _eval('globalThis.savedFetch = globalThis.fetch'.toJS));
  tearDown(() => _eval('globalThis.fetch = globalThis.savedFetch'.toJS));

  Future<List<int>> fetch({int maxBytes = 3}) => fetchImageBytes(
    Uri.parse('https://images.example/image.png'),
    maxBytes: maxBytes,
    timeout: const Duration(seconds: 1),
  );

  void response(String body, {String headers = '{}', int status = 200}) {
    _eval(
      '''
      globalThis.cancelled = false;
      globalThis.fetch = async () => new Response(
        $body, {status: $status, headers: $headers}
      );
    '''
          .toJS,
    );
  }

  test('an oversized open image stream is cancelled before it ends', () async {
    response('''new ReadableStream({
      start(controller) { controller.enqueue(new Uint8Array([1, 2, 3, 4])); },
      cancel() { globalThis.cancelled = true; }
    })''');
    await expectLater(
      fetch().timeout(const Duration(seconds: 2)),
      throwsA(isA<StateError>()),
    );
    expect((_eval('globalThis.cancelled'.toJS) as JSBoolean).toDart, isTrue);
  });

  test('the byte cap counts all chunks in an image stream', () async {
    response('''new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array([1, 2]));
        controller.enqueue(new Uint8Array([3, 4]));
      },
      cancel() { globalThis.cancelled = true; }
    })''');
    await expectLater(fetch(), throwsA(isA<StateError>()));
    expect((_eval('globalThis.cancelled'.toJS) as JSBoolean).toDart, isTrue);
  });

  test('an image body at the cap is returned in full', () async {
    response('new Uint8Array([1, 2, 3])', headers: '{"content-length": "3"}');
    expect(await fetch(), [1, 2, 3]);
  });

  test('a declared oversized image is rejected', () async {
    response('new Uint8Array([1])', headers: '{"content-length": "4"}');
    await expectLater(fetch(), throwsA(isA<StateError>()));
  });

  test('an unsuccessful image response is rejected', () async {
    response('null', status: 404);
    await expectLater(fetch(), throwsA(isA<StateError>()));
  });

  test('an image with no response body returns no bytes', () async {
    response('null', status: 204);
    expect(await fetch(), isEmpty);
  });
  test('an interrupted image stream releases its reader', () async {
    _eval(
      '''globalThis.fetch = async (_, init) => {
      globalThis.imageBody = new ReadableStream({
        start(controller) {
          init.signal.addEventListener('abort', () => controller.error(init.signal.reason));
        }
      });
      return new Response(globalThis.imageBody);
    };'''
          .toJS,
    );
    await expectLater(fetch(), throwsA(anything));
    expect(
      (_eval('globalThis.imageBody.locked'.toJS) as JSBoolean).toDart,
      isFalse,
    );
  });
}
