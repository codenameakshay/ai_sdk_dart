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
    test('raw url mapping requires an explicit host provider', () {
      expect(
        () => imageProviderFor(
          DataContentUrl(Uri.parse('https://example.com/a.png')),
        ),
        throwsUnsupportedError,
      );
    });

    testWidgets('renders byte data via a MemoryImage', (tester) async {
      final bytes = base64Decode(_pngBase64);
      await tester.pumpWidget(
        _wrap(
          MessageImage(
            image: LanguageModelV4ImagePart(image: DataContentBytes(bytes)),
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
            image: LanguageModelV4ImagePart(
              image: DataContentBase64(_pngBase64),
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<MemoryImage>());
    });

    testWidgets('blocks url data unless the host opts in', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageImage(
            image: LanguageModelV4ImagePart(
              image: DataContentUrl(Uri.parse('https://example.com/a.png')),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.bySemanticsLabel('Remote image blocked'), findsOneWidget);
    });

    testWidgets('uses the host provider for trusted url data', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MessageImage(
            image: LanguageModelV4ImagePart(
              image: DataContentUrl(Uri.parse('https://example.com/a.png')),
            ),
            remoteImageProviderBuilder: (url) => NetworkImage(url.toString()),
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
              image: LanguageModelV4ImagePart(
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
            file: LanguageModelV4FilePart(
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
            file: LanguageModelV4FilePart(
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
            file: LanguageModelV4FilePart(
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

    testWidgets('exposes accessible labels for images and attachments', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MessageImage(
                image: LanguageModelV4ImagePart(
                  image: DataContentBase64(_pngBase64),
                  mediaType: 'image/png',
                ),
              ),
              MessageAttachment(
                file: LanguageModelV4FilePart(
                  data: DataContentUrl(Uri.parse('https://example.com/r.pdf')),
                  mediaType: 'application/pdf',
                  filename: 'report.pdf',
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      final imageNode = tester
          .getSemantics(find.byType(MessageImage))
          .getSemanticsData();
      final attachmentNode = tester
          .getSemantics(find.byType(MessageAttachment))
          .getSemanticsData();
      expect(imageNode.label, 'Attached image, image/png');
      expect(attachmentNode.label, 'Attachment: report.pdf');
      expect(attachmentNode.value, 'application/pdf');
      semantics.dispose();
    });
  });
}
