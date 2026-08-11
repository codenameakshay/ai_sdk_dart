/// Structured warning surfaced by a language model provider.
sealed class LanguageModelV4Warning {
  const LanguageModelV4Warning();

  String get type;
}

class LanguageModelV4UnsupportedWarning extends LanguageModelV4Warning {
  const LanguageModelV4UnsupportedWarning({
    // coverage:ignore-line
    required this.feature,
    this.details,
  });

  @override
  String get type => 'unsupported'; // coverage:ignore-line

  final String feature;
  final String? details;
}

class LanguageModelV4CompatibilityWarning extends LanguageModelV4Warning {
  const LanguageModelV4CompatibilityWarning({
    // coverage:ignore-line
    required this.feature,
    this.details,
  });

  @override
  String get type => 'compatibility'; // coverage:ignore-line

  final String feature;
  final String? details;
}

class LanguageModelV4DeprecatedWarning extends LanguageModelV4Warning {
  const LanguageModelV4DeprecatedWarning({
    // coverage:ignore-line
    required this.setting,
    required this.message,
  });

  @override
  String get type => 'deprecated';

  final String setting;
  final String message;
}

class LanguageModelV4OtherWarning extends LanguageModelV4Warning {
  const LanguageModelV4OtherWarning({
    required this.message,
  }); // coverage:ignore-line

  @override
  String get type => 'other'; // coverage:ignore-line

  final String message;
}
