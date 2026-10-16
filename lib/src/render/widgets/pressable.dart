/// A pressable container: a column, row, container or stack that holds an `action`
/// (schema 9.19.0, `x-style.layout.composition.pressable`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/tokens.dart';
import '../key_repeat_guard.dart';
import '../long_press_hold.dart';
import '../press_feedback.dart';
import '../../model/press_feedback.dart';
import '../../model/write_action.dart';
import '../node_renderer.dart';
import 'write_control.dart';

extension PressableWidgets on NodeRenderer {
  /// What wraps the box of [node] if it is a pressable container, or `null`.
  ///
  /// The wrapper goes AROUND the box (background, border, padding) and INSIDE the margin: the target is
  /// the node's box without its margin (`pressable.target`). The action runs through [emit], the same
  /// path as a button's, in the record scope of this node.
  ///
  /// [own] is the style of the node now: its radius is the radius of the ring that shows the keyboard focus.
  Widget Function(Widget box)? pressWrapperOf(ChildNode node, NodeStyle? own) {
    final press = node.press;
    if (press == null) return null;
    final label = press.label == null ? '' : text(press.label!);
    final longPress = press.longPress;
    final longLabel = press.longPressLabel == null ? '' : text(press.longPressLabel!);
    return (box) => PressableCard(
      key: ValueKey<String>('sdui-press-${node.id}@${instance.join('.')}'),
      label: isSilentAccessibleName(label) ? null : label,
      longPressLabel: isSilentAccessibleName(longLabel) ? null : longLabel,
      control: controlOfAction(press.action),
      feedback: pressFeedbackKindOf(node),
      focusRing: theme.color(ColorToken.primary),
      focusRadius: theme.resolveBoxRadius(own?.radius),
      // A card that holds only a long press has no tap: the press does nothing, but it still takes the tap.
      onPress: press.hasAction ? () => emit(press.action, node.id) : null,
      onLongPress: longPress == null ? null : () => emit(longPress, node.id),
      child: box,
    );
  }
}

/// A card that is a button.
///
/// *Who takes the press.* The card registers one tap recognizer over its whole box. A control inside has
/// its own recognizer and is deeper in the hit-test path, so it wins the gesture arena and the card gets
/// nothing (neither the action nor the analytics event). Content (text, picture, an ordinary row) has no
/// recognizer, so the press lands on the card. A DISABLED button keeps a recognizer that does nothing,
/// which is how it swallows the press instead of passing it on.
///
/// *Meaning.* One semantics node: a button whose name is the `label` first and then the text of the
/// content. The controls inside form their own nodes (the card does not merge them), each with its own
/// name.
///
/// *Keyboard.* A focus stop before the controls inside; Enter and Space press; a held key's auto-repeat
/// is not a press ([KeyRepeatGuard]).
///
/// *Long press* (schema 9.26.0). [onLongPress] fires at the threshold while the finger is down, and the lifted finger
/// then presses nothing; the context menu key and Shift+F10 perform it at once on the focused card. A screen reader
/// gets it as a custom action named by [longPressLabel]. A card that has only a long press has no [onPress]: it is
/// still a control (it is focused, named and sinks under the finger), and a tap on it does nothing.
class PressableCard extends StatefulWidget {
  const PressableCard({
    super.key,
    required this.onPress,
    required this.child,
    this.onLongPress,
    this.longPressLabel,
    this.label,
    this.control,
    this.feedback,
    this.focusRing,
    this.focusRadius,
  });

  /// The tap; `null` for a card that has only a long press.
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final Widget child;

  /// The name of the long press for a screen reader, or `null` when there is none that can be heard.
  final String? longPressLabel;

  /// The hidden name, or `null` when there is none (then the name is the text of the content).
  final String? label;

  /// What a write action makes of the card (`x-choice`): an option of a choice (a radio with a checked state) or a
  /// toggle (a button with a toggled state); `null` for a card that does something else.
  final WriteControl? control;

  /// How the card sinks under the finger (9.25.0); `null` when the node turned the feedback off.
  final PressFeedbackKind? feedback;

  /// The colour of the ring drawn when the keyboard focus is on the card, or `null` for no ring, and the radius of
  /// the card it follows. Touch focus shows nothing.
  final Color? focusRing;
  final BorderRadiusGeometry? focusRadius;

  static const Map<ShortcutActivator, Intent> _keys = {
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _focused = false;
  final HoldTrace _hold = HoldTrace();

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final onPress = widget.onPress;
    final onLongPress = widget.onLongPress;
    final long = longPressSemantics(onLongPress: onLongPress, name: widget.longPressLabel);
    // The ring is shown for the keyboard only, like the ring of a switch or a checkbox.
    final ring = _focused && widget.focusRing != null && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Shortcuts(
      shortcuts: {
        if (onPress != null) ...PressableCard._keys,
        if (onLongPress != null) ...kLongPressKeyBindings,
      },
      child: Actions(
        actions: {
          if (onPress != null)
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onPress();
                return null;
              },
            ),
          if (onLongPress != null)
            LongPressIntent: CallbackAction<LongPressIntent>(
              onInvoke: (_) {
                onLongPress();
                return null;
              },
            ),
        },
        child: KeyRepeatGuard(
          child: Focus(
            onFocusChange: (focused) {
              if (mounted && _focused != focused) setState(() => _focused = focused);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                button: control?.role != WriteControlRole.option,
                toggled: control?.role == WriteControlRole.toggle ? control!.on : null,
                inMutuallyExclusiveGroup: control?.role == WriteControlRole.option ? true : null,
                checked: control?.role == WriteControlRole.option ? control!.on : null,
                label: widget.label,
                onTap: onPress,
                onLongPress: long.onLongPress,
                customSemanticsActions: long.custom,
                // The recognizer does not describe itself: the node above already says "button" and
                // carries the tap action, and a second one would split the node and the text content.
                child: PressFeedback(
                  kind: widget.feedback,
                  onLongPress: onLongPress,
                  hold: _hold,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    // Always a recognizer, so a tap on a card with no tap of its own does not fall to the card around
                    // it; after a long press that fired, or a finger that moved off, the tap is dropped.
                    onTap: () {
                      if (_hold.suppressTap) return;
                      onPress?.call();
                    },
                    // The structure is the same with and without the ring, so the state of what is inside survives
                    // the focus coming and going.
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: ring
                          ? BoxDecoration(borderRadius: widget.focusRadius, border: Border.all(color: widget.focusRing!, width: 2))
                          : const BoxDecoration(),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
