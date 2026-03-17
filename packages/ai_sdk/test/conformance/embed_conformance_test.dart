import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('embed conformance', () {
    // ── embed() ───────────────────────────────────────────────────────────

    group('embed()', () {
      test('returns value, embedding, and usage', () async {
        final model = FakeEmbeddingModel([
          0.1,
          0.2,
          0.3,
        ], usage: const EmbeddingModelV2Usage(tokens: 3));
        final result = await embed(model: model, value: 'hello');
        expect(result.value, 'hello');
        expect(result.embedding, [0.1, 0.2, 0.3]);
        expect(result.usage?.tokens, 3);
      });

      test('embedding vector is non-empty', () async {
        final model = FakeEmbeddingModel([0.5, 0.5, 0.5, 0.5]);
        final result = await embed(model: model, value: 'test');
        expect(result.embedding, isNotEmpty);
      });

      test('usage is null when model does not return usage', () async {
        final model = FakeEmbeddingModel([0.1, 0.2]);
        final result = await embed(model: model, value: 'test');
        expect(result.usage, isNull);
      });

      test('value in result matches the input value', () async {
        final model = FakeEmbeddingModel([0.1, 0.2, 0.3]);
        final result = await embed(model: model, value: 'specific text');
        expect(result.value, 'specific text');
      });
    });

    // ── cosineSimilarity() ────────────────────────────────────────────────

    group('cosineSimilarity()', () {
      test('identical vectors return similarity of 1.0', () {
        final v = [1.0, 0.0, 0.0];
        expect(cosineSimilarity(v, v), closeTo(1.0, 1e-9));
      });

      test('same-direction vectors return 1.0', () {
        // [2,0,0] and [1,0,0] point in same direction
        expect(
          cosineSimilarity([2.0, 0.0, 0.0], [1.0, 0.0, 0.0]),
          closeTo(1.0, 1e-9),
        );
      });

      test('orthogonal vectors return 0.0', () {
        expect(cosineSimilarity([1.0, 0.0], [0.0, 1.0]), closeTo(0.0, 1e-9));
      });

      test('opposite vectors return -1.0', () {
        expect(cosineSimilarity([1.0, 0.0], [-1.0, 0.0]), closeTo(-1.0, 1e-9));
      });

      test('known angle: 45 degrees gives ~0.707', () {
        // [1,1] and [1,0] → cos(45°) ≈ 0.7071
        final sim = cosineSimilarity([1.0, 1.0], [1.0, 0.0]);
        expect(sim, closeTo(0.7071, 0.001));
      });

      test('throws ArgumentError for vectors of different lengths', () {
        expect(
          () => cosineSimilarity([1.0, 0.0], [1.0, 0.0, 0.0]),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for empty vectors', () {
        expect(() => cosineSimilarity([], []), throwsArgumentError);
      });

      test('result is in range [-1, 1] for arbitrary vectors', () {
        final a = [0.3, 0.4, 0.7, 0.1];
        final b = [0.9, 0.1, 0.2, 0.5];
        final sim = cosineSimilarity(a, b);
        expect(sim, greaterThanOrEqualTo(-1.0));
        expect(sim, lessThanOrEqualTo(1.0));
      });

      test('zero-magnitude vector returns 0.0 (no direction)', () {
        // Both zero vectors — denominator is 0, should return 0.0
        expect(cosineSimilarity([0.0, 0.0], [0.0, 0.0]), 0.0);
      });
    });
  });
}
