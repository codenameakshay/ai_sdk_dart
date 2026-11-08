/// OpenUI Lang 1.0 in pure Dart: parse a streamed program, evaluate it with
/// local state and tools, and generate the system prompt that teaches it.
library;

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
export 'src/spec/schema.dart' show S, Schema;
export 'src/runtime/queries.dart' show ToolNotFound;
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
export 'src/message.dart' show OpenUiMessage;
