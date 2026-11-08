import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

/// A program from the reference gallery.
final class GalleryProgram {
  const GalleryProgram({
    required this.id,
    required this.title,
    required this.note,
    required this.code,
  });
  final String id;
  final String title;
  final String note;
  final String code;
}

final class GallerySection {
  const GallerySection(this.title, this.programs);
  final String title;
  final List<GalleryProgram> programs;
}

/// The gallery's sections, in the reference's order.
List<GallerySection> gallerySections(String json) {
  final data = jsonDecode(json) as Map<String, Object?>;
  List<GalleryProgram> read(String key) => [
    for (final p in (data[key] as List).cast<Map<String, Object?>>())
      GalleryProgram(
        id: p['id'] as String,
        title: (p['title'] as String?) ?? (p['id'] as String),
        note: (p['note'] as String?) ?? '',
        code: p['code'] as String,
      ),
  ];
  return [
    GallerySection('Composition', read('compositionPrograms')),
    GallerySection('Working tools', [
      ...read('toolPrograms'),
      ...read('examples'),
    ]),
    GallerySection('Components', read('programs')),
  ];
}

void main() => runApp(const GalleryApp());

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, this.programs});

  /// The gallery JSON; read from the bundled asset when null.
  final String? programs;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  ThemeMode _mode = ThemeMode.light;
  bool _online = false;
  late final Future<List<GallerySection>> _sections = widget.programs != null
      ? Future.value(gallerySections(widget.programs!))
      : rootBundle
            .loadString('assets/gallery_programs.json')
            .then(gallerySections);
  final _search = WikimediaImageSearch();
  final _route = OsrmStreetRoute();

  @override
  Widget build(BuildContext context) {
    final services = _online
        ? OpenUiServices(searchImages: _search.call, streetRoute: _route.call)
        : const OpenUiServices(mapTiles: null);
    return MaterialApp(
      title: 'Open Intelligent UI',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0285FF),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF0285FF),
        brightness: Brightness.dark,
      ),
      builder: (context, child) =>
          OpenUiScope(services: services, child: child!),
      home: FutureBuilder(
        future: _sections,
        builder: (context, snapshot) => GalleryHome(
          sections: snapshot.data ?? const [],
          dark: _mode == ThemeMode.dark,
          online: _online,
          onDark: (v) =>
              setState(() => _mode = v ? ThemeMode.dark : ThemeMode.light),
          onOnline: (v) => setState(() => _online = v),
        ),
      ),
    );
  }
}

class GalleryHome extends StatelessWidget {
  const GalleryHome({
    super.key,
    required this.sections,
    required this.dark,
    required this.online,
    required this.onDark,
    required this.onOnline,
  });
  final List<GallerySection> sections;
  final bool dark;
  final bool online;
  final ValueChanged<bool> onDark;
  final ValueChanged<bool> onOnline;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Component gallery'),
      actions: [
        IconButton(
          tooltip: dark ? 'Light theme' : 'Dark theme',
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
          onPressed: () => onDark(!dark),
        ),
      ],
    ),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Hand-written OpenUI Lang 1.0 programs rendered by this port with the Intelligent UI library: '
            '${intelligentUi.components.length} components and ${intelligentUi.functions.length} functions.',
          ),
        ),
        SwitchListTile(
          title: const Text('Online services'),
          subtitle: const Text(
            'Photos from Wikimedia, street routes from OSRM and map tiles',
          ),
          value: online,
          onChanged: onOnline,
        ),
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              section.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final p in section.programs)
            ListTile(
              title: Text(p.title),
              subtitle: p.note.isEmpty
                  ? null
                  : Text(p.note, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProgramPage(program: p),
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

/// One gallery program, rendered with the demo data tools.
class ProgramPage extends StatefulWidget {
  const ProgramPage({super.key, required this.program});
  final GalleryProgram program;

  @override
  State<ProgramPage> createState() => _ProgramPageState();
}

class _ProgramPageState extends State<ProgramPage> {
  late final OpenUiSession _session = OpenUiSession(
    intelligentUi,
    tools: demoTools(),
  )..update(widget.program.code, streaming: false);

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _notice(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.program.title),
      actions: [
        IconButton(
          tooltip: 'OpenUI Lang source',
          icon: const Icon(Icons.code),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  widget.program.code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: OpenUiView(
        session: _session,
        builders: intelligentUiBuilders,
        onToAssistant: (e) {
          final context = e.params['context'];
          _notice(
            'Sent to the assistant: “${e.humanFriendlyMessage}”${context != null ? ' with ${jsonEncode(context)}' : ''}',
          );
        },
        onAction: (e) {
          if (e.type == 'CopyToClipboard') _notice('Copied to the clipboard');
        },
      ),
    ),
  );
}
