/// Structured warning surfaced by a language model provider.
sealed class LanguageModelV4Warning {
  const LanguageModelV4Warning();

  String get type;
}

class LanguageModelV4UnsupportedWarning extends LanguageModelV4Warning {
  const LanguageModelV4UnsupportedWarning({
    required this.feature,
    this.details,
  });

  @override
  String get type => 'unsupported';

  final String feature;
  final String? details;
}

class LanguageModelV4CompatibilityWarning extends LanguageModelV4Warning {
  const LanguageModelV4CompatibilityWarning({
    required this.feature,
    this.details,
  });

  @override
  String get type => 'compatibility';

  final String feature;
  final String? details;
}

class LanguageModelV4DeprecatedWarning extends LanguageModelV4Warning {
  const LanguageModelV4DeprecatedWarning({
    required this.setting,
    required this.message,
  });

  @override
  String get type => 'deprecated';

  final String setting;
  final String message;
}

class LanguageModelV4OtherWarning extends LanguageModelV4Warning {
  const LanguageModelV4OtherWarning({required this.message});

  @override
  String get type => 'other';

  final String message;
}
