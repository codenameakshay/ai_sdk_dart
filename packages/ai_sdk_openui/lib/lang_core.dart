/// The low-level OpenUI Lang API with `@openuidev/lang-core`'s names: lexer, parser, serializer, evaluator,
/// store and query manager.
library;

export 'src/lang/ast.dart'
    show
        Ast,
        astFromJson,
        isAstJson,
        isElementNodeJson,
        ArrNode,
        AssignNode,
        BinOpNode,
        BoolNode,
        CompNode,
        ElementNode,
        IndexNode,
        MemberNode,
        NullNode,
        NumNode,
        ObjNode,
        PlaceholderNode,
        RefNode,
        RuntimeRefNode,
        RuntimeRefType,
        StateRefNode,
        StrNode,
        TernaryNode,
        UnaryOpNode,
        ValueNode,
        walkAst;
export 'src/lang/lexer.dart' show T, Token, parseExpression, tokenize;
export 'src/lang/merge.dart' show mergeStatements;
export 'src/lang/parser.dart'
    show
        CompiledSchema,
        MutationStatementInfo,
        ParseMeta,
        ParseResult,
        Parser,
        QueryStatementInfo,
        StreamParser,
        createParser,
        createStreamingParser,
        parse;
export 'src/lang/serialize.dart' show jsonToOpenUI;
export 'src/lang/statements.dart' show RawStatement, autoClose, split;
export 'src/lang/validation.dart'
    show JsonSchema, ValidationCode, ValidationError;
export 'src/runtime/errors.dart' show enrichErrors;
export 'src/runtime/evaluator.dart'
    show
        ActionPlan,
        ActionStep,
        CustomStep,
        EvaluationContext,
        IsReactiveProp,
        OpenUrlStep,
        ReactiveAssign,
        ResetStep,
        RunStep,
        RuntimeFunction,
        SetStep,
        ToAssistantStep,
        evaluate,
        evaluateElementProps,
        actionSteps,
        evaluateRoot,
        stripReactiveAssign;
export 'src/runtime/queries.dart'
    show
        MutationNode,
        MutationResult,
        QueryManager,
        QueryNode,
        QuerySnapshot,
        ToolCaller,
        ToolProvider,
        createQueryManager;
export 'src/runtime/state_field.dart' show StateField, resolveStateField;
export 'src/runtime/store.dart' show Store;
export 'src/spec/library.dart' show generateSystemPrompt;
export 'src/spec/prompt.dart'
    show PromptEntry, PromptGroup, PromptSpec, PromptTool, generatePrompt;
export 'src/spec/schema.dart' show buildSignature;
