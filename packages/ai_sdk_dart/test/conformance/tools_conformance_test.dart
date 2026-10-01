import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('tools conformance', () {
    // ── Basic tool execution ───────────────────────────────────────────────

    group('tool execution', () {
      test('tool.execute receives parsed input and returns result', () async {
        Object? receivedInput;
        final model = FakeToolModel(
          toolName: 'greet',
          toolInput: {'name': 'Alice'},
        );

        final result = await generateText(
          model: model,
          prompt: 'greet someone',
          tools: {
            'greet': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                  },
                },
                fromJson: (json) {
                  receivedInput = json;
                  return json;
                },
              ),
              execute: (input, _) async => 'Hello, ${input['name']}!',
            ),
          },
        );

        expect(receivedInput, {'name': 'Alice'});
        // Tool results are in steps[0].toolResults, not result.toolResults
        // (result.toolResults filters lastContent which contains calls, not results)
        expect(result.steps[0].toolResults.length, 1);
        expect(result.steps[0].toolResults[0].isError, isFalse);
      });

      test('tool result text contains executor return value', () async {
        final model = FakeToolModel(
          toolName: 'calc',
          toolInput: {'a': 1, 'b': 2},
        );

        final result = await generateText(
          model: model,
          prompt: 'add numbers',
          tools: {
            'calc': tool<Map<String, dynamic>, int>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (input, _) async => 3,
            ),
          },
        );

        expect(result.steps[0].toolResults.length, 1);
        final output = result.steps[0].toolResults[0].output;
        expect(output, isA<ToolResultOutputText>());
        expect((output as ToolResultOutputText).text, '3');
      });

      test('ToolExecutionOptions includes toolCallId and messages', () async {
        ToolExecutionOptions? capturedOptions;
        final model = FakeToolModel(toolName: 'capture', toolInput: {'x': 1});

        await generateText(
          model: model,
          prompt: 'hi',
          tools: {
            'capture': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (input, options) async {
                capturedOptions = options;
                return 'ok';
              },
            ),
          },
        );

        expect(capturedOptions, isNotNull);
        expect(capturedOptions!.toolCallId, isNotEmpty);
        expect(capturedOptions!.messages, isNotNull);
      });
    });

    // ── Dynamic tool ───────────────────────────────────────────────────────

    group('dynamicTool', () {
      test('dynamicTool accepts any input without schema parsing', () async {
        Object? receivedInput;
        final model = FakeToolModel(
          toolName: 'dynamic',
          toolInput: {'raw': 'data'},
        );

        await generateText(
          model: model,
          prompt: 'run dynamic tool',
          tools: {
            'dynamic': dynamicTool<String>(
              execute: (input, _) async {
                receivedInput = input;
                return 'done';
              },
            ),
          },
        );

        expect(receivedInput, {'raw': 'data'});
      });
    });

    // ── toolChoice ─────────────────────────────────────────────────────────

    group('toolChoice', () {
      test('ToolChoiceAuto: tools are exposed but not forced', () async {
        final capturingModel = FakeCapturingModel(responseText: 'plain text');
        await generateText(
          model: capturingModel,
          prompt: 'hi',
          toolChoice: const ToolChoiceAuto(),
          tools: {
            'myTool': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          },
        );

        final opts = capturingModel.capturedOptions.first;
        expect(opts.toolChoice, isA<ToolChoiceAuto>());
        expect(opts.tools.length, 1);
      });

      test('ToolChoiceNone: empty tool list sent to model', () async {
        final capturingModel = FakeCapturingModel(responseText: 'no tools');
        await generateText(
          model: capturingModel,
          prompt: 'hi',
          toolChoice: const ToolChoiceNone(),
          tools: {
            'unused': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          },
        );

        final opts = capturingModel.capturedOptions.first;
        expect(opts.tools, isEmpty);
      });

      test('ToolChoiceRequired: model must call at least one tool', () async {
        final model = FakeToolModel(toolName: 'required_tool', toolInput: {});

        final result = await generateText(
          model: model,
          prompt: 'hi',
          toolChoice: const ToolChoiceRequired(),
          tools: {
            'required_tool': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'executed',
            ),
          },
        );

        expect(result.toolCalls.length, 1);
      });

      test('ToolChoiceRequired throws when no tools provided', () {
        final model = FakeCapturingModel();
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            toolChoice: const ToolChoiceRequired(),
          ),
          throwsA(isA<AiNoSuchToolError>()),
        );
      });

      test('ToolChoiceSpecific exposes only the named tool', () async {
        final capturingModel = FakeToolModel(toolName: 'toolA', toolInput: {});
        await generateText(
          model: capturingModel,
          prompt: 'hi',
          toolChoice: const ToolChoiceSpecific(toolName: 'toolA'),
          tools: {
            'toolA': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'a',
            ),
            'toolB': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'b',
            ),
          },
        );

        // The model received only toolA
        expect(
          capturingModel.lastCallOptions!.tools.map((t) => t.name).toList(),
          ['toolA'],
        );
      });

      test('ToolChoiceSpecific for unknown tool throws AiNoSuchToolError', () {
        final model = FakeCapturingModel();
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            toolChoice: const ToolChoiceSpecific(toolName: 'missing'),
            tools: {
              'existing': tool<Map<String, dynamic>, String>(
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

    // ── AiNoSuchToolError ─────────────────────────────────────────────────

    group('AiNoSuchToolError', () {
      test('thrown when model calls tool not in ToolSet', () async {
        final model = FakeToolModel(toolName: 'unknownTool', toolInput: {});

        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            tools: {
              'existingTool': tool<Map<String, dynamic>, String>(
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

    // ── Tool input examples ────────────────────────────────────────────────

    group('tool inputExamples', () {
      test(
        'inputExamples are forwarded to the provider in tool definition',
        () async {
          final capturingModel = FakeCapturingModel();
          await generateText(
            model: capturingModel,
            prompt: 'hi',
            tools: {
              'search': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                inputExamples: const [
                  ToolInputExample(input: {'query': 'Dart SDK'}),
                ],
              ),
            },
          );

          final providerTool =
              capturingModel.capturedOptions.first.functionTools.first;
          expect(providerTool.inputExamples, isNotNull);
          expect(providerTool.inputExamples!.length, 1);
        },
      );

      test('tool description is forwarded to provider', () async {
        final capturingModel = FakeCapturingModel();
        await generateText(
          model: capturingModel,
          prompt: 'hi',
          tools: {
            'search': tool<Map<String, dynamic>, String>(
              description: 'Search the web for information',
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          },
        );

        final providerTool = capturingModel.capturedOptions.first.tools.first;
        expect(providerTool.description, 'Search the web for information');
      });
    });

    // ── Multi-step tool loop ───────────────────────────────────────────────

    group('multi-step tool loop', () {
      test('tool results feed into next step automatically', () async {
        final model = FakeMultiStepModel([
          LanguageModelV4GenerateResult(
            content: [
              const LanguageModelV4ToolCallPart(
                toolCallId: 'c1',
                toolName: 'add',
                input: {'a': 1, 'b': 2},
              ),
            ],
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
          const LanguageModelV4GenerateResult(
            content: [LanguageModelV4TextPart(text: 'Result is 3')],
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]);

        final result = await generateText(
          model: model,
          prompt: 'What is 1+2?',
          maxSteps: 3,
          tools: {
            'add': tool<Map<String, dynamic>, int>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (input, _) async =>
                  ((input['a'] as num) + (input['b'] as num)).toInt(),
            ),
          },
        );

        expect(result.steps.length, 2);
        expect(result.text, 'Result is 3');
      });

      test('stops at maxSteps even if more tool calls would occur', () async {
        // Model always returns a tool call
        var callCount = 0;
        final model = _CountingToolModel(() {
          callCount++;
          return LanguageModelV4GenerateResult(
            content: [
              LanguageModelV4ToolCallPart(
                toolCallId: 'c$callCount',
                toolName: 'loop',
                input: {'n': callCount},
              ),
            ],
            finishReason: LanguageModelV4FinishReason.toolCalls,
          );
        });

        final result = await generateText(
          model: model,
          prompt: 'hi',
          maxSteps: 3,
          tools: {
            'loop': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'continuing',
            ),
          },
        );

        expect(result.steps.length, lessThanOrEqualTo(3));
      });

      test('tool that returns stream: last emitted value is used', () async {
        final model = FakeToolModel(toolName: 'stream_tool', toolInput: {});

        final result = await generateText(
          model: model,
          prompt: 'hi',
          tools: {
            'stream_tool': tool<Map<String, dynamic>, Object?>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async {
                return Stream.fromIterable(['first', 'second', 'final-value']);
              },
            ),
          },
        );

        final output =
            result.steps[0].toolResults[0].output as ToolResultOutputText;
        expect(output.text, 'final-value');
      });
    });

    // ── Tool approval ─────────────────────────────────────────────────────

    group('tool approval', () {
      test(
        'needsApproval tool returns approvalRequest without executing',
        () async {
          final model = FakeToolModel(
            toolName: 'dangerous',
            toolInput: {'action': 'delete'},
          );

          final result = await generateText(
            model: model,
            prompt: 'do something',
            tools: {
              'dangerous': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                needsApproval: (input, _) async => true,
                execute: (_, _) async => 'executed',
              ),
            },
          );

          expect(result.toolApprovalRequests.length, 1);
          expect(result.toolResults, isEmpty);
        },
      );
    });
  });

  // ---------------------------------------------------------------------------
  // jsonSchema() helper
  // ---------------------------------------------------------------------------

  group('jsonSchema()', () {
    test('jsonSchema field matches the provided map', () {
      final map = {
        'type': 'string',
        'enum': ['a', 'b'],
      };
      final schema = jsonSchema(map);
      expect(schema.jsonSchema, map);
    });

    test('fromJson returns the map unmodified', () {
      final schema = jsonSchema({'type': 'object'});
      final input = {'key': 'value', 'num': 1};
      expect(schema.fromJson(input), same(input));
    });

    test('can be used as tool inputSchema', () async {
      final myTool = tool<Map<String, dynamic>, String>(
        inputSchema: jsonSchema({'type': 'object', 'properties': {}}),
        description: 'Test tool',
        execute: (input, _) async => 'result',
      );
      expect(myTool.inputSchema.jsonSchema['type'], 'object');
    });

    test(
      'schema validators reject invalid decoded input with stable issues',
      () {
        final schema = Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          validator: _RequiredFieldValidator(),
          fromJson: (json) => json,
        );

        expect(
          () => schema.fromJson(const {}),
          throwsA(
            isA<SchemaValidationException>().having(
              (error) => error.issues.single.path,
              'path',
              '/name',
            ),
          ),
        );
        expect(
          SchemaValidationException(const [
            SchemaValidationIssue(
              path: '',
              message: 'invalid',
              schemaPath: '#/type',
            ),
          ]).toString(),
          'Schema validation failed (1 issues).',
        );
      },
    );

    test(
      'tool helper defaults and provider message conversion are explicit',
      () {
        final noExecutor = tool<Map<String, dynamic>, String>(
          inputSchema: jsonSchema({'type': 'object'}),
        );
        expect(noExecutor.executeDynamic, isNull);
        expect(noExecutor.approvalPolicy, ToolApprovalPolicy.never);

        final approvalTool = tool<Map<String, dynamic>, String>(
          inputSchema: jsonSchema({'type': 'object'}),
          needsApproval: (_, _) => false,
        );
        expect(approvalTool.approvalPolicy, ToolApprovalPolicy.conditional);

        final providerMessage = LanguageModelV4Message(
          role: LanguageModelV4Role.tool,
          content: const [LanguageModelV4TextPart(text: 'done')],
        );
        final message = ModelMessage.fromProvider(providerMessage);
        expect(message.role, ModelMessageRole.tool);
        expect(message.parts, hasLength(1));
        expect((message.parts!.single as LanguageModelV4TextPart).text, 'done');
      },
    );
  });
}

class _RequiredFieldValidator implements SchemaValidator {
  @override
  List<SchemaValidationIssue> validate(Map<String, dynamic> value) {
    if (value.containsKey('name')) return const [];
    return const [
      SchemaValidationIssue(
        path: '/name',
        message: 'name is required',
        schemaPath: '#/required',
      ),
    ];
  }
}

// Helper model that calls a factory function for each doGenerate
class _CountingToolModel extends LanguageModelV4 {
  _CountingToolModel(this._factory);

  final LanguageModelV4GenerateResult Function() _factory;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'counting-tool-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return _factory();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}
