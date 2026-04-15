import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Middleware for intercepting and transforming embedding model calls.
///
/// Two hook points (both optional via [EmbeddingModelMiddlewareBase]):
///
/// - [transformParams] — modify call options before the embedding call.
/// - [wrapEmbed]       — intercept the doEmbed call entirely.
///
/// Mirrors the `wrapEmbeddingModel` middleware concept from the JS AI SDK v6.
abstract interface class EmbeddingModelMiddleware<VALUE> {
  /// Transform [EmbeddingModelV2CallOptions] before the call reaches the model.
  FutureOr<EmbeddingModelV2CallOptions<VALUE>> transformParams({
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  });

  /// Optionally wrap the doEmbed call.
  Future<EmbeddingModelV2GenerateResult<VALUE>> wrapEmbed({
    required Future<EmbeddingModelV2GenerateResult<VALUE>> Function(
      EmbeddingModelV2CallOptions<VALUE> options,
    )
    doEmbed,
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  });
}

/// Wraps an [EmbeddingModelV2] with one or more [EmbeddingModelMiddleware]
/// layers.
///
/// Mirrors the `wrapEmbeddingModel` API from the JS AI SDK v6:
/// ```dart
/// final wrapped = wrapEmbeddingModel(
///   model: openai.embedding('text-embedding-3-small'),
///   middleware: myEmbeddingMiddleware,
/// );
/// // or with multiple middleware:
/// final wrapped = wrapEmbeddingModel(
///   model: openai.embedding('text-embedding-3-small'),
///   middleware: [mw1, mw2],
/// );
/// ```
///
/// When [middleware] is a single [EmbeddingModelMiddleware] it is treated as a
/// one-element list. Middleware is applied left-to-right (first is outermost).
EmbeddingModelV2<VALUE> wrapEmbeddingModel<VALUE>({
  required EmbeddingModelV2<VALUE> model,
  required Object middleware,
}) {
  final List<EmbeddingModelMiddleware<VALUE>> mwList;
  if (middleware is EmbeddingModelMiddleware<VALUE>) {
    mwList = [middleware];
  } else if (middleware is List<EmbeddingModelMiddleware<VALUE>>) {
    mwList = middleware;
  } else {
    throw ArgumentError(
      'middleware must be an EmbeddingModelMiddleware<VALUE> or '
      'List<EmbeddingModelMiddleware<VALUE>>',
    );
  }
  var wrapped = model;
  for (final mw in mwList.reversed) {
    wrapped = _WrappedEmbeddingModel<VALUE>(inner: wrapped, middleware: mw);
  }
  return wrapped;
}

class _WrappedEmbeddingModel<VALUE> implements EmbeddingModelV2<VALUE> {
  const _WrappedEmbeddingModel({
    required this.inner,
    required this.middleware,
  });

  final EmbeddingModelV2<VALUE> inner;
  final EmbeddingModelMiddleware<VALUE> middleware;

  @override
  String get provider => inner.provider;

  @override
  String get modelId => inner.modelId;

  @override
  String get specificationVersion => inner.specificationVersion;

  @override
  Future<EmbeddingModelV2GenerateResult<VALUE>> doEmbed(
    EmbeddingModelV2CallOptions<VALUE> options,
  ) async {
    final transformed = await middleware.transformParams(
      options: options,
      model: inner,
    );
    return middleware.wrapEmbed(
      doEmbed: inner.doEmbed,
      options: transformed,
      model: inner,
    );
  }
}

/// Base class providing pass-through defaults for embedding model middleware.
///
/// Extend this and override only the methods you need.
abstract class EmbeddingModelMiddlewareBase<VALUE>
    implements EmbeddingModelMiddleware<VALUE> {
  const EmbeddingModelMiddlewareBase();

  /// Default: returns [options] unchanged.
  @override
  FutureOr<EmbeddingModelV2CallOptions<VALUE>> transformParams({
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  }) => options;

  /// Default: passes straight through to the inner model.
  @override
  Future<EmbeddingModelV2GenerateResult<VALUE>> wrapEmbed({
    required Future<EmbeddingModelV2GenerateResult<VALUE>> Function(
      EmbeddingModelV2CallOptions<VALUE> options,
    )
    doEmbed,
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  }) => doEmbed(options);
}
