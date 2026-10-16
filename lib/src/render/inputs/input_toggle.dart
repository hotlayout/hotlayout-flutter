/// The switch and the checkbox.
library;

import '../press_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../model/input_rules.dart';
import '../../model/tokens.dart';
import '../../theme/render_theme.dart';
import '../icon_glyph.dart';
import 'input_label.dart';

// ───────────────────────────── switch and checkbox ─────────────────────────────

enum InputToggleKind { switchControl, checkbox }

/// A switch or a checkbox: a full-width row whose whole strip is tappable. The drawing follows
/// the data of the `x-style.layout.inputs.switch` / `checkbox` blocks.
class InputToggle extends StatefulWidget {
  const InputToggle({
    required this.kind,
    required this.theme,
    required this.label,
    required this.bound,
    required this.path,
    required this.disabled,
    required this.onWrite,
    this.mandatory = false,
    super.key,
  });

  /// Required (schema 9.14.0): an asterisk after the label (checkbox only) and a state for the
  /// screen reader. A switch is never required.
  final bool mandatory;

  final InputToggleKind kind;
  final RenderTheme theme;
  final String label;

  /// What the data layers currently give (`readInputFlag`).
  final bool bound;
  final String? path;
  final bool disabled;
  final ValueChanged<bool>? onWrite;

  @override
  State<InputToggle> createState() => _InputToggleState();
}

class _InputToggleState extends State<InputToggle> {
  ToggleState _state = kInitialToggle;
  final FocusNode _focus = FocusNode(debugLabel: 'sdui-toggle');
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && _hadFocus != _focus.hasFocus) setState(() => _hadFocus = _focus.hasFocus);
    });
  }

  @override
  void didUpdateWidget(InputToggle old) {
    super.didUpdateWidget(old);
    if (old.bound != widget.bound) _state = syncToggle(_state, widget.bound);
    if (widget.disabled && !old.disabled && _focus.hasFocus) _focus.unfocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _on => shownToggle(_state, widget.bound);

  void _press() {
    final result = pressToggle(_state, widget.bound, disabled: widget.disabled, hasPath: widget.path != null);
    setState(() => _state = result.state);
    final write = result.write;
    if (write != null) widget.onWrite?.call(write);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.disabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final activates =
        key == LogicalKeyboardKey.space ||
        (widget.kind == InputToggleKind.switchControl &&
            (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter));
    if (!activates) return KeyEventResult.ignored;
    // Auto-repeat of a held key is not a press: it is swallowed, and only the first press
    // toggles.
    if (event is KeyDownEvent) _press();
    return event is KeyUpEvent ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final on = _on;
    final isSwitch = widget.kind == InputToggleKind.switchControl;
    final labelStyle = theme.text(TypographyToken.bodyM).copyWith(color: theme.color(ColorToken.onSurface));
    final labelLine = (labelStyle.fontSize ?? 14) * (labelStyle.height ?? 1.0);
    final label = requiredLabel(
      widget.label,
      style: labelStyle,
      strut: StrutStyle(
        fontFamily: labelStyle.fontFamily,
        fontSize: labelStyle.fontSize,
        height: labelStyle.height,
        forceStrutHeight: true,
      ),
      mark: widget.mandatory && !isSwitch
          ? RequiredMark(color: theme.color(ColorToken.danger), gap: theme.space(SpacingToken.xs))
          : null,
    );
    final showFocus = _hadFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final primary = theme.color(ColorToken.primary);

    Widget row;
    if (isSwitch) {
      final track = _SwitchTrack(theme: theme, on: on, focusRing: showFocus ? primary : null);
      final gap = theme.space(SpacingToken.md);
      Widget line(Widget text) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: text),
          SizedBox(width: gap),
          track,
        ],
      );
      row = _Narrow(
        // The track and the gap are the least the row must have; in a narrower space the label
        // gets zero width (`switchLabelWidthOf`) and is not drawn (at zero width it would wrap
        // letter by letter), and the rest is clipped.
        least: kSwitchTrackWidth + gap,
        narrow: line(const SizedBox.shrink()),
        child: line(label),
      );
    } else {
      final box = _CheckboxBox(theme: theme, on: on, focusRing: showFocus ? primary : null);
      final gap = theme.space(SpacingToken.sm);
      Widget line(Widget text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: checkboxBoxOffsetOf(labelLine)),
            child: box,
          ),
          SizedBox(width: gap),
          Expanded(child: text),
        ],
      );
      row = _Narrow(least: kCheckboxBoxSize + gap, narrow: line(const SizedBox.shrink()), child: line(label));
    }

    Widget result = Semantics(
      container: true,
      enabled: !widget.disabled,
      label: widget.label,
      isRequired: widget.mandatory && !isSwitch ? true : null,
      toggled: isSwitch ? on : null,
      checked: isSwitch ? null : on,
      onTap: widget.disabled ? null : _press,
      excludeSemantics: true,
      child: Focus(
        focusNode: _focus,
        canRequestFocus: !widget.disabled,
        skipTraversal: widget.disabled,
        onKeyEvent: _onKey,
        child: PressFeedback(
          kind: null,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.disabled ? null : _press, child: row),
        ),
      ),
    );
    if (widget.disabled) result = Opacity(opacity: kInputDisabledOpacity, child: result);
    return result;
  }
}

