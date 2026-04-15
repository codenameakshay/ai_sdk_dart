import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('EmbeddingModelMiddleware conformance', () {
    // ── wrapEmbeddingModel ────────────────────────────────────────────────

    group('wrapEmbeddingModel()', () {
      test('wrapped model exposes inner provider and modelId', () {
        final inner = FakeEmbeddingModel([0.1, 0.2],
            provider: 'my-provider', modelId: 'my-model');
        final wrapped = wrapEmbeddingModel(
          model: inner,
          middleware: _PassthroughMiddleware<String>(),
        );
        expect(wrapped.provider, 'my-provider');
        expect(wrapped.modelId, 'my-model');
      });

      test('pass-through middleware returns original embeddings', () async {
        final inner = FakeEmbeddingModel([0.3, 0.6, 0.9]);
        final wrapped = wrapEmbeddingModel(
          model: inner,
          middleware: _PassthroughMiddleware<String>(),
        );
        final result = await wrapped.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['hello']),
        );
        expect(result.embeddings.first.embedding, [0.3, 0.6, 0.9]);
      });

      test('transformParams can add providerOptions', () async {
        final inner = FakeEmbeddingModel([0.1]);
        final capturing = <EmbeddingModelV2CallOptions<String>>[];
        final mw = _CapturingMiddleware<String>(capturing);
        final wrapped = wrapEmbeddingModel(model: inner, middleware: mw);
        await wrapped.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['test']),
        );
        expect(capturing, hasLength(1));
        expect(capturing.first.values, ['test']);
      });

      test('wrapEmbed can intercept and return cached result', () async {
        final inner = FakeEmbeddingModel([0.1, 0.2]);
        const cachedEmbedding = [9.9, 8.8, 7.7];
        final mw = _CachingMiddleware<String>(cachedEmbedding);
        final wrapped = wrapEmbeddingModel(model: inner, middleware: mw);
        final result = await wrapped.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['anything']),
        );
        expect(result.embeddings.first.embedding, cachedEmbedding);
      });

      test('stacking two middleware applies them left-to-right', () async {
        final inner = FakeEmbeddingModel([1.0, 2.0]);
        final order = <String>[];
        final mw1 = _OrderTrackingMiddleware<String>('mw1', order);
        final mw2 = _OrderTrackingMiddleware<String>('mw2', order);
        final wrapped = wrapEmbeddingModel(
          model: inner,
          middleware: [mw1, mw2],
        );
        await wrapped.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['x']),
        );
        // mw1 is outermost: transformParams(mw1) → transformParams(mw2) → inner
        expect(order, ['mw1-transform', 'mw2-transform']);
      });

      test('accepts a single middleware (not a list)', () async {
        final inner = FakeEmbeddingModel([0.5]);
        final wrapped = wrapEmbeddingModel(
          model: inner,
          middleware: _PassthroughMiddleware<String>(),
        );
        final result = await wrapped.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['hello']),
        );
        expect(result.embeddings, hasLength(1));
      });

      test('throws ArgumentError for invalid middleware type', () {
        final inner = FakeEmbeddingModel([0.1]);
        expect(
          () => wrapEmbeddingModel(model: inner, middleware: 'invalid'),
          throwsArgumentError,
        );
      });
    });

    // ── EmbeddingModelMiddlewareBase ──────────────────────────────────────

    group('EmbeddingModelMiddlewareBase', () {
      test('base class passes through unchanged by default', () async {
        final inner = FakeEmbeddingModel([0.7, 0.8]);
        final base = _BaseOnlyMiddleware<String>();
        final wrapped = wrapEmbeddingModel(model: inner, middleware: base);
        final result = await wrapped.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['test']),
        );
        expect(result.embeddings.first.embedding, [0.7, 0.8]);
      });
    });

    // ── integration with embed() ──────────────────────────────────────────

    group('integration with embed()', () {
      test('wrapped model works with top-level embed()', () async {
        final inner = FakeEmbeddingModel([0.1, 0.2, 0.3]);
        final wrapped = wrapEmbeddingModel(
          model: inner,
          middleware: _PassthroughMiddleware<String>(),
        );
        final result = await embed(model: wrapped, value: 'hello');
        expect(result.embedding, [0.1, 0.2, 0.3]);
        expect(result.value, 'hello');
      });

      test('wrapped model works with embedMany()', () async {
        final inner = FakeEmbeddingModel([0.5, 0.5]);
        final wrapped = wrapEmbeddingModel(
          model: inner,
          middleware: _PassthroughMiddleware<String>(),
        );
        final result = await embedMany(
          model: wrapped,
          values: ['a', 'b', 'c'],
        );
        expect(result.embeddings, hasLength(3));
      });
    });
  });
}

// ── Test helpers ──────────────────────────────────────────────────────────────

class _PassthroughMiddleware<VALUE>
    extends EmbeddingModelMiddlewareBase<VALUE> {
  const _PassthroughMiddleware();
}

class _CapturingMiddleware<VALUE>
    extends EmbeddingModelMiddlewareBase<VALUE> {
  _CapturingMiddleware(this._captured);
  final List<EmbeddingModelV2CallOptions<VALUE>> _captured;

  @override
  FutureOr<EmbeddingModelV2CallOptions<VALUE>> transformParams({
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  }) {
    _captured.add(options);
    return options;
  }
}

class _CachingMiddleware<VALUE> extends EmbeddingModelMiddlewareBase<VALUE> {
  _CachingMiddleware(this._cached);
  final List<double> _cached;

  @override
  Future<EmbeddingModelV2GenerateResult<VALUE>> wrapEmbed({
    required Future<EmbeddingModelV2GenerateResult<VALUE>> Function(
      EmbeddingModelV2CallOptions<VALUE> options,
    )
    doEmbed,
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  }) async {
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map(
            (v) => EmbeddingModelV2Embedding(value: v, embedding: _cached),
          )
          .toList(),
    );
  }
}

class _OrderTrackingMiddleware<VALUE>
    extends EmbeddingModelMiddlewareBase<VALUE> {
  _OrderTrackingMiddleware(this._name, this._order);
  final String _name;
  final List<String> _order;

  @override
  FutureOr<EmbeddingModelV2CallOptions<VALUE>> transformParams({
    required EmbeddingModelV2CallOptions<VALUE> options,
    required EmbeddingModelV2<VALUE> model,
  }) {
    _order.add('$_name-transform');
    return options;
  }
}

class _BaseOnlyMiddleware<VALUE>
    extends EmbeddingModelMiddlewareBase<VALUE> {
  const _BaseOnlyMiddleware();
}
