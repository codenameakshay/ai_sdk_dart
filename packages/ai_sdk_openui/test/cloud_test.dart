import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
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
}
