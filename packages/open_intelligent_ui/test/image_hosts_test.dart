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
