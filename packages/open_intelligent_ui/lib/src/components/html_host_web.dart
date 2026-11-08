// coverage:ignore-file
// Platform glue for Flutter web: real sandboxed iframes, as the reference uses.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'html_document.dart';

bool get canHostWebPages => true;

/// The page in an `<iframe sandbox="allow-scripts">` with an opaque origin:
/// no access to this app, its cookies or storage, no forms, popups or
/// navigation of the app. The frame reports its height by postMessage.
Widget htmlPageHost({
  required String document,
  required ValueChanged<double> onHeight,
}) => _WebFrame(document: document, onHeight: onHeight);

/// The YouTube embed with the reference's sandbox and permissions.
Widget youTubeHost({
  required String id,
  required String title,
  String? referrer,
}) => HtmlElementView.fromTagName(
  tagName: 'iframe',
  onElementCreated: (element) {
    final frame = element as web.HTMLIFrameElement
      ..src = 'https://www.youtube-nocookie.com/embed/$id'
      ..title = title
      ..allow =
          'accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen'
      ..referrerPolicy = 'strict-origin-when-cross-origin';
    frame.setAttribute(
      'sandbox',
      'allow-scripts allow-same-origin allow-presentation allow-popups',
    );
    frame.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
  },
);

class _WebFrame extends StatefulWidget {
  const _WebFrame({required this.document, required this.onHeight});
  final String document;
  final ValueChanged<double> onHeight;
  @override
  State<_WebFrame> createState() => _WebFrameState();
}

class _WebFrameState extends State<_WebFrame> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener = ((web.MessageEvent event) {
    if (_frame == null || event.source != _frame!.contentWindow) return;
    final data = event.data;
    if (data == null || !data.isA<JSObject>()) return;
    final obj = data as JSObject;
    if (obj.getProperty<JSAny?>('type'.toJS)?.dartify() !=
        'iui-html-view-height') {
      return;
    }
    final h = clampHeight(obj.getProperty<JSAny?>('height'.toJS)?.dartify());
    if (h != null) widget.onHeight(h);
  }).toJS;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _listener);
  }

  @override
  void didUpdateWidget(_WebFrame old) {
    super.didUpdateWidget(old);
    if (old.document != widget.document) _frame?.srcdoc = widget.document.toJS;
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = _frame = element as web.HTMLIFrameElement;
      frame
        ..setAttribute('sandbox', 'allow-scripts')
        ..referrerPolicy = 'no-referrer'
        ..srcdoc = widget.document.toJS;
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%';
    },
  );
}
