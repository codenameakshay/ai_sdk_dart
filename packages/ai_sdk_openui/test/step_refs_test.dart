import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/spec/schema.dart'
    show Steps, signature, typeAnnotation;
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  String get description => '';
}

void main() {
  final link = _Spec('Link', {
    'action': S.union([
      Steps.openUrl,
      S.actionRef('Copy', {'text': S.string()}),
    ]).optional(),
  });
  final col = _Spec('Col', {'children': S.list(S.ref('Link'))});
  final library = OpenUiLibrary(
    root: col,
    components: [col, link],
    actions: [
      ActionSpec(
        'Copy',
        description: 'Copy text',
        params: {'text': S.string()},
      ),
    ],
  );

  test('step refs print as @Name in signatures', () {
    expect(
      signature('Link', {
        'action': S.union([
          Steps.openUrl,
          S.actionRef('Copy', {'text': S.string()}),
        ]).optional(),
      }),
      'Link(action?: @OpenUrl | @Copy)',
    );
    expect(typeAnnotation(Steps.toAssistant), '@ToAssistant');
  });

  test('step refs emit their legacy shape into the defs', () {
    final defs = library.toJsonSchema()[r'$defs'] as Map<String, Object?>;

    expect(defs['OpenUrl'], {
      'type': 'object',
      'properties': {
        'type': {'type': 'string', 'const': 'open_url'},
        'url': {'type': 'string'},
      },
      'required': ['type', 'url'],
      'additionalProperties': false,
    });
    expect(defs['Copy'], {
      'type': 'object',
      'properties': {
        'type': {'type': 'string', 'const': 'Copy'},
        'params': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
          'additionalProperties': false,
        },
      },
      'required': ['type', 'params'],
      'additionalProperties': false,
    });
    expect((defs['Link'] as Map)['properties']['action'], {
      'anyOf': [
        {r'$ref': r'#/$defs/OpenUrl'},
        {r'$ref': r'#/$defs/Copy'},
      ],
    });
  });

  test('a program using both step kinds in an action slot parses clean', () {
    expect(
      library
          .parse(
            'root = Col([Link(@OpenUrl("https://a.b")), Link(@Copy("hi"))])',
          )
          .isClean,
      isTrue,
    );
  });

  test('the system prompt lists the restricted steps for an action slot', () {
    final prompt = library.systemPrompt();

    expect(prompt, contains('Link(action?: @OpenUrl | @Copy)'));
    expect(
      prompt,
      contains(
        'Props typed like `@OpenUrl | @ToAssistant` accept only the steps listed.',
      ),
    );
  });

  test('an optional step ref prints with a question mark', () {
    expect(
      signature('Link', {'action': Steps.openUrl.optional()}),
      'Link(action?: @OpenUrl)',
    );
  });

  test('a reactive step ref keeps its other flags and prints as a binding', () {
    expect(
      signature('Link', {'action': Steps.openUrl.optional().reactive()}),
      r'Link(action?: $binding<@OpenUrl>)',
    );
  });
}
