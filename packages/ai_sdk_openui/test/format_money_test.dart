import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Test output';
  @override
  Map<String, Schema> get props => {'value': S.any()};
}

OpenUiSession _open(FunctionSpec fn, String expr, {String? locale}) {
  final lib = OpenUiLibrary(
    root: const _Out(),
    components: const [_Out()],
    functions: [fn],
  );
  final s = OpenUiSession(
    lib,
    locale: locale,
    records: [
      BoundRecord('order', {
        'total': {'minor': 12345600, 'currency': 'INR'},
        'fee': {'minor': 4550, 'currency': 'INR'},
      }),
    ],
  )..update('root = Out($expr)', streaming: false);
  addTearDown(s.dispose);
  return s;
}

void main() {
  test('a bound-only @FormatMoney formats a bound amount', () {
    final s = _open(
      formatMoneyWith(boundOnly: true),
      r'@FormatMoney($order.total)',
      locale: 'en_IN',
    );
    expect(s.errors, isEmpty);
    expect(s.root!.props['value'], '₹1,23,456.00');
  });

  test('a bound-only @FormatMoney rejects an amount the model wrote', () {
    final s = _open(
      formatMoneyWith(boundOnly: true),
      '@FormatMoney({minor: 100, currency: "INR"})',
    );
    expect(s.root!.props['value'], isNull);
    expect(s.errors.map((e) => e.code), contains(OpenUiErrorCode.boundOnly));
  });

  test('the default @FormatMoney still takes a written amount', () {
    final s = _open(formatMoney, '@FormatMoney({minor: 100, currency: "INR"})');
    expect(s.errors, isEmpty);
    expect(s.root!.props['value'], '₹1.00');
    expect(formatMoney.params['amount']!.isBoundOnly, isFalse);
  });

  test('@FormatMoney can drop an all-zero fraction', () {
    final fn = formatMoneyWith(trimZeroFraction: true);
    expect(
      _open(
        fn,
        r'@FormatMoney($order.total)',
        locale: 'en_IN',
      ).root!.props['value'],
      '₹1,23,456',
    );
    expect(
      _open(
        fn,
        r'@FormatMoney($order.fee)',
        locale: 'en_IN',
      ).root!.props['value'],
      '₹45.50',
    );
    expect(
      _open(fn, r'@FormatMoney($order.total)').root!.props['value'],
      '₹123,456',
    );
  });

  test('@FormatMoney gives nothing for an unknown currency', () {
    final s = _open(formatMoney, '@FormatMoney({minor: 100, currency: "XYZ"})');
    expect(s.root!.props['value'], isNull);
  });
}
