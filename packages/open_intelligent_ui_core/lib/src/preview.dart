import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import 'view.dart';

/// react-lang `RendererPreviewState`: what an [OpenUiPreview] shows, and how
/// to open or close it.
final class OpenUiPreviewState {
  const OpenUiPreviewState._({
    required this.metadata,
    required this.isOpen,
    required this.isStreaming,
    required this.open,
    required this.close,
  });

  /// The response's OpenUI Cloud metadata, such as its `name`.
  final ResponseMetadata metadata;
  final bool isOpen;

  /// Whether the model is still writing the response.
  final bool isStreaming;
  final VoidCallback open;
  final VoidCallback close;
}

/// react-lang `WithPreviewRenderer`: a button that names the response and
/// expands its [view]. The view is built only while the preview is open.
///
/// Pass [open] to control visibility; otherwise the preview keeps it,
/// starting at [defaultOpen].
class OpenUiPreview extends StatefulWidget {
  const OpenUiPreview({
    super.key,
    required this.view,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.onMetadata,
    this.builder,
  });

  final OpenUiView view;
  final bool? open;
  final bool defaultOpen;
  final ValueChanged<bool>? onOpenChange;

  /// Called after the first frame and whenever the response's name changes.
  final ValueChanged<ResponseMetadata>? onMetadata;

  /// Lays out the preview: [content] is [view] while open, else null. Omit
  /// for a trigger button above the content and its close button.
  final Widget Function(
    BuildContext context,
    OpenUiPreviewState preview,
    Widget? content,
  )?
  builder;

  /// react-lang `useRendererPreview`: the nearest preview's state.
  static OpenUiPreviewState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PreviewScope>()?.state ??
      (throw FlutterError('OpenUiPreview.of needs an OpenUiPreview above it.'));

  @override
  State<OpenUiPreview> createState() => _OpenUiPreviewState();
}

class _OpenUiPreviewState extends State<OpenUiPreview> {
  late bool _open = widget.defaultOpen;
  void Function()? _cancel;
  String? _name;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(OpenUiPreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.view.session, widget.view.session)) {
      _cancel?.call();
      _watch();
    }
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  void _watch() {
    final session = widget.view.session;
    _cancel = session.listen(_changed);
    _name = session.metadata.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onMetadata?.call(widget.view.session.metadata);
    });
  }

  void _changed() {
    if (!mounted) return;
    final metadata = widget.view.session.metadata;
    final renamed = metadata.name != _name;
    _name = metadata.name;
    setState(() {});
    if (renamed) widget.onMetadata?.call(metadata);
  }

  bool get _isOpen => widget.open ?? _open;

  void _setOpen(bool next) {
    if (next == _isOpen) return;
    if (widget.open == null) setState(() => _open = next);
    widget.onOpenChange?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.view.session;
    final preview = OpenUiPreviewState._(
      metadata: session.metadata,
      isOpen: _isOpen,
      isStreaming: session.isGenerating,
      open: () => _setOpen(true),
      close: () => _setOpen(false),
    );
    final content = _isOpen ? widget.view : null;
    final builder = widget.builder;
    return _PreviewScope(
      state: preview,
      child: Builder(
        builder: (context) => builder == null
            ? _DefaultPreview(preview: preview, content: content)
            : builder(context, preview, content),
      ),
    );
  }
}

class _DefaultPreview extends StatelessWidget {
  const _DefaultPreview({required this.preview, required this.content});
  final OpenUiPreviewState preview;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final name = preview.metadata.name;
    final title = name == null || name.isEmpty ? 'Untitled artifact' : name;
    final content = this.content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: preview.isOpen,
          child: TextButton(
            onPressed: preview.isOpen ? preview.close : preview.open,
            child: Text('$title${preview.isStreaming ? ' (generating…)' : ''}'),
          ),
        ),
        if (content != null)
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: preview.close,
                  child: Text('Close $title'),
                ),
                content,
              ],
            ),
          ),
      ],
    );
  }
}

class _PreviewScope extends InheritedWidget {
  const _PreviewScope({required this.state, required super.child});
  final OpenUiPreviewState state;

  @override
  bool updateShouldNotify(_PreviewScope old) => true;
}
