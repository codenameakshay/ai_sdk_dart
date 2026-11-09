import '../../runtime/money.dart';
import '../../spec/library.dart';
import '../../spec/schema.dart';

/// `@FormatMoney(amount)`: an exact `Money` amount as text, in the session's
/// locale. Add it with `library.extend(LibraryExtension(addFunctions: [formatMoney]))`.
final FunctionSpec formatMoney = formatMoneyWith();

/// `@FormatMoney` with options. [boundOnly] takes the amount only from a
/// host-bound record (`$order.total`), never one the model wrote.
/// [trimZeroFraction] writes `₹1,23,456` for `₹1,23,456.00`.
FunctionSpec formatMoneyWith({
  bool boundOnly = false,
  bool trimZeroFraction = false,
}) => FunctionSpec(
  'FormatMoney',
  description:
      'An exact money amount {minor, currency} or {amount: "12.34", currency} as text, e.g. \$123.45',
  params: {'amount': boundOnly ? S.any().boundOnly() : S.any()},
  returns: S.string(),
  fn: (a) =>
      Money.parse(a['amount']).format(trimZeroFraction: trimZeroFraction),
  localized: (a, locale) => Money.parse(
    a['amount'],
  ).format(locale: locale, trimZeroFraction: trimZeroFraction),
);
