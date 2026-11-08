// A port of V8's legacy-compatible date parser (src/date/dateparser.h,
// dateparser-inl.h, dateparser.cc and ParseDateTimeString in date.cc, V8
// 14.6), so `new Date(text)` reads the same strings in Dart.
//
// Copyright 2011 the V8 project authors. All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Google Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

/// The epoch milliseconds JavaScript's `new Date(text)` gives, or NaN.
/// [fromLocal] turns a local wall-clock time (as epoch milliseconds read as
/// UTC) into epoch milliseconds, for strings without a time zone.
double jsDateParse(String text, int Function(int wallMs) fromLocal) {
  final out = List<double>.filled(_outputSize, 0);
  if (!_parse(text, out)) return double.nan;
  final day = makeDay(out[_year], out[_month], out[_day]);
  final time =
      out[_hour] * 3600000 +
      out[_minute] * 60000 +
      out[_second] * 1000 +
      out[_millisecond];
  var date = day * _msPerDay + time;
  if (out[_utcOffset].isNaN) {
    if (!(date.abs() <= _maxTime + 864000000)) return double.nan;
    try {
      date = fromLocal(date.toInt()).toDouble();
    } on Object {
      return double.nan;
    }
  } else {
    date -= out[_utcOffset] * 1000;
  }
  return date.abs() <= _maxTime ? date + 0 : double.nan;
}

/// ECMAScript `MakeDay` as V8 computes it: days since 1970-01-01 of [year],
/// a 0-based [month] that may overflow into other years, and [date]; NaN
/// out of range.
double makeDay(double year, double month, double date) {
  if (!(year >= -1000000 && year <= 1000000) ||
      !(month >= -10000000 && month <= 10000000) ||
      !date.isFinite) {
    return double.nan;
  }
  var y = year.truncate();
  var m = month.truncate();
  y += m ~/ 12;
  m = m.remainder(12);
  if (m < 0) {
    m += 12;
    y -= 1;
  }
  const yearDelta = 399999;
  int daysBefore(int y) =>
      365 * (y + yearDelta) +
      (y + yearDelta) ~/ 4 -
      (y + yearDelta) ~/ 100 +
      (y + yearDelta) ~/ 400;
  final leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
  final fromMonth = (leap ? _leapMonthDays : _monthDays)[m];
  return (daysBefore(y) - daysBefore(1970) + fromMonth).toDouble() +
      date.truncateToDouble() -
      1;
}

const _monthDays = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
const _leapMonthDays = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];
const _msPerDay = 86400000.0;
const _maxTime = 8.64e15;

const _year = 0;
const _month = 1;
const _day = 2;
const _hour = 3;
const _minute = 4;
const _second = 5;
const _millisecond = 6;
const _utcOffset = 7;
const _outputSize = 8;

const _none = 0x7FFFFFFF;
const _maxSignificantDigits = 9;

bool _between(int x, int lo, int hi) => x >= lo && x <= hi;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

// ECMAScript WhiteSpace: TAB, VT, FF, SP, NBSP, ZWNBSP and category Zs.
bool _isWhiteSpace(int c) =>
    c == 0x09 ||
    c == 0x0B ||
    c == 0x0C ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0xFEFF ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;

bool _isLineTerminator(int c) =>
    c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029;

final class _InputReader {
  _InputReader(this._text) {
    next();
  }
  final String _text;
  int _index = 0;
  int ch = 0;

  int get position => _index;

  void next() {
    ch = _index < _text.length ? _text.codeUnitAt(_index) : 0;
    _index++;
  }

  int readUnsignedNumeral() {
    var n = 0;
    var i = 0;
    while (ch == 0x30) {
      next();
    }
    while (isDigit) {
      if (i < _maxSignificantDigits) n = n * 10 + ch - 0x30;
      i++;
      next();
    }
    return n;
  }

  int readWord(List<int> prefix) {
    var length = 0;
    for (; isAsciiAlphaOrAbove && !isWhiteSpaceChar; next(), length++) {
      if (length < prefix.length) prefix[length] = ch | 0x20;
    }
    for (var i = length; i < prefix.length; i++) {
      prefix[i] = 0;
    }
    return length;
  }

  bool skip(int c) {
    if (ch != c) return false;
    next();
    return true;
  }

  bool skipWhiteSpace() {
    if (!_isWhiteSpace(ch) && !_isLineTerminator(ch)) return false;
    next();
    return true;
  }

