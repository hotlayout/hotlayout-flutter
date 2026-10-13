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
    return (box) => PressableCard(
      key: ValueKey<String>('sdui-press-${node.id}@${instance.join('.')}'),
      label: isSilentAccessibleName(label) ? null : label,
      control: controlOfAction(press.action),
      focusRing: theme.color(ColorToken.primary),
      focusRadius: theme.resolveBoxRadius(own?.radius),
      onPress: () => emit(press.action, node.id),
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
class PressableCard extends StatefulWidget {
  const PressableCard({
    super.key,
    required this.onPress,
    required this.child,
    this.label,
    this.control,
    this.focusRing,
    this.focusRadius,
  });

  final VoidCallback onPress;
  final Widget child;

  /// The hidden name, or `null` when there is none (then the name is the text of the content).
  final String? label;

  /// What a write action makes of the card (`x-choice`): an option of a choice (a radio with a checked state) or a
  /// toggle (a button with a toggled state); `null` for a card that does something else.
  final WriteControl? control;

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

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final onPress = widget.onPress;
    // The ring is shown for the keyboard only, like the ring of a switch or a checkbox.
    final ring = _focused && widget.focusRing != null && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Shortcuts(
      shortcuts: PressableCard._keys,
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onPress();
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
                // The recognizer does not describe itself: the node above already says "button" and
                // carries the tap action, and a second one would split the node and the text content.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: onPress,
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
    );
  }
}