/// A control row that may run short of room: in a space narrower than [least] the row is laid out
/// at [least] and clipped rather than overflowing (a `Row` there would throw a layout error).
class _Narrow extends StatelessWidget {
  const _Narrow({required this.least, required this.child, required this.narrow});

  final double least;
  final Widget child;

  /// The row without a label, for a space where the label has no width.
  final Widget narrow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || constraints.maxWidth > least) return child;
      if (constraints.maxWidth == least) return narrow;
      return UnconstrainedBox(
        alignment: AlignmentDirectional.centerStart,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: least, child: narrow),
      );
    },
  );
}

class _SwitchTrack extends StatelessWidget {
  const _SwitchTrack({required this.theme, required this.on, required this.focusRing});

  final RenderTheme theme;
  final bool on;
  final Color? focusRing;

  @override
  Widget build(BuildContext context) {
    final trackColor = theme.color(on ? ColorToken.primary : ColorToken.muted);
    final thumbColor = theme.color(on ? ColorToken.onPrimary : ColorToken.surface);
    return SizedBox(
      width: kSwitchTrackWidth,
      height: kSwitchTrackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              key: const ValueKey('sdui-switch-track'),
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(theme.radius(RadiusToken.pill)),
              ),
            ),
          ),
          PositionedDirectional(
            start: switchThumbOffsetOf(on),
            top: (kSwitchTrackHeight - kSwitchThumbSize) / 2,
            child: DecoratedBox(
              key: const ValueKey('sdui-switch-thumb'),
              decoration: BoxDecoration(color: thumbColor, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: kSwitchThumbSize),
            ),
          ),
          if (focusRing != null)
            Positioned.fill(
              left: -3,
              top: -3,
              right: -3,
              bottom: -3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(theme.radius(RadiusToken.pill)),
                    border: Border.all(color: focusRing!, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckboxBox extends StatelessWidget {
  const _CheckboxBox({required this.theme, required this.on, required this.focusRing});

  final RenderTheme theme;
  final bool on;
  final Color? focusRing;

  @override
  Widget build(BuildContext context) {
    final primary = theme.color(ColorToken.primary);
    final box = Container(
      key: const ValueKey('sdui-checkbox-box'),
      width: kCheckboxBoxSize,
      height: kCheckboxBoxSize,
      decoration: BoxDecoration(
        color: on ? primary : null,
        borderRadius: BorderRadius.circular(kCheckboxBoxRadius),
        border: Border.all(color: on ? primary : theme.color(ColorToken.muted), width: kCheckboxBorderWidth),
      ),
      alignment: Alignment.center,
      // The check mark is the set's `check` icon, 16 on a side, independent of the font scale and
      // not mirrored (it is not in `x-mirroredIcons`).
      child: on
          ? MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
              child: IconGlyph(IconToken.check, size: kCheckboxMarkSize, color: theme.color(ColorToken.onPrimary)),
            )
          : null,
    );
    if (focusRing == null) return box;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          left: -3,
          top: -3,
          right: -3,
          bottom: -3,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kCheckboxBoxRadius + 3),
                border: Border.all(color: focusRing!, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

