import 'package:flutter/material.dart';

import 'pages/completion_page.dart';
import 'pages/embeddings_page.dart';
import 'pages/image_gen_page.dart';
import 'pages/multimodal_page.dart';
import 'pages/object_stream_page.dart';
import 'pages/provider_chat_page.dart';
import 'pages/stt_page.dart';
import 'pages/tools_chat_page.dart';
import 'pages/tts_page.dart';
import 'pages/widget_gallery_page.dart';

void main() {
  runApp(const App());
}

enum AdvancedExamplePage {
  providerChat,
  toolsChat,
  imageGen,
  multimodal,
  embeddings,
  tts,
  stt,
  completion,
  objectStream,
  widgetGallery,
}

class App extends StatelessWidget {
  const App({super.key, this.initialPage, this.initialToolsFixture});

  final AdvancedExamplePage? initialPage;
  final ToolsChatFixture? initialToolsFixture;

  @override
  Widget build(BuildContext context) {
    final routePage = initialPage ?? _initialPageFromUri();
    final toolsFixture =
        initialToolsFixture ?? _initialToolsFixtureFromUri(routePage);
    final page =
        routePage ??
        (toolsFixture == null
            ? AdvancedExamplePage.providerChat
            : AdvancedExamplePage.toolsChat);

    return MaterialApp(
      title: 'AI SDK Dart Advanced',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'advanced-app',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _Shell(initialPage: page, initialToolsFixture: toolsFixture),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.initialPage, required this.initialToolsFixture});

  final AdvancedExamplePage initialPage;
  final ToolsChatFixture? initialToolsFixture;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with RestorationMixin {
  late final RestorableInt _selectedIndex;
  ToolsChatFixture? _initialToolsFixture;

  static const _navItems = [
    _NavItem(
      AdvancedExamplePage.providerChat,
      'Provider Chat',
      Icons.swap_horiz,
    ),
    _NavItem(AdvancedExamplePage.toolsChat, 'Tools Chat', Icons.build),
    _NavItem(AdvancedExamplePage.imageGen, 'Image Gen', Icons.image),
    _NavItem(AdvancedExamplePage.multimodal, 'Multimodal', Icons.photo_camera),
    _NavItem(AdvancedExamplePage.embeddings, 'Embeddings', Icons.psychology),
    _NavItem(
      AdvancedExamplePage.tts,
      'Text-to-Speech',
      Icons.record_voice_over,
    ),
    _NavItem(AdvancedExamplePage.stt, 'Speech-to-Text', Icons.mic),
    _NavItem(AdvancedExamplePage.completion, 'Completion', Icons.edit_note),
    _NavItem(
      AdvancedExamplePage.objectStream,
      'Object Stream',
      Icons.data_object,
    ),
    _NavItem(
      AdvancedExamplePage.widgetGallery,
      'Widget Gallery',
      Icons.widgets_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = RestorableInt(_navItemsIndex(widget.initialPage));
    _initialToolsFixture = widget.initialPage == AdvancedExamplePage.toolsChat
        ? widget.initialToolsFixture
        : null;
  }

  @override
  String? get restorationId => 'advanced-shell';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedIndex, 'selected-index');
    if (_navItems[_selectedIndex.value].page != AdvancedExamplePage.toolsChat) {
      _initialToolsFixture = null;
    }
  }

  @override
  void dispose() {
    _selectedIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_navItems[_selectedIndex.value].label)),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF6750A4)),
              child: Text(
                'AI SDK Advanced',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ...List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              return ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                selected: _selectedIndex.value == i,
                onTap: () {
                  setState(() {
                    _selectedIndex.value = i;
                    if (item.page != AdvancedExamplePage.toolsChat) {
                      _initialToolsFixture = null;
                    }
                  });
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
      body: _buildPage(_navItems[_selectedIndex.value].page),
    );
  }

  Widget _buildPage(AdvancedExamplePage page) {
    return switch (page) {
      AdvancedExamplePage.providerChat => const ProviderChatPage(),
      AdvancedExamplePage.toolsChat => ToolsChatPage(
        fixture: _initialToolsFixture,
      ),
      AdvancedExamplePage.imageGen => const ImageGenPage(),
      AdvancedExamplePage.multimodal => const MultimodalPage(),
      AdvancedExamplePage.embeddings => const EmbeddingsPage(),
      AdvancedExamplePage.tts => const TtsPage(),
      AdvancedExamplePage.stt => const SttPage(),
      AdvancedExamplePage.completion => const CompletionPage(),
      AdvancedExamplePage.objectStream => const ObjectStreamPage(),
      AdvancedExamplePage.widgetGallery => const WidgetGalleryPage(),
    };
  }
}

class _NavItem {
  const _NavItem(this.page, this.label, this.icon);

  final AdvancedExamplePage page;
  final String label;
  final IconData icon;
}

int _navItemsIndex(AdvancedExamplePage page) =>
    _ShellState._navItems.indexWhere((item) => item.page == page);

AdvancedExamplePage? _initialPageFromUri() {
  final page = Uri.base.queryParameters['page'];
  return switch (page) {
    'provider-chat' => AdvancedExamplePage.providerChat,
    'tools-chat' => AdvancedExamplePage.toolsChat,
    'image-gen' => AdvancedExamplePage.imageGen,
    'multimodal' => AdvancedExamplePage.multimodal,
    'embeddings' => AdvancedExamplePage.embeddings,
    'tts' => AdvancedExamplePage.tts,
    'stt' => AdvancedExamplePage.stt,
    'completion' => AdvancedExamplePage.completion,
    'object-stream' => AdvancedExamplePage.objectStream,
    'widget-gallery' => AdvancedExamplePage.widgetGallery,
    _ => null,
  };
}

ToolsChatFixture? _initialToolsFixtureFromUri(AdvancedExamplePage? page) {
  if (page != null && page != AdvancedExamplePage.toolsChat) return null;
  final state = Uri.base.queryParameters['state'];
  return switch (state) {
    'normal' => ToolsChatFixture.normal,
    'approval' => ToolsChatFixture.approval,
    'error' => ToolsChatFixture.error,
    'sources-tool' => ToolsChatFixture.sourcesTool,
    'long-history' => ToolsChatFixture.longHistory,
    _ => null,
  };
}
