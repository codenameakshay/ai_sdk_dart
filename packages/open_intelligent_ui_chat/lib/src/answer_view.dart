import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/widgets.dart';

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

/// Renders one answer of an [OpenUiAnswers] by its message [id]: its program,
/// or its text as prose when a finished message is not a program.
///
/// Build it after the first `update` for [id]; the view follows the session
/// from then on, switching between program and prose as its text changes.
class OpenUiAnswerView extends StatefulWidget {
  const OpenUiAnswerView({
    super.key,
    required this.answers,
    required this.id,
    this.builders,
    this.onToAssistant,
    this.onAction,
    this.fallbackServices = const OpenUiServices(),
  });

  final OpenUiAnswers answers;
  final String id;

  /// Defaults to [openUiCoreBuilders].
  final OpenUiBuilderLookup? builders;

  /// Receives `@ToAssistant` turns.
  final ValueChanged<ActionEvent>? onToAssistant;

  /// Library actions the view does not handle itself.
  final ValueChanged<ActionEvent>? onAction;

  /// Services wherever the app's scope leaves them unset.
  final OpenUiServices fallbackServices;

  @override
  State<OpenUiAnswerView> createState() => _OpenUiAnswerViewState();
}

class _OpenUiAnswerViewState extends State<OpenUiAnswerView> {
  OpenUiSession? _session;
  void Function()? _cancel;

  @override
  void initState() {
    super.initState();
    _bind(widget.answers.sessionOf(widget.id));
  }

  @override
  void didUpdateWidget(OpenUiAnswerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.answers, widget.answers) ||
        oldWidget.id != widget.id) {
      _bind(widget.answers.sessionOf(widget.id));
    }
  }

  void _bind(OpenUiSession? session) {
    if (identical(_session, session)) return;
    _cancel?.call();
    _session = session;
    _cancel = session?.listen(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answers = widget.answers;
    final session = answers.sessionOf(widget.id);
    if (!identical(_session, session)) _bind(session);
    final text = answers.textOf(widget.id);
    if (session == null || text == null) return const SizedBox.shrink();
    final content = parseMessage(text).content;
    if (!answers.isStreaming(widget.id) &&
        session.root == null &&
        content.trim().isNotEmpty) {
      return AssistantMessageView(
        message: ModelMessage(
          role: ModelMessageRole.assistant,
          content: content,
        ),
      );
    }
    return OpenUiView(
      session: session,
      builders: widget.builders ?? openUiCoreBuilders,
      onToAssistant: widget.onToAssistant,
      onAction: widget.onAction,
      fallbackServices: widget.fallbackServices,
    );
  }
}
