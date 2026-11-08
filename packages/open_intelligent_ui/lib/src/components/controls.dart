import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../view.dart';
import 'glyph.dart';

typedef _Choice = ({String value, String label, String? description});

TextStyle _text(
  OpenUiTheme theme, {
  required double size,
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
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  decoration: TextDecoration.none,
);

TextStyle _labelStyle(OpenUiTheme theme) =>
    _text(theme, size: 14, weight: FontWeight.w500, height: 1.4);

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

FieldState _field(OpenUiNode node, String prop, String? label) =>
    node.field(prop, name: _nonEmpty(label));

Widget _labeled(OpenUiTheme theme, String? label, Widget child) {
  if (_nonEmpty(label) == null) return child;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label!, style: _labelStyle(theme)),
      const SizedBox(height: 8),
      child,
    ],
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
String _numberText(double value) {
  final fixed = value.toStringAsFixed(2);
  final negative = fixed.startsWith('-');
  final parts = (negative ? fixed.substring(1) : fixed).split('.');
  final grouped = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  final fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$grouped${fraction.isEmpty ? '' : '.$fraction'}';
}

String _textOf(BuildContext context) {
  final parts = <String>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is RichText) {
      if (widget.text.style?.fontFamily?.contains('IuiLucide') != true) {
        parts.add(widget.text.toPlainText());
      }
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  final text = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.substring(0, math.min(120, text.length));
}

/// Hover, press and keyboard focus for a tappable surface.
class _Press extends StatefulWidget {
  const _Press({required this.builder, required this.onTap, this.radius = 999});

  final Widget Function(bool hovered, bool pressed) builder;
  final void Function(BuildContext context)? onTap;
  final double radius;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final theme = OpenUiTheme.of(context);
    return FocusableActionDetector(
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
                Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
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

Widget buildButton(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = node.props['label'] == null
      ? ''
      : jsString(node.props['label']);
  final variant = node.props.string('variant') ?? 'solid';
  final tone = node.props.string('color');
  final size = node.props.string('size') ?? 'md';
  final icon = node.props.string('icon');
  final enabled = node.props.boolean('disabled') != true && !node.isStreaming;
  final toneColor = switch (tone) {
    'danger' || 'success' => theme.status[tone],
    _ => null,
  };
  final (minHeight, padding, fontSize) = switch (size) {
    'sm' => (
      32.0,
      const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      13.0,
    ),
    'lg' => (
      44.0,
      const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      15.0,
    ),
    _ => (36.0, const EdgeInsets.symmetric(vertical: 8, horizontal: 16), 14.0),
  };
  final button = _Press(
    onTap: enabled
        ? (_) => node.run('action', label: label, sendLabel: true)
        : null,
    builder: (hovered, pressed) {
      final overlay = pressed
          ? theme.pressed
          : hovered
          ? theme.hover
          : null;
      Color? background;
      Color foreground = toneColor ?? theme.ink;
      Color? border;
      EdgeInsets pad = padding;
      switch (variant) {
        case 'outline':
          background = Color.alphaBlend(
            overlay ?? const Color(0x00000000),
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
            foreground = theme.brightness == Brightness.dark
                ? const Color(0xFF121212)
                : const Color(0xFFFFFFFF);
          } else {
            background = hovered && !pressed ? theme.inkHover : theme.ink;
            foreground = theme.onInk;
          }
      }
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: pad,
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border ?? const Color(0x00000000)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Glyph(icon, size: size == 'sm' ? 14 : 16, color: foreground),
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
                    color: foreground,
                    weight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  final semantic = Semantics(button: true, enabled: enabled, child: button);
  if (node.props.boolean('block') == true) {
    return SizedBox(width: double.infinity, child: semantic);
  }
  return Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    heightFactor: 1,
    child: semantic,
  );
}

Widget buildIconButton(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final icon = node.props.string('icon') ?? '';
  final given = _nonEmpty(node.props.string('label'));
  final label = given ?? icon;
  final variant = node.props.string('variant') ?? 'outline';
  final enabled = !node.isStreaming;
  Widget button = _Press(
    onTap: enabled ? (_) => node.run('action', label: label) : null,
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
          const Color(0x00000000),
        ),
        'solid' => (
          hovered && !pressed ? theme.inkHover : theme.ink,
          theme.onInk,
          theme.ink,
        ),
        _ => (
          Color.alphaBlend(overlay ?? const Color(0x00000000), theme.canvas),
          theme.ink,
          theme.border,
        ),
      };
      return Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: border),
          ),
          child: Glyph(icon, size: 16, color: foreground),
        ),
      );
    },
  );
  if (given != null) button = Tooltip(message: given, child: button);
  return Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    heightFactor: 1,
    child: Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: button,
    ),
  );
}

