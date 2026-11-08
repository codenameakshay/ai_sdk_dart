import 'package:ai_sdk_openui/src/runtime/mcp.dart';
import 'package:test/test.dart';

void main() {
  test('extractToolResult parses JSON text content', () {
    expect(
      extractToolResult({
        'content': [
          {'type': 'text', 'text': '{"a":1}'},
        ],
      }),
      {'a': 1},
    );
  });

  test('extractToolResult joins split text parts before parsing JSON', () {
    expect(
      extractToolResult({
        'content': [
          {'type': 'text', 'text': '{"a":'},
          {'type': 'text', 'text': '1}'},
        ],
      }),
      {'a': 1},
    );
  });

  test(
    'extractToolResult returns plain text, null without text, and empty text',
    () {
      expect(
        extractToolResult({
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
        }),
        'hello',
      );
      expect(
        extractToolResult({
          'content': [
            {'type': 'image', 'data': 'x'},
          ],
        }),
        isNull,
      );
      expect(
        extractToolResult({
          'content': [
            {'type': 'text'},
          ],
        }),
        '',
      );
    },
  );

  test('extractToolResult prefers structuredContent over text', () {
    expect(
      extractToolResult({
        'content': [],
        'structuredContent': {'s': 1},
      }),
      {'s': 1},
    );
    expect(
      extractToolResult({
        'content': [
          {'type': 'text', 'text': 'x'},
        ],
        'structuredContent': null,
      }),
      'x',
    );
  });

  test('extractToolResult throws McpToolError joining the error text', () {
    expect(
      () => extractToolResult({
        'isError': true,
        'content': [
          {'type': 'text', 'text': 'bad'},
          {'type': 'text', 'text': 'worse'},
        ],
      }),
      throwsA(
        isA<McpToolError>()
            .having((e) => e.toolErrorText, 'toolErrorText', 'bad\nworse')
            .having((e) => e.message, 'message', 'MCP tool error: bad\nworse'),
      ),
    );
  });

  test(
    'extractToolResult names an unknown MCP error when no text is given',
    () {
      for (final content in [
        <Object?>[],
        [
          {'type': 'text'},
        ],
      ]) {
        expect(
          () => extractToolResult({'isError': true, 'content': content}),
          throwsA(
            isA<McpToolError>()
                .having(
                  (e) => e.toolErrorText,
                  'toolErrorText',
                  'Unknown error',
                )
                .having(
                  (e) => e.message,
                  'message',
                  'MCP tool error: Unknown error',
                ),
          ),
        );
      }
    },
  );

  test('McpToolError with empty text reports an unknown error', () {
    const error = McpToolError('');
    expect(error.message, 'MCP tool error: Unknown error');
    expect(error.toString(), 'MCP tool error: Unknown error');
  });
}
