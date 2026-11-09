import '../../runtime/money.dart';
import '../../spec/library.dart';
import '../../spec/schema.dart';

/// `@FormatMoney(amount)`: an exact `Money` amount as text, in the session's
/// locale. Add it with `library.extend(LibraryExtension(addFunctions: [formatMoney]))`.
final FunctionSpec formatMoney = FunctionSpec(
  'FormatMoney',
  description:
      'An exact money amount {minor, currency} or {amount: "12.34", currency} as text, e.g. \$123.45',
  params: {'amount': S.any()},
  returns: S.string(),
  fn: (a) => Money.parse(a['amount']).format(),
  localized: (a, locale) => Money.parse(a['amount']).format(locale: locale),
);
