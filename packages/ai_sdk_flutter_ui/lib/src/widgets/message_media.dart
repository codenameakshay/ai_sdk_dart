import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// Creates an image provider for a remote URL that the host application has
/// explicitly chosen to trust.
typedef RemoteImageProviderBuilder = ImageProvider Function(Uri url);

/// Renders an image content part ([LanguageModelV4ImagePart]) from any of the
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
    this.remoteImageProviderBuilder,
  });

  /// The image part to render.
  final LanguageModelV4ImagePart image;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// How the image should be inscribed into its box.
  final BoxFit fit;

  /// Corner rounding applied to the image.
  final BorderRadius borderRadius;

  /// Opts in to loading URL-backed images.
  ///
  /// Remote images are blocked by default because model/provider content is
  /// untrusted and an automatic request can disclose the user's IP address or
  /// reach services on a private network. Validate the URL before returning an
  /// image provider.
  final RemoteImageProviderBuilder? remoteImageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final mediaType = image.mediaType;
    final data = image.image;
    if (data is DataContentUrl && remoteImageProviderBuilder == null) {
      return Semantics(
        image: true,
        label: 'Remote image blocked',
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: borderRadius,
            child: _ImageError(width: width, height: height),
          ),
        ),
      );
    }
    final semanticLabel = mediaType == null || mediaType.isEmpty
        ? 'Attached image'
        : 'Attached image, $mediaType';
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Image(
            image: imageProviderFor(
              data,
              remoteImageProviderBuilder: remoteImageProviderBuilder,
            ),
            width: width,
            height: height,
            fit: fit,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || AiMotion.reduced(context)) {
                return child;
              }
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: AiMotion.quick,
                curve: AiMotion.standard,
                child: child,
              );
            },
            errorBuilder: (context, _, _) => Semantics(
              label: 'Image failed to load',
              image: true,
              child: _ImageError(width: width, height: height),
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps trusted [LanguageModelV4DataContent] to a core [ImageProvider].
///
/// URL-backed data requires [remoteImageProviderBuilder] so the host controls
/// the network trust decision. [MessageImage] blocks it before calling this
/// function when the builder is absent.
ImageProvider imageProviderFor(
  LanguageModelV4DataContent data, {
  RemoteImageProviderBuilder? remoteImageProviderBuilder,
}) {
  return switch (data) {
    DataContentBytes(:final bytes) => MemoryImage(bytes),
    DataContentBase64(:final base64) => MemoryImage(base64Decode(base64)),
    DataContentUrl(:final url) =>
      remoteImageProviderBuilder?.call(url) ??
          (throw UnsupportedError(
            'URL-backed images require remoteImageProviderBuilder.',
          )),
    DataContentProviderReference() => throw UnsupportedError(
      'Provider-owned image references require a host image provider.',
    ),
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

/// Renders a non-image file content part ([LanguageModelV4FilePart]) as a
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
  final LanguageModelV4FilePart file;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = file.filename ?? file.mediaType;
    final showSubtitle = file.filename != null;
    final canOpen = onTap != null;

    return Semantics(
      container: true,
      label: 'Attachment: $title',
      value: file.mediaType,
      button: canOpen,
      hint: canOpen ? 'Open attachment' : null,
      onTap: canOpen ? onTap : null,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canOpen
                  ? () {
                      AiHaptics.selection();
                      onTap!();
                    }
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconFor(file.mediaType),
                        color: scheme.onSurfaceVariant,
                      ),
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

/// Renders a file produced as part of the model's reasoning trace.
///
/// Reasoning files intentionally have their own widget because they are a
/// separate provider content part from user-visible file attachments.
class MessageReasoningFileAttachment extends StatelessWidget {
  const MessageReasoningFileAttachment({super.key, required this.file});

  final LanguageModelV4ReasoningFilePart file;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Reasoning attachment',
      value: file.mediaType,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                file.mediaType,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
