import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

/// What a test sees after pumping a program.
final class Pumped {
  Pumped(this.session, this.events, this.copied, this.opened);
  final OpenUiSession session;

  /// Every `@ToAssistant` and library action event, in order.
  final List<ActionEvent> events;
  final List<String> copied;
  final List<Uri> opened;
}

/// Pumps [program] through the real session and builders, in a phone-sized
/// Material app with the given [brightness].
Future<Pumped> pumpProgram(
  WidgetTester tester,
  String program, {
  Brightness brightness = Brightness.light,
  List<OpenUiTool> tools = const [],
  Map<String, Object?> initialState = const {},
  OpenUiServices? services,
  bool streaming = false,
  OpenUiTheme? theme,
  TextDirection textDirection = TextDirection.ltr,
  bool semanticsIdentifiers = false,
  OpenUiLibrary? library,
  String? locale,
}) async {
  final session = OpenUiSession(
    library ?? intelligentUi,
    tools: tools,
    initialState: initialState,
    locale: locale,
  )..update(program, streaming: streaming);
  addTearDown(session.dispose);
  final events = <ActionEvent>[];
  final copied = <String>[];
  final opened = <Uri>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: theme == null
          ? ThemeData(brightness: brightness)
          : ThemeData(brightness: brightness, extensions: [theme]),
      home: OpenUiScope(
        services:
            services ??
            OpenUiServices(
              copyText: (text) async => copied.add(text),
              openUrl: (url) async => opened.add(url),
              mapTiles: null,
              imageLoader: networkImages,
            ),
        child: Scaffold(
          body: Directionality(
            textDirection: textDirection,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: OpenUiView(
                session: session,
                builders: intelligentUiBuilders,
                onToAssistant: events.add,
                onAction: events.add,
                semanticsIdentifiers: semanticsIdentifiers,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return Pumped(session, events, copied, opened);
}