  bool skipParentheses() {
    if (ch != 0x28) return false;
    var balance = 0;
    do {
      if (ch == 0x29) {
        --balance;
      } else if (ch == 0x28) {
        ++balance;
      }
      next();
    } while (balance > 0 && ch != 0);
    return true;
  }

  bool get isEnd => ch == 0;
  bool get isDigit => _isDigit(ch);
  bool get isAsciiAlphaOrAbove => ch >= 0x41;
  bool get isWhiteSpaceChar => _isWhiteSpace(ch);
}

enum _Keyword { invalid, monthName, timeZoneName, timeSeparator, amPm }

enum _Tag { invalid, unknown, whiteSpace, number, symbol, endOfInput, keyword }

final class _Token {
  const _Token(this.tag, this.length, this.value, [this.keyword]);
  final _Tag tag;
  final int length;
  final int value;
  final _Keyword? keyword;

  static const endOfInput = _Token(_Tag.endOfInput, 0, -1);
  static const invalid = _Token(_Tag.invalid, 0, -1);
  static const unknown = _Token(_Tag.unknown, 1, -1);

  bool get isInvalid => tag == _Tag.invalid;
  bool get isNumber => tag == _Tag.number;
  bool get isWhiteSpace => tag == _Tag.whiteSpace;
  bool get isEndOfInput => tag == _Tag.endOfInput;
  bool get isKeyword => tag == _Tag.keyword;
  bool isSymbol(int c) => tag == _Tag.symbol && value == c;
  bool isKeywordType(_Keyword k) => isKeyword && keyword == k;
  bool isFixedLengthNumber(int n) => isNumber && length == n;
  bool get isAsciiSign =>
      tag == _Tag.symbol && (value == 0x2D || value == 0x2B);
  // '+' is 43 and '-' is 45, so 44 - value is 1 or -1.
  int get asciiSign => 44 - value;
  bool get isKeywordZ =>
      isKeywordType(_Keyword.timeZoneName) && length == 1 && value == 0;
}

final class _Tokenizer {
  _Tokenizer(this._in) {
    _next = _scan();
  }
  final _InputReader _in;
  late _Token _next;

  _Token next() {
    final result = _next;
    _next = _scan();
    return result;
  }

  _Token peek() => _next;

  bool skipSymbol(int c) {
    if (!_next.isSymbol(c)) return false;
    _next = _scan();
    return true;
  }

  _Token _scan() {
    final pre = _in.position;
    if (_in.isEnd) return _Token.endOfInput;
    if (_in.isDigit) {
      final n = _in.readUnsignedNumeral();
      return _Token(_Tag.number, _in.position - pre, n);
    }
    for (final c in const [0x3A, 0x2D, 0x2B, 0x2E, 0x29]) {
      if (_in.skip(c)) return _Token(_Tag.symbol, 1, c);
    }
    if (_in.isAsciiAlphaOrAbove && !_in.isWhiteSpaceChar) {
      final prefix = [0, 0, 0];
      final length = _in.readWord(prefix);
      final (type, value) = _lookup(prefix, length);
      return _Token(_Tag.keyword, length, value, type);
    }
    if (_in.skipWhiteSpace()) {
      return _Token(_Tag.whiteSpace, _in.position - pre, -1);
    }
    if (_in.skipParentheses()) return _Token.unknown;
    _in.next();
    return _Token.unknown;
  }
}

const _keywords = <(String, _Keyword, int)>[
  ('jan', _Keyword.monthName, 1),
  ('feb', _Keyword.monthName, 2),
  ('mar', _Keyword.monthName, 3),
  ('apr', _Keyword.monthName, 4),
  ('may', _Keyword.monthName, 5),
  ('jun', _Keyword.monthName, 6),
  ('jul', _Keyword.monthName, 7),
  ('aug', _Keyword.monthName, 8),
  ('sep', _Keyword.monthName, 9),
  ('oct', _Keyword.monthName, 10),
  ('nov', _Keyword.monthName, 11),
  ('dec', _Keyword.monthName, 12),
  ('am', _Keyword.amPm, 0),
  ('pm', _Keyword.amPm, 12),
  ('ut', _Keyword.timeZoneName, 0),
  ('utc', _Keyword.timeZoneName, 0),
  ('z', _Keyword.timeZoneName, 0),
  ('gmt', _Keyword.timeZoneName, 0),
  ('cdt', _Keyword.timeZoneName, -5),
  ('cst', _Keyword.timeZoneName, -6),
  ('edt', _Keyword.timeZoneName, -4),
  ('est', _Keyword.timeZoneName, -5),
  ('mdt', _Keyword.timeZoneName, -6),
  ('mst', _Keyword.timeZoneName, -7),
  ('pdt', _Keyword.timeZoneName, -7),
  ('pst', _Keyword.timeZoneName, -8),
  ('t', _Keyword.timeSeparator, 0),
];

