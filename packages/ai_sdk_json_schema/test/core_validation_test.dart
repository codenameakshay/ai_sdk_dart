import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  final schema = validatedJsonSchema<Map<String, dynamic>>(
    schema: {
      'type': 'object',
      'required': ['city'],
      'properties': {
        'city': {'type': 'string'},
      },
    },
    fromJson: (json) => json,
  );
  test('invalid tool inputs never execute application code', () async {
    var executed = false;
    final result = await generateText(
      model: MockLanguageModelV4(
        response: const [
          LanguageModelV4ToolCallPart(
            toolCallId: 'call',
            toolName: 'weather',
            input: {'unexpected': 1},
          ),
        ],
      ),
      prompt: 'weather',
      tools: {
        'weather': tool<Map<String, dynamic>, String>(
          inputSchema: schema,
          execute: (_, _) async {
            executed = true;
            return 'wrong';
          },
        ),
      },
    );
    expect(executed, isFalse);
    expect(result.steps.single.toolResults.single.isError, isTrue);
  });
  test(
    'invalid final structured output preserves the validation cause',
    () async {
      await expectLater(
        generateObject(
          model: MockLanguageModelV4(
            response: const [LanguageModelV4TextPart(text: '{"city":7}')],
          ),
          schema: schema,
          prompt: 'weather',
        ),
        throwsA(
          isA<AiNoObjectGeneratedError>().having(
            (error) => error.cause,
            'cause',
            isA<SchemaValidationException>(),
          ),
        ),
      );
    },
  );
}
