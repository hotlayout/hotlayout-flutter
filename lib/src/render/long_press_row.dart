/// A list row that has a long press (schema 9.26.0, `x-longPress`).
library;

import 'package:flutter/material.dart';

import '../model/press_feedback.dart';
import 'long_press_hold.dart';
import 'press_feedback.dart';
import 'tap_target.dart';

/// The touch, the keys and the semantics of a row whose document gave it a `longPress`.
///
/// The row's `action`, when it has one, is [onPress]; the long press fires at the threshold while the finger is down
/// and the lifted finger then presses nothing. The context menu key and Shift+F10 perform it at once on the focused
/// row (a row with no long press is not a focus stop, as before). A screen reader gets the long press as a custom
/// action named by [longPressLabel]. A row with only a long press is still a control: a tap on it does nothing.
class LongPressRow extends StatefulWidget {
  const LongPressRow({
    super.key,
    required this.child,
    required this.onLongPress,
    this.onPress,
    this.longPressLabel,
    this.feedback,
  });

  final Widget child;
  final VoidCallback onLongPress;
  final VoidCallback? onPress;

  /// The name of the long press for a screen reader, or `null` when there is none that can be heard.
  final String? longPressLabel;

  /// How the row sinks under the finger (9.25.0); `null` when it gives no feedback.
  final PressFeedbackKind? feedback;

  @override
  State<LongPressRow> createState() => _LongPressRowState();
}

class _LongPressRowState extends State<LongPressRow> {
  final HoldTrace _hold = HoldTrace();

  @override
  Widget build(BuildContext context) {
    final long = longPressSemantics(onLongPress: widget.onLongPress, name: widget.longPressLabel);
    return Shortcuts(
      shortcuts: kLongPressKeyBindings,
      child: Actions(
        actions: {
          LongPressIntent: CallbackAction<LongPressIntent>(
            onInvoke: (_) {
              widget.onLongPress();
              return null;
            },
          ),
        },
        child: Focus(
          child: Semantics(
            button: true,
            onLongPress: long.onLongPress,
            customSemanticsActions: long.custom,
            child: TapTarget(
              child: PressFeedback(
                kind: widget.feedback,
                onLongPress: widget.onLongPress,
                hold: _hold,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Always a recognizer: a tap on a row with no tap of its own does not fall to what is around it.
                  onTap: () {
                    if (_hold.suppressTap) return;
                    widget.onPress?.call();
                  },
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
