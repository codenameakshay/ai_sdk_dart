import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('errors conformance', () {
    // ── AiSdkError base class ─────────────────────────────────────────────

    group('AiSdkError', () {
      test('AiApiCallError is an instance of AiSdkError', () {
        const err = AiApiCallError('HTTP 429 rate limited');
        expect(err, isA<AiSdkError>());
      });

      test('AiNoSuchToolError is an instance of AiSdkError', () {
        const err = AiNoSuchToolError('Tool "foo" not found');
        expect(err, isA<AiSdkError>());
      });

      test('AiInvalidToolInputError is an instance of AiSdkError', () {
        const err = AiInvalidToolInputError('Tool input is not a JSON object');
        expect(err, isA<AiSdkError>());
      });

      test('AiNoContentGeneratedError is an instance of AiSdkError', () {
        const err = AiNoContentGeneratedError('No content was generated.');
        expect(err, isA<AiSdkError>());
      });

      test('AiNoObjectGeneratedError is an instance of AiSdkError', () {
        final err = AiNoObjectGeneratedError(
          message: 'Failed to generate structured output',
          text: 'not json',
          response: null,
          usage: null,
        );
        expect(err, isA<AiSdkError>());
      });
    });

    // ── AiApiCallError ─────────────────────────────────────────────────────

    group('AiApiCallError', () {
      test('has descriptive message', () {
        const err = AiApiCallError('HTTP 500: Internal Server Error');
        expect(err.message, isNotEmpty);
        expect(err.message, contains('500'));
      });

      test('toString includes class name and message', () {
        const err = AiApiCallError('request failed');
        expect(err.toString(), contains('AiApiCallError'));
        expect(err.toString(), contains('request failed'));
      });
    });

    // ── AiNoSuchToolError ─────────────────────────────────────────────────

    group('AiNoSuchToolError', () {
      test('message is descriptive', () {
        const err = AiNoSuchToolError('Tool "unknownTool" not found');
        expect(err.message, isNotEmpty);
      });

      test('toString includes class name', () {
        const err = AiNoSuchToolError('missing tool');
        expect(err.toString(), contains('AiNoSuchToolError'));
      });

      test('is thrown by generateText when model calls unknown tool', () async {
        final model = _FakeUnknownToolModel();
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            tools: {
              'real_tool': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
              ),
            },
          ),
          throwsA(isA<AiNoSuchToolError>()),
        );
      });
    });

    // ── AiInvalidToolInputError ───────────────────────────────────────────

    group('AiInvalidToolInputError', () {
      test('has descriptive message', () {
        const err = AiInvalidToolInputError('Tool input is not a JSON object');
        expect(err.message, isNotEmpty);
      });

      test('toString includes class name', () {
        const err = AiInvalidToolInputError('bad input');
        expect(err.toString(), contains('AiInvalidToolInputError'));
      });
    });

    // ── AiNoContentGeneratedError ─────────────────────────────────────────

    group('AiNoContentGeneratedError', () {
      test('has descriptive message', () {
        const err = AiNoContentGeneratedError('No content generated.');
        expect(err.message, isNotEmpty);
      });

      test('toString includes class name', () {
        const err = AiNoContentGeneratedError('empty');
        expect(err.toString(), contains('AiNoContentGeneratedError'));
      });
    });

    // ── AiNoObjectGeneratedError ──────────────────────────────────────────

    group('AiNoObjectGeneratedError', () {
      test('exposes text field containing the raw model output', () {
        final err = AiNoObjectGeneratedError(
          message: 'Structured output failed',
          text: 'this is not json',
          response: null,
          usage: null,
        );
        expect(err.text, 'this is not json');
      });

      test('exposes response field (can be null)', () {
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: null,
          usage: null,
        );
        expect(err.response, isNull);
      });

      test('exposes response field when provided', () {
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: const LanguageModelV3ResponseMetadata(id: 'resp-123'),
          usage: null,
        );
        expect(err.response?.id, 'resp-123');
      });

      test('exposes usage field (can be null)', () {
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: null,
          usage: null,
        );
        expect(err.usage, isNull);
      });

      test('exposes usage field when provided', () {
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: null,
          usage: const LanguageModelV3Usage(inputTokens: 5, outputTokens: 3),
        );
        expect(err.usage?.inputTokens, 5);
      });

      test('exposes cause field (can be null)', () {
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: null,
          usage: null,
        );
        expect(err.cause, isNull);
      });

      test('exposes cause field when provided', () {
        final cause = FormatException('invalid json');
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: null,
          usage: null,
          cause: cause,
        );
        expect(err.cause, same(cause));
      });

      test('message field is non-empty', () {
        final err = AiNoObjectGeneratedError(
          message: 'Failed to generate a valid structured output.',
          text: 'bad',
          response: null,
          usage: null,
        );
        expect(err.message, isNotEmpty);
      });

      test('toString includes class name and message', () {
        final err = AiNoObjectGeneratedError(
          message: 'structured output failed',
          text: '',
          response: null,
          usage: null,
        );
        expect(err.toString(), contains('AiNoObjectGeneratedError'));
      });

      group('isInstance()', () {
        test('returns true for AiNoObjectGeneratedError', () {
          final err = AiNoObjectGeneratedError(
            message: 'fail',
            text: 'bad',
            response: null,
            usage: null,
          );
          expect(AiNoObjectGeneratedError.isInstance(err), isTrue);
        });

        test('returns false for other AiSdkError subtypes', () {
          expect(
            AiNoObjectGeneratedError.isInstance(
              const AiApiCallError('http error'),
            ),
            isFalse,
          );
          expect(
            AiNoObjectGeneratedError.isInstance(
              const AiNoSuchToolError('no tool'),
            ),
            isFalse,
          );
        });

        test('returns false for plain Exceptions', () {
          expect(
            AiNoObjectGeneratedError.isInstance(Exception('generic')),
            isFalse,
          );
        });

        test('returns false for non-error objects', () {
          expect(AiNoObjectGeneratedError.isInstance('a string'), isFalse);
          expect(AiNoObjectGeneratedError.isInstance(42), isFalse);
          expect(AiNoObjectGeneratedError.isInstance(Object()), isFalse);
        });
      });
    });

    // ── Exception interface ───────────────────────────────────────────────

    group('Exception interface', () {
      test('all error types implement Exception', () {
        expect(const AiApiCallError('e'), isA<Exception>());
        expect(const AiNoSuchToolError('e'), isA<Exception>());
        expect(const AiInvalidToolInputError('e'), isA<Exception>());
        expect(const AiNoContentGeneratedError('e'), isA<Exception>());
        expect(
          AiNoObjectGeneratedError(
            message: 'e',
            text: '',
            response: null,
            usage: null,
          ),
          isA<Exception>(),
        );
      });
    });
  });
}

/// A fake model that calls an unknown tool to trigger AiNoSuchToolError.
class _FakeUnknownToolModel implements LanguageModelV3 {
  @override
  String get provider => 'fake';

  @override
  String get modelId => 'fake-unknown-tool';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return const LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3ToolCallPart(
          toolCallId: 'c1',
          toolName: 'nonexistent_tool',
          input: {},
        ),
      ],
      finishReason: LanguageModelV3FinishReason.toolCalls,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}
