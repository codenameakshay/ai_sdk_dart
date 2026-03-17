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

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI SDK Dart Advanced',
      debugShowCheckedModeBanner: false,
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
      home: const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _selectedIndex = 0;

  static const _navItems = [
    _NavItem('Provider Chat', Icons.swap_horiz, ProviderChatPage()),
    _NavItem('Tools Chat', Icons.build, ToolsChatPage()),
    _NavItem('Image Gen', Icons.image, ImageGenPage()),
    _NavItem('Multimodal', Icons.photo_camera, MultimodalPage()),
    _NavItem('Embeddings', Icons.psychology, EmbeddingsPage()),
    _NavItem('Text-to-Speech', Icons.record_voice_over, TtsPage()),
    _NavItem('Speech-to-Text', Icons.mic, SttPage()),
    _NavItem('Completion', Icons.edit_note, CompletionPage()),
    _NavItem('Object Stream', Icons.data_object, ObjectStreamPage()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_navItems[_selectedIndex].label),
      ),
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
                selected: _selectedIndex == i,
                onTap: () {
                  setState(() => _selectedIndex = i);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
      body: _navItems[_selectedIndex].page,
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.page);

  final String label;
  final IconData icon;
  final Widget page;
}
