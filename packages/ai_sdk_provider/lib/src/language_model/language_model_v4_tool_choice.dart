/// Controls how/whether the model calls tools.
sealed class LanguageModelV4ToolChoice {
  const LanguageModelV4ToolChoice();
}

/// The model decides whether and which tools to call (default).
class ToolChoiceAuto extends LanguageModelV4ToolChoice {
  const ToolChoiceAuto();
}

/// The model must not call any tools.
class ToolChoiceNone extends LanguageModelV4ToolChoice {
  const ToolChoiceNone();
}

/// The model must call at least one tool.
class ToolChoiceRequired extends LanguageModelV4ToolChoice {
  const ToolChoiceRequired();
}

/// The model must call the specified tool.
class ToolChoiceSpecific extends LanguageModelV4ToolChoice {
  const ToolChoiceSpecific({required this.toolName});

  final String toolName;
}
