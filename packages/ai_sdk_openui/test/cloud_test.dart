import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/spec/cloud.dart' show validateChatLibrary;
import 'package:test/test.dart';

final class _C implements ComponentSpec {
  const _C(this.typeName, this.props);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  String get description => '';
}

final _text = _C('Text', {'text': S.string()});
final _col = _C('Col', {'children': S.list(S.ref('Text'))});
final _lib = OpenUiLibrary(root: _col, components: [_col, _text]);

Map<String, Object?> _decodeConfig(String prompt) {
  expect(prompt, startsWith(']]>openui:config\n'));
  return jsonDecode(prompt.substring(17)) as Map<String, Object?>;
}

void main() {
  group('cloudSystemPrompt', () {
    test('without a library pins the built-in chat library version', () {
      expect(
        cloudSystemPrompt(),
        ']]>openui:config\n{"libraryVersion":"0.1.0"}',
      );
    });

    test('instructions follow the config block on a new line', () {
      expect(
        cloudSystemPrompt(instructions: 'Be brief'),
        ']]>openui:config\n{"libraryVersion":"0.1.0"}\nBe brief',
      );
    });

    test('prompt options without a library throw', () {
      expect(
        () => cloudSystemPrompt(
          promptOptions: const CloudPromptOptions(preamble: 'x'),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '[generateSystemPrompt] promptOptions requires a library — the built-in library ignores it.',
          ),
        ),
      );
    });

    test('an empty preamble without a library is ignored', () {
      expect(
        cloudSystemPrompt(
          promptOptions: const CloudPromptOptions(preamble: ''),
        ),
        ']]>openui:config\n{"libraryVersion":"0.1.0"}',
      );
    });

    test('a library is sent as chatLibrary without its components', () {
      final config = _decodeConfig(cloudSystemPrompt(library: _lib));

      expect(config, {
        'chatLibrary': {'root': 'Col', 'schema': _lib.toJsonSchema()},
      });
    });

    test('empty examples are kept alongside the preamble', () {
      final config = _decodeConfig(
        cloudSystemPrompt(
          library: _lib,
          promptOptions: const CloudPromptOptions(examples: [], preamble: 'P'),
        ),
      );

      expect(config['systemPromptOptions'], {'examples': [], 'preamble': 'P'});
    });

    test('additional rules are sent in systemPromptOptions', () {
      final config = _decodeConfig(
        cloudSystemPrompt(
          library: _lib,
          promptOptions: const CloudPromptOptions(
            additionalRules: ['Keep it short'],
          ),
        ),
      );

      expect(config['systemPromptOptions'], {
        'additionalRules': ['Keep it short'],
      });
    });

    test('a group naming a component outside the library throws', () {
      final lib = OpenUiLibrary(
        root: _col,
        components: [_col, _text],
        groups: [
          ComponentGroup('G', [_C('Ghost', {})]),
        ],
      );

      expect(
        () => cloudSystemPrompt(library: lib),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '[generateSystemPrompt] Invalid library: Component group "G" references unknown component "Ghost".',
          ),
        ),
      );
    });

    test('the library id is sent and the components are not', () {
      final lib = OpenUiLibrary(root: _col, components: [_col, _text], id: 'x');

      final chatLibrary =
          _decodeConfig(cloudSystemPrompt(library: lib))['chatLibrary']
              as Map<String, Object?>;

      expect(chatLibrary['id'], 'x');
      expect(chatLibrary.containsKey('components'), isFalse);
    });
  });

  group('artifactTool', () {
    test('enables every artifact kind when none are given', () {
      expect(artifactTool(), {
        'type': 'artifact',
        'artifacts': [
          {'artifact_type': 'slides', 'library_version': '0.1.0'},
          {'artifact_type': 'report', 'library_version': '0.1.0'},
        ],
      });
    });

    test('a single report artifact uses its pinned version', () {
      expect(
        artifactTool(artifacts: [const ArtifactOption(ArtifactKind.report)]),
        {
          'type': 'artifact',
          'artifacts': [
            {'artifact_type': 'report', 'library_version': '0.1.0'},
          ],
        },
      );
    });

    test('instructions are sent and a library version can be overridden', () {
      expect(
        artifactTool(
          artifacts: [
            const ArtifactOption(
              ArtifactKind.slides,
              instruction: 'Use the corporate template.',
            ),
            const ArtifactOption(ArtifactKind.report),
          ],
        ),
        {
          'type': 'artifact',
          'artifacts': [
            {
              'artifact_type': 'slides',
              'instruction': 'Use the corporate template.',
              'library_version': '0.1.0',
            },
            {'artifact_type': 'report', 'library_version': '0.1.0'},
          ],
        },
      );
      expect(
        artifactTool(
          artifacts: [
            const ArtifactOption(
              ArtifactKind.report,
              libraryVersion: '0.2.0',
              instruction: '',
            ),
          ],
        ),
        {
          'type': 'artifact',
          'artifacts': [
            {'artifact_type': 'report', 'library_version': '0.2.0'},
          ],
        },
      );
    });

    test('an empty artifact list throws', () {
      expect(
        () => artifactTool(artifacts: []),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'artifactTool: `artifacts` must not be empty — omit it to enable all artifact types.',
          ),
        ),
      );
    });

    test('a repeated artifact kind throws', () {
      expect(
        () => artifactTool(
          artifacts: [
            const ArtifactOption(ArtifactKind.slides),
            const ArtifactOption(ArtifactKind.slides),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            "artifactTool: duplicate artifact 'slides'.",
          ),
        ),
      );
    });
  });

  // Messages are what lang-core 1.0.0's generateSystemPrompt({cloud: true, library}) throws in Node 26.
  group('validateChatLibrary', () {
    String messages(Object? spec) =>
        [for (final i in validateChatLibrary(spec)) i.message].join(' ');

    test('reports a missing root, an unknown required property and a bad ref', () {
      expect(
        messages({
          'root': 'Missing',
          'components': <String, Object?>{},
          'schema': {
            r'$defs': {
              'Card': {
                'properties': {
                  'body': {r'$ref': r'#/$defs/Nope'},
                },
                'required': ['ghost'],
              },
            },
          },
        }),
        r'Root component "Missing" was not found in schema.$defs. Available components: Card. '
        r'$defs/Card lists required property "ghost" that is not in properties. '
        r'Unresolvable $ref "#/$defs/Nope" at $defs/Card/properties/body — refs must be "#/$defs/<name>" pointing at a component in $defs.',
      );
    });

    test('reports every malformed part in one pass', () {
      expect(
        messages({
          'root': '',
          'components': <String, Object?>{},
          'schema': {
            r'$defs': {
              'A': 5,
              'B': {'properties': <Object?>[], 'required': 'x'},
              'C': {
                'properties': {
                  'p': {
                    'items': [
                      {r'$ref': 'bad'},
                    ],
                  },
                },
                'required': ['p', 2],
              },
            },
          },
          'componentGroups': [
            {
              'name': 'g',
              'components': ['A', 'Z', 3],
            },
            {'name': 1},
          ],
        }),
        r'chatLibrary.root, when present, must be a non-empty string. '
        r'$defs/A must be an object component schema. '
        r'$defs/B/properties must be an object. '
        r'$defs/B/required must be an array of property names. '
        r'$defs/C/required must be an array of property names. '
        r'Unresolvable $ref "bad" at $defs/C/properties/p/items/0 — refs must be "#/$defs/<name>" pointing at a component in $defs. '
        r'Component group "g" references unknown component "Z". '
        r'Component group "g" references unknown component "3". '
        r'Each componentGroups entry must be {name: string, components: string[], notes?: string[]}.',
      );
    });

    test('stops at a schema that is not an object or has no defs', () {
      expect(
        messages({'root': 'A', 'schema': 5}),
        r'chatLibrary.schema must be an object with a $defs map of component schemas.',
      );
      expect(
        messages({
          'root': 'A',
          'schema': {r'$defs': <String, Object?>{}},
        }),
        r'chatLibrary.schema.$defs must be a non-empty object keyed by component name.',
      );
      expect(messages(5), 'chatLibrary must be an object.');
    });

    test('accepts a library spec', () {
      expect(validateChatLibrary(_lib.toSpec()), isEmpty);
    });
  });
}
