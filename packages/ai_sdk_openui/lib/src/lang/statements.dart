import 'lexer.dart';

/// lang-core `autoClose`: closes unclosed strings and brackets of a partial
/// program so it parses.
({String text, bool wasIncomplete}) autoClose(String input) {
  final stack = <String>[];
  String? inStr;
  var esc = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (esc) {
      esc = false;
      continue;
    }
    if (c == r'\' && inStr != null) {
      esc = true;
      continue;
    }
    if (inStr != null) {
      if (c == inStr) inStr = null;
      continue;
    }
    if (c == '"' || c == "'") {
      inStr = c;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add(c);
    } else if (stack.isNotEmpty &&
        ((c == ')' && stack.last == '(') ||
            (c == ']' && stack.last == '[') ||
            (c == '}' && stack.last == '{'))) {
      stack.removeLast();
    }
  }
  if (inStr == null && stack.isEmpty) {
    return (text: input, wasIncomplete: false);
  }
  final out = StringBuffer(input);
  if (inStr != null) {
    if (esc) out.write(r'\');
    out.write(inStr);
  }
  for (final open in stack.reversed) {
    out.write(switch (open) {
      '(' => ')',
      '[' => ']',
      _ => '}',
    });
  }
  return (text: out.toString(), wasIncomplete: true);
}

final class RawStatement {
  const RawStatement(this.id, this.idTokenType, this.tokens);
  final String id;
  final T idTokenType;
  final List<Token> tokens;
}

/// lang-core `split`: one statement per `identifier = expression` line, with
/// newlines inside brackets and before a ternary's `?`/`:` ignored.
List<RawStatement> split(List<Token> tokens) {
  final stmts = <RawStatement>[];
  var pos = 0;
  void skipLine() {
    while (pos < tokens.length &&
        tokens[pos].t != T.newline &&
        tokens[pos].t != T.eof) {
      pos++;
    }
  }

  while (pos < tokens.length) {
    while (pos < tokens.length && tokens[pos].t == T.newline) {
      pos++;
    }
    if (pos >= tokens.length || tokens[pos].t == T.eof) break;
    final tok = tokens[pos];
    if (tok.t != T.ident && tok.t != T.type && tok.t != T.stateVar) {
      skipLine();
      continue;
    }
    pos++;
    if (pos >= tokens.length || tokens[pos].t != T.equals) {
      skipLine();
      continue;
    }
    pos++;
    final expr = <Token>[];
    var depth = 0;
    var ternaryDepth = 0;
    while (pos < tokens.length && tokens[pos].t != T.eof) {
      final tt = tokens[pos].t;
      if (tt == T.newline && depth <= 0 && ternaryDepth <= 0) {
        var peek = pos + 1;
        while (peek < tokens.length && tokens[peek].t == T.newline) {
          peek++;
        }
        final nextT = peek < tokens.length ? tokens[peek].t : T.eof;
        if (nextT == T.question || (nextT == T.colon && ternaryDepth > 0)) {
          pos++;
          continue;
        }
        break;
      }
      if (tt == T.newline) {
        pos++;
        continue;
      }
      if (tt == T.lParen || tt == T.lBracket || tt == T.lBrace) {
        depth++;
      } else if ((tt == T.rParen || tt == T.rBracket || tt == T.rBrace) &&
          depth > 0) {
        depth--;
      } else if (tt == T.question && depth == 0) {
        ternaryDepth++;
      } else if (tt == T.colon && depth == 0 && ternaryDepth > 0) {
        ternaryDepth--;
      }
      expr.add(tokens[pos++]);
    }
    if (expr.isNotEmpty) stmts.add(RawStatement(tok.v as String, tok.t, expr));
  }
  return stmts;
}

int _skipString(String input, int start) {
  if (input[start] != '"') return start;
  var i = start + 1;
  while (i < input.length) {
    final c = input[i];
    if (c == r'\') {
      i += 2;
    } else if (c == '"') {
      return i + 1;
    } else {
      i++;
    }
  }
  return i;
}

bool _fenceAt(String s, int i) =>
    i + 2 < s.length && s[i] == '`' && s[i + 1] == '`' && s[i + 2] == '`';

/// lang-core `stripFences`: the code inside markdown fences, or the input.
String stripFences(String input) {
  final blocks = <String>[];
  var i = 0;
  while (i < input.length) {
    var fenceStart = -1;
    while (i < input.length) {
      final nextI = _skipString(input, i);
      if (nextI > i) {
        i = nextI;
        continue;
      }
      if (_fenceAt(input, i)) {
        fenceStart = i;
        break;
      }
      i++;
    }
    if (fenceStart == -1) break;
    var j = fenceStart + 3;
    while (j < input.length && input[j] != '\n') {
      j++;
    }
    if (j >= input.length) {
      blocks.add(
        input.substring(fenceStart + 3).replaceFirst(RegExp(r'^[^\n]*\n?'), ''),
      );
      i = input.length;
      break;
    }
    j++;
    var closePos = -1;
    var k = j;
    while (k < input.length) {
      final nextK = _skipString(input, k);
      if (nextK > k) {
        k = nextK;
        continue;
      }
      if (_fenceAt(input, k)) {
        closePos = k;
        break;
      }
      k++;
    }
    if (closePos != -1) {
      blocks.add(input.substring(j, closePos));
      i = closePos + 3;
    } else {
      blocks.add(input.substring(j));
      i = input.length;
    }
  }
  if (blocks.isNotEmpty) return blocks.join('\n');
  return input;
}

/// lang-core `stripComments`: drops `//` and `#` line comments outside
/// strings. A string's open quote carries across lines, as in lang-core.
String stripComments(String input) {
  String? inStr;
  return input
      .split('\n')
      .map((line) {
        for (var i = 0; i < line.length; i++) {
          final c = line[i];
          if (inStr != null) {
            if (c == r'\' && i + 1 < line.length) {
              i++;
              continue;
            }
            if (c == inStr) inStr = null;
            continue;
          }
          if (c == '"' || c == "'") {
            inStr = c;
            continue;
          }
          if ((c == '/' && i + 1 < line.length && line[i + 1] == '/') ||
              c == '#') {
            return line.substring(0, i).trimRight();
          }
        }
        return line;
      })
      .join('\n');
}

String preprocess(String input) =>
    stripComments(stripFences(input.trim())).trim();
