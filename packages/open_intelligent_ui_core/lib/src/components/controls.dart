import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart' show Impure, formatDecimal;
import 'package:flutter/cupertino.dart'
    show
        CupertinoButton,
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData,
        showCupertinoModalPopup;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';

import '../localizations.dart';
import '../theme.dart';
import '../view.dart';
import 'action_gate.dart';
import 'block_slot.dart' show PressableScope;
import 'flex_row.dart';
import 'glyph.dart';

typedef _Choice = ({String value, String label, String? description});

TextStyle _text(
  OpenUiTheme theme, {
  double? size,
  Color? color,
  FontWeight? weight,
  double? height,
  bool tabular = false,
}) => TextStyle(
  fontFamily: theme.fontFamily,
  fontSize: size,
  fontWeight: weight,
  height: height,
  color: color ?? theme.ink,
  fontFeatures: tabular ? theme.typography.tabular : theme.typography.allText,
  decoration: TextDecoration.none,
);

TextStyle _labelStyle(OpenUiTheme theme) => _text(
  theme,
  size: theme.fontSizeOf('Field.label', 14),
  weight: theme.typography.medium,
  height: 1.4,
);

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

FieldState _field(OpenUiNode node, String prop, String? label) =>
    node.field(prop, name: _nonEmpty(label));

/// A labelled field; like a wrapping `<label>`, the label names the field.
Widget _labeled(OpenUiTheme theme, String? label, Widget child) {
  if (_nonEmpty(label) == null) return child;
  return MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: _labelStyle(theme)),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

List<_Choice> _choices(List<Object?> raw) {
  final out = <_Choice>[];
  void add(Object? o) {
    if (o is String) {
      out.add((value: o, label: o, description: null));
    } else if (o is Map && o['value'] is String) {
      final value = o['value'] as String;
      out.add((
        value: value,
        label: o['label'] is String ? o['label'] as String : value,
        description: o['description'] is String
            ? o['description'] as String
            : null,
      ));
    } else if (o is List) {
      o.forEach(add);
    }
  }

  raw.forEach(add);
  return out;
}

String _plain(Object? value) => value == null ? '' : jsString(value);

/// `toLocaleString("en-US", {maximumFractionDigits: 2})`.
String _numberText(double value) =>
    formatDecimal(value, minFraction: 0, maxFraction: 2);

String _textOf(BuildContext context) {
  final parts = <String>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Glyph) return;
    if (widget is RichText) {
      parts.add(widget.text.toPlainText());
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  final text = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.substring(0, math.min(120, text.length));
}

/// Hover, press and keyboard focus for a tappable surface: Enter and Space
/// activate it, and keyboard focus draws a 2px ink ring 3px outside it.
class Press extends StatefulWidget {
  const Press({
    super.key,
    required this.builder,
    required this.onTap,
    this.radius = 999,
    this.focusNode,
  });

