import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:test/test.dart';

void main() {
  test('parseOpenAiEmbeddings pairs vectors with inputs and bounds rows', () {
    final result = parseOpenAiEmbeddings(
      {
        'data': [
          {
            'embedding': [1, 0.5],
          },
          {
            'embedding': [2, 2.5],
          },
          {
            'embedding': [9, 9],
          },
        ],
      },
      ['a', 'b'],
    );
    expect(result.embeddings.map((e) => e.value), ['a', 'b']);
    expect(result.embeddings.first.embedding, [1.0, 0.5]);
    expect(result.embeddings.last.embedding, [2.0, 2.5]);
  });

  test('parseOpenAiEmbeddings tolerates a missing data array', () {
    expect(parseOpenAiEmbeddings({}, ['a']).embeddings, isEmpty);
  });
}
