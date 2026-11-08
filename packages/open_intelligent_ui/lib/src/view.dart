import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import 'form_validation.dart';
import 'services.dart';
import 'theme.dart';

/// Builds one component from its evaluated element.
typedef OpenUiBuilder = Widget Function(BuildContext context, OpenUiNode node);

/// Looks up the builder for a component name; null renders nothing.
typedef OpenUiBuilderLookup = OpenUiBuilder? Function(String typeName);

/// Renders an [OpenUiSession]'s evaluated tree and routes its events.
///
/// `@OpenUrl` goes to [OpenUiServices.openUrl], `@CopyToClipboard` to
/// [OpenUiServices.copyText], `@ToAssistant` (and a Button without an action)
/// to [onToAssistant]; every other library action goes to [onAction].
class OpenUiView extends StatefulWidget {
  const OpenUiView({
    super.key,
    required this.session,
    required this.builders,
    this.onToAssistant,
    this.onAction,
  });

  final OpenUiSession session;
  final OpenUiBuilderLookup builders;
  final ValueChanged<ActionEvent>? onToAssistant;
  final ValueChanged<ActionEvent>? onAction;

  @override
  State<OpenUiView> createState() => _OpenUiViewState();
}

class _OpenUiViewState extends State<OpenUiView> {
  void Function()? _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = widget.session.listen(_changed);
  }

  @override
  void didUpdateWidget(OpenUiView old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _cancel?.call();
      _cancel = widget.session.listen(_changed);
    }
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _emit(BuildContext context, ActionEvent event) {
    final services = OpenUiScope.servicesOf(context);
    switch (event.type) {
      case ActionEvent.continueConversation:
        widget.onToAssistant?.call(event);
      case ActionEvent.openUrl:
        final uri = webUri(event.params['url']);
        if (uri != null) services.openUrl(uri);
      case 'CopyToClipboard':
        final text = event.params['text'];
        if (text is String) services.copyText(text);
        widget.onAction?.call(event);
      default:
        widget.onAction?.call(event);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final root = session.root;
    if (root == null) return const SizedBox.shrink();
    final loading = session.isQueryLoading;
    final theme = OpenUiTheme.of(context);
    final content = DefaultTextStyle.merge(
      style: TextStyle(fontFamily: theme.fontFamily, color: theme.ink),
      child: _RuntimeScope(
        session: session,
        builders: widget.builders,
        emit: (event) => _emit(context, event),
        child: OpenUiElementView(element: root),
      ),
    );
    return Stack(
      children: [
        AnimatedOpacity(
          opacity: loading ? 0.7 : 1,
          duration: const Duration(milliseconds: 200),
          child: content,
        ),
        if (loading)
          const Positioned(
            top: 8,
            right: 8,
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Loading data',
              ),
            ),
          ),
      ],
    );
  }
}

/// The http(s) URL in [value], or null. Other schemes never open.
Uri? webUri(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty
      ? uri
      : null;
}

class _RuntimeScope extends InheritedWidget {
  const _RuntimeScope({
    required this.session,
    required this.builders,
    required this.emit,
    required super.child,
  });
  final OpenUiSession session;
  final OpenUiBuilderLookup builders;
  final void Function(ActionEvent) emit;

  static _RuntimeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RuntimeScope>() ??
      (throw FlutterError('OpenUiElementView needs an OpenUiView above it.'));

  @override
  bool updateShouldNotify(_RuntimeScope old) =>
      !identical(session, old.session) || !identical(builders, old.builders);
}

class _FormScope extends InheritedWidget {
  const _FormScope({
    required this.name,
    required this.validation,
    required super.child,
  });
  final String name;
  final OpenUiFormValidation validation;

  @override
  bool updateShouldNotify(_FormScope old) =>
      name != old.name || !identical(validation, old.validation);
}

/// Owns one Form's [OpenUiFormValidation] for as long as the Form is mounted.
class _FormHost extends StatefulWidget {
  const _FormHost({required this.name, required this.child});
  final String name;
  final Widget child;

  @override
  State<_FormHost> createState() => _FormHostState();
}

class _FormHostState extends State<_FormHost> {
  final _validation = OpenUiFormValidation();

