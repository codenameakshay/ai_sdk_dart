import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import 'form_validation.dart';
import 'services.dart';
import 'theme.dart';

/// Builds one component from its evaluated element.
typedef OpenUiBuilder = Widget Function(BuildContext context, OpenUiNode node);

/// Looks up the builder for a component name; null renders nothing.
typedef OpenUiBuilderLookup = OpenUiBuilder? Function(String typeName);

/// Renders an [OpenUiSession]'s evaluated tree and routes its events, like
/// react-lang's `Renderer`.
///
/// `@OpenUrl` goes to [OpenUiServices.openUrl], `@CopyToClipboard` to
/// [OpenUiServices.copyText], `@ToAssistant` (and a Button without an action)
/// to [onToAssistant]; every other library action goes to [onAction].
///
/// Without a [child], the content shows dimmed with [queryLoader] (else a
/// spinner) while a Query loads. A [child] composes [OpenUiContent],
/// [OpenUiQueryLoading], [OpenUiQueryError] and [OpenUiRetry] around the same
/// session, like `Renderer.Root` and its slots.
class OpenUiView extends StatefulWidget {
  const OpenUiView({
    super.key,
    required this.session,
    required this.builders,
    this.onToAssistant,
    this.onAction,
    this.queryLoader,
    this.child,
    this.fallbackServices = const OpenUiServices(),
  });

  final OpenUiSession session;
  final OpenUiBuilderLookup builders;
  final ValueChanged<ActionEvent>? onToAssistant;
  final ValueChanged<ActionEvent>? onAction;

  /// Shown while a Query loads, in place of the default spinner.
  final Widget? queryLoader;

  /// Slot composition; null shows the default content.
  final Widget? child;

  /// Services for whatever the nearest OpenUiScope leaves unset (see
  /// OpenUiServices.orElse).
  final OpenUiServices fallbackServices;

  /// react-lang `useRendererQuery`: the nearest view's Query state.
  static OpenUiQueryState queryOf(BuildContext context) =>
      _RendererScope.of(context).query;

  @override
  State<OpenUiView> createState() => _OpenUiViewState();
}

class _OpenUiViewState extends State<OpenUiView> {
  void Function()? _cancel;
  OpenUiServices? _ambient, _fallback;
  late OpenUiServices _services;

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

  void _emit(ActionEvent event) {
    final services = _services;
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
    final ambient =
        context.dependOnInheritedWidgetOfExactType<OpenUiScope>()?.services ??
        const OpenUiServices();
    if (!identical(ambient, _ambient) ||
        !identical(widget.fallbackServices, _fallback)) {
      _ambient = ambient;
      _fallback = widget.fallbackServices;
      _services = ambient.orElse(widget.fallbackServices);
    }
    return OpenUiScope(
      services: _services,
      child: _RendererScope(
        root: session.root,
        query: OpenUiQueryState._(
          isLoading: session.isQueryLoading,
          errors: session.queryErrors,
          retry: session.retryQueries,
        ),
        queryLoader: widget.queryLoader,
        child: _RuntimeScope(
          session: session,
          builders: widget.builders,
          emit: _emit,
          child: widget.child ?? const _DefaultContent(),
        ),
      ),
    );
  }
}

/// react-lang `RendererQueryState`: the Query loading, failures and retry of
/// the nearest [OpenUiView].
final class OpenUiQueryState {
  const OpenUiQueryState._({
    required this.isLoading,
    required this.errors,
    required this.retry,
  });

  /// Whether a Query is waiting for generation or fetching data.
  final bool isLoading;

  /// The failed Queries' errors.
  final List<OpenUiError> errors;

  /// Retries the failed Queries, or every Query when none failed.
  final VoidCallback retry;

  /// A Query failed and is loading again.
  bool get isRetrying => errors.isNotEmpty && isLoading;
}

class _RendererScope extends InheritedWidget {
  const _RendererScope({
    required this.root,
    required this.query,
    required this.queryLoader,
    required super.child,
  });
  final OpenUiElement? root;
  final OpenUiQueryState query;
  final Widget? queryLoader;

  static _RendererScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RendererScope>() ??
      (throw FlutterError(
        'OpenUiView slots must be used within an OpenUiView.',
      ));

  // Fields read the store while building, so every view update reaches the slots.
  @override
  bool updateShouldNotify(_RendererScope old) => true;
}

