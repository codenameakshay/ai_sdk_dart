import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/spec/extend.dart';
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

String _sig(OpenUiLibrary lib, String name) =>
    (lib.toSpec()['components'] as Map)[name]['signature'] as String;

void main() {
  final text = _C('Text', {'text': S.string()});
  final image = _C('Image', {'src': S.string()});
  final card = _C('Card', {
    'children': S.list(S.union([S.ref('Text'), S.ref('Image')])),
    'footer': S.ref('Text').optional(),
  });
  final stack = _C('Stack', {
    'items': S.list(S.union([S.ref('Card'), S.ref('Text')])),
  });
  final video = _C('Video', {'url': S.string()});
  final base = OpenUiLibrary(
    root: stack,
    components: [stack, card, text, image],
    groups: [
      ComponentGroup('Content', [text, image]),
    ],
  );

  test('a component added to a named slot joins that union only', () {
    final ext = base.extend(
      LibraryExtension(
        addComponents: [
          ComponentAddition(video, slots: ['Card.children']),
        ],
      ),
    );

    expect(ext.components.keys.toList(), [
      'Stack',
      'Card',
      'Text',
      'Image',
      'Video',
    ]);
    expect(
      _sig(ext, 'Card'),
      'Card(children: (Text | Image | Video)[], footer?: Text)',
    );
    expect(
      _sig(base, 'Card'),
      'Card(children: (Text | Image)[], footer?: Text)',
    );
    expect(ext.parse('root = Stack([Card([Video("u")])])').isClean, isTrue);
  });

  test('a parent name alone places the component in its only content slot', () {
    final ext = base.extend(
      LibraryExtension(
        addComponents: [
          ComponentAddition(video, slots: ['Card']),
        ],
      ),
    );

    expect(
      _sig(ext, 'Card'),
      'Card(children: (Text | Image | Video)[], footer?: Text)',
    );
  });

  test('a parent name alone places the component in the stack items', () {
    final ext = base.extend(
      LibraryExtension(
        addComponents: [
          ComponentAddition(video, slots: ['Stack']),
        ],
      ),
    );

    expect(_sig(ext, 'Stack'), 'Stack(items: (Card | Text | Video)[])');
  });

  test('a component added without slots changes no parent', () {
    final ext = base.extend(
      LibraryExtension(addComponents: [ComponentAddition(video)]),
    );

    expect(
      _sig(ext, 'Card'),
      'Card(children: (Text | Image)[], footer?: Text)',
    );
    expect(ext.components.keys, contains('Video'));
  });

  test('removing a component drops it from unions and groups', () {
    final ext = base.extend(
      const LibraryExtension(removeComponents: ['Image']),
    );

    expect(_sig(ext, 'Card'), 'Card(children: (Text)[], footer?: Text)');
    expect(ext.components.keys, isNot(contains('Image')));
    expect(ext.groups.single.components.map((c) => c.typeName), ['Text']);
  });

  test('removing the only type a prop allows throws', () {
    expect(
      () => base.extend(const LibraryExtension(removeComponents: ['Text'])),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Cannot remove "Text": it is the only type allowed in Card.footer.',
        ),
      ),
    );
  });

  test('removing the root or an unknown component throws', () {
    expect(
      () => base.extend(const LibraryExtension(removeComponents: ['Stack'])),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Cannot remove "Stack": it is the library root.',
        ),
      ),
    );
    expect(
      () => base.extend(const LibraryExtension(removeComponents: ['Nope'])),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Cannot remove "Nope": not in the library.',
        ),
      ),
    );
  });

  test('adding an existing name or an empty slot list throws', () {
    expect(
      () => base.extend(
        LibraryExtension(addComponents: [ComponentAddition(text)]),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Component "Text" already exists. Use override.',
        ),
      ),
    );
    expect(
      () => base.extend(
        LibraryExtension(
          addComponents: [ComponentAddition(video, slots: const [])],
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] "slots" for "Video" is empty. Omit it to only list it.',
        ),
      ),
    );
  });

  test('an override replaces the component and keeps the base untouched', () {
    final text2 = _C('Text', {
      'text': S.string(),
      'tone': S.oneOf(['a', 'b']).optional(),
    });
    final ext = base.extend(LibraryExtension(overrideComponents: [text2]));

    expect(identical(ext.components['Text'], text2), isTrue);
    expect(_sig(ext, 'Text'), 'Text(text: string, tone?: "a" | "b")');
    expect(_sig(base, 'Text'), 'Text(text: string)');
  });

  test('a bad override throws', () {
    expect(
      () => base.extend(LibraryExtension(overrideComponents: [_C('Nope', {})])),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Cannot override "Nope": not in the library. Use add.',
        ),
      ),
    );
    expect(
      () => base.extend(LibraryExtension(overrideComponents: [text, text])),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Component "Text" is overridden twice.',
        ),
      ),
    );
    expect(
      () => base.extend(
        LibraryExtension(
          overrideComponents: [text],
          removeComponents: ['Text'],
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Cannot remove "Text": it is added or overridden in the same call.',
        ),
      ),
    );
  });

  test('a bad slot for an added component throws with the candidates', () {
    ArgumentError errorFor(String slot) {
      try {
        base.extend(
          LibraryExtension(
            addComponents: [
              ComponentAddition(video, slots: [slot]),
            ],
          ),
        );
      } on ArgumentError catch (e) {
        return e;
      }
      fail('expected an ArgumentError for slot "$slot"');
    }

    expect(
      errorFor('Card.footer').message,
      '[extend] Slot "Card.footer" for "Video" must be one content slot. Candidates: Card.children.',
    );
    expect(
      errorFor('Text').message,
      '[extend] Slot "Text" for "Video": "Text" has no content slot (a prop that is a union of components, or an optional or array of one).',
    );
    expect(
      errorFor('Nope.items').message,
      '[extend] Slot "Nope.items" for "Video": "Nope" is not in the library.',
    );
  });

  test('added functions are listed and serialised', () {
    final ext = base.extend(
      LibraryExtension(
        addFunctions: [
          FunctionSpec(
            'Double',
            description: 'x2',
            params: {'n': S.number()},
            fn: (a) => (a['n'] as num) * 2,
          ),
        ],
      ),
    );

    expect(ext.functions.map((f) => f.name).toList(), ['Double']);
    expect(ext.toJsonSchema()['functions'], containsPair('Double', isA<Map>()));
  });

  test('removing a type rebinds nested unions, objects and records', () {
    final panel = _C('Panel', {
      'parts': S.union([
        S.list(S.union([S.ref('Text'), S.ref('Image')])),
        S.string(),
      ]),
      'meta': S.object({
        'pick': S.union([S.ref('Text'), S.ref('Image')]),
      }),
      'extras': S.record(S.string(), S.union([S.ref('Text'), S.ref('Image')])),
      'label': S.string(),
    });
    final lib = OpenUiLibrary(root: panel, components: [panel, text, image]);

    final ext = lib.extend(const LibraryExtension(removeComponents: ['Image']));

    expect(
      _sig(ext, 'Panel'),
      'Panel(parts: (Text)[] | string, meta: {pick: Text}, extras: Record<string, Text>, label: string)',
    );
  });

  test('removing every type of a union prop throws', () {
    final panel = _C('Panel', {
      'pair': S.union([S.ref('Text'), S.ref('Image')]),
    });
    final lib = OpenUiLibrary(root: panel, components: [panel, text, image]);

    expect(
      () => lib.extend(
        const LibraryExtension(removeComponents: ['Text', 'Image']),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '[extend] Cannot remove "Text": it is the only type allowed in Panel.pair.',
        ),
      ),
    );
  });
}
