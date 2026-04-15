import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A middleware function that can intercept and transform image model calls.
///
/// Only one hook point: [wrapGenerate] — intercept the doGenerate call.
///
/// Mirrors `wrapImageModel` from the JS AI SDK v6.
abstract interface class ImageModelMiddleware {
  /// Transform [ImageModelV3CallOptions] before the call reaches the model.
  ///
  /// Return modified options (or the same instance if no change is needed).
  FutureOr<ImageModelV3CallOptions> transformParams({
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  });

  /// Optionally wrap the doGenerate call.
  Future<ImageModelV3GenerateResult> wrapGenerate({
    required Future<ImageModelV3GenerateResult> Function(
      ImageModelV3CallOptions options,
    )
    doGenerate,
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  });
}

/// Wraps an [ImageModelV3] with one or more [ImageModelMiddleware] layers.
///
/// Mirrors the `wrapImageModel` API from the JS AI SDK v6:
/// ```dart
/// final wrapped = wrapImageModel(
///   model: openai.image('dall-e-3'),
///   middleware: myImageMiddleware,
/// );
/// // or with multiple middleware:
/// final wrapped = wrapImageModel(
///   model: openai.image('dall-e-3'),
///   middleware: [mw1, mw2],
/// );
/// ```
///
/// When [middleware] is a single [ImageModelMiddleware] it is treated as a
/// one-element list. Middleware is applied left-to-right (first is outermost).
ImageModelV3 wrapImageModel({
  required ImageModelV3 model,
  required Object middleware,
}) {
  final List<ImageModelMiddleware> mwList;
  if (middleware is ImageModelMiddleware) {
    mwList = [middleware];
  } else if (middleware is List<ImageModelMiddleware>) {
    mwList = middleware;
  } else {
    throw ArgumentError(
      'middleware must be an ImageModelMiddleware or '
      'List<ImageModelMiddleware>',
    );
  }
  var wrapped = model;
  for (final mw in mwList.reversed) {
    wrapped = _WrappedImageModel(inner: wrapped, middleware: mw);
  }
  return wrapped;
}

class _WrappedImageModel implements ImageModelV3 {
  const _WrappedImageModel({required this.inner, required this.middleware});

  final ImageModelV3 inner;
  final ImageModelMiddleware middleware;

  @override
  String get provider => inner.provider;

  @override
  String get modelId => inner.modelId;

  @override
  String get specificationVersion => inner.specificationVersion;

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    final transformed = await middleware.transformParams(
      options: options,
      model: inner,
    );
    return middleware.wrapGenerate(
      doGenerate: inner.doGenerate,
      options: transformed,
      model: inner,
    );
  }
}

/// Base class providing pass-through defaults for image model middleware.
///
/// Extend this and override only the methods you need.
abstract class ImageModelMiddlewareBase implements ImageModelMiddleware {
  const ImageModelMiddlewareBase();

  /// Default: returns [options] unchanged.
  @override
  FutureOr<ImageModelV3CallOptions> transformParams({
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  }) => options;

  /// Default: passes straight through to the inner model.
  @override
  Future<ImageModelV3GenerateResult> wrapGenerate({
    required Future<ImageModelV3GenerateResult> Function(
      ImageModelV3CallOptions options,
    )
    doGenerate,
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  }) => doGenerate(options);
}
