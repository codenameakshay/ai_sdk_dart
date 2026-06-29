import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A fake rerank model that returns documents in a fixed ranked order.
class FakeRerankModel implements RerankModelV1 {
  FakeRerankModel(
    this.ranked, {
    this.delay,
    this.provider = 'fake',
    this.modelId = 'fake-rerank-model',
  });

  /// Pre-ranked documents to return (highest relevance first).
  final List<RerankDocument> ranked;

  /// Optional artificial delay before returning — used to test timeouts.
  final Duration? delay;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v1';

  RerankModelV1CallOptions? lastOptions;

  @override
  Future<RerankModelV1Result> doRerank(RerankModelV1CallOptions options) async {
    lastOptions = options;
    if (delay != null) await Future<void>.delayed(delay!);
    final docs = options.topN != null
        ? ranked.take(options.topN!).toList()
        : ranked;
    return RerankModelV1Result(documents: docs);
  }
}

void main() {
  group('rerank conformance', () {
    RerankDocument doc(int index, String text, double score) =>
        RerankDocument(index: index, document: text, relevanceScore: score);

    test('returns documents in ranked order with scores', () async {
      final model = FakeRerankModel([
        doc(0, 'Paris is the capital of France.', 0.95),
        doc(1, 'Berlin is in Germany.', 0.10),
      ]);

      final result = await rerank(
        model: model,
        query: 'What is the capital of France?',
        documents: const [
          'Paris is the capital of France.',
          'Berlin is in Germany.',
        ],
      );

      expect(result.documents, hasLength(2));
      expect(result.documents.first.document, 'Paris is the capital of France.');
      expect(result.documents.first.index, 0);
      expect(result.documents.first.relevanceScore, 0.95);
      expect(result.documents.last.relevanceScore, 0.10);
    });

    test('document getter returns the top-ranked result', () async {
      final model = FakeRerankModel([
        doc(2, 'most relevant', 0.99),
        doc(0, 'less relevant', 0.2),
      ]);

      final result = await rerank(
        model: model,
        query: 'q',
        documents: const ['a', 'b', 'c'],
      );

      expect(result.document.document, 'most relevant');
      expect(result.document.index, 2);
    });

    test('forwards query, documents, topN and providerOptions to model',
        () async {
      final model = FakeRerankModel([doc(0, 'a', 0.5)]);
      const providerOptions = <String, Map<String, dynamic>>{
        'cohere': {'model': 'rerank-english-v3.0'},
      };

      await rerank(
        model: model,
        query: 'my query',
        documents: const ['a', 'b'],
        topN: 1,
        headers: const {'x-test': '1'},
        providerOptions: providerOptions,
      );

      expect(model.lastOptions?.query, 'my query');
      expect(model.lastOptions?.documents, ['a', 'b']);
      expect(model.lastOptions?.topN, 1);
      expect(model.lastOptions?.headers, {'x-test': '1'});
      expect(model.lastOptions?.providerOptions, providerOptions);
    });

    test('topN limits the number of returned documents', () async {
      final model = FakeRerankModel([
        doc(0, 'a', 0.9),
        doc(1, 'b', 0.8),
        doc(2, 'c', 0.7),
      ]);

      final result = await rerank(
        model: model,
        query: 'q',
        documents: const ['a', 'b', 'c'],
        topN: 2,
      );

      expect(result.documents, hasLength(2));
    });

    test('timeout throws when the model is too slow', () async {
      final model = FakeRerankModel(
        [doc(0, 'a', 0.5)],
        delay: const Duration(milliseconds: 200),
      );

      expect(
        () => rerank(
          model: model,
          query: 'q',
          documents: const ['a'],
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<Object>()),
      );
    });

    test('completes within a generous timeout', () async {
      final model = FakeRerankModel([doc(0, 'a', 0.5)]);
      final result = await rerank(
        model: model,
        query: 'q',
        documents: const ['a'],
        timeout: const Duration(seconds: 5),
      );
      expect(result.document.document, 'a');
    });
  });
}
