import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

final _pixelBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('allowImageHosts matches parsed hosts, not URL text', () {
    final loader = allowImageHosts(['good.com']);

    expect(loader(Uri.parse('https://good.com/a.png')), isNotNull);
    expect(loader(Uri.parse('https://img.good.com:8443/a.png')), isNotNull);
    expect(loader(Uri.parse('https://GOOD.COM/a.png')), isNotNull);
    expect(loader(Uri.parse('https://notgood.com/a.png')), isNull);
    expect(loader(Uri.parse('https://good.com.evil.test/a.png')), isNull);
    expect(loader(Uri.parse('https://good.com@evil.test/a.png')), isNull);
    expect(loader(Uri.parse('ftp://good.com/a.png')), isNull);
  });

  test('an allowed image URL cannot redirect to another host', () async {
    var redirectHits = 0;
    var sourceHits = 0;
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final targetServer = target;
    final sourceServer = source;

    final targetSubscription = targetServer.listen((request) async {
      redirectHits++;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'png')
        ..add(_pixelBytes);
      await request.response.close();
    });
    final sourceSubscription = sourceServer.listen((request) async {
      sourceHits++;
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://localhost:${targetServer.port}/pixel.png',
        );
      await request.response.close();
    });
    addTearDown(() async {
      await sourceSubscription.cancel();
      await targetSubscription.cancel();
      await sourceServer.close(force: true);
      await targetServer.close(force: true);
    });

    final provider = allowImageHosts(['127.0.0.1'])(
      Uri.parse('http://127.0.0.1:${sourceServer.port}/redirect.png'),
    );
    expect(provider, isNotNull);

    Object? loadError;
    try {
      final image = await _resolve(provider!);
      image.dispose();
    } catch (error) {
      loadError = error;
    }
    expect(sourceHits, 1);
    expect(redirectHits, 0);
    expect(loadError, isNotNull);
  });

  test('an allowed image can load bytes directly', () async {
    final imageServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = imageServer.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'png')
        ..add(_pixelBytes);
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await imageServer.close(force: true);
    });

    final provider = allowImageHosts(['127.0.0.1'])(
      Uri.parse('http://127.0.0.1:${imageServer.port}/pixel.png'),
    );
    expect(provider, isNotNull);
    final image = await _resolve(provider!);
    image.dispose();
  });

  test('an image larger than maxBytes fails before it is decoded', () async {
    for (final declared in [true, false]) {
      final imageServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final subscription = imageServer.listen((request) async {
        final response = request.response..statusCode = HttpStatus.ok;
        if (declared) response.contentLength = 4096;
        for (var i = 0; i < 4; i++) {
          response.add(List.filled(1024, 0));
          await response.flush();
        }
        await response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await imageServer.close(force: true);
      });

      final provider = allowImageHosts(['127.0.0.1'], maxBytes: 1000)(
        Uri.parse('http://127.0.0.1:${imageServer.port}/big.png'),
      );
      await expectLater(
        _resolve(provider!),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('larger than 1000 bytes'),
          ),
        ),
        reason: declared ? 'Content-Length' : 'chunked',
      );
    }
  });

  test('an image server that never answers times out', () async {
    final imageServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    final subscription = imageServer.listen(requests.add);
    addTearDown(() async {
      await subscription.cancel();
      await imageServer.close(force: true);
    });

    final provider = allowImageHosts(
      ['127.0.0.1'],
      timeout: const Duration(milliseconds: 200),
    )(Uri.parse('http://127.0.0.1:${imageServer.port}/slow.png'));
    final watch = Stopwatch()..start();
    await expectLater(_resolve(provider!), throwsA(isA<TimeoutException>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    expect(requests, hasLength(1));
  });

  test('image caps are part of the provider key', () {
    final url = Uri.parse('https://good.com/a.png');
    final loader = allowImageHosts(['good.com']);

    expect(loader(url), allowImageHosts(['good.com'])(url));
    expect(loader(url).hashCode, allowImageHosts(['good.com'])(url).hashCode);
    expect(loader(url), isNot(allowImageHosts(['good.com'], maxBytes: 1)(url)));
    expect(
      loader(url),
      isNot(allowImageHosts(['good.com'], timeout: Duration.zero)(url)),
    );
  });
}

Future<ImageInfo> _resolve(ImageProvider provider) async {
  final completed = Completer<ImageInfo>();
  final stream = provider.resolve(const ImageConfiguration());
  final listener = ImageStreamListener(
    (image, _) {
      if (!completed.isCompleted) completed.complete(image);
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completed.isCompleted) completed.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  try {
    return await completed.future.timeout(const Duration(seconds: 5));
  } finally {
    stream.removeListener(listener);
  }
}
