import 'package:flutter/material.dart';

/// An inline error banner with optional retry and dismiss actions.
///
/// Render it when a controller enters its error state — e.g. when
/// `ChatController.error` is non-null or `CompletionController.error` is set —
/// and wire [onRetry] to `regenerate()`/`complete(...)` and [onDismiss] to
/// `clearError()`.
///
/// Pure presentation: it reads only its inputs and themes via
/// `Theme.of(context)`.
///
/// ```dart
/// if (controller.error != null)
///   ChatErrorView(
///     error: controller.error!,
///     onRetry: controller.regenerate,
///     onDismiss: controller.clearError,
///   )
/// ```
class ChatErrorView extends StatelessWidget {
  const ChatErrorView({
    super.key,
    required this.error,
    this.message,
    this.onRetry,
    this.onDismiss,
    this.retryLabel = 'Retry',
  });

  /// The error to surface. Rendered via [Object.toString] unless [message] is
  /// given.
  final Object error;

  /// Optional human-friendly message shown instead of `error.toString()`.
  final String? message;

  /// When provided, a retry button is shown.
  final VoidCallback? onRetry;

  /// When provided, a dismiss (close) button is shown.
  final VoidCallback? onDismiss;

  /// Label for the retry button.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final text = message ?? error.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                text,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const ValueKey('chat-error-retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: scheme.onErrorContainer),
              child: Text(retryLabel),
            ),
          if (onDismiss != null)
            IconButton(
              key: const ValueKey('chat-error-dismiss'),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, color: scheme.onErrorContainer),
            ),
        ],
      ),
    );
  }
}
