import 'dart:convert';

import 'package:flutter/material.dart';

import '../object_stream_controller.dart';
import 'chat_error_view.dart';

/// Signature for rendering the current value of an [ObjectStreamController].
typedef ObjectValueBuilder<T> =
    Widget Function(BuildContext context, T value, bool isStreaming);

/// Renders the live state of an [ObjectStreamController] — mirrors the JS
/// `useObject` UI: a spinner while loading, the partial value as it streams,
/// and an error banner if the stream fails.
///
/// By default the value is shown as pretty-printed JSON; pass a [builder] to
/// render it however you like (e.g. a schema-driven form). Rebuilds reactively
/// as partial values arrive.
///
/// ```dart
/// ObjectStreamView<Recipe>(
///   controller: recipeController,
///   builder: (context, recipe, streaming) => RecipeCard(recipe),
/// )
/// ```
class ObjectStreamView<T> extends StatelessWidget {
  const ObjectStreamView({
    super.key,
    required this.controller,
    this.builder,
    this.loadingBuilder,
    this.emptyState,
  });

  /// The controller whose `value`/`isStreaming`/`error` drive this view.
  final ObjectStreamController<T> controller;

  /// Optional custom renderer for the current value. Defaults to pretty JSON.
  final ObjectValueBuilder<T>? builder;

  /// Optional widget shown while loading before the first value arrives.
  /// Defaults to a centered [CircularProgressIndicator].
  final WidgetBuilder? loadingBuilder;

  /// Optional widget shown when idle with no value and no error.
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final error = controller.error;
        if (error != null) return ChatErrorView(error: error);

        final value = controller.value;
        if (value == null) {
          if (controller.isLoading) {
            return loadingBuilder?.call(context) ??
                const Center(child: CircularProgressIndicator());
          }
          return emptyState ?? const SizedBox.shrink();
        }

        final builder = this.builder;
        if (builder != null) {
          return builder(context, value, controller.isStreaming);
        }
        return _JsonView(value: value);
      },
    );
  }
}

class _JsonView extends StatelessWidget {
  const _JsonView({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        _pretty(value),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: scheme.onSurface,
        ),
      ),
    );
  }

  static String _pretty(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
