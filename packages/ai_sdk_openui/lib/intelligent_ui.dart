/// The Open Intelligent UI component library (a port of
/// thesysdev/open-intelligent-ui at 9df2e64): components, `@functions`,
/// `@CopyToClipboard`, the chat and dashboard prompts, and demo data tools.
library;

export 'src/iui/components.dart' show IuiComponent;
export 'src/iui/demo_tools.dart' show demoTools;
export 'src/iui/actions.dart' show copyToClipboard;
export 'src/iui/library.dart'
    show
        chatPrompt,
        chatPromptFor,
        dashboardPrompt,
        intelligentUi,
        intelligentUiWithout,
        optionalIuiComponents;

export 'src/iui/functions/number_format.dart' show formatDecimal;