(_Keyword, int) _lookup(List<int> prefix, int length) {
  for (final (word, type, value) in _keywords) {
    var j = 0;
    while (j < 3 && prefix[j] == (j < word.length ? word.codeUnitAt(j) : 0)) {
      j++;
    }
    // A word longer than the keyword only matches a month name.
    if (j == 3 && (length <= 3 || type == _Keyword.monthName)) {
      return (type, value);
    }
  }
  return (_Keyword.invalid, 0);
}

int _readMilliseconds(_Token token) {
  var number = token.value;
  var length = token.length;
  if (length == 1) {
    number *= 100;
  } else if (length == 2) {
    number *= 10;
  } else if (length > 3) {
    if (length > _maxSignificantDigits) length = _maxSignificantDigits;
    var factor = 1;
    do {
      factor *= 10;
      length--;
    } while (length > 3);
    number ~/= factor;
  }
  return number;
}

final class _TimeZone {
  int sign = _none;
  int hour = _none;
  int minute = _none;

  void set(int offsetInHours) {
    sign = offsetInHours < 0 ? -1 : 1;
    hour = offsetInHours * sign;
    minute = 0;
  }

  void setSign(int s) => sign = s < 0 ? -1 : 1;
  bool isExpecting(int n) =>
      hour != _none && minute == _none && _Time.isMinute(n);
  bool get isUtc => hour == 0 && minute == 0;
  bool get isEmpty => hour == _none;

  bool write(List<double> out) {
    if (sign != _none) {
      if (hour == _none) hour = 0;
      if (minute == _none) minute = 0;
      var total = hour * 3600 + minute * 60;
      if (total > 0x3FFFFFFF) return false;
      if (sign < 0) total = -total;
      out[_utcOffset] = total.toDouble();
    } else {
      out[_utcOffset] = double.nan;
    }
    return true;
  }
}

final class _Time {
  final _comp = List<int>.filled(4, 0);
  int _index = 0;
  int _hourOffset = _none;

  static bool isMinute(int x) => _between(x, 0, 59);
  static bool isHour(int x) => _between(x, 0, 23);
  static bool isSecond(int x) => _between(x, 0, 59);
  static bool _isHour12(int x) => _between(x, 0, 12);
  static bool _isMillisecond(int x) => _between(x, 0, 999);

  bool get isEmpty => _index == 0;
  bool isExpecting(int n) =>
      (_index == 1 && isMinute(n)) ||
      (_index == 2 && isSecond(n)) ||
      (_index == 3 && _isMillisecond(n));

  bool add(int n) {
    if (_index >= 4) return false;
    _comp[_index++] = n;
    return true;
  }

  bool addFinal(int n) {
    if (!add(n)) return false;
    while (_index < 4) {
      _comp[_index++] = 0;
    }
    return true;
  }

  void setHourOffset(int n) => _hourOffset = n;

  bool write(List<double> out) {
    while (_index < 4) {
      _comp[_index++] = 0;
    }
    var hour = _comp[0];
    final minute = _comp[1];
    final second = _comp[2];
    final millisecond = _comp[3];
    if (_hourOffset != _none) {
      if (!_isHour12(hour)) return false;
      hour %= 12;
      hour += _hourOffset;
    }
    if (!isHour(hour) ||
        !isMinute(minute) ||
        !isSecond(second) ||
        !_isMillisecond(millisecond)) {
      // A 24th hour is allowed if minutes, seconds and milliseconds are 0.
      if (hour != 24 || minute != 0 || second != 0 || millisecond != 0) {
        return false;
      }
    }
    out[_hour] = hour.toDouble();
    out[_minute] = minute.toDouble();
    out[_second] = second.toDouble();
    out[_millisecond] = millisecond.toDouble();
    return true;
  }
}

final class _Day {
  final _comp = List<int>.filled(3, 0);
  int _index = 0;
  int _namedMonth = _none;
  bool _isIsoDate = false;

  static bool isMonth(int x) => _between(x, 1, 12);
  static bool isDay(int x) => _between(x, 1, 31);

  bool get isEmpty => _index == 0;

  bool add(int n) {
    if (_index >= 3) return false;
    _comp[_index++] = n;
    return true;
  }

