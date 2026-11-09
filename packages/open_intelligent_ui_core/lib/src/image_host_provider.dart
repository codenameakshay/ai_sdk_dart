import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_fetch_stub.dart'
    if (dart.library.io) 'image_fetch_io.dart'
    if (dart.library.js_interop) 'image_fetch_web.dart'
    as image_fetch;

/// The default byte cap of an allow-listed image: 10 MiB.
const defaultImageMaxBytes = 10 * 1024 * 1024;

/// The default time an allow-listed image fetch may take.
const defaultImageTimeout = Duration(seconds: 30);

/// Loads an HTTP image without following redirects.
@immutable
class AllowlistedImageProvider extends ImageProvider<AllowlistedImageProvider> {
  /// Creates an image provider for [uri] at the given display [scale].
  const AllowlistedImageProvider(
    this.uri, {
    this.scale = 1.0,
    this.maxBytes = defaultImageMaxBytes,
    this.timeout = defaultImageTimeout,
  });

  /// The image URL to fetch.
  final Uri uri;

  /// The image's display scale.
  final double scale;

  /// The largest response body it reads; a larger image fails.
  final int maxBytes;

  /// How long the whole fetch may take before it fails.
  final Duration timeout;

  @override
  Future<AllowlistedImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<AllowlistedImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    AllowlistedImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadAsync(key, decode),
    scale: key.scale,
    informationCollector: () => <DiagnosticsNode>[
      ErrorDescription('Image URL: ${key.uri}'),
    ],
  );

  Future<ui.Codec> _loadAsync(
    AllowlistedImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await image_fetch.fetchImageBytes(
      key.uri,
      maxBytes: key.maxBytes,
      timeout: key.timeout,
    );
    if (bytes.isEmpty) throw StateError('Image response was empty: ${key.uri}');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is AllowlistedImageProvider &&
      other.uri == uri &&
      other.scale == scale &&
      other.maxBytes == maxBytes &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(uri, scale, maxBytes, timeout);

  @override
  String toString() => 'AllowlistedImageProvider("$uri", scale: $scale)';
}
