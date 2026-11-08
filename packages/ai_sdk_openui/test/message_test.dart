import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

void main() {
  group('OpenUiMessage.parse', () {
    test('text with no marker is all content', () {
      final m = OpenUiMessage.parse('root = A()\nx = 1');
      expect(m.content, 'root = A()\nx = 1');
      expect(m.context, isNull);
      expect(m.attributes, isEmpty);
      expect(m.end, isFalse);
    });

    test('reads attributes, content and JSON context', () {
      final m = OpenUiMessage.parse(
        ']]>openui:content?v=2&library+Version=0.5%21&flag\n'
        'root = A()\n'
        ']]>openui:context\n'
        '[{"n":1}]',
      );
      expect(m.content, 'root = A()');
      expect(m.attributes, {'v': '2', 'library Version': '0.5!', 'flag': ''});
      expect(m.context, [
        {'n': 1},
      ]);
    });

    test('keeps context that is not JSON as text', () {
      final m = OpenUiMessage.parse(
        ']]>openui:content\nhi\n]]>openui:context\nnot json',
      );
      expect(m.context, 'not json');
    });

    test('strips carriage returns at section ends', () {
      final m = OpenUiMessage.parse(
        ']]>openui:content\r\nhi\r\n]]>openui:context\r\n[1]',
      );
      expect(m.content, 'hi');
      expect(m.context, [1]);
    });

    test('a retry marker glued to text starts a new content section', () {
      final m = OpenUiMessage.parse('root = A(]]>openui:content\nroot = B()');
      expect(m.content, 'root = B()');
    });

    test('the last content section wins and context before it is ignored', () {
      final m = OpenUiMessage.parse(
        ']]>openui:content\na\n]]>openui:context\n[1]\n'
        ']]>openui:content\nb',
      );
      expect(m.content, 'b');
      expect(m.context, isNull);
    });

    test('an end marker closes the content', () {
      final m = OpenUiMessage.parse(
        ']]>openui:content\nroot = A()\n]]>openui:end\n',
      );
      expect(m.content, 'root = A()');
      expect(m.end, isTrue);
    });

    test('streaming holds back a partial marker line', () {
      const raw = 'root = A()\n]]>open';
      expect(OpenUiMessage.parse(raw, streaming: true).content, 'root = A()');
      expect(OpenUiMessage.parse(raw).content, raw);
    });

    test('streaming cuts a partial retry marker glued to text', () {
      final m = OpenUiMessage.parse('root = A()]]>openui:con', streaming: true);
      expect(m.content, 'root = A()');
    });
  });

  group('OpenUiMessage.build', () {
    test('writes markers, encoded attributes and JSON context', () {
      const m = OpenUiMessage(
        content: 'root = A()',
        context: [
          {'n': 1.0},
        ],
        attributes: {'v': '2', 'library Version': "0.5!'()~*"},
      );
      expect(
        m.build(),
        ']]>openui:content?v=2&library+Version=0.5%21%27%28%29%7E*\n'
        'root = A()\n'
        ']]>openui:context\n'
        '[{"n":1}]',
      );
      final back = OpenUiMessage.parse(m.build());
      expect(back.content, 'root = A()');
      expect(back.attributes, m.attributes);
    });

    test('adds the end marker and passes string context through', () {
      expect(
        const OpenUiMessage(content: 'x', context: 'raw', end: true).build(),
        ']]>openui:content\nx\n]]>openui:context\nraw\n]]>openui:end',
      );
    });
  });

  group('OpenUiMessage.fromAction', () {
    const formState = {
      'prefs': {
        'pace': {'value': 'Packed', 'componentType': 'RadioGroup'},
      },
    };

    test('sends the message with the click and form state', () {
      const event = ActionEvent(
        type: ActionEvent.continueConversation,
        params: {},
        humanFriendlyMessage: 'Tailor my Lisbon trip',
        formState: formState,
        formName: 'prefs',
      );
      expect(
        OpenUiMessage.fromAction(event),
        ']]>openui:content\n'
        'Tailor my Lisbon trip\n'
        ']]>openui:context\n'
        '["User clicked: Tailor my Lisbon trip",'
        '{"prefs":{"pace":{"value":"Packed","componentType":"RadioGroup"}}}]',
      );
    });

    test('appends the action context after the form state', () {
      const event = ActionEvent(
        type: ActionEvent.continueConversation,
        params: {
          'context': {'orderId': 42},
        },
        humanFriendlyMessage: 'Show details',
        formState: {},
      );
      expect(
        OpenUiMessage.fromAction(event),
        ']]>openui:content\nShow details\n]]>openui:context\n'
        '["User clicked: Show details",{},{"orderId":42}]',
      );
    });

    test('drops the content line when there is no message', () {
      const event = ActionEvent(
        type: ActionEvent.continueConversation,
        params: {},
        formState: {},
      );
      expect(
        OpenUiMessage.fromAction(event),
        '\n]]>openui:context\n["User clicked: ",{}]',
      );
    });
  });
}
