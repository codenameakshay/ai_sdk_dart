import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'js_date.dart';
import 'shared.dart';
import 'unicode.dart';

const _dayMs = 86400000;

// JavaScript's Date range, 8.64e15 ms, in whole days.
const _maxDay = 100000000;

// Past this every date is out of range; clamping keeps int arithmetic from overflowing.
const _wholeLimit = 1000000000;

final _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

const _formats = {
  'short': 'MMM d',
  'weekday': 'EEE',
  'time': 'h:mm a',
  'datetime': 'MMM d, h:mm a',
};

/// The UTC midnight of a calendar day (days since 1970-01-01).
DateTime utcDay(int day) {
  if (day.abs() > _maxDay) throw StateError('date out of range');
  return DateTime.fromMillisecondsSinceEpoch(day * _dayMs, isUtc: true);
}

/// Days since 1970-01-01 of a calendar date, as `Date.UTC(year, month - 1,
/// day) / DAY`: months and days past their range roll over, and a year from
/// 0 to 99 means 1900 to 1999.
int dayOf(int year, int month, int day) {
  final y = year >= 0 && year <= 99 ? year + 1900 : year;
  final days = makeDay(y.toDouble(), (month - 1).toDouble(), day.toDouble());
  if (!(days.abs() <= _maxDay)) throw StateError('date out of range');
  return days.toInt();
}

/// A date as a calendar day plus, for a timestamp or date-time, the instant.
/// "YYYY-MM-DD" is a calendar date with no time zone; other dates are read in
/// the viewer's time zone, as `new Date(value)` reads them.
({int day, DateTime? instant}) parseDate(Object value) {
  if (value is String) {
    final m = _dateOnly.firstMatch(jsTrim(value));
    if (m != null) {
      final y = int.parse(m[1]!);
      final mo = int.parse(m[2]!);
      final d = int.parse(m[3]!);
      final day = dayOf(y, mo, d);
      final (_, cm, cd) = _ymd(day);
      if (cm != mo || cd != d) throw StateError('invalid date "$value"');
      return (day: day, instant: null);
    }
  }
  final ms = switch (value) {
    String() => jsDateParse(value, Impure.fromLocal),
    num() when value.isFinite && value.abs() <= 8.64e15 =>
      value.truncateToDouble(),
    _ => double.nan,
  };
  if (ms.isNaN) throw StateError('invalid date "$value"');
  final instant = DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true);
  final local = Impure.toLocal(instant);
  return (day: dayOf(local.year, local.month, local.day), instant: instant);
}

/// The `YYYY-MM-DD` of a calendar day, as `toISOString().slice(0, 10)`
/// writes it: years outside 0 to 9999 get a sign and six digits.
String isoDay(int day) {
  final d = utcDay(day);
  final year = d.year >= 0 && d.year <= 9999
      ? d.year.toString().padLeft(4, '0')
      : '${d.year < 0 ? '-' : '+'}${d.year.abs().toString().padLeft(6, '0')}';
  String two(int n) => n.toString().padLeft(2, '0');
  return '$year-${two(d.month)}-${two(d.day)}'.substring(0, 10);
}

/// en-US `toLocaleString` of [at] for a FormatDate style. A year at or
/// before 0 shows as its era year (0 is 1, -1 is 2), as Intl writes it.
String _formatDate(DateTime at, String style) {
  final year = at.year <= 0 ? 1 - at.year : at.year;
  return switch (style) {
    'date' => '${DateFormat('MMM d', 'en_US').format(at)}, $year',
    'long' => '${DateFormat('EEEE, MMMM d', 'en_US').format(at)}, $year',
    'month' => '${DateFormat('MMM', 'en_US').format(at)} $year',
    _ => DateFormat(_formats[style]!, 'en_US').format(at),
  };
}

/// Year, month (1-12) and day of a calendar day.
(int, int, int) _ymd(int day) {
  final d = utcDay(day);
  return (d.year, d.month, d.day);
}

int _whole(Object? n) => (n as num).clamp(-_wholeLimit, _wholeLimit).truncate();

