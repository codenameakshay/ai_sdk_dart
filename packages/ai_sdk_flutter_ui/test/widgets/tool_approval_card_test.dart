import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _request = LanguageModelV4ToolApprovalRequestPart(
  approvalId: 'approval_c1',
  toolCall: LanguageModelV4ToolCallPart(
    toolCallId: 'c1',
    toolName: 'deleteFile',
    input: {'path': '/tmp/secret'},
  ),
);

void main() {
  group('ToolApprovalCard', () {
    testWidgets('shows the tool name and pretty-printed input', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ToolApprovalCard(
            request: _request,
            onApprove: (_) {},
            onDeny: (_) {},
          ),
        ),
      );

      expect(find.text('deleteFile'), findsOneWidget);
      expect(find.textContaining('"path": "/tmp/secret"'), findsOneWidget);
    });

    testWidgets('approve button fires onApprove', (tester) async {
      var approved = false;
      String? reason = 'unset';
      await tester.pumpWidget(
        _wrap(
          ToolApprovalCard(
            request: _request,
            onApprove: (r) {
              approved = true;
              reason = r;
            },
            onDeny: (_) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
      expect(approved, isTrue);
      expect(reason, isNull); // no reason field by default
    });

    testWidgets('deny button fires onDeny', (tester) async {
      var denied = false;
      await tester.pumpWidget(
        _wrap(
          ToolApprovalCard(
            request: _request,
            onApprove: (_) {},
            onDeny: (_) => denied = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('tool-approval-deny')));
      expect(denied, isTrue);
    });

    testWidgets('passes the typed reason when a reason field is shown', (
      tester,
    ) async {
      String? captured;
      await tester.pumpWidget(
        _wrap(
          ToolApprovalCard(
            request: _request,
            showReasonField: true,
            onApprove: (r) => captured = r,
            onDeny: (_) {},
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('tool-approval-reason')),
        'looks safe',
      );
      await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
      expect(captured, 'looks safe');
    });

    testWidgets('falls back to toString for non-JSON input', (tester) async {
      final request = LanguageModelV4ToolApprovalRequestPart(
        approvalId: 'a1',
        toolCall: LanguageModelV4ToolCallPart(
          toolCallId: 'c1',
          toolName: 'weird',
          input: const Unencodable(),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ToolApprovalCard(request: request, onApprove: (_) {}, onDeny: (_) {}),
        ),
      );

      expect(find.textContaining('UNENCODABLE'), findsOneWidget);
    });

    testWidgets('uses labels from the inherited strings scope', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AiSdkUiStringsScope(
            strings: const AiSdkUiStrings(
              toolApprovalTitle: 'Werkzeug bestätigen?',
              approve: 'Zulassen',
              deny: 'Ablehnen',
              approvalReasonHint: 'Begründung',
            ),
            child: ToolApprovalCard(
              request: _request,
              showReasonField: true,
              onApprove: (_) {},
              onDeny: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Werkzeug bestätigen?'), findsOneWidget);
      expect(find.text('Zulassen'), findsOneWidget);
      expect(find.text('Ablehnen'), findsOneWidget);
      expect(find.text('Begründung'), findsOneWidget);
    });
  });
}