  @override
  void dispose() {
    _validation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormScope(
    name: widget.name,
    validation: _validation,
    child: widget.child,
  );
}

int _nextFieldId = 0;

/// Renders one element through its builder. If the builder throws, the
/// element keeps showing its last good widget.
class OpenUiElementView extends StatefulWidget {
  const OpenUiElementView({super.key, required this.element});
  final OpenUiElement element;

  @override
  State<OpenUiElementView> createState() => _OpenUiElementViewState();
}

class _OpenUiElementViewState extends State<OpenUiElementView> {
  final String _id = 'field-${_nextFieldId++}';
  Widget? _lastGood;

  @override
  Widget build(BuildContext context) {
    final runtime = _RuntimeScope.of(context);
    final builder = runtime.builders(widget.element.typeName);
    if (builder == null) return const SizedBox.shrink();
    final node = OpenUiNode._(
      element: widget.element,
      session: runtime.session,
      emit: runtime.emit,
      context: context,
      generatedId: _id,
    );
    try {
      return _lastGood = builder(context, node);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'open_intelligent_ui',
          context: ErrorDescription('building ${widget.element.typeName}'),
        ),
      );
      return _lastGood ?? const SizedBox.shrink();
    }
  }
}

/// What a component builder reads: its props, the theme, services, and the
/// runtime operations (render children, bind fields, run actions).
final class OpenUiNode {
  OpenUiNode._({
    required this.element,
    required OpenUiSession session,
    required void Function(ActionEvent) emit,
    required BuildContext context,
    required String generatedId,
  }) : _session = session,
       _emit = emit,
       _context = context,
       _generatedId = generatedId;

  final OpenUiElement element;
  final OpenUiSession _session;
  final void Function(ActionEvent) _emit;
  final BuildContext _context;
  final String _generatedId;

  Props get props => element.props;
  OpenUiTheme get theme => OpenUiTheme.of(_context);
  OpenUiServices get services => OpenUiScope.servicesOf(_context);

  /// While the model is still writing, actions wait.
  bool get isStreaming => _session.isStreaming;

  /// The enclosing Form's name, if any.
  String? get formName =>
      _context.dependOnInheritedWidgetOfExactType<_FormScope>()?.name;

  /// The enclosing Form's validation, if any.
  OpenUiFormValidation? get formValidation =>
      _context.dependOnInheritedWidgetOfExactType<_FormScope>()?.validation;

  /// Renders a value: an element, text, a number (as JavaScript prints it),
  /// or a list of them (flattened).
  List<Widget> render(Object? value) => [..._render(value)];

  Iterable<Widget> _render(Object? value) sync* {
    switch (value) {
      case null:
        return;
      case OpenUiElement():
        yield OpenUiElementView(element: value);
      case List():
        for (final v in value) {
          yield* _render(v);
        }
      case String() || num() || bool():
        yield Text(jsString(value));
      default:
        return;
    }
  }

  /// [render] of one prop.
  List<Widget> children([String prop = 'children']) => render(props[prop]);

  /// A field's value and setter. A `$binding` prop writes its `$variable`;
  /// otherwise it is a form field named [name], else this element's
  /// statement id, else a stable generated id.
  FieldState field(String prop, {String? name}) => _session.field(
    name ?? element.statementId ?? _generatedId,
    props[prop],
    formName: formName,
    componentType: element.typeName,
  );

  /// Runs the action in [prop]. With no action and [sendLabel], the [label]
  /// goes to the assistant, like a Button without an action.
  void run(String prop, {String label = '', bool sendLabel = false}) {
    final action = props.action(prop);
    if (action == null && !sendLabel) return;
    _session.run(action, label: label, formName: formName, emit: _emit);
  }

  /// Whether [prop] holds an action.
  bool hasAction(String prop) => props.action(prop) != null;

  /// Puts [child] in a Form scope named after this element.
  Widget form(Widget child) =>
      _FormHost(name: element.statementId ?? _generatedId, child: child);

  /// Copies [text] with the host's clipboard.
  Future<void> copy(String text) => services.copyText(text);
}

@visibleForTesting
void resetFieldIds() => _nextFieldId = 0;
