import 'package:ai_sdk_openui/src/lang/lexer.dart';
import 'package:ai_sdk_openui/src/lang/statements.dart';
import 'package:test/test.dart';

typedef Stmt = (String, T, List<T>);

String _enc(Stmt s) =>
    '${s.$1} ${s.$2.name} ${s.$3.map((t) => t.name).join(' ')}';

/// The (id, id token kind, expression token kinds) of each statement.
List<String> statements(String src) => [
  for (final s in split(tokenize(src)))
    _enc((s.id, s.idTokenType, [for (final t in s.tokens) t.t])),
];

void expectStmts(String src, List<Stmt> expected) =>
    expect(statements(src), expected.map(_enc).toList());

void main() {
  group('autoClose', () {
    test('leaves a complete program alone', () {
      final r = autoClose('a = Foo([1, {b: "x"}])');
      expect(r.text, 'a = Foo([1, {b: "x"}])');
      expect(r.wasIncomplete, isFalse);
    });

    test('closes brackets in reverse order', () {
      final r = autoClose('a = Foo([1, {b: (2');
      expect(r.text, 'a = Foo([1, {b: (2)}])');
      expect(r.wasIncomplete, isTrue);
    });

    test('closes a double-quoted string, then the brackets', () {
      expect(autoClose('a = Foo("ab').text, 'a = Foo("ab")');
    });

    test('closes a single-quoted string', () {
      expect(autoClose("a = Foo('ab").text, "a = Foo('ab')");
    });

    test('a bracket inside a string does not count', () {
      final r = autoClose('a = Foo("(")');
      expect(r.text, 'a = Foo("(")');
      expect(r.wasIncomplete, isFalse);
    });

    test('a quote of the other kind inside a string does not end it', () {
      expect(autoClose('a = "it\'s').text, 'a = "it\'s"');
    });

    test('an escaped quote does not end the string', () {
      expect(autoClose(r'a = "x\"y').text, r'a = "x\"y"');
    });

    test('a trailing backslash in a string is completed, then closed', () {
      expect(autoClose(r'a = "x\').text, r'a = "x\\"');
    });

    test('a closer that does not match the open bracket is ignored', () {
      final r = autoClose('a = Foo(]');
      expect(r.text, 'a = Foo(])');
      expect(r.wasIncomplete, isTrue);
    });

    test('a stray closer with nothing open is ignored', () {
      final r = autoClose('a = 1)');
      expect(r.text, 'a = 1)');
      expect(r.wasIncomplete, isFalse);
    });

    test('empty input is complete', () {
      expect(autoClose('').wasIncomplete, isFalse);
    });
  });

  group('split', () {
    test('one statement per line, keeping the kind of each id', () {
      expectStmts('root = Card(1)\ntitle = "x"\n\$n = 3', [
        ('root', T.ident, [T.type, T.lParen, T.num, T.rParen]),
        ('title', T.ident, [T.str]),
        (r'$n', T.stateVar, [T.num]),
      ]);
    });

    test('a type name can be a statement id', () {
      expectStmts('Root = 1', [
        ('Root', T.type, [T.num]),
      ]);
    });

    test('skips lines that do not start with an identifier', () {
      expectStmts('1 2 3\n"str" = 4\n( = 1\na = 5', [
        ('a', T.ident, [T.num]),
      ]);
    });

    test('skips lines whose identifier is not followed by =', () {
      expectStmts('foo bar baz\nqux\nfoo == 1\na = 2', [
        ('a', T.ident, [T.num]),
      ]);
    });

    test('drops a statement with no expression', () {
      expectStmts('a =\nb = 1', [
        ('b', T.ident, [T.num]),
      ]);
    });

    test('blank lines between statements are skipped', () {
      expectStmts('a = 1\n\n\n\nb = 2', [
        ('a', T.ident, [T.num]),
        ('b', T.ident, [T.num]),
      ]);
    });

    test('newlines inside brackets do not end the statement', () {
      expectStmts('a = Foo(\n1,\n[2,\n3]\n)\nb = 1', [
        (
          'a',
          T.ident,
          [
            T.type,
            T.lParen,
            T.num,
            T.comma,
            T.lBracket,
            T.num,
            T.comma,
            T.num,
            T.rBracket,
            T.rParen,
          ],
        ),
        ('b', T.ident, [T.num]),
      ]);
    });

    test('a ? on the next line continues the statement', () {
      expectStmts('a = x\n\n? 1\n: 2\nb = 3', [
        ('a', T.ident, [T.ident, T.question, T.num, T.colon, T.num]),
        ('b', T.ident, [T.num]),
      ]);
    });

    test('a : on the next line does not continue outside a ternary', () {
      expectStmts('a = 1\n: 2', [
        ('a', T.ident, [T.num]),
      ]);
    });

    test('a : on the next line continues an open ternary', () {
      expectStmts('a = x ? 1\n: 2', [
        ('a', T.ident, [T.ident, T.question, T.num, T.colon, T.num]),
      ]);
    });

    test('a ? inside brackets does not open a ternary', () {
      expectStmts('a = Foo(x ? 1 : 2)\nb = 1', [
        (
          'a',
          T.ident,
          [
            T.type,
            T.lParen,
            T.ident,
            T.question,
            T.num,
            T.colon,
            T.num,
            T.rParen,
          ],
        ),
        ('b', T.ident, [T.num]),
      ]);
    });

    test('an extra closing bracket does not unbalance the next line', () {
      expectStmts('a = 1)\nb = 2', [
        ('a', T.ident, [T.num, T.rParen]),
        ('b', T.ident, [T.num]),
      ]);
    });

    test('empty input has no statements', () {
      expect(statements(''), isEmpty);
    });
  });

  group('stripFences', () {
    test('returns the code in a fence, without the language line', () {
      expect(stripFences('```openui\nroot = A(1)\n```'), 'root = A(1)\n');
      expect(stripFences('```\nroot = A(1)\n```'), 'root = A(1)\n');
    });

    test('drops the prose around a fence', () {
      expect(
        stripFences('Here you go:\n```openui\na = 1\n```\nHope it helps.'),
        'a = 1\n',
      );
    });

    test('joins several fences with a newline', () {
      expect(
        stripFences('x\n```\na = 1\n```\ny\n```ts\nb = 2\n```\nz'),
        'a = 1\n\nb = 2\n',
      );
    });

    test('an unclosed fence runs to the end of the input', () {
      expect(stripFences('```openui\nroot = A(1)'), 'root = A(1)');
      expect(stripFences('text\n```\na = 1\nb = 2'), 'a = 1\nb = 2');
    });

    test('a fence line with no newline after it has an empty body', () {
      expect(stripFences('```openui'), '');
      expect(stripFences('text ```ts'), '');
    });

    test('a fence inside a string does not open a block', () {
      const src = 'a = "```"\nb = 2';
      expect(stripFences(src), src);
    });

    test('a fence inside a string does not close a block', () {
      expect(
        stripFences('```\na = "```"\nb = 2\n```\ntail'),
        'a = "```"\nb = 2\n',
      );
    });

    test('an escaped quote keeps the string open across a fence', () {
      const src =
          r'a = "x\"```"'
          '\nb = 1';
      expect(stripFences(src), src);
    });

    test('an unterminated string hides every later fence', () {
      const src = 'a = "abc\n```\nb = 1\n```';
      expect(stripFences(src), src);
    });

    test('a string ending in a lone backslash is skipped to the end', () {
      const src = r'a = "abc\';
      expect(stripFences(src), src);
    });

    test('single quotes do not hide a fence', () {
      expect(stripFences("a = '\n```\nb = 1\n```"), 'b = 1\n');
    });

    test('input with no fence comes back unchanged', () {
      expect(stripFences('a = 1\nb = 2'), 'a = 1\nb = 2');
      expect(stripFences('``not a fence``'), '``not a fence``');
      expect(stripFences(''), '');
    });
  });

  group('stripComments', () {
    test('drops // and # comments with the blanks before them', () {
      expect(
        stripComments('a = 1 // one\nb = 2 # two\nc = 3'),
        'a = 1\nb = 2\nc = 3',
      );
    });

    test('a comment-only line becomes an empty line', () {
      expect(stripComments('// header\na = 1\n# note'), '\na = 1\n');
    });

    test('keeps // and # inside double and single quotes', () {
      expect(
        stripComments('a = "x // y" # c\nb = \'#tag\' // c'),
        'a = "x // y"\nb = \'#tag\'',
      );
    });

    test('a single slash is not a comment', () {
      expect(stripComments('a = 6 / 2'), 'a = 6 / 2');
    });

    test('an escaped quote does not end the string', () {
      expect(stripComments(r'a = "x\" // y" // c'), r'a = "x\" // y"');
    });

    test('a quote left open carries to the next line, as in lang-core', () {
      expect(
        stripComments('a = "x\nb = 1 // not a comment"\nc = 2 // comment'),
        'a = "x\nb = 1 // not a comment"\nc = 2',
      );
    });

    test('a lone trailing backslash in a string is kept', () {
      expect(stripComments(r'a = "x\'), r'a = "x\');
    });

    test('text without comments is unchanged', () {
      expect(stripComments('a = 1\n\nb = 2'), 'a = 1\n\nb = 2');
    });
  });

  group('preprocess', () {
    test('trims, unwraps fences and drops comments, in that order', () {
      expect(
        preprocess('  \nSure:\n```openui\nroot = A(1) // c\n# x\n```\n  '),
        'root = A(1)',
      );
    });

    test('fences are stripped before comments, so a fence in one wins', () {
      expect(preprocess('  a = 1 // ```\n'), '');
    });
  });
}