  void setNamedMonth(int n) => _namedMonth = n;
  void setIsoDate() => _isIsoDate = true;

  bool write(List<double> out) {
    if (_index < 1) return false;
    // Day and month default to 1.
    while (_index < 3) {
      _comp[_index++] = 1;
    }
    var year = 0; // 0 is 2000, for KJS compatibility.
    int month;
    int day;
    if (_namedMonth == _none) {
      if (_isIsoDate || (_index == 3 && !isDay(_comp[0]))) {
        year = _comp[0];
        month = _comp[1];
        day = _comp[2];
      } else {
        month = _comp[0];
        day = _comp[1];
        if (_index == 3) year = _comp[2];
      }
    } else {
      month = _namedMonth;
      if (_index == 1) {
        day = _comp[0];
      } else if (!isDay(_comp[0])) {
        year = _comp[0];
        day = _comp[1];
      } else {
        day = _comp[0];
        year = _comp[1];
      }
    }
    if (!_isIsoDate) {
      if (_between(year, 0, 49)) {
        year += 2000;
      } else if (_between(year, 50, 99)) {
        year += 1900;
      }
    }
    if (!isMonth(month) || !isDay(day)) return false;
    out[_year] = year.toDouble();
    out[_month] = (month - 1).toDouble();
    out[_day] = day.toDouble();
    return true;
  }
}

bool _parse(String text, List<double> out) {
  final scanner = _Tokenizer(_InputReader(text));
  final tz = _TimeZone();
  final time = _Time();
  final day = _Day();

  final first = _parseEs5DateTime(scanner, day, time, tz);
  if (first.isInvalid) return false;
  var hasReadNumber = !day.isEmpty;
  for (var token = first; !token.isEndOfInput; token = scanner.next()) {
    if (token.isNumber) {
      hasReadNumber = true;
      final n = token.value;
      if (scanner.skipSymbol(0x3A)) {
        if (scanner.skipSymbol(0x3A)) {
          // n + "::"
          if (!time.isEmpty) return false;
          time.add(n);
          time.add(0);
        } else {
          // n + ":"
          if (!time.add(n)) return false;
          if (scanner.peek().isSymbol(0x2E)) scanner.next();
        }
      } else if (scanner.skipSymbol(0x2E) && time.isExpecting(n)) {
        time.add(n);
        if (!scanner.peek().isNumber) return false;
        final ms = _readMilliseconds(scanner.next());
        if (ms < 0) return false;
        time.addFinal(ms);
      } else if (tz.isExpecting(n)) {
        tz.minute = n;
      } else if (time.isExpecting(n)) {
        time.addFinal(n);
        // Require end, white space, "Z", "+" or "-" right after the time.
        final peek = scanner.peek();
        if (!peek.isEndOfInput &&
            !peek.isWhiteSpace &&
            !peek.isKeywordZ &&
            !peek.isAsciiSign) {
          return false;
        }
      } else {
        if (!day.add(n)) return false;
        scanner.skipSymbol(0x2D);
      }
    } else if (token.isKeyword) {
      final type = token.keyword;
      final value = token.value;
      if (type == _Keyword.amPm && !time.isEmpty) {
        time.setHourOffset(value);
      } else if (type == _Keyword.monthName) {
        day.setNamedMonth(value);
        scanner.skipSymbol(0x2D);
      } else if (type == _Keyword.timeZoneName && hasReadNumber) {
        tz.set(value);
      } else {
        // Garbage words are illegal once a number has been read, and the
        // first number must be separated from garbage words.
        if (hasReadNumber) return false;
        if (scanner.peek().isNumber) return false;
      }
    } else if (token.isAsciiSign && (tz.isUtc || !time.isEmpty)) {
      // A UTC offset, only after UTC or a time.
      tz.setSign(token.asciiSign);
      var n = 0;
      var length = 0;
      if (scanner.peek().isNumber) {
        final number = scanner.next();
        length = number.length;
        n = number.value;
      }
      hasReadNumber = true;
      if (scanner.peek().isSymbol(0x3A)) {
        tz.hour = n;
        tz.minute = _none;
      } else if (length == 1 || length == 2) {
        tz.hour = n;
        tz.minute = 0;
      } else if (length == 3 || length == 4) {
        tz.hour = n ~/ 100;
        tz.minute = n % 100;
      } else {
        return false;
      }
    } else if ((token.isAsciiSign || token.isSymbol(0x29)) && hasReadNumber) {
      // An extra sign or ')' is illegal once a number has been read.
      return false;
    }
  }
  return day.write(out) && time.write(out) && tz.write(out);
}

