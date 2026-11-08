import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/widgets.dart';

/// The container a block sits directly in, for the reference's structural CSS rules.
enum SlotParent { card, grid, carouselItem, cardSizedFlow, other }

/// Wraps one direct child of a container.
final class BlockSlot extends InheritedWidget {
  const BlockSlot({
    super.key,
    required this.element,
    required this.parent,
    required this.index,
    required this.previous,
    required this.flow,
    required super.child,
  });

  final OpenUiElement? element;
  final SlotParent parent;
  final int index;
  final OpenUiElement? previous;

  /// The container spaces blocks with flow rules (it has no gap).
  final bool flow;

  /// The slot around [element] itself; null when [element] sits deeper.
  static BlockSlot? of(BuildContext context, OpenUiElement element) {
    final slot = context.dependOnInheritedWidgetOfExactType<BlockSlot>();
    return identical(slot?.element, element) ? slot : null;
  }

  @override
  bool updateShouldNotify(BlockSlot oldWidget) =>
      !identical(element, oldWidget.element) ||
      parent != oldWidget.parent ||
      index != oldWidget.index ||
      !identical(previous, oldWidget.previous) ||
      flow != oldWidget.flow;
}

/// Inside a Card's first-child row, a small or medium Title reads as the card title.
final class CardHeadScope extends InheritedWidget {
  const CardHeadScope({super.key, required this.active, required super.child});

  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardHeadScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(CardHeadScope oldWidget) =>
      active != oldWidget.active;
}
