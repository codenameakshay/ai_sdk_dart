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
}