/// Reads as much of an ES5 ISO date-time as it can:
/// `[('-'|'+')yy]yyyy[-MM[-DD]][THH:mm[:ss[.sss]][Z|(+|-)hh:mm]]`. Returns
/// end of input on success, invalid when the string cannot be a date, or the
/// first token the legacy parser should continue from.
_Token _parseEs5DateTime(
  _Tokenizer scanner,
  _Day day,
  _Time time,
  _TimeZone tz,
) {
  if (scanner.peek().isAsciiSign) {
    // Keep the sign token for the legacy parser if it isn't used.
    final signToken = scanner.next();
    if (!scanner.peek().isFixedLengthNumber(6)) return signToken;
    final sign = signToken.asciiSign;
    final year = scanner.next().value;
    if (sign < 0 && year == 0) return signToken;
    day.add(sign * year);
  } else if (scanner.peek().isFixedLengthNumber(4)) {
    day.add(scanner.next().value);
  } else {
    return scanner.next();
  }
  if (scanner.skipSymbol(0x2D)) {
    if (!scanner.peek().isFixedLengthNumber(2) ||
        !_Day.isMonth(scanner.peek().value)) {
      return scanner.next();
    }
    day.add(scanner.next().value);
    if (scanner.skipSymbol(0x2D)) {
      if (!scanner.peek().isFixedLengthNumber(2) ||
          !_Day.isDay(scanner.peek().value)) {
        return scanner.next();
      }
      day.add(scanner.next().value);
    }
  }
  if (!scanner.peek().isKeywordType(_Keyword.timeSeparator)) {
    if (!scanner.peek().isEndOfInput) return scanner.next();
  } else {
    scanner.next();
    if (!scanner.peek().isFixedLengthNumber(2) ||
        !_between(scanner.peek().value, 0, 24)) {
      return _Token.invalid;
    }
    // 24:00[:00[.000]] is allowed, but no other time starting with 24.
    final hourIs24 = scanner.peek().value == 24;
    time.add(scanner.next().value);
    if (!scanner.skipSymbol(0x3A)) return _Token.invalid;
    if (!scanner.peek().isFixedLengthNumber(2) ||
        !_Time.isMinute(scanner.peek().value) ||
        (hourIs24 && scanner.peek().value > 0)) {
      return _Token.invalid;
    }
    time.add(scanner.next().value);
    if (scanner.skipSymbol(0x3A)) {
      if (!scanner.peek().isFixedLengthNumber(2) ||
          !_Time.isSecond(scanner.peek().value) ||
          (hourIs24 && scanner.peek().value > 0)) {
        return _Token.invalid;
      }
      time.add(scanner.next().value);
      if (scanner.skipSymbol(0x2E)) {
        if (!scanner.peek().isNumber ||
            (hourIs24 && scanner.peek().value > 0)) {
          return _Token.invalid;
        }
        // More or fewer than the three digits are allowed.
        time.add(_readMilliseconds(scanner.next()));
      }
    }
    if (scanner.peek().isKeywordZ) {
      scanner.next();
      tz.set(0);
    } else if (scanner.peek().isSymbol(0x2B) || scanner.peek().isSymbol(0x2D)) {
      tz.setSign(scanner.next().value == 0x2B ? 1 : -1);
      if (scanner.peek().isFixedLengthNumber(4)) {
        // The hhmm extension.
        final hourMinute = scanner.next().value;
        final hour = hourMinute ~/ 100;
        final minute = hourMinute % 100;
        if (!_Time.isHour(hour) || !_Time.isMinute(minute)) {
          return _Token.invalid;
        }
        tz.hour = hour;
        tz.minute = minute;
      } else {
        if (!scanner.peek().isFixedLengthNumber(2) ||
            !_Time.isHour(scanner.peek().value)) {
          return _Token.invalid;
        }
        tz.hour = scanner.next().value;
        if (!scanner.skipSymbol(0x3A)) return _Token.invalid;
        if (!scanner.peek().isFixedLengthNumber(2) ||
            !_Time.isMinute(scanner.peek().value)) {
          return _Token.invalid;
        }
        tz.minute = scanner.next().value;
      }
    }
    if (!scanner.peek().isEndOfInput) return _Token.invalid;
  }
  // Date-only forms without an offset are UTC; date-time forms are local.
  if (tz.isEmpty && time.isEmpty) tz.set(0);
  day.setIsoDate();
  return _Token.endOfInput;
}
