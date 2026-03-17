/// Controls how/whether the model calls tools.
sealed class LanguageModelV3ToolChoice {
  const LanguageModelV3ToolChoice();
}

/// The model decides whether and which tools to call (default).
class ToolChoiceAuto extends LanguageModelV3ToolChoice {
  const ToolChoiceAuto();
}

/// The model must not call any tools.
class ToolChoiceNone extends LanguageModelV3ToolChoice {
  const ToolChoiceNone();
}

/// The model must call at least one tool.
class ToolChoiceRequired extends LanguageModelV3ToolChoice {
  const ToolChoiceRequired();
}

/// The model must call the specified tool.
class ToolChoiceSpecific extends LanguageModelV3ToolChoice {
  const ToolChoiceSpecific({required this.toolName});

  final String toolName;
}