  final Widget Function(bool hovered, bool pressed) builder;
  final void Function(BuildContext context)? onTap;
  final double radius;
  final FocusNode? focusNode;

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final theme = OpenUiTheme.of(context);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call(context);
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: enabled ? () => widget.onTap!(context) : null,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.passthrough,
            children: [
              widget.builder(_hover && enabled, _down && enabled),
              if (_focus)
                PositionedDirectional(
                  start: -5,
                  top: -5,
                  end: -5,
                  bottom: -5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.ink, width: 2),
                        borderRadius: BorderRadius.circular(widget.radius + 5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _brighten(Color c, double factor) => Color.from(
  alpha: c.a,
  red: math.min(1, c.r * factor),
  green: math.min(1, c.g * factor),
  blue: math.min(1, c.b * factor),
);

/// The selected tile's check: the reference's own 12px mark
/// (`M2.5 6.2l2.3 2.3 4.7-5`, stroke 1.8), not lucide's.
final class _CheckMark extends CustomPainter {
  const _CheckMark(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(2.5, 6.2)
      ..lineTo(4.8, 8.5)
      ..lineTo(9.5, 3.5),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  @override
  bool shouldRepaint(_CheckMark old) => old.color != color;
}

const _buttonFade = Duration(milliseconds: 150);

/// `.iui-button`, the reference's pill button, for Button and Timer. Its
/// background, border and text colour ease over 150ms, as in CSS.
class IuiButton extends StatelessWidget {
  const IuiButton({
    super.key,
    required this.label,
    this.icon,
    this.variant = 'solid',
    this.tone,
    this.size = 'md',
    this.phase,
    this.onTap,
  });

  final String label;
  final String? icon;

  /// `solid`, `outline`, `soft` or `ghost`.
  final String variant;

  /// `danger` or `success`; anything else is the ink.
  final String? tone;

  /// `sm`, `md` or `lg`.
  final String size;

  /// A handled action's phase: a spinner while pending or unknown, a check
  /// when done.
  final ActionPhase? phase;

  /// Null shows the button disabled.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final enabled = onTap != null;
    final toneColor = switch (tone) {
      'danger' || 'success' => theme.status[tone],
      _ => null,
    };
    final (minHeight, padding, fontSize) = switch (size) {
      'sm' => (
        32.0,
        const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        theme.fontSizeOf('Button.sm', 13),
      ),
      'lg' => (
        44.0,
        const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        theme.fontSizeOf('Button.lg', 15),
      ),
      _ => (
        36.0,
        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        theme.fontSizeOf('Button', 14),
      ),
    };
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: Press(
        onTap: enabled ? (_) => onTap!() : null,
        builder: (hovered, pressed) {
          final overlay = pressed
              ? theme.pressed
              : hovered
              ? theme.hover
              : null;
          Color? background;
          Color foreground = toneColor ?? theme.ink;
          Color? border;
          EdgeInsetsGeometry pad = padding;
          switch (variant) {
            case 'outline':
              background = Color.alphaBlend(
                overlay ?? Colors.transparent,
                theme.canvas,
              );
              border = theme.border;
            case 'soft':
              background = hovered || pressed ? theme.pressed : theme.surface;
            case 'ghost':
              background = overlay;
              pad = padding.copyWith(left: 10, right: 10);
            default:
              if (toneColor != null) {
                background = hovered && !pressed
                    ? _brighten(toneColor, 1.08)
                    : toneColor;
                foreground = theme.onTone;
              } else {
                background = hovered && !pressed ? theme.inkHover : theme.ink;
                foreground = theme.onInk;
              }
          }
          final s = theme.styleOf('Button', variant);
          background = s.background ?? background;
          foreground = s.foreground ?? foreground;
          border = s.border ?? border;
          return Opacity(
            opacity: enabled ? 1 : 0.4,
            child: AnimatedContainer(
              duration: _buttonFade,
              curve: Curves.ease,
              constraints: BoxConstraints(minHeight: minHeight),
              padding: s.padding ?? pad,
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: border ?? Colors.transparent),
                borderRadius: BorderRadius.circular(
                  s.radius ?? theme.radii.full,
                ),
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: foreground),
                duration: _buttonFade,
                curve: Curves.ease,
                builder: (context, color, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (phase == ActionPhase.pending ||
                        phase == ActionPhase.unknown) ...[
                      _Spinner(size: size == 'sm' ? 14 : 16, color: color),
                      const SizedBox(width: 7),
                    ] else if (phase == ActionPhase.done) ...[
                      Glyph(
                        'check',
                        size: size == 'sm' ? 14 : 16,
                        color: color,
                      ),
                      const SizedBox(width: 7),
                    ] else if (Glyph.has(context, icon)) ...[
                      Glyph(icon!, size: size == 'sm' ? 14 : 16, color: color),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          theme,
                          size: fontSize,
                          color: color,
                          weight: theme.typography.medium,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Widget buildButton(BuildContext context, OpenUiNode node) {
  final label = node.props['label'] == null
      ? ''
      : jsString(node.props['label']);
  final enabled = node.props.boolean('disabled') != true && !node.isStreaming;
  final button = ActionGate(
    node: node,
    prop: 'action',
    enabled: enabled,
    label: (_) => label,
    sendLabel: true,
    builder: (context, status, onTap) => IuiButton(
      label: label,
      icon: node.props.string('icon'),
      variant: node.props.string('variant') ?? 'solid',
      tone: node.props.string('color'),
      size: node.props.string('size') ?? 'md',
      phase: status?.phase,
      onTap: onTap == null ? null : () => onTap(context),
    ),
  );
  if (node.props.boolean('block') == true) {
    return SizedBox(width: double.infinity, child: button);
  }
  return Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: button,
  );
}

Widget buildIconButton(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final icon = node.props.string('icon') ?? '';
  final given = _nonEmpty(node.props.string('label'));
  final label = given ?? icon;
  final variant = node.props.string('variant') ?? 'outline';
  final enabled = !node.isStreaming;
  return Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: ActionGate(
      node: node,
      prop: 'action',
      enabled: enabled,
      label: (_) => label,
      builder: (context, status, onTap) {
        final phase = status?.phase;
        Widget button = Press(
          onTap: onTap,
          builder: (hovered, pressed) {
            final overlay = pressed
                ? theme.pressed
                : hovered
                ? theme.hover
                : null;
            final (background, foreground, border) = switch (variant) {
              'ghost' => (
                overlay,
                hovered || pressed ? theme.ink : theme.muted,
                Colors.transparent,
              ),
              'solid' => (
                hovered && !pressed ? theme.inkHover : theme.ink,
                theme.onInk,
                theme.ink,
              ),
              _ => (
                Color.alphaBlend(overlay ?? Colors.transparent, theme.canvas),
                theme.ink,
                theme.border,
              ),
            };
            return Opacity(
              opacity: onTap != null ? 1 : 0.4,
              child: AnimatedContainer(
                duration: _buttonFade,
                curve: Curves.ease,
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: Border.all(color: border),
                ),
                child: switch (phase) {
                  ActionPhase.pending ||
                  ActionPhase.unknown => _Spinner(size: 16, color: foreground),
                  ActionPhase.done => Glyph(
                    'check',
                    size: 16,
                    color: foreground,
                  ),
                  ActionPhase.failed => Glyph(
                    Glyph.has(context, 'circle-alert')
                        ? 'circle-alert'
                        : 'info',
                    size: 16,
                    color: theme.status['danger'] ?? foreground,
                  ),
                  _ => Glyph(icon, size: 16, color: foreground),
                },
              ),
            );
          },
        );
        if (given != null) {
          button = Tooltip(
            message: given,
            decoration: BoxDecoration(
              color: theme.ink,
              borderRadius: BorderRadius.circular(theme.radii.sm),
            ),
            textStyle: _text(
              theme,
              size: theme.fontSizeOf('Tooltip', 12),
              color: theme.onInk,
            ),
            child: button,
          );
        }
        return Semantics(
          container: true,
          button: true,
          enabled: onTap != null,
          label: label,
          child: button,
        );
      },
    ),
  );
}

/// A 2px spinner sized to an icon or a button's text.
class _Spinner extends StatelessWidget {
  const _Spinner({required this.size, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: color,
      semanticsLabel: OpenUiLocalizations.of(context).loadingData,
    ),
  );
}

Widget buildPressable(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final streaming = node.isStreaming;
  final selected = node.props.boolean('selected') == true;
  final radius = theme.radiusOf(node.props['radius']) ?? theme.radii.lg;
  final hasRow = node.props
      .elements('children')
      .any(
        (e) =>
            e.typeName == 'Row' ||
            (e.typeName == 'Box' && e.props.string('direction') == 'row'),
      );
  final background = node.props['background'];
  final on = theme.inkOn(background);
  final padding = theme.spaceOf(node.props.number('padding'));
  final shape = BorderRadius.circular(radius);
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  final fade = reduce ? Duration.zero : const Duration(milliseconds: 120);
  Widget content = PressableScope(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: node.children(),
    ),
  );
  if (on != null) {
    content = OpenUiThemeScope(
      theme: theme.withInk(on),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: on),
        child: content,
      ),
    );
  }
  final ring = selected && !hasRow;
  return ActionGate(
    node: node,
    prop: 'action',
    enabled: !streaming,
    label: _textOf,
    builder: (context, status, onTap) => Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      toggled: node.props['selected'] is bool ? selected : null,
      child: Press(
        radius: radius,
        onTap: onTap,
        builder: (hovered, pressed) {
          final scale = hasRow || reduce
              ? 1.0
              : (pressed ? 0.98 : (hovered ? 1.01 : 1.0));
          final overlay = pressed
              ? 0.08
              : hovered
              ? 0.05
              : (ring ? 0.06 : 0.0);
          final pending =
              status?.phase == ActionPhase.pending ||
              status?.phase == ActionPhase.unknown;
          return Opacity(
            opacity: pending ? 0.6 : 1,
            child: AnimatedScale(
              scale: scale,
              duration: fade,
              curve: Curves.easeOut,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: fade,
                    curve: Curves.easeOut,
                    padding: padding == null ? null : EdgeInsets.all(padding),
                    decoration: BoxDecoration(
                      color: theme.bg(background),
                      gradient: theme.bgGradient(background),
                      borderRadius: shape,
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: shape,
                      border: Border.all(
                        color: ring
                            ? theme.ink.withValues(alpha: 0.2)
                            : Colors.transparent,
                      ),
                    ),
                    child: content,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: fade,
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: theme.ink.withValues(alpha: overlay),
                          borderRadius: shape,
                        ),
                      ),
                    ),
                  ),
                  if (ring)
                    PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.ink,
                          shape: BoxShape.circle,
                        ),
                        child: CustomPaint(
                          size: const Size.square(12),
                          painter: _CheckMark(theme.checkInk),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

num? _parseTyped(String text) {
  final s = text.replaceAll(',', '').trim();
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  return n != null && n.isFinite ? n : null;
}

/// A bordered text field that keeps its controller (and so focus, caret and
/// half-typed text) across the tree rebuilds every state change causes.
class _TextBox extends StatefulWidget {
  const _TextBox({
    required this.text,
    required this.onChanged,
    this.numeric = false,
    this.hint,
    this.rows,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final bool numeric;
  final String? hint;
  final int? rows;

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);

  void _reset() => _controller.value = TextEditingValue(
    text: widget.text,
    selection: TextSelection.collapsed(offset: widget.text.length),
  );

  void _focusChanged() {
    if (!_focus.hasFocus && _controller.text != widget.text) _reset();
  }

  @override
  void didUpdateWidget(_TextBox old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text || widget.text == _controller.text) return;
    // A number field shows what is typed ("1." or "-") until it parses.
    if (widget.numeric &&
        _parseTyped(_controller.text) == _parseTyped(widget.text)) {
      return;
    }
    _reset();
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final rows = widget.rows;
    final component = rows == null ? 'Input' : 'TextArea';
    final s = theme.styleOf(component);
    final style = _text(
      theme,
      size: theme.fontSizeOf(component, 16),
      height: 1.4,
      tabular: true,
    );
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, child) => Container(
        constraints: BoxConstraints(minHeight: s.size ?? 42),
        padding:
            s.padding ??
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.canvas,
          borderRadius: BorderRadius.circular(theme.radii.md),
          border: Border.all(
            color: _focus.hasFocus ? theme.ink : theme.borderStrong,
          ),
          boxShadow: _focus.hasFocus
              ? [
                  BoxShadow(
                    color: theme.ink.withValues(alpha: 0.18),
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: TextSelectionTheme(
          data: TextSelectionThemeData(
            cursorColor: theme.ink,
            selectionColor: theme.selection,
            selectionHandleColor: theme.ink,
          ),
          child: child!,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          style: style,
          cursorColor: theme.ink,
          minLines: rows,
          maxLines: rows ?? 1,
          keyboardType: widget.numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : (rows == null ? TextInputType.text : TextInputType.multiline),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: widget.hint,
            hintStyle: style.copyWith(color: theme.faint),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

Widget buildInput(BuildContext context, OpenUiNode node) {
  final label = node.props.string('label');
  final f = _field(node, 'value', label);
  final numeric = node.props['type'] == 'number';
  return _labeled(
    node.theme,
    label,
    _TextBox(
      text: _plain(f.value),
      numeric: numeric,
      hint: node.props.string('placeholder'),
      onChanged: (text) {
        if (!numeric) return f.set(text);
        if (text.trim().isEmpty) return f.set(null);
        final parsed = _parseTyped(text);
        if (parsed != null) f.set(parsed);
      },
    ),
  );
}

Widget buildTextArea(BuildContext context, OpenUiNode node) {
  final label = node.props.string('label');
  final f = _field(node, 'value', label);
  final rows = (node.props.number('rows') ?? 3).round().clamp(2, 20);
  return _labeled(
    node.theme,
    label,
    _TextBox(
      text: _plain(f.value),
      rows: rows,
      hint: node.props.string('placeholder'),
      onChanged: f.set,
    ),
  );
}

Widget buildSelect(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = node.props.string('label');
  final f = _field(node, 'value', label);
  final choices = _choices(node.props.list('options'));
  final value = _plain(f.value);
  final selected = choices.indexWhere((o) => o.value == value);
  final style = _text(theme, size: theme.fontSizeOf('Select', 16), height: 1.4);
  return _labeled(
    theme,
    label,
    Container(
      constraints: const BoxConstraints(minHeight: 42),
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
      decoration: BoxDecoration(
        color: theme.canvas,
        borderRadius: BorderRadius.circular(theme.radii.md),
        border: Border.all(color: theme.borderStrong),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            isExpanded: true,
            isDense: true,
            value: selected < 0 ? null : selected,
            hint: Text(
              node.props.string('placeholder') ??
                  OpenUiLocalizations.of(context).choose,
              style: style.copyWith(color: theme.faint),
            ),
            style: style,
            dropdownColor: theme.canvas,
            borderRadius: BorderRadius.circular(theme.radii.md),
            icon: Glyph(
              'chevron-down',
              size: 16,
              strokeWidth: 2.4,
              color: theme.chevron,
            ),
            items: [
              for (final (i, o) in choices.indexed)
                DropdownMenuItem(value: i, child: Text(o.label)),
            ],
            onChanged: (i) => f.set(choices[i!].value),
          ),
        ),
      ),
    ),
  );
}

const _segmentFade = Duration(milliseconds: 200);

Widget buildSegmentedControl(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final f = _field(node, 'value', null);
  final value = _plain(f.value);
  final block = node.props.boolean('block') == true;
  final dark = theme.brightness == Brightness.dark;
  final compact = MediaQuery.sizeOf(context).width <= 640;
  Widget segment(_Choice o) {
    final selected = o.value == value;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Press(
        onTap: (_) => f.set(o.value),
        builder: (hovered, pressed) => AnimatedContainer(
          duration: _segmentFade,
          curve: Curves.ease,
          padding: EdgeInsets.symmetric(
            vertical: 6,
            horizontal: compact ? 11 : 14,
          ),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? theme.surfaceStrong : theme.canvas)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: selected ? Border.all(color: theme.border) : null,
            boxShadow: selected ? theme.shadowSmall : null,
          ),
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: selected || hovered ? theme.ink : theme.muted,
            ),
            duration: _segmentFade,
            curve: Curves.ease,
            builder: (context, color, _) => Text(
              o.label,
              softWrap: false,
              style: _text(
                theme,
                size: theme.fontSizeOf('SegmentedControl', 13),
                height: 1.4,
                color: color,
                weight: selected ? theme.typography.medium : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  final choices = _choices(node.props.list('options'));
  final bar = Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: theme.surface,
      borderRadius: BorderRadius.circular(999),
    ),
    child: block
        ? FlexRow(
            gap: 2,
            children: [
              // A Stack measures its child at natural width, then centres it
              // in the share the row gives it.
              for (final o in choices)
                FlexRowItem(
                  grow: 1,
                  shrink: false,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [segment(o)],
                  ),
                ),
            ],
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 2,
              children: [for (final o in choices) segment(o)],
            ),
          ),
  );
  final group = Semantics(
    container: true,
    role: SemanticsRole.radioGroup,
    child: bar,
  );
  return block
      ? group
      : Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: group,
        );
}

Widget buildSlider(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = _nonEmpty(node.props.string('label'));
  final f = _field(node, 'value', label);
  final min = node.props.number('min')?.toDouble() ?? 0;
  final maxProp = node.props.number('max')?.toDouble();
  final max = maxProp != null && maxProp > min ? maxProp : min + 100;
  final stepProp = node.props.number('step')?.toDouble();
  final step = stepProp != null && stepProp > 0 ? stepProp : 1.0;
  // `Number(field.value)`; null is an unset (undefined) field, so NaN.
  final raw = f.value == null ? double.nan : jsNumber(f.value);
  final value = raw.isFinite ? raw.clamp(min, max).toDouble() : min;
  final unit = node.props.string('unit') ?? '';
  final prefix = RegExp(r'^[$€£¥₹]').hasMatch(unit);
  String readoutOf(double v) =>
      prefix ? '$unit${_numberText(v)}' : '${_numberText(v)}$unit';
  double snap(double v) {
    final snapped = min + ((v - min) / step).round() * step;
    return double.parse(snapped.clamp(min, max).toStringAsFixed(10));
  }

  final readout = readoutOf(value);
  final count = (max - min) / step;
  final steps = count.round();
  final divisions = (count - steps).abs() < 1e-9 && steps >= 1 && steps <= 1000
      ? steps
      : null;
  final marks = [
    for (final m in node.props.list('marks'))
      if (m is Map &&
          m['value'] is num &&
          (m['value'] as num).isFinite &&
          (m['value'] as num) >= min &&
          (m['value'] as num) <= max)
        (
          at: ((m['value'] as num) - min) / (max - min),
          label: _plain(m['label']),
        ),
  ];
  final small = _text(theme, size: theme.fontSizeOf('Slider', 13), height: 1.4);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (label != null || unit.isNotEmpty)
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(label ?? '', style: small)),
            const SizedBox(width: 12),
            Text(
              readout,
              softWrap: false,
              style: _text(
                theme,
                size: theme.fontSizeOf('Slider.value', 12),
                height: 1.4,
                weight: theme.typography.medium,
                tabular: true,
              ),
            ),
          ],
        ),
      SizedBox(
        height: 40,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 24,
            activeTrackColor: theme.rangeTrack,
            inactiveTrackColor: theme.rangeTrack,
            thumbColor: theme.ink,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 9,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayShape: SliderComponentShape.noOverlay,
            tickMarkShape: SliderTickMarkShape.noTickMark,
            trackShape: const _RangeTrack(),
          ),
          child: MergeSemantics(
            child: Semantics(
              label: label ?? OpenUiLocalizations.of(context).sliderValue,
              child: Slider(
                min: min,
                max: max,
                value: value,
                divisions: divisions,
                semanticFormatterCallback: (v) => readoutOf(snap(v)),
                onChanged: (v) {
                  final next = snap(v);
                  f.set(next == next.truncateToDouble() ? next.toInt() : next);
                },
              ),
            ),
          ),
        ),
      ),
      if (marks.isNotEmpty)
        ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, box) {
              final style = _text(
                theme,
                size: theme.fontSizeOf('Slider.mark', 11),
                height: 18 / 11,
                color: theme.muted,
                tabular: true,
              );
              return SizedBox(
                height: 16,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final m in marks)
                      if (m.at <= 0.02)
                        PositionedDirectional(
                          top: -2,
                          start: (box.maxWidth - 18) * m.at,
                          child: Text(m.label, softWrap: false, style: style),
                        )
                      else if (m.at >= 0.98)
                        PositionedDirectional(
                          top: -2,
                          end: (box.maxWidth - 18) * (1 - m.at),
                          child: Text(m.label, softWrap: false, style: style),
                        )
                      else
                        PositionedDirectional(
                          top: -2,
                          start: 9 + (box.maxWidth - 18) * m.at,
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, 0),
                            child: Text(m.label, softWrap: false, style: style),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
    ],
  );
}

