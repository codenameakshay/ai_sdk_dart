import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// A valid 1x1 transparent PNG.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  group('MessageImage', () {
    testWidgets('renders byte data via a MemoryImage', (tester) async {
      final bytes = base64Decode(_pngBase64);
      await tester.pumpWidget(
        _wrap(
          MessageImage(
            image: LanguageModelV3ImagePart(image: DataContentBytes(bytes)),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
    });

    testWidgets('renders base64 data via a MemoryImage', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MessageImage(
            image: LanguageModelV3ImagePart(
              image: DataContentBase64(_pngBase64),
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
    });

    testWidgets('renders url data via a NetworkImage', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageImage(
            image: LanguageModelV3ImagePart(
              image: DataContentUrl(Uri.parse('https://example.com/a.png')),
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('falls back to a placeholder when the image fails to decode', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          _wrap(
            MessageImage(
              image: LanguageModelV3ImagePart(
                image: DataContentBytes(Uint8List.fromList(const [1, 2, 3, 4])),
              ),
            ),
          ),
        );
        // Let the (failing) decode complete.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });

  group('MessageAttachment', () {
    testWidgets('renders the filename when present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageAttachment(
            file: LanguageModelV3FilePart(
              data: DataContentUrl(Uri.parse('https://example.com/r.pdf')),
              mediaType: 'application/pdf',
              filename: 'report.pdf',
            ),
          ),
        ),
      );

      expect(find.text('report.pdf'), findsOneWidget);
    });

    testWidgets('falls back to the media type when there is no filename', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MessageAttachment(
            file: LanguageModelV3FilePart(
              data: DataContentUrl(Uri.parse('https://example.com/r.pdf')),
              mediaType: 'application/pdf',
            ),
          ),
        ),
      );

      expect(find.textContaining('application/pdf'), findsOneWidget);
    });

    testWidgets('fires onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          MessageAttachment(
            file: LanguageModelV3FilePart(
              data: DataContentUrl(Uri.parse('https://example.com/r.pdf')),
              mediaType: 'application/pdf',
              filename: 'report.pdf',
            ),
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('report.pdf'));
      expect(tapped, isTrue);
    });
  });
}
