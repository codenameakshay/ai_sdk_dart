import 'package:flutter/material.dart';

import 'pages/chat_page.dart';
import 'pages/completion_page.dart';
import 'pages/object_stream_page.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI SDK Dart',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'flutter-chat-app',
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
      home: _Shell(initialIndex: initialIndex),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.initialIndex});

  final int initialIndex;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with RestorationMixin {
  late final RestorableInt _index;

  static final _pages = [
    const ChatPage(),
    const CompletionPage(),
    const ObjectStreamPage(),
  ];

  @override
  void initState() {
    super.initState();
    _index = RestorableInt(widget.initialIndex);
  }

  @override
  String? get restorationId => 'flutter-chat-shell';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_index, 'selected-index');
  }

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index.value],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index.value,
        onDestinationSelected: (i) => setState(() => _index.value = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Completion',
          ),
          NavigationDestination(
            icon: Icon(Icons.data_object_outlined),
            selectedIcon: Icon(Icons.data_object),
            label: 'Object',
          ),
        ],
      ),
    );
  }
}
