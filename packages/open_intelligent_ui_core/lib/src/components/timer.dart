import 'dart:async';
import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../localizations.dart';
import '../theme.dart';
import '../view.dart';
import 'controls.dart' show IuiButton;

/// `Timer(seconds, label?)`: counts the bound seconds down to 0.
Widget buildTimer(BuildContext context, OpenUiNode node) {
  final label = node.props.string('label');
  return CountdownTimer(
    field: node.field(
      'seconds',
      name: label != null && label.isNotEmpty ? label : null,
    ),
    label: label,
    streaming: node.isStreaming,
  );
}

String clock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = h > 0 ? '$m'.padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${'$s'.padLeft(2, '0')}';
}

class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.field,
    required this.label,
    required this.streaming,
  });
  final FieldState field;
  final String? label;
  final bool streaming;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  Timer? _ticker;
  int? _startedAt;

  int get _left {
    final n = jsNumber(widget.field.value);
    return n.isFinite ? math.max(0, n.floor()) : 0;
  }

  bool get _running => _ticker != null;

  void _toggle() {
    if (_running) {
      setState(_stop);
      return;
    }
    setState(() {
      _startedAt ??= _left;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = math.max(0, _left - 1);
        widget.field.set(next);
        if (next == 0 && mounted) setState(_stop);
      });
    });
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _reset() {
    final start = _startedAt;
    setState(() {
      _stop();
      _startedAt = null;
    });
    if (start != null) widget.field.set(start);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final strings = OpenUiLocalizations.of(context);
    final left = _left;
    final done = left == 0 && _startedAt != null;
    final label = widget.label;
    return Semantics(
      container: true,
      label: label == null || label.isEmpty ? strings.timer : label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.border),
          borderRadius: BorderRadius.circular(theme.radii.lg),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null && label.isNotEmpty) ...[
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: theme.typography.size(14),
                      height: 1.4,
                      fontWeight: theme.typography.medium,
                      color: theme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  clock(left),
                  style: TextStyle(
                    fontSize: theme.typography.size(32),
                    height: 1.1,
                    fontWeight: theme.typography.semibold,
                    letterSpacing: -0.32,
                    fontFeatures: theme.typography.tabular,
                    color: done ? theme.status['success'] : theme.ink,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IuiButton(
                  icon: _running ? 'pause' : 'play',
                  label: _running
                      ? strings.pause
                      : (_startedAt == null || left == 0
                            ? strings.start
                            : strings.resume),
                  size: 'sm',
                  onTap: widget.streaming || left == 0 ? null : _toggle,
                ),
                const SizedBox(width: 8),
                IuiButton(
                  icon: 'rotate-ccw',
                  label: strings.reset,
                  variant: 'ghost',
                  size: 'sm',
                  onTap: widget.streaming || _startedAt == null ? null : _reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
