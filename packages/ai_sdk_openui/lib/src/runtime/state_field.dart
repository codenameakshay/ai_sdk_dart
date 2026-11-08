import 'evaluator.dart';
import 'store.dart';

/// lang-core `StateField`: a form field's value and setter, bound to a
/// `$variable` or held by the form.
final class StateField<T> {
  const StateField({
    required this.name,
    required this.value,
    required this.setValue,
    required this.isReactive,
  });
  final String name;
  final T value;
  final void Function(T value) setValue;
  final bool isReactive;
}

/// lang-core `resolveStateField`: a `$binding` ([ReactiveAssign]) reads and
/// writes the store, running its expression with `$value`; any other field
/// reads [fieldGetter] (falling back to [bindingValue]) and writes [fieldSetter].
StateField<T> resolveStateField<T>(
  String name,
  Object? bindingValue,
  Store? store,
  EvaluationContext? context,
  Object? Function(String fieldName) fieldGetter,
  void Function(String fieldName, Object? value) fieldSetter,
) {
  if (bindingValue is ReactiveAssign && store != null && context != null) {
    return StateField(
      name: name,
      value: store.get(bindingValue.target) as T,
      setValue: (value) => store.set(
        bindingValue.target,
        evaluate(
          bindingValue.expr,
          context.copyWith(extraScope: {r'$value': value}),
        ),
      ),
      isReactive: true,
    );
  }
  return StateField(
    name: name,
    value: (fieldGetter(name) ?? bindingValue) as T,
    setValue: (value) => fieldSetter(name, value),
    isReactive: false,
  );
}
