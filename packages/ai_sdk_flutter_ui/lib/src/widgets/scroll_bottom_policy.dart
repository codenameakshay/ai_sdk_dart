import 'package:flutter/widgets.dart';

/// Shared near-bottom policy for transcript auto-pin and the return-to-latest
/// affordance.
abstract final class ScrollBottomPolicy {
  static const double threshold = 120;

  static double distanceFromBottom(ScrollMetrics metrics) {
    final distance = metrics.maxScrollExtent - metrics.pixels;
    return distance <= 0 ? 0 : distance;
  }

  static bool isNearBottom(
    ScrollMetrics metrics, {
    double threshold = ScrollBottomPolicy.threshold,
  }) => distanceFromBottom(metrics) <= threshold;

  static bool isNearBottomController(
    ScrollController controller, {
    double threshold = ScrollBottomPolicy.threshold,
  }) {
    if (!controller.hasClients) return false;
    final position = controller.position;
    if (!position.hasContentDimensions) return false;
    return isNearBottom(position, threshold: threshold);
  }
}
