import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Finish reason matcher
// ---------------------------------------------------------------------------

/// Matches a [GenerateTextResult] with a specific [expected] finish reason.
Matcher hasFinishReason(LanguageModelV3FinishReason expected) =>
    _FinishReasonMatcher(expected);

class _FinishReasonMatcher extends Matcher {
  const _FinishReasonMatcher(this.expected);

  final LanguageModelV3FinishReason expected;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is GenerateTextResult) return item.finishReason == expected;
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('has finishReason $expected');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is GenerateTextResult) {
      return mismatchDescription.add('had finishReason ${item.finishReason}');
    }
    return mismatchDescription.add('was not a GenerateTextResult');
  }
}

// ---------------------------------------------------------------------------
// Usage matcher
// ---------------------------------------------------------------------------

/// Matches usage fields on a [GenerateTextResult] or [LanguageModelV3Usage].
Matcher hasUsage({int? inputTokens, int? outputTokens, int? totalTokens}) =>
    _UsageMatcher(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: totalTokens,
    );

class _UsageMatcher extends Matcher {
  const _UsageMatcher({this.inputTokens, this.outputTokens, this.totalTokens});

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    LanguageModelV3Usage? usage;
    if (item is GenerateTextResult) {
      usage = item.usage;
    } else if (item is LanguageModelV3Usage) {
      usage = item;
    }
    if (usage == null) return false;
    if (inputTokens != null && usage.inputTokens != inputTokens) return false;
    if (outputTokens != null && usage.outputTokens != outputTokens)
      return false;
    if (totalTokens != null && usage.totalTokens != totalTokens) return false;
    return true;
  }

  @override
  Description describe(Description description) => description.add(
    'has usage (inputTokens: $inputTokens, outputTokens: $outputTokens)',
  );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    LanguageModelV3Usage? usage;
    if (item is GenerateTextResult) usage = item.usage;
    if (item is LanguageModelV3Usage) usage = item;
    return mismatchDescription.add(
      'had usage (inputTokens: ${usage?.inputTokens}, outputTokens: ${usage?.outputTokens})',
    );
  }
}

// ---------------------------------------------------------------------------
// Tool call matcher
// ---------------------------------------------------------------------------

/// Matches a result that contains a tool call with [toolName].
Matcher hasToolCall(String toolName) => _ToolCallMatcher(toolName);

class _ToolCallMatcher extends Matcher {
  const _ToolCallMatcher(this.toolName);

  final String toolName;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    List<LanguageModelV3ToolCallPart>? toolCalls;
    if (item is GenerateTextResult) {
      toolCalls = item.toolCalls;
    } else if (item is List<LanguageModelV3ToolCallPart>) {
      toolCalls = item;
    }
    if (toolCalls == null) return false;
    return toolCalls.any((call) => call.toolName == toolName);
  }

  @override
  Description describe(Description description) =>
      description.add('has tool call "$toolName"');
}

// ---------------------------------------------------------------------------
// Stream events matcher
// ---------------------------------------------------------------------------

/// Matches that a list of events contains an event of [runtimeType].
Matcher containsEventType(Type runtimeType) =>
    _ContainsEventTypeMatcher(runtimeType);

class _ContainsEventTypeMatcher extends Matcher {
  const _ContainsEventTypeMatcher(this.expectedType);

  final Type expectedType;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List) return false;
    return item.any((e) => e.runtimeType == expectedType);
  }

  @override
  Description describe(Description description) =>
      description.add('contains event of type $expectedType');
}

// ---------------------------------------------------------------------------
// AiSdkError matchers
// ---------------------------------------------------------------------------

/// Matches that a Future throws an [AiSdkError] subtype [T].
Matcher throwsAiError<T extends AiSdkError>() => throwsA(isA<T>());

/// Matches that a value is an instance of [AiSdkError].
Matcher isAiSdkError() => isA<AiSdkError>();
