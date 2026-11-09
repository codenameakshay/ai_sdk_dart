import 'dart:collection';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/foundation.dart';

import 'localizations.dart';

/// Field errors for one Form: registers fields, validates them, and notifies on change.
final class OpenUiFormValidation extends ChangeNotifier {
  final Map<String, String?> _errors = {};
  final Map<String, ({List<ParsedRule> rules, Object? Function() getValue})>
  _fields = {};

  /// The words of the built-in rules' errors. A Form sets it to the
  /// [OpenUiLocalizations] of its context.
  ValidationMessages messages = const ValidationMessages();

  /// Field name to its error message; null when the field passed.
  Map<String, String?> get errors => UnmodifiableMapView(_errors);

  String? getFieldError(String name) => _errors[name];

  /// Validates [value] against [rules] and stores its error; true when it passes.
  bool validateField(String name, Object? value, List<ParsedRule> rules) {
    final error = validate(value, rules, null, messages);
    if (!_errors.containsKey(name) || _errors[name] != error) {
      _errors[name] = error;
      notifyListeners();
    }
    return error == null;
  }

  void registerField(
    String name,
    List<ParsedRule> rules,
    Object? Function() getValue,
  ) {
    _fields[name] = (rules: rules, getValue: getValue);
  }

  void unregisterField(String name) => _fields.remove(name);

  /// Validates every registered field and replaces all errors; true when all pass.
  bool validateForm() {
    var allValid = true;
    final errors = <String, String?>{};
    for (final entry in _fields.entries) {
      var value = entry.value.getValue();
      // A stored field is `{value}`, with `componentType` when a component gave one.
      if (value is Map && value.containsKey('value')) value = value['value'];
      final error = validate(value, entry.value.rules, null, messages);
      errors[entry.key] = error;
      if (error != null) allValid = false;
    }
    _errors
      ..clear()
      ..addAll(errors);
    notifyListeners();
    return allValid;
  }

  void clearFieldError(String name) {
    if (_errors[name] == null) return;
    _errors[name] = null;
    notifyListeners();
  }
}
