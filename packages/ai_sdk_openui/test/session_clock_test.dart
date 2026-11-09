import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/iui/functions/dates.dart';
import 'package:ai_sdk_openui/src/iui/functions/js_date.dart';
import 'package:ai_sdk_openui/src/iui/functions/numbers.dart';
import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

/// A one-prop component: each expression runs through the real parser,
/// evaluator and session, with the session's clock and time zone.
final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Test output';
  @override
  Map<String, Schema> get props => {'value': S.any()};
}

final OpenUiLibrary _lib = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  functions: [...dateFunctions, ...numberFunctions],
);

OpenUiSession _session({
  DateTime Function()? clock,
  double Function()? random,
  OpenUiTimeZone? timeZone,
}) {
  final s = OpenUiSession(
    _lib,
    clock: clock,
    random: random,
    timeZone: timeZone,
  );
  addTearDown(s.dispose);
  return s;
}

Object? _value(OpenUiSession s, String expr) {
  s.update('root = Out($expr)', streaming: false);
  return s.root!.props['value'];
}

final _instant = DateTime.utc(2026, 11, 9, 18, 45);
final _kolkata = OpenUiTimeZone.fixed(const Duration(hours: 5, minutes: 30));
final _newYork = OpenUiTimeZone.fixed(const Duration(hours: -5));

void main() {
  test('two sessions format the same program in their own clock and zone', () {
    final india = _session(clock: () => _instant, timeZone: _kolkata);
    final us = _session(
      clock: () => _instant.add(const Duration(days: 1)),
      timeZone: _newYork,
    );
    const program = '@FormatDate(@Now(), "datetime")';
    expect(_value(india, program), 'Nov 10, 12:15 AM');
    expect(_value(us, program), 'Nov 10, 1:45 PM');
    expect(_value(india, '@Today()'), '2026-11-10');
    expect(_value(us, '@Today()'), '2026-11-10');
    expect(_value(india, '@Now()'), '2026-11-09T18:45:00.000Z');
  });

  test('a session reads a zone-less date string in its own zone', () {
    const program = '@DaysBetween("2026-10-09T02:00Z", "2026-10-09T02:00")';
    expect(_value(_session(timeZone: _kolkata), program), 0);
    expect(_value(_session(timeZone: _newYork), program), 1);
    expect(_value(_session(timeZone: OpenUiTimeZone.utc), program), 0);
  });

  test('a session draws from its own random source', () {
    const program = '@Random(1, 10, true)';
    expect(_value(_session(random: () => 0), program), 1);
    expect(_value(_session(random: () => 0.999), program), 10);
  });

  test('a session without a clock or zone uses the process defaults', () {
    Impure.now = () => _instant;
    Impure.useUtc();
    addTearDown(Impure.reset);
    expect(_value(_session(), '@FormatDate(@Now(), "time")'), '6:45 PM');
    expect(
      _value(_session(timeZone: _kolkata), '@FormatDate(@Now(), "time")'),
      '12:15 AM',
    );
  });

  test('a zone whose offset changes reads wall-clock times as JavaScript', () {
    // Europe/London in 2026: +01:00 from Mar 29 01:00Z to Oct 25 01:00Z.
    final london = OpenUiTimeZone(
      (utc) =>
          !utc.isBefore(DateTime.utc(2026, 3, 29, 1)) &&
              utc.isBefore(DateTime.utc(2026, 10, 25, 1))
          ? const Duration(hours: 1)
          : Duration.zero,
    );
    int at(String text) => Impure.run(
      timeZone: london,
      () => jsDateParse(text, Impure.fromLocal),
    ).toInt();
    int utc(int month, int day, int hour, [int minute = 0]) =>
        DateTime.utc(2026, month, day, hour, minute).millisecondsSinceEpoch;
    expect(at('2026-03-28T12:00'), utc(3, 28, 12));
    expect(at('2026-03-30T12:00'), utc(3, 30, 11));
    // 01:30 is skipped: it reads with the earlier offset, so 02:30 BST.
    expect(at('2026-03-29T01:30'), utc(3, 29, 1, 30));
    // 01:30 happens twice: the earlier instant, 01:30 BST.
    expect(at('2026-10-25T01:30'), utc(10, 25, 0, 30));
    expect(
      Impure.run(
        timeZone: london,
        () => Impure.toLocal(DateTime.utc(2026, 3, 30, 11)).hour,
      ),
      12,
    );
  });

  test('a session clock applies only inside that session', () {
    final s = _session(clock: () => _instant, random: () => 0);
    expect(_value(s, '@Random(1, 10, true)'), 1);
    expect(Impure.now(), isNot(_instant));
  });

  test('an unconfigured session does not inherit another session clock', () {
    final defaultInstant = DateTime.utc(2030);
    Impure.now = () => defaultInstant;
    addTearDown(Impure.reset);
    final unconfigured = _session();
    final actual = Impure.run(
      now: () => _instant,
      () => _value(unconfigured, '@Now()'),
    );
    expect(actual, '2030-01-01T00:00:00.000Z');
  });

  test(
    'impure inputs stay isolated across asynchronous continuations',
    () async {
      Impure.now = () => DateTime.utc(2030);
      Impure.random = () => 0.25;
      Impure.useUtc();
      addTearDown(Impure.reset);
      await Impure.run(
        now: () => _instant,
        random: () => 0.75,
        timeZone: _kolkata,
        () async {
          await Future<void>.delayed(Duration.zero);
          expect(Impure.now(), _instant);
          expect(Impure.random(), 0.75);
          await Impure.run(() async {
            await Future<void>.delayed(Duration.zero);
            expect(Impure.now(), DateTime.utc(2030));
            expect(Impure.random(), 0.25);
            expect(Impure.toLocal(_instant), _instant);
          });
          expect(Impure.toLocal(_instant), DateTime.utc(2026, 11, 10, 0, 15));
        },
      );
    },
  );

  test('a localized session formats in its own zone', () {
    final s = OpenUiSession(
      _lib,
      locale: 'en_GB',
      clock: () => _instant,
      timeZone: _kolkata,
    );
    addTearDown(s.dispose);
    expect(_value(s, '@FormatDate(@Now(), "date")'), '10 Nov 2026');
    expect(s.localNow, DateTime.utc(2026, 11, 10, 0, 15));
  });

  test('answers give each message session the same clock and zone', () {
    final answers = OpenUiAnswers(
      library: _lib,
      clock: () => _instant,
      random: () => 0,
      timeZone: _newYork,
    );
    addTearDown(answers.dispose);
    final s = answers.update(
      'm1',
      'root = Out(@FormatDate(@Now(), "datetime"))',
      streaming: false,
    );
    expect(s.root!.props['value'], 'Nov 9, 1:45 PM');
    expect(
      answers
          .update('m2', 'root = Out(@Random(1, 10, true))', streaming: false)
          .root!
          .props['value'],
      1,
    );
  });
}
