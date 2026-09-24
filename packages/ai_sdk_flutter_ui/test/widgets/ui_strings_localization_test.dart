import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _localized(Widget child) => MaterialApp(
  home: AiSdkUiStringsScope(
    strings: AiSdkUiStrings(
      copyMessage: 'Copier',
      toolApprovalRequired: (tool) => 'Autoriser $tool',
      toolCall: (tool) => 'Appel $tool',
      documentSource: (title) => 'Source $title',
      document: (mediaType) => 'Document $mediaType',
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('uses localized action and dynamic accessibility labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _localized(
        Column(
          children: [
            MessageActionsBar(copyText: 'text'),
            ToolApprovalCard(
              request: const LanguageModelV4ToolApprovalRequestPart(
                approvalId: 'a1',
                toolCall: LanguageModelV4ToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'deleteFile',
                  input: {},
                ),
              ),
              onApprove: (_) {},
              onDeny: (_) {},
            ),
            const ToolCallCard(
              call: LanguageModelV4ToolCallPart(
                toolCallId: 'c2',
                toolName: 'search',
                input: {},
              ),
            ),
          ],
        ),
      ),
    );

    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('message-copy')))
          .getSemanticsData()
          .label,
      'Copier',
    );
    expect(find.bySemanticsLabel('Autoriser deleteFile'), findsOneWidget);
    expect(find.bySemanticsLabel('Appel search'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('uses localized document source semantics and tooltip', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _localized(
        const AssistantMessageView(
          message: ModelMessage.parts(
            role: ModelMessageRole.assistant,
            parts: [
              LanguageModelV4DocumentSourcePart(
                id: 'doc-1',
                mediaType: 'application/pdf',
                title: 'Report',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Source Report'), findsOneWidget);
    expect(find.byTooltip('Document application/pdf'), findsOneWidget);
    semantics.dispose();
  });
}
