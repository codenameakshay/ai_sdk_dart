import 'dart:async';

import 'package:flutter/material.dart';

import '../services.dart';
import '../theme.dart';
import '../view.dart';
import 'glyph.dart';

const _iconSizes = {'sm': 14.0, 'md': 18.0, 'lg': 24.0, 'xl': 32.0};

/// `Icon(name, size?, color?)`.
Widget buildIcon(BuildContext context, OpenUiNode node) => Glyph(
  node.props.string('name'),
  size: _iconSizes[node.props.string('size') ?? 'md'] ?? 18,
  color: node.theme.fg(node.props['color']),
);

/// `SearchImage(query, aspectRatio?, radius?, fit?)`.
Widget buildSearchImage(BuildContext context, OpenUiNode node) => Photo(
  query: node.props.string('query') ?? '',
  aspectRatio: node.props.number('aspectRatio'),
  radius: node.props['radius'],
  fit: node.props.string('fit'),
);

/// `Image(src, alt, aspectRatio?, radius?, fit?)`.
Widget buildImage(BuildContext context, OpenUiNode node) => Photo(
  query: node.props.string('alt') ?? '',
  src: node.props.string('src'),
  aspectRatio: node.props.number('aspectRatio'),
  radius: node.props['radius'],
  fit: node.props.string('fit'),
);

/// Searches made through each [OpenUiServices.searchImages], by query. A
/// failure or an empty answer is retried next time.
final Expando<Map<String, Future<List<Uri>>>> _searches = Expando();

Future<List<Uri>> _search(OpenUiServices services, String query) {
  final search = services.searchImages!;
  final cache = _searches[search] ??= {};
  final hit = cache[query];
  if (hit != null) return hit;
  final request = search(query).then(
    (urls) {
      final https = [
        for (final u in urls)
          if (u.scheme == 'https' || u.scheme == 'http') u,
      ];
      final unique = [
        ...{...https},
      ];
      if (unique.isEmpty) cache.remove(query);
      return unique;
    },
    onError: (Object _) {
      cache.remove(query);
      return <Uri>[];
    },
  );
  if (cache.length > 200) cache.remove(cache.keys.first);
  return cache[query] = request;
}

/// Marks a photo as a media row's photo, which the reference shows at 4:3.
class MediaRowSlot extends InheritedWidget {
  const MediaRowSlot({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaRowSlot>() != null;

  @override
  bool updateShouldNotify(MediaRowSlot old) => false;
}

/// A photo from [src], or, without one or when it fails, the best search
/// result for [query]. The query waits 500ms to settle: it may still stream.
class Photo extends StatefulWidget {
  const Photo({
    super.key,
    required this.query,
    this.src,
    this.aspectRatio,
    this.radius,
    this.fit,
  });
  final String query;
  final String? src;
  final num? aspectRatio;
  final Object? radius;
  final String? fit;

  @override
  State<Photo> createState() => _PhotoState();
}

class _PhotoState extends State<Photo> {
  final Set<Uri> _failed = {};
  String? _searched;
  List<Uri>? _found;
  Timer? _debounce;

  Uri? get _src => webUri(widget.src);
  String get _alt => widget.query.trim();
  bool get _needSearch =>
      (_src == null || _failed.contains(_src)) && _alt.length > 2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(Photo old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.src != widget.src) _schedule();
  }

  void _schedule() {
    final services = OpenUiScope.servicesOf(context);
    if (!_needSearch || services.searchImages == null || _searched == _alt) {
      return;
    }
    _debounce?.cancel();
    final query = _alt;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final found = await _search(services, query);
      if (mounted && _alt == query) {
        setState(() {
          _searched = query;
          _found = found;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final services = OpenUiScope.servicesOf(context);
    final found = _searched == _alt ? _found : null;
    final candidates = [?_src, ...?found];
    final current = candidates.where((u) => !_failed.contains(u)).firstOrNull;
    final settled =
        current == null &&
        (!_needSearch || services.searchImages == null || found != null);
    final ratio =
        widget.aspectRatio != null &&
            widget.aspectRatio! > 0.2 &&
            widget.aspectRatio! < 5
        ? widget.aspectRatio!.toDouble()
        : 1.5;
    final radius =
        OpenUiTheme.radius(widget.radius ?? 'lg') ?? OpenUiTheme.radiusLg;
    final Widget content;
    if (current != null) {
      content = Image.network(
        current.toString(),
        key: ValueKey(current),
        fit: widget.fit == 'contain' ? BoxFit.contain : BoxFit.cover,
        semanticLabel: _alt,
        frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
          opacity: sync || frame != null ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: child,
        ),
        errorBuilder: (context, error, stack) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _failed.add(current));
              _schedule();
            }
          });
          return const SizedBox.expand();
        },
      );
    } else {
      content = Semantics(
        label: _alt,
        image: true,
        child: settled
            ? Center(child: Glyph('image', size: 28, color: theme.borderStrong))
            : const SizedBox.expand(),
      );
    }
    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: theme.surface,
          child: SizedBox.expand(child: content),
        ),
      ),
    );
  }
}
