import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// Renders an image content part ([LanguageModelV3ImagePart]) from any of the
/// three `DataContent` carriers — raw bytes, base64, or a URL — using core
/// Flutter image widgets (no extra dependency). The image fades in once decoded
/// (suppressed under reduced motion).
///
/// Decode/network failures fall back to a broken-image placeholder rather than
/// throwing, so a malformed part never breaks the surrounding message.
///
/// ```dart
/// MessageImage(image: imagePart, width: 220)
/// ```
class MessageImage extends StatelessWidget {
  const MessageImage({
    super.key,
    required this.image,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  /// The image part to render.
  final LanguageModelV3ImagePart image;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// How the image should be inscribed into its box.
  final BoxFit fit;

  /// Corner rounding applied to the image.
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image(
        image: imageProviderFor(image.image),
        width: width,
        height: height,
        fit: fit,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || AiMotion.reduced(context)) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: AiMotion.quick,
            curve: AiMotion.standard,
            child: child,
          );
        },
        errorBuilder: (context, _, __) =>
            _ImageError(width: width, height: height),
      ),
    );
  }
}

/// Maps a [LanguageModelV3DataContent] to the matching core [ImageProvider]:
/// bytes/base64 → [MemoryImage], URL → [NetworkImage].
ImageProvider imageProviderFor(LanguageModelV3DataContent data) {
  return switch (data) {
    DataContentBytes(:final bytes) => MemoryImage(bytes),
    DataContentBase64(:final base64) => MemoryImage(base64Decode(base64)),
    DataContentUrl(:final url) => NetworkImage(url.toString()),
  };
}

class _ImageError extends StatelessWidget {
  const _ImageError({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height ?? 96,
      alignment: Alignment.center,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
    );
  }
}

/// Renders a non-image file content part ([LanguageModelV3FilePart]) as a
/// compact attachment tile: a type icon, the filename (falling back to the
/// media type), and the media type as a subtitle.
///
/// The package does not open files itself; supply [onTap] to handle it. The
/// tile answers a press with a subtle scale and a selection haptic.
///
/// ```dart
/// MessageAttachment(file: filePart, onTap: () => openFile(filePart))
/// ```
class MessageAttachment extends StatelessWidget {
  const MessageAttachment({super.key, required this.file, this.onTap});

  /// The file part to render.
  final LanguageModelV3FilePart file;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = file.filename ?? file.mediaType;
    final showSubtitle = file.filename != null;

    return PressableScale(
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AiHaptics.selection();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(file.mediaType), color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    if (showSubtitle)
                      Text(
                        file.mediaType,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String mediaType) {
    if (mediaType.startsWith('image/')) return Icons.image_outlined;
    if (mediaType.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mediaType.startsWith('video/')) return Icons.movie_outlined;
    if (mediaType.contains('pdf')) return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }
}