/// The reference's range input: a 24px pill across the full width, and a
/// thumb whose centre travels from 12px in at one end to 12px in at the
/// other (WebKit's 3px track border around the 18px thumb).
final class _RangeTrack extends SliderTrackShape {
  const _RangeTrack();

  static const _height = 24.0;
  static const _inset = 12.0;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx + _inset,
    offset.dy + (parentBox.size.height - _height) / 2,
    parentBox.size.width - 2 * _inset,
    _height,
  );

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final travel = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          travel.left - _inset,
          travel.top,
          travel.right + _inset,
          travel.bottom,
        ),
        const Radius.circular(_height / 2),
      ),
      Paint()..color = sliderTheme.inactiveTrackColor!,
    );
  }
}

Widget buildCheckbox(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = node.props['label'] == null
      ? ''
      : jsString(node.props['label']);
  final f = _field(node, 'checked', label);
  final checked = f.value == true;
  final done = checked && node.props.boolean('lineThrough') == true;
  final box = theme.styleOf('Checkbox');
  final boxSize = box.size ?? 17;
  final boxRadius = box.radius ?? 4;
  return Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: Semantics(
      checked: checked,
      label: label,
      child: Press(
        radius: boxRadius,
        onTap: (_) => f.set(!checked),
        builder: (hovered, pressed) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: boxSize,
                height: boxSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: checked ? theme.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(boxRadius),
                  border: checked
                      ? null
                      : Border.all(color: theme.muted, width: 1.5),
                ),
                child: checked
                    ? Glyph('check', size: 13, color: theme.onInk)
                    : null,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: done ? theme.muted : theme.ink),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.ease,
                  builder: (context, color, _) => Text(
                    label,
                    style: _text(theme, color: color).copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: done ? color : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _StepIntent extends Intent {
  const _StepIntent(this.delta);
  final int delta;
}

/// A native radio group's keys: arrows move the choice, wrapping around,
/// and the focus with it; Tab stops only at the checked option.
final class _RadioKeys extends StatefulWidget {
  const _RadioKeys({
    required this.count,
    required this.selected,
    required this.onSelect,
    required this.builder,
  });

  final int count;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget Function(List<FocusNode> nodes) builder;

  @override
  State<_RadioKeys> createState() => _RadioKeysState();
}

final class _RadioKeysState extends State<_RadioKeys> {
  final List<FocusNode> _nodes = [];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _step(_StepIntent intent) {
    final from = _nodes.indexWhere((n) => n.hasFocus);
    if (from < 0) return;
    final to = (from + intent.delta) % widget.count;
    widget.onSelect(to);
    _nodes[to].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    while (_nodes.length < widget.count) {
      _nodes.add(FocusNode());
    }
    if (_nodes.length > widget.count) {
      final gone = _nodes.sublist(widget.count);
      _nodes.removeRange(widget.count, _nodes.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in gone) {
          node.dispose();
        }
      });
    }
    final stop = widget.selected < 0 ? 0 : widget.selected;
    for (final (i, node) in _nodes.indexed) {
      node.skipTraversal = i != stop;
    }
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
      },
      child: Actions(
        actions: {
          _StepIntent: CallbackAction<_StepIntent>(
            onInvoke: (intent) {
              _step(intent);
              return null;
            },
          ),
        },
        child: widget.builder(_nodes),
      ),
    );
  }
}