final List<FunctionSpec> dateFunctions = [
  FunctionSpec(
    'Now',
    description: 'The current date and time as an ISO string',
    params: {},
    returns: S.string(),
    fn: (_) => DateTime.fromMillisecondsSinceEpoch(
      Impure.now().millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String(),
  ),
  FunctionSpec(
    'Today',
    description: 'Today\'s date in the viewer\'s time zone, as "YYYY-MM-DD"',
    params: {},
    returns: S.string(),
    fn: (_) => isoDay(parseDate(Impure.now().millisecondsSinceEpoch).day),
  ),
  FunctionSpec(
    'FormatDate',
    description:
        'A date as text: "date" Oct 9, 2026 (default), "short" Oct 9, "long" Friday, October 9, 2026, "weekday" Fri, "month" Oct 2026, "time" 9:30 PM, "datetime", "iso" 2026-10-09. Dates are "YYYY-MM-DD", ISO or a timestamp',
    params: {
      'date': date(),
      'style': S.oneOf([
        'date',
        'short',
        'long',
        'weekday',
        'month',
        'time',
        'datetime',
        'iso',
      ]).optional(),
    },
    returns: S.string(),
    fn: (a) {
      final parsed = parseDate(a['date']!);
      final style = a['style'] as String? ?? 'date';
      if (style == 'iso') return isoDay(parsed.day);
      final instant = parsed.instant;
      // A calendar date formats in UTC so its day never shifts with the viewer's zone.
      final at = instant == null ? utcDay(parsed.day) : Impure.toLocal(instant);
      return _formatDate(at, style);
    },
  ),
  FunctionSpec(
    'AddDays',
    description: 'The date days later (negative: earlier), as "YYYY-MM-DD"',
    params: {'date': date(), 'days': S.number()},
    returns: S.string(),
    fn: (a) => isoDay(parseDate(a['date']!).day + _whole(a['days'])),
  ),
  FunctionSpec(
    'AddMonths',
    description:
        'The date months later (negative: earlier), kept within the month (Jan 31 + 1 is Feb 28), as "YYYY-MM-DD"; 12 months is a year',
    params: {'date': date(), 'months': S.number()},
    returns: S.string(),
    fn: (a) {
      final (y, m, d) = _ymd(parseDate(a['date']!).day);
      final target = m + _whole(a['months']);
      final last = _ymd(dayOf(y, target + 1, 0)).$3;
      return isoDay(dayOf(y, target, math.min(d, last)));
    },
  ),
  FunctionSpec(
    'DaysBetween',
    description:
        'Calendar days from one date to another (negative if to is earlier)',
    params: {'from': date(), 'to': date()},
    returns: S.number(),
    fn: (a) => parseDate(a['to']!).day - parseDate(a['from']!).day,
  ),
  FunctionSpec(
    'MonthsBetween',
    description:
        'Whole months from one date to another (negative if to is earlier); @Floor(@MonthsBetween(birthday, @Today()) / 12) is an age',
    params: {'from': date(), 'to': date()},
    returns: S.number(),
    fn: (a) {
      final (y1, m1, d1) = _ymd(parseDate(a['from']!).day);
      final (y2, m2, d2) = _ymd(parseDate(a['to']!).day);
      var months = (y2 - y1) * 12 + (m2 - m1);
      if (months > 0 && d2 < d1) months -= 1;
      if (months < 0 && d2 > d1) months += 1;
      return months;
    },
  ),
  FunctionSpec(
    'StartOf',
    description:
        'First day of the date\'s "week" (Monday), "month" or "year", as "YYYY-MM-DD"',
    params: {
      'date': date(),
      'unit': S.oneOf(['week', 'month', 'year']),
    },
    returns: S.string(),
    fn: (a) {
      final day = parseDate(a['date']!).day;
      final unit = a['unit'] as String;
      if (unit == 'week') return isoDay(day - (utcDay(day).weekday - 1));
      final (y, m, _) = _ymd(day);
      return isoDay(dayOf(y, unit == 'month' ? m : 1, 1));
    },
  ),
];
