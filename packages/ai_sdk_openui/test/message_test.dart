import 'package:ai_sdk_openui/ai_sdk_openui.dart'
    show ActionEvent, buildActionUserMessage;
import 'package:ai_sdk_openui/src/lang/message.dart';
import 'package:test/test.dart';

void main() {
  group('parseMessage', () {
    test('returns plain text as the content of a bare message', () {
      final message = parseMessage('root = Text("hi")');
      expect(message.content, 'root = Text("hi")');
      expect(message.context, isNull);
      expect(message.attributes, isEmpty);
      expect(message.end, isFalse);
    });

    test('reads attributes, context and end from marker lines', () {
      final message = parseMessage(
        ']]>openui:content?name=My+Deck&x=a%26b\nroot = A()\n'
        ']]>openui:context\n{"k":1}\n]]>openui:end\n',
      );
      expect(message.content, 'root = A()');
      expect(message.context, {'k': 1});
      expect(message.attributes, {'name': 'My Deck', 'x': 'a&b'});
      expect(message.end, isTrue);
    });

    test('keeps the attribute text when its escapes are malformed', () {
      final message = parseMessage(']]>openui:content?name=%E0%A4%A\nroot');
      expect(message.attributes, {'name': '%E0%A4%A'});
    });

    test('takes the last content section when a message is retried', () {
      expect(
        parseMessage(']]>openui:content\nold\n]]>openui:content\nnew').content,
        'new',
      );
      expect(parseMessage('old line]]>openui:content\nnew').content, 'new');
    });

    test('holds a partial marker while streaming', () {
      expect(
        parseMessage(
          ']]>openui:content\nroot = A()\n]]>openui:con',
          streaming: true,
        ).content,
        'root = A()',
      );
      expect(parseMessage('abc]]>op', streaming: true).content, 'abc');
      expect(
        parseMessage(']]>openui:content\nroot\n]]>o', streaming: true).content,
        'root',
      );
    });

    test('strips a carriage return from the end of each marker line', () {
      final message = parseMessage(
        ']]>openui:content\nroot\r\n]]>openui:context\nnot json',
      );
      expect(message.content, 'root');
      expect(message.context, 'not json');
    });

    test('keeps the lines after an end marker in the content', () {
      final message = parseMessage(']]>openui:content\na\n]]>openui:end\nb');
      expect(message.content, 'a\nb');
      expect(message.end, isTrue);
    });

    test('ignores a context section that comes before the content', () {
      final message = parseMessage(
        ']]>openui:context\n"x"\n]]>openui:content\nbody',
      );
      expect(message.content, 'body');
      expect(message.context, isNull);
    });
  });

  group('buildMessage', () {
    test('writes content with its marker line', () {
      expect(
        buildMessage(content: 'root = A()'),
        ']]>openui:content\nroot = A()',
      );
    });

    test('encodes attributes and writes JSON context and end', () {
      expect(
        buildMessage(
          content: 'c',
          context: {'a': 1},
          attributes: {'name': 'My Deck!', 'k y': "a&b(c)~'"},
          end: true,
        ),
        ']]>openui:content?name=My+Deck%21&k+y=a%26b%28c%29%7E%27\n'
        'c\n]]>openui:context\n{"a":1}\n]]>openui:end',
      );
    });

    test('writes text context as it is', () {
      expect(
        buildMessage(content: 'c', context: 'raw text'),
        ']]>openui:content\nc\n]]>openui:context\nraw text',
      );
    });

    test('round trips through parseMessage', () {
      final message = parseMessage(
        buildMessage(
          content: 'x = 1',
          context: [1, 2],
          attributes: {'n': 'a b'},
          end: true,
        ),
      );
      expect(message.content, 'x = 1');
      expect(message.context, [1, 2]);
      expect(message.attributes, {'n': 'a b'});
      expect(message.end, isTrue);
    });
  });

  group('buildActionUserMessage', () {
    Object? contextOf(
      Map<String, Object?> params, [
      Map<String, Object?> formState = const {},
    ]) => parseMessage(
      buildActionUserMessage(
        ActionEvent(
          type: ActionEvent.continueConversation,
          humanFriendlyMessage: 'Save',
          params: params,
          formState: formState,
        ),
      ),
    ).context;

    test('puts the @ToAssistant context third, after the form state', () {
      expect(contextOf({'context': 0}), ['User clicked: Save', {}, 0]);
      expect(contextOf({}, {r'$a': 1}), [
        'User clicked: Save',
        {r'$a': 1},
      ]);
    });

    test('writes the message as content and the click as context', () {
      expect(
        buildActionUserMessage(
          const ActionEvent(
            type: ActionEvent.continueConversation,
            humanFriendlyMessage: 'Save',
            formState: {r'$a': 1},
          ),
        ),
        ']]>openui:content\nSave\n]]>openui:context\n["User clicked: Save",{"\$a":1}]',
      );
    });

    test('an empty message is stored without its content line', () {
      expect(
        buildActionUserMessage(
          const ActionEvent(type: ActionEvent.continueConversation),
        ),
        '\n]]>openui:context\n["User clicked: ",{}]',
      );
    });
  });

  group('lang-core message.test.ts cases', () {
    test('round trips content, context, attributes, and end', () {
      const content =
          'root = Card([title])\ntitle = TextContent("a ]]>openui:end")';
      final raw = buildMessage(
        content: content,
        context: [
          {'note': 'rush'},
        ],
        attributes: {'library': '@acme/support@1.2.0', 'note': 'a b!'},
        end: true,
      );
      expect(
        raw.split('\n').first,
        ']]>openui:content?library=%40acme%2Fsupport%401.2.0&note=a+b%21',
      );
      final parsed = parseMessage(raw);
      expect(parsed.content, content);
      expect(parsed.context, [
        {'note': 'rush'},
      ]);
      expect(parsed.attributes, {
        'library': '@acme/support@1.2.0',
        'note': 'a b!',
      });
      expect(parsed.end, isTrue);
      expect(parseMessage('$raw\n').content, content);
    });

    test('keeps plain text byte for byte', () {
      const plain = 'Hi\r\n```openui-lang\nroot = A()\n```\n';
      final message = parseMessage(plain);
      expect(message.content, plain);
      expect(message.context, isNull);
      expect(message.end, isFalse);
    });

    test('uses the last content and keeps non-JSON context as text', () {
      final message = parseMessage(
        ']]>openui:content\nold\n]]>openui:context\n{}\n'
        ']]>openui:content?v=2\nnew\r\n]]>openui:context\n{"a":',
      );
      expect(message.content, 'new');
      expect(message.context, '{"a":');
      expect(message.attributes, {'v': '2'});
      expect(message.end, isFalse);
    });

    test('holds back a marker line cut mid-stream', () {
      const raw = ']]>openui:content\nroot = A()\n]]>open';
      expect(parseMessage(raw, streaming: true).content, 'root = A()');
      expect(parseMessage(raw).content, 'root = A()\n]]>open');
    });

    test(
      'reads a content line that starts mid-line after a cut-off attempt',
      () {
        const header = ']]>openui:content?v=2';
        final message = parseMessage(
          '$header\nroot = A("Broken$header\nroot = B()\n]]>openui:end',
        );
        expect(message.content, 'root = B()');
        expect(message.attributes, {'v': '2'});
        expect(message.end, isTrue);
      },
    );

    test('holds back a mid-line content line cut mid-stream', () {
      const raw =
          ']]>openui:content\nroot = A("Broken]]>openui:content?v=2\nroot = B()';
      final header = raw.indexOf(']]>', 3);
      for (final end in [header + 3, header + 14, raw.indexOf('\nroot = B')]) {
        expect(
          parseMessage(raw.substring(0, end), streaming: true).content,
          'root = A("Broken',
        );
      }
      final message = parseMessage(raw, streaming: true);
      expect(message.content, 'root = B()');
      expect(message.attributes, {'v': '2'});
    });

    test('ignores an end line before the winning content', () {
      const raw =
          ']]>openui:context\n{"\$x":1}\n]]>openui:end\n]]>openui:content\nroot = A()';
      final message = parseMessage(raw);
      expect(message.content, 'root = A()');
      expect(message.context, isNull);
      expect(message.end, isFalse);
    });
  });
}
