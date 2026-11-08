import 'dart:convert';

import '../runtime/builtins.dart';
import 'ast.dart';
import 'js.dart';

enum T {
  newline,
  lParen,
  rParen,
  lBracket,
  rBracket,
  lBrace,
  rBrace,
  comma,
  colon,
  equals,
  trueKw,
  falseKw,
  nullKw,
  eof,
  str,
  num,
  ident,
  type,
  stateVar,
  dot,
  plus,
  minus,
  star,
  slash,
  percent,
  eqEq,
  notEq,
  greater,
  less,
  greaterEq,
  lessEq,
  and,
  or,
  not,
  question,
  builtinCall,
}

final class Token {
  const Token(this.t, [this.v]);
  final T t;
  final Object? v;
}

bool _isLower(String c) => c.compareTo('a') >= 0 && c.compareTo('z') <= 0;
bool _isUpper(String c) => c.compareTo('A') >= 0 && c.compareTo('Z') <= 0;
bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
bool _isIdentStart(String c) => _isLower(c) || _isUpper(c) || c == '_';
bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);

const _valueEnds = {
  T.num, T.str, T.ident, T.type, T.rParen, T.rBracket, T.trueKw, T.falseKw, //
  T.nullKw, T.stateVar, T.builtinCall,
};

/// lang-core `tokenize`.
List<Token> tokenize(String src) {
  final tokens = <Token>[];
  var i = 0;
  final n = src.length;
  while (i < n) {
    while (i < n && (src[i] == ' ' || src[i] == '\t' || src[i] == '\r')) {
      i++;
    }
    if (i >= n) break;
    final c = src[i];
    final next = i + 1 < n ? src[i + 1] : '';
    final single = switch (c) {
      '\n' => T.newline,
      '(' => T.lParen,
      ')' => T.rParen,
      '[' => T.lBracket,
      ']' => T.rBracket,
      '{' => T.lBrace,
      '}' => T.rBrace,
      ',' => T.comma,
      ':' => T.colon,
      '.' => T.dot,
      '?' => T.question,
      '+' => T.plus,
      '*' => T.star,
      '/' => T.slash,
      '%' => T.percent,
      _ => null,
    };
    if (single != null) {
      tokens.add(Token(single));
      i++;
      continue;
    }
    if (c == '=' || c == '!' || c == '>' || c == '<') {
      final pair = next == '=';
      tokens.add(
        Token(switch (c) {
          '=' => pair ? T.eqEq : T.equals,
          '!' => pair ? T.notEq : T.not,
          '>' => pair ? T.greaterEq : T.greater,
          _ => pair ? T.lessEq : T.less,
        }),
      );
      i += pair ? 2 : 1;
      continue;
    }
    if (c == '&' || c == '|') {
      tokens.add(Token(c == '&' ? T.and : T.or));
      i += next == c ? 2 : 1;
      continue;
    }
    if (c == '"') {
      final start = i;
      i++;
      var closed = false;
      while (i < n) {
        if (src[i] == r'\') {
          i += 2;
        } else if (src[i] == '"') {
          i++;
          closed = true;
          break;
        } else {
          i++;
        }
      }
      if (i > n) i = n;
      final raw = src.substring(start, i);
      tokens.add(
        Token(T.str, _decodeDoubleQuoted(closed ? raw : '$raw"', raw)),
      );
      continue;
    }
    if (c == "'") {
      i++;
      final out = StringBuffer();
      while (i < n) {
        if (src[i] == r'\') {
          i++;
          if (i < n) {
            final esc = src[i];
            out.write(switch (esc) {
              'n' => '\n',
              't' => '\t',
              _ => esc,
            });
            i++;
          }
        } else if (src[i] == "'") {
          i++;
          break;
        } else {
          out.write(src[i]);
          i++;
        }
      }
      tokens.add(Token(T.str, out.toString()));
      continue;
    }
    if (c == '-') {
      final prev = tokens.isEmpty ? null : tokens.last;
      final negativeLiteral =
          !(prev != null && _valueEnds.contains(prev.t)) && _isDigit(next);
      if (!negativeLiteral) {
        tokens.add(const Token(T.minus));
        i++;
        continue;
      }
    }
    if (_isDigit(c) || (c == '-' && _isDigit(next))) {
      final start = i;
      if (src[i] == '-') i++;
      while (i < n && _isDigit(src[i])) {
        i++;
      }
      if (i + 1 < n && src[i] == '.' && _isDigit(src[i + 1])) {
        i++;
        while (i < n && _isDigit(src[i])) {
          i++;
        }
      }
      if (i < n && (src[i] == 'e' || src[i] == 'E')) {
        i++;
        if (i < n && (src[i] == '+' || src[i] == '-')) i++;
        while (i < n && _isDigit(src[i])) {
          i++;
        }
      }
      final text = src.substring(start, i);
      tokens.add(Token(T.num, _parseNumberLiteral(text)));
      continue;
    }
    if (c == r'$' && _isIdentStart(next)) {
      final start = i;
      i++;
      while (i < n && _isIdentPart(src[i])) {
        i++;
      }
      tokens.add(Token(T.stateVar, src.substring(start, i)));
      continue;
    }
    if (_isIdentStart(c)) {
      final start = i;
      while (i < n && _isIdentPart(src[i])) {
        i++;
      }
      final word = src.substring(start, i);
      tokens.add(switch (word) {
        'true' => const Token(T.trueKw),
        'false' => const Token(T.falseKw),
        'null' => const Token(T.nullKw),
        _ => Token(_isUpper(c) ? T.type : T.ident, word),
      });
      continue;
    }
    if (c == '@' && _isIdentStart(next)) {
      i++;
      final start = i;
      while (i < n && _isIdentPart(src[i])) {
        i++;
      }
      tokens.add(Token(T.builtinCall, src.substring(start, i)));
      continue;
    }
    i++;
  }
  tokens.add(const Token(T.eof));
  return tokens;
}

