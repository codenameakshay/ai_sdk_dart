import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../view.dart';
import 'glyph.dart';
import 'html_document.dart';
import 'html_host.dart' as host;
import 'media.dart';

/// `HtmlView(html, height?, title?)`: a sandboxed page for games and canvas.
Widget buildHtmlView(BuildContext context, OpenUiNode node) {
  final raw = node.props.number('height');
  return HtmlPage(
    html: node.props.string('html') ?? '',
    fixedHeight: raw != null && raw > 0
        ? raw.toDouble().clamp(htmlViewMinHeight, htmlViewMaxHeight)
        : null,
    title: node.props.string('title'),
    streaming: node.isStreaming,
  );
}

class HtmlPage extends StatefulWidget {
  const HtmlPage({
    super.key,
    required this.html,
    required this.streaming,
    this.fixedHeight,
    this.title,
  });
  final String html;
  final bool streaming;
  final double? fixedHeight;
  final String? title;

  @override
  State<HtmlPage> createState() => _HtmlPageState();
}

class _HtmlPageState extends State<HtmlPage> {
  double? _measured;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final title = widget.title == null || widget.title!.isEmpty
        ? 'Interactive view'
        : widget.title!;
    final Widget body;
    if (widget.streaming) {
      // A page that is still streaming would reload on every chunk.
      body = Center(
        child: Text(
          'Preparing the interactive view…',
          style: TextStyle(fontSize: 13, color: theme.muted),
        ),
      );
    } else if (host.canHostWebPages) {
      body = host.htmlPageHost(
        document: htmlViewDocument(
          widget.html,
          dark: theme.brightness == Brightness.dark,
          report: identical(0, 0.0)
              ? HeightReport.parent
              : HeightReport.channel,
        ),
        onHeight: widget.fixedHeight != null
            ? (_) {}
            : (h) => setState(() => _measured = h),
      );
    } else {
      body = _Unsupported(
        icon: 'app-window',
        title: title,
        note: 'This interactive view runs on Android, iOS, macOS and the web.',
      );
    }
    return Semantics(
      container: true,
      label: title,
      child: Container(
        height: widget.fixedHeight ?? _measured ?? htmlViewStartHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.canvas,
          border: Border.all(color: theme.border),
          borderRadius: BorderRadius.circular(OpenUiTheme.radiusLg),
        ),
        child: body,
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({
    required this.icon,
    required this.title,
    required this.note,
  });
  final String icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Glyph(icon, size: 24, color: theme.muted),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: theme.ink),
              ),
              const SizedBox(height: 4),
              Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: theme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `YouTube(video, title?)`: an embedded video by id or URL. Where no web
/// view runs, a thumbnail that opens the video.
Widget buildYouTube(BuildContext context, OpenUiNode node) {
  final id = youTubeId(jsString(node.props['video'] ?? ''));
  if (id == null) return const SizedBox.shrink();
  final title = node.props.string('title');
  final label = title == null || title.isEmpty ? 'YouTube video' : title;
  final Widget body = host.canHostWebPages
      ? host.youTubeHost(
          id: id,
          title: label,
          referrer: node.services.embedReferrer,
        )
      : Semantics(
          button: true,
          label: 'Play $label',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => node.services.openUrl(
              Uri.parse('https://www.youtube.com/watch?v=$id'),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Photo(
                  query: '',
                  src: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
                  aspectRatio: 16 / 9,
                  radius: 0,
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Glyph(
                      'play',
                      size: 22,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  return AspectRatio(
    aspectRatio: 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(OpenUiTheme.radiusLg),
      child: ColoredBox(color: const Color(0xFF000000), child: body),
    ),
  );
}
