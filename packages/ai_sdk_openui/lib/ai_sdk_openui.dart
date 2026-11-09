/// OpenUI Lang 1.0 in pure Dart: parse a streamed program, evaluate it with
/// local state and tools, and generate the system prompt that teaches it.
library;

export 'src/lang/merge.dart' show mergeStatements;
export 'src/lang/message.dart' show ParsedMessage, buildMessage, parseMessage;
export 'src/lang/parser.dart' show ParseResult;
export 'src/lang/policy.dart'
    show
        UnknownComponentPolicy,
        ValidationIssue,
        ValidationPolicy,
        ValidationReport,
        canonicalJson,
        validateProgram;
export 'src/runtime/action_message.dart' show buildActionUserMessage;
export 'src/runtime/answers.dart'
    show
        OpenUiAnswers,
        OpenUiMessageDone,
        OpenUiMessageEvent,
        OpenUiPatch,
        OpenUiTextDelta,
        OpenUiTextSnapshot,
        messageState,
        messageWithState;
export 'src/runtime/errors.dart'
    show OpenUiError, OpenUiErrorCode, OpenUiErrorSource;
export 'src/runtime/host_actions.dart'
    show
        ActionFailure,
        ActionHandler,
        ActionInvocation,
        ActionPhase,
        ActionResult,
        ActionStatus,
        ActionSuccess;
export 'src/runtime/form_validation.dart'
    show
        ParsedRule,
        ValidationMessages,
        ValidatorFn,
        builtInValidators,
        parseRules,
        parseStructuredRules,
        validate;
export 'src/runtime/mcp.dart' show McpToolError, extractToolResult;
export 'src/runtime/money.dart' show Money;
export 'src/runtime/response_bundle.dart' show ResponseMetadata;
export 'src/spec/bound.dart' show BoundRecord;
export 'src/spec/prompt.dart' show describeBoundRecords;
export 'src/spec/cloud.dart'
    show
        ArtifactKind,
        ArtifactOption,
        CloudPromptOptions,
        artifactTool,
        cloudChatLibraryVersion,
        cloudSystemPrompt,
        reportLibraryVersion,
        slidesLibraryVersion;
export 'src/spec/extend.dart'
    show ComponentAddition, LibraryExtension, OpenUiLibraryExtend;
export 'src/spec/library.dart'
    show
        ActionSpec,
        ComponentDef,
        ComponentGroup,
        ComponentSpec,
        FunctionSpec,
        OpenUiLibrary,
        OpenUiTool,
        ParseReport,
        PromptOptions,
        actionSchema;
export 'src/spec/schema.dart' show S, Schema, Steps;
export 'src/runtime/queries.dart' show ToolNotFoundError;
export 'src/iui/functions/shared.dart' show OpenUiTimeZone;
export 'src/runtime/session.dart'
    show
        ActionEvent,
        FieldState,
        OpenUiAction,
        OpenUiBinding,
        OpenUiElement,
        OpenUiSession,
        Props;
export 'src/lang/js.dart' show jsNumber, jsString;