String _decodeDoubleQuoted(String json, String raw) {
  try {
    return jsonDecode(json) as String;
  } on FormatException {
    var s = raw;
    if (s.startsWith('"')) s = s.substring(1);
    if (s.endsWith('"')) s = s.substring(0, s.length - 1);
    return s;
  }
}

num _parseNumberLiteral(String text) {
  final d = double.tryParse(text);
  if (d == null) return double.nan;
  if (d == 0 && d.isNegative) return d;
  return d == d.truncateToDouble() && d.abs() < 9007199254740992
      ? d.toInt()
      : d;
}

/// lang-core `parseExpression`: a Pratt parser over one statement's tokens.
Ast parseExpression(List<Token> tokens) {
  var pos = 0;
  Token cur() => pos < tokens.length ? tokens[pos] : const Token(T.eof);
  Token adv() {
    final tok = cur();
    pos++;
    return tok;
  }

  void eat(T kind) {
    if (cur().t == kind) pos++;
  }

  int infixPrec(Token tok) => switch (tok.t) {
    T.question => 1,
    T.or => 2,
    T.and => 3,
    T.eqEq || T.notEq => 4,
    T.greater || T.less || T.greaterEq || T.lessEq => 5,
    T.plus || T.minus => 6,
    T.star || T.slash || T.percent => 7,
    T.dot || T.lBracket => 9,
    _ => 0,
  };

  late Ast Function(int minPrec) parseExpr;

  Ast parseComp() {
    final name = cur().v as String;
    adv();
    eat(T.lParen);
    final args = <Ast>[];
    while (cur().t != T.rParen && cur().t != T.eof) {
      args.add(parseExpr(0));
      if (cur().t == T.comma) adv();
    }
    eat(T.rParen);
    return CompNode(name, args);
  }

  Ast parseArr() {
    adv();
    final els = <Ast>[];
    while (cur().t != T.rBracket && cur().t != T.eof) {
      els.add(parseExpr(0));
      if (cur().t == T.comma) adv();
    }
    eat(T.rBracket);
    return ArrNode(els);
  }

  String keyOf(Token kt) => switch (kt.t) {
    T.ident || T.str || T.type => kt.v as String,
    T.num => _numberKey(kt.v as num),
    T.stateVar => (kt.v as String).substring(1),
    _ => '?',
  };

  Ast parseObj() {
    adv();
    final entries = <(String, Ast)>[];
    while (cur().t != T.rBrace && cur().t != T.eof) {
      final key = keyOf(cur());
      adv();
      eat(T.colon);
      entries.add((key, parseExpr(0)));
      if (cur().t == T.comma) adv();
    }
    eat(T.rBrace);
    return ObjNode(entries);
  }

  Ast parsePrefix() {
    final tok = cur();
    switch (tok.t) {
      case T.str:
        adv();
        return StrNode(tok.v as String);
      case T.num:
        adv();
        return NumNode(tok.v as num);
      case T.trueKw:
        adv();
        return const BoolNode(true);
      case T.falseKw:
        adv();
        return const BoolNode(false);
      case T.nullKw:
        adv();
        return const NullNode();
      case T.lBracket:
        return parseArr();
      case T.lBrace:
        return parseObj();
      case T.stateVar:
        adv();
        if (cur().t == T.equals) {
          adv();
          return AssignNode(tok.v as String, parseExpr(0));
        }
        return StateRefNode(tok.v as String);
      case T.type:
        final name = tok.v as String;
        final calls = pos + 1 < tokens.length && tokens[pos + 1].t == T.lParen;
        if (calls && (!builtinNames.contains(name) || name == 'Action')) {
          return parseComp();
        }
        adv();
        return RefNode(name);
      case T.builtinCall:
        if (pos + 1 < tokens.length && tokens[pos + 1].t == T.lParen) {
          final call = parseComp() as CompNode;
          return builtinNames.contains(call.name)
              ? call
              : CompNode(call.name, call.args, isAtCall: true);
        }
        adv();
        return RefNode(tok.v as String);
      case T.ident:
        adv();
        return RefNode(tok.v as String);
      case T.not:
        adv();
        return UnaryOpNode('!', parseExpr(8));
      case T.minus:
        adv();
        return UnaryOpNode('-', parseExpr(8));
      case T.lParen:
        adv();
        final inner = parseExpr(0);
        eat(T.rParen);
        return inner;
      default:
        adv();
        return const NullNode();
    }
  }

  Ast parseInfix(Ast left) {
    final tok = cur();
    final binary = switch (tok.t) {
      T.plus => ('+', 6),
      T.minus => ('-', 6),
      T.star => ('*', 7),
      T.slash => ('/', 7),
      T.percent => ('%', 7),
      T.eqEq => ('==', 4),
      T.notEq => ('!=', 4),
      T.greater => ('>', 5),
      T.less => ('<', 5),
      T.greaterEq => ('>=', 5),
      T.lessEq => ('<=', 5),
      T.and => ('&&', 3),
      T.or => ('||', 2),
      _ => null,
    };
    if (binary != null) {
      adv();
      return BinOpNode(binary.$1, left, parseExpr(binary.$2));
    }
    switch (tok.t) {
      case T.question:
        adv();
        final then = parseExpr(0);
        eat(T.colon);
        return TernaryNode(left, then, parseExpr(0));
      case T.dot:
        adv();
        final f = cur();
        adv();
        return MemberNode(left, keyOf(f));
      case T.lBracket:
        adv();
        final index = parseExpr(0);
        eat(T.rBracket);
        return IndexNode(left, index);
      default:
        return left;
    }
  }

  parseExpr = (int minPrec) {
    var left = parsePrefix();
    while (infixPrec(cur()) > minPrec) {
      left = parseInfix(left);
    }
    return left;
  };

  return parseExpr(0);
}

String _numberKey(num v) => Js.numberToString(v);