Widget _rootView(BuildContext context, OpenUiElement root) {
  final theme = OpenUiTheme.of(context);
  return DefaultTextStyle.merge(
    style: TextStyle(fontFamily: theme.fontFamily, color: theme.ink),
    child: OpenUiElementView(element: root),
  );
}

class _QueryLoader extends StatelessWidget {
  const _QueryLoader();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      semanticsLabel: 'Loading data',
    ),
  );
}

/// react-lang's default content: dimmed while a Query loads, with the
/// view's queryLoader above it, else a spinner in its top corner.
class _DefaultContent extends StatelessWidget {
  const _DefaultContent();

  @override
  Widget build(BuildContext context) {
    final scope = _RendererScope.of(context);
    final root = scope.root;
    if (root == null) return const SizedBox.shrink();
    final loading = scope.query.isLoading;
    final content = AnimatedOpacity(
      opacity: loading ? 0.7 : 1,
      duration: const Duration(milliseconds: 200),
      child: _rootView(context, root),
    );
    final loader = scope.queryLoader;
    if (loader != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [if (loading) loader, content],
      );
    }
    return Stack(
      children: [
        content,
        if (loading) const Positioned(top: 8, right: 8, child: _QueryLoader()),
      ],
    );
  }
}

/// react-lang `Renderer.Content`: the generated content, dimmed while a
/// Query loads and hidden while a Query failure shows. It stays mounted
/// either way.
class OpenUiContent extends StatelessWidget {
  const OpenUiContent({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = _RendererScope.of(context);
    final root = scope.root;
    if (root == null) return const SizedBox.shrink();
    final query = scope.query;
    return Visibility(
      visible: query.errors.isEmpty,
      maintainState: true,
      child: AnimatedOpacity(
        opacity: query.isLoading ? 0.7 : 1,
        duration: const Duration(milliseconds: 200),
        child: _rootView(context, root),
      ),
    );
  }
}

/// react-lang `Renderer.QueryLoading`: [child] (else the view's queryLoader,
/// else a spinner) while a Query loads, except while a Query failure shows.
class OpenUiQueryLoading extends StatelessWidget {
  const OpenUiQueryLoading({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scope = _RendererScope.of(context);
    final query = scope.query;
    if (!query.isLoading || query.errors.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return child ?? scope.queryLoader ?? const _QueryLoader();
  }
}

/// react-lang `Renderer.QueryError`: [child] while a Query has failed.
class OpenUiQueryError extends StatelessWidget {
  const OpenUiQueryError({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      OpenUiView.queryOf(context).errors.isEmpty
      ? const SizedBox.shrink()
      : child ?? const SizedBox.shrink();
}

/// react-lang `Renderer.Retry`: a button that retries the failed Queries. It
/// is disabled while a Query loads, when none failed, or when not [enabled].
class OpenUiRetry extends StatelessWidget {
  const OpenUiRetry({
    super.key,
    required this.child,
    this.onPressed,
    this.enabled = true,
  });
  final Widget child;

  /// Called before the retry.
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final query = OpenUiView.queryOf(context);
    final disabled = !enabled || query.isLoading || query.errors.isEmpty;
    return TextButton(
      onPressed: disabled
          ? null
          : () {
              onPressed?.call();
              query.retry();
            },
      child: child,
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
/// element keeps showing its last good widget, and the error goes to the
/// session's `onError` as a `render-error`, as react-lang's error boundary
/// reports it. Errors thrown while building the widgets a builder returns
/// stay with Flutter's own handler: Flutter catches each widget's build
/// error itself, so only a global hook could see them.
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
      runtime.session.reportRenderError(widget.element.typeName, error);
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

  /// react-lang `useIsQueryLoading`: whether a Query is loading.
  bool get isQueryLoading => _session.isQueryLoading;

  /// react-lang `useGetFieldValue`: field [name] of form [formName], or the
  /// top-level field [name] without one.
  Object? fieldValue(String name, {String? formName}) =>
      _session.fieldValue(name, formName: formName);

  /// react-lang `useSetDefaultValue`: after this frame, once the answer has
  /// settled, stores [defaultValue] for field [name] of the enclosing Form
  /// unless it has a value. Call it while building.
  void setDefaultValue(
    String name,
    Object? defaultValue, {
    String? componentType,
  }) {
    final session = _session;
    final formName = this.formName;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => session.setDefaultValue(
        name,
        defaultValue,
        formName: formName,
        componentType: componentType,
      ),
    );
  }

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