Widget buildRadioGroup(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = node.props.string('label');
  final f = _field(node, 'value', label);
  final value = _plain(f.value);
  final variant = switch (node.props.string('variant')) {
    'pills' => 'pills',
    'cards' => 'cards',
    _ => 'list',
  };
  final choices = _choices(node.props.list('options'));

  Widget option(_Choice o, FocusNode focus) {
    final selected = o.value == value;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          o.label,
          style: _text(
            theme,
            size: variant == 'list' ? null : theme.fontSizeOf('RadioGroup', 15),
            height: variant == 'list' ? null : 22 / 15,
            weight: variant == 'cards' ? theme.typography.medium : null,
            color: variant == 'pills' && selected ? theme.onInk : theme.ink,
          ),
        ),
        if (o.description != null) ...[
          const SizedBox(height: 2),
          Text(
            o.description!,
            style: _text(
              theme,
              size: theme.fontSizeOf('RadioGroup.description', 14),
              height: 21 / 14,
              color: theme.muted,
            ),
          ),
        ],
      ],
    );
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Press(
        focusNode: focus,
        radius: variant == 'cards'
            ? theme.radii.xl
            : (variant == 'pills' ? 999 : 4),
        onTap: (_) => f.set(o.value),
        builder: (hovered, pressed) {
          if (variant == 'list') {
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 17,
                    height: 17,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? theme.ink : Colors.transparent,
                      border: selected
                          ? null
                          : Border.all(color: theme.muted, width: 1.5),
                    ),
                    child: selected
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.onInk,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 6),
                          )
                        : null,
                  ),
                  const SizedBox(width: 9),
                  Flexible(child: text),
                ],
              ),
            );
          }
          final cards = variant == 'cards';
          final ringWidth = cards && selected ? 2.0 : 1.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.ease,
            constraints: const BoxConstraints(minHeight: 42),
            padding: cards
                ? EdgeInsets.symmetric(
                    vertical: 15 - ringWidth,
                    horizontal: 17 - ringWidth,
                  )
                : const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
            decoration: BoxDecoration(
              color: selected
                  ? (cards ? theme.pressed : theme.ink)
                  : (hovered ? theme.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(cards ? theme.radii.xl : 999),
              border: Border.all(
                color: selected ? theme.ink : theme.border,
                width: ringWidth,
              ),
            ),
            child: text,
          );
        },
      ),
    );
  }

  Widget options(List<FocusNode> nodes) => switch (variant) {
    'pills' => Wrap(
      spacing: theme.spacing.controlGap,
      runSpacing: theme.spacing.controlGap,
      children: [for (final (i, o) in choices.indexed) option(o, nodes[i])],
    ),
    'cards' => LayoutBuilder(
      builder: (context, box) {
        final gap = theme.spacing.controlGap;
        final columns = math.max(
          1,
          ((box.maxWidth + gap) / (200 + gap)).floor(),
        );
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0; start < choices.length; start += columns) ...[
              if (start > 0) SizedBox(height: gap),
              FlexRow(
                gap: gap,
                align: FlexAlign.stretch,
                children: [
                  for (
                    var i = start;
                    i < math.min(start + columns, choices.length);
                    i++
                  )
                    FlexRowItem(
                      fixed: (_) => width,
                      child: option(choices[i], nodes[i]),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
    _ => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, o) in choices.indexed) ...[
          if (i > 0) const SizedBox(height: 2),
          option(o, nodes[i]),
        ],
      ],
    ),
  };
  return Semantics(
    container: true,
    role: SemanticsRole.radioGroup,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_nonEmpty(label) != null) ...[
          Text(label!, style: _labelStyle(theme)),
          const SizedBox(height: 10),
        ],
        _RadioKeys(
          count: choices.length,
          selected: choices.indexWhere((o) => o.value == value),
          onSelect: (i) => f.set(choices[i].value),
          builder: options,
        ),
      ],
    ),
  );
}

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? _parseDate(String? value) {
  if (value == null || !_datePattern.hasMatch(value)) return null;
  final date = DateTime.tryParse(value);
  return date != null && _formatDate(date) == value ? date : null;
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Widget buildDatePicker(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = node.props.string('label');
  final f = _field(node, 'value', label);
  final current = f.value is String ? _parseDate(f.value as String) : null;
  final min = _parseDate(node.props.string('min'));
  final max = _parseDate(node.props.string('max'));
  final style = _text(
    theme,
    size: theme.fontSizeOf('DatePicker', 16),
    height: 1.4,
    tabular: true,
  );
  final localizations = MaterialLocalizations.of(context);
  final shown = current == null
      ? localizations.dateHelpText
      : localizations.formatCompactDate(current);
  return _labeled(
    theme,
    label,
    Semantics(
      button: true,
      label: _nonEmpty(label) == null
          ? OpenUiLocalizations.of(context).date
          : null,
      excludeSemantics: _nonEmpty(label) == null,
      value: current == null ? null : _formatDate(current),
      child: Press(
        radius: theme.radii.md,
        onTap: (ctx) async {
          final first = min ?? DateTime(1900);
          final last = max != null && !max.isBefore(first)
              ? max
              : (first.isAfter(DateTime(2100)) ? first : DateTime(2100));
          final today = Impure.toLocal(Impure.now());
          var initial = current ?? DateTime(today.year, today.month, today.day);
          if (initial.isBefore(first)) initial = first;
          if (initial.isAfter(last)) initial = last;
          if (Theme.of(ctx).platform == TargetPlatform.iOS) {
            await showCupertinoModalPopup<void>(
              context: ctx,
              builder: (popup) => _cupertinoThemed(
                theme,
                Container(
                  height: 260,
                  color: theme.canvas,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: CupertinoButton(
                            onPressed: () => Navigator.pop(popup),
                            child: Text(OpenUiLocalizations.of(ctx).done),
                          ),
                        ),
                        Expanded(
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
                            initialDateTime: initial,
                            minimumDate: first,
                            maximumDate: last,
                            onDateTimeChanged: (d) => f.set(_formatDate(d)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return;
          }
          final picked = await showDatePicker(
            context: ctx,
            initialDate: initial,
            firstDate: first,
            lastDate: last,
            builder: (_, child) =>
                Theme(data: _materialTheme(theme), child: child!),
          );
          if (picked != null) f.set(_formatDate(picked));
        },
        builder: (hovered, pressed) => Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.canvas,
            borderRadius: BorderRadius.circular(theme.radii.md),
            border: Border.all(color: theme.borderStrong),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shown,
                  style: current == null
                      ? style.copyWith(color: theme.faint)
                      : style,
                ),
              ),
              Opacity(
                opacity: 0.55,
                child: Glyph('calendar', size: 16, color: theme.ink),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Material colours and font from [t], for Material popups such as the date
/// picker, so they match a view whose theme differs from the app's.
ThemeData _materialTheme(OpenUiTheme t) => ThemeData(
  brightness: t.brightness,
  fontFamily: t.fontFamily,
  colorScheme: ColorScheme(
    brightness: t.brightness,
    primary: t.ink,
    onPrimary: t.onInk,
    secondary: t.ink,
    onSecondary: t.onInk,
    error: t.status['danger'] ?? t.ink,
    onError: t.onTone,
    surface: t.canvas,
    onSurface: t.ink,
  ),
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: t.ink,
    selectionColor: t.selection,
    selectionHandleColor: t.ink,
  ),
);

/// [child] with [t] as its OpenUI and Cupertino theme: a Cupertino popup
/// takes neither from the view that opens it.
Widget _cupertinoThemed(OpenUiTheme t, Widget child) => OpenUiThemeScope(
  theme: t,
  child: CupertinoTheme(
    data: CupertinoThemeData(
      brightness: t.brightness,
      primaryColor: t.ink,
      scaffoldBackgroundColor: t.canvas,
      textTheme: CupertinoTextThemeData(
        primaryColor: t.ink,
        dateTimePickerTextStyle: const CupertinoTextThemeData()
            .dateTimePickerTextStyle
            .copyWith(color: t.ink, fontFamily: t.fontFamily),
      ),
    ),
    child: child,
  ),
);