Widget buildPressable(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final streaming = node.isStreaming;
  final selected = node.props.boolean('selected') == true;
  final radius =
      OpenUiTheme.radius(node.props['radius']) ?? OpenUiTheme.radiusLg;
  final hasRow = node.props
      .elements('children')
      .any((e) => e.typeName == 'Row');
  final on = theme.inkOn(node.props['background']);
  final padding = OpenUiTheme.space(node.props.number('padding'));
  final shape = BorderRadius.circular(radius);
  Widget content = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: node.children(),
  );
  if (on != null) {
    content = Theme(
      data: Theme.of(context).copyWith(extensions: [theme.withInk(on)]),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: on),
        child: content,
      ),
    );
  }
  final ring = selected && !hasRow;
  return Semantics(
    button: true,
    enabled: !streaming,
    selected: selected,
    child: _Press(
      radius: radius,
      onTap: streaming
          ? null
          : (ctx) => node.run('action', label: _textOf(ctx)),
      builder: (hovered, pressed) {
        final scale = hasRow ? 1.0 : (pressed ? 0.98 : (hovered ? 1.01 : 1.0));
        final overlay = pressed
            ? 0.08
            : hovered
            ? 0.05
            : (ring ? 0.06 : 0.0);
        return AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          child: Stack(
            children: [
              Container(
                padding: padding == null ? null : EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: theme.bg(node.props['background']),
                  borderRadius: shape,
                ),
                foregroundDecoration: ring
                    ? BoxDecoration(
                        borderRadius: shape,
                        border: Border.all(
                          color: theme.ink.withValues(alpha: 0.2),
                        ),
                      )
                    : null,
                child: content,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.ink.withValues(alpha: overlay),
                      borderRadius: shape,
                    ),
                  ),
                ),
              ),
              if (ring)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.ink,
                      shape: BoxShape.circle,
                    ),
                    child: Glyph('check', size: 12, color: theme.onInk),
                  ),
                ),
            ],
          ),
        );
      },
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
    final style = _text(theme, size: 16, height: 1.4, tabular: true);
    final rows = widget.rows;
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, child) => Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.canvas,
          borderRadius: BorderRadius.circular(OpenUiTheme.radiusMd),
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
        child: child,
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
  final style = _text(theme, size: 16, height: 1.4);
  return _labeled(
    theme,
    label,
    Container(
      constraints: const BoxConstraints(minHeight: 42),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 12, right: 12),
      decoration: BoxDecoration(
        color: theme.canvas,
        borderRadius: BorderRadius.circular(OpenUiTheme.radiusMd),
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
              node.props.string('placeholder') ?? 'Choose…',
              style: style.copyWith(color: theme.faint),
            ),
            style: style,
            dropdownColor: theme.canvas,
            borderRadius: BorderRadius.circular(OpenUiTheme.radiusMd),
            icon: Glyph('chevron-down', size: 16, color: theme.muted),
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

Widget buildSegmentedControl(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final f = _field(node, 'value', null);
  final value = _plain(f.value);
  final block = node.props.boolean('block') == true;
  final dark = theme.brightness == Brightness.dark;
  Widget segment(_Choice o) {
    final selected = o.value == value;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: _Press(
        onTap: (_) => f.set(o.value),
        builder: (hovered, pressed) => Container(
          alignment: block ? Alignment.center : null,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? theme.surfaceStrong : theme.canvas)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(999),
            border: selected ? Border.all(color: theme.border) : null,
            boxShadow: selected ? theme.shadowSmall : null,
          ),
          child: Text(
            o.label,
            softWrap: false,
            style: _text(
              theme,
              size: 13,
              height: 1.4,
              color: selected || hovered ? theme.ink : theme.muted,
              weight: selected ? FontWeight.w500 : null,
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
        ? Row(
            children: [
              for (final (i, o) in choices.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(child: segment(o)),
              ],
            ],
          )
        : Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [for (final o in choices) segment(o)],
          ),
  );
  return block
      ? bar
      : Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: bar,
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
  final raw = f.value is num && (f.value as num).isFinite
      ? (f.value as num).toDouble()
      : null;
  final value = raw == null ? min : raw.clamp(min, max).toDouble();
  final unit = node.props.string('unit') ?? '';
  final prefix = RegExp(r'^[$€£¥₹]').hasMatch(unit);
  final readout = prefix
      ? '$unit${_numberText(value)}'
      : '${_numberText(value)}$unit';
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
  final small = _text(theme, size: 13, height: 1.4);
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
                size: 12,
                height: 1.4,
                weight: FontWeight.w500,
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
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            min: min,
            max: max,
            value: value,
            semanticFormatterCallback: (_) => readout,
            onChanged: (v) {
              final snapped = min + ((v - min) / step).round() * step;
              final next = double.parse(
                snapped.clamp(min, max).toStringAsFixed(10),
              );
              f.set(next == next.truncateToDouble() ? next.toInt() : next);
            },
          ),
        ),
      ),
      if (marks.isNotEmpty)
        ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, box) {
              final style = _text(
                theme,
                size: 11,
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
                        Positioned(
                          left: 0,
                          child: Text(m.label, softWrap: false, style: style),
                        )
                      else if (m.at >= 0.98)
                        Positioned(
                          right: 0,
                          child: Text(m.label, softWrap: false, style: style),
                        )
                      else
                        Positioned(
                          left: 9 + (box.maxWidth - 18) * m.at,
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

Widget buildCheckbox(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final label = node.props['label'] == null
      ? ''
      : jsString(node.props['label']);
  final f = _field(node, 'checked', label);
  final checked = f.value == true;
  final done = checked && node.props.boolean('lineThrough') == true;
  return Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    heightFactor: 1,
    child: Semantics(
      checked: checked,
      label: label,
      child: _Press(
        radius: 4,
        onTap: (_) => f.set(!checked),
        builder: (hovered, pressed) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 17,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: checked ? theme.ink : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(4),
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
                child: Text(
                  label,
                  style:
                      _text(
                        theme,
                        size: 16,
                        color: done ? theme.muted : theme.ink,
                      ).copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: done ? theme.muted : null,
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

  Widget option(_Choice o) {
    final selected = o.value == value;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          o.label,
          style: _text(
            theme,
            size: variant == 'list' ? 16 : 15,
            height: variant == 'list' ? null : 22 / 15,
            weight: variant == 'cards' ? FontWeight.w500 : null,
            color: variant == 'pills' && selected ? theme.onInk : theme.ink,
          ),
        ),
        if (o.description != null) ...[
          const SizedBox(height: 2),
          Text(
            o.description!,
            style: _text(theme, size: 14, height: 21 / 14, color: theme.muted),
          ),
        ],
      ],
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: _Press(
        radius: variant == 'cards' ? 14 : (variant == 'pills' ? 999 : 4),
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
                      color: selected ? theme.ink : const Color(0x00000000),
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
          return Container(
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
                  : (hovered ? theme.hover : const Color(0x00000000)),
              borderRadius: BorderRadius.circular(cards ? 14 : 999),
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

  Widget options;
  switch (variant) {
    case 'pills':
      options = Wrap(
        spacing: OpenUiTheme.controlGap,
        runSpacing: OpenUiTheme.controlGap,
        children: [for (final o in choices) option(o)],
      );
    case 'cards':
      options = LayoutBuilder(
        builder: (context, box) {
          const gap = OpenUiTheme.controlGap;
          final columns = math.max(
            1,
            ((box.maxWidth + gap) / (200 + gap)).floor(),
          );
          final width = (box.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final o in choices) SizedBox(width: width, child: option(o)),
            ],
          );
        },
      );
    default:
      options = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, o) in choices.indexed) ...[
            if (i > 0) const SizedBox(height: 2),
            option(o),
          ],
        ],
      );
  }
  return Semantics(
    container: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_nonEmpty(label) != null) ...[
          Text(label!, style: _labelStyle(theme)),
          const SizedBox(height: 10),
        ],
        options,
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
  final style = _text(theme, size: 16, height: 1.4, tabular: true);
  final shown = current == null
      ? 'mm/dd/yyyy'
      : '${current.month.toString().padLeft(2, '0')}/${current.day.toString().padLeft(2, '0')}/${current.year.toString().padLeft(4, '0')}';
  return _labeled(
    theme,
    label,
    Semantics(
      button: true,
      label: _nonEmpty(label) ?? 'Date',
      value: current == null ? null : _formatDate(current),
      child: _Press(
        radius: OpenUiTheme.radiusMd,
        onTap: (ctx) async {
          final first = min ?? DateTime(1900);
          final last = max != null && !max.isBefore(first)
              ? max
              : (first.isAfter(DateTime(2100)) ? first : DateTime(2100));
          final today = DateTime.now();
          var initial = current ?? DateTime(today.year, today.month, today.day);
          if (initial.isBefore(first)) initial = first;
          if (initial.isAfter(last)) initial = last;
          final picked = await showDatePicker(
            context: ctx,
            initialDate: initial,
            firstDate: first,
            lastDate: last,
          );
          if (picked != null) f.set(_formatDate(picked));
        },
        builder: (hovered, pressed) => Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.canvas,
            borderRadius: BorderRadius.circular(OpenUiTheme.radiusMd),
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
