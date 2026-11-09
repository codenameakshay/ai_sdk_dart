import '../lang/js.dart';

/// lang-core `createStore`: `$variables` and form fields. Keys still at
/// their declared default are pristine and follow new defaults while the
/// program streams; a key the user changed keeps its value.
final class Store {
  final Map<String, Object?> _state = {};
  final Set<String> _pristine = {};
  final Set<String> _localWrites = {};
  final List<void Function()> _listeners = [];

  Object? get(String name) => _state[name];

  bool has(String name) => _state.containsKey(name);

  /// The state as JSON values (whole numbers as ints, see [Js.normalize]).
  Map<String, Object?> get snapshot =>
      Map.unmodifiable(Js.normalize(_state, json: true)! as Map);

  void set(
    String name,
    Object? value, {
    bool pristine = false,
    bool local = true,
  }) {
    if (local) _localWrites.add(name);
    if (pristine) {
      _pristine.add(name);
    } else {
      _pristine.remove(name);
    }
    final existing = _state[name];
    if (_state.containsKey(name) && Js.objectIs(existing, value)) return;
    if (value is Map && existing is Map && value.length == existing.length) {
      if (value.keys.every(
        (k) => existing.containsKey(k) && Js.objectIs(value[k], existing[k]),
      )) {
        return;
      }
    }
    _state[name] = value;
    _notify();
  }

  /// Restores keys not written locally since this store was created.
  void restoreUntouched(Map<String, Object?> state) {
    initialize(
      const {},
      Map.fromEntries(
        state.entries.where((entry) => !_localWrites.contains(entry.key)),
      ),
    );
  }

  /// Applies declared defaults and persisted values; persisted wins.
  void initialize(
    Map<String, Object?> defaults,
    Map<String, Object?> persisted,
  ) {
    var changed = false;
    for (final MapEntry(:key, :value) in persisted.entries) {
      _pristine.remove(key);
      if (!_state.containsKey(key) || !Js.objectIs(_state[key], value)) {
        _state[key] = value;
        changed = true;
      }
    }
    for (final MapEntry(:key, :value) in defaults.entries) {
      if (!_state.containsKey(key)) {
        _state[key] = value;
        _pristine.add(key);
        changed = true;
      } else if (_pristine.contains(key) && !_sameValue(_state[key], value)) {
        _state[key] = value;
        changed = true;
      }
    }
    if (changed) _notify();
  }

  /// Declared defaults are freshly materialized on every parse, so a list or
  /// object default compares by value here; lang-core's identity check would
  /// see a change on every chunk.
  bool _sameValue(Object? a, Object? b) =>
      Js.objectIs(a, b) || (a is! num && Js.stringify(a) == Js.stringify(b));

  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    for (final l in [..._listeners]) {
      l();
    }
  }

  void dispose() {
    _state.clear();
    _pristine.clear();
    _localWrites.clear();
    _listeners.clear();
  }
}
