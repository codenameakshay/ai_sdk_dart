// coverage:ignore-file
// Platform glue: a native web view, which flutter_test cannot create. The
// policy it applies lives in html_document.dart, which is tested.
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'html_document.dart';

/// Whether this platform can show a web view.
bool get canHostWebPages => WebViewPlatform.instance != null;

/// A model-written page: JavaScript on, every navigation after the first
/// load blocked, and one channel that only reports the content height.
Widget htmlPageHost({
  required String document,
  required ValueChanged<double> onHeight,
}) => _NativePage(document: document, onHeight: onHeight);

/// A YouTube embed that may only navigate within YouTube's own hosts.
Widget youTubeHost({
  required String id,
  required String title,
  String? referrer,
}) => _NativeYouTube(id: id, referrer: referrer);

class _NativePage extends StatefulWidget {
  const _NativePage({required this.document, required this.onHeight});
  final String document;
  final ValueChanged<double> onHeight;
  @override
  State<_NativePage> createState() => _NativePageState();
}

class _NativePageState extends State<_NativePage> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(const Color(0x00000000))
    ..addJavaScriptChannel(
      'IuiHeight',
      onMessageReceived: (m) {
        final h = clampHeight(m.message);
        if (mounted && h != null) widget.onHeight(h);
      },
    )
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            !_loaded && request.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) => _loaded = true,
      ),
    )
    ..loadHtmlString(widget.document);
  bool _loaded = false;

  @override
  void didUpdateWidget(_NativePage old) {
    super.didUpdateWidget(old);
    if (old.document != widget.document) {
      _loaded = false;
      _controller.loadHtmlString(widget.document);
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

class _NativeYouTube extends StatefulWidget {
  const _NativeYouTube({required this.id, this.referrer});
  final String id;
  final String? referrer;
  @override
  State<_NativeYouTube> createState() => _NativeYouTubeState();
}

class _NativeYouTubeState extends State<_NativeYouTube> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && uri.scheme == 'https' && isYouTubeHost(uri.host)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ),
    )
    ..loadRequest(
      Uri.parse('https://www.youtube-nocookie.com/embed/${widget.id}'),
      headers: _headers(widget.referrer),
    );

  static Map<String, String> _headers(String? referrer) => {
    'Referer': referrer ?? 'https://www.youtube-nocookie.com/',
  };

  @override
  void didUpdateWidget(_NativeYouTube old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.referrer != widget.referrer) {
      _controller.loadRequest(
        Uri.parse('https://www.youtube-nocookie.com/embed/${widget.id}'),
        headers: _headers(widget.referrer),
      );
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
