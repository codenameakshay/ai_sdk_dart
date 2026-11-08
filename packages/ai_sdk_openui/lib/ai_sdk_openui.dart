/// OpenUI Lang 1.0 in pure Dart: parse a streamed program, evaluate it with
/// local state and tools, and generate the system prompt that teaches it.
library;

export 'src/lang/merge.dart' show mergeStatements;
export 'src/lang/message.dart' show ParsedMessage, buildMessage, parseMessage;
export 'src/runtime/errors.dart'
    show OpenUiError, OpenUiErrorCode, OpenUiErrorSource;
export 'src/runtime/form_validation.dart'
    show
        ParsedRule,
        ValidatorFn,
        builtInValidators,
        parseRules,
        parseStructuredRules,
        validate;
export 'src/runtime/mcp.dart' show McpToolError, extractToolResult;
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
export 'src/runtime/session.dart'
    show
        ActionEvent,
        FieldState,
        OpenUiAction,
        OpenUiBinding,
        OpenUiElement,
        OpenUiSession,
        Props;
export 'src/lang/js.dart' show jsString;
