/// THE LONG PRESS OF A NODE (schema 9.26.0, `longPress` and `longPressLabel`; rules in `x-longPress`).
///
/// A second action of a pressable container and of a list row: a finger kept down for [kLongPressMs] without moving
/// farther than [kLongPressSlop]. It has the form of `action` and runs along the same path (catalog, `track`, `haptic`,
/// `carryRecord`, `paramBindings`). It fires at the threshold while the finger is still down; the press of `action`
/// does not happen after it. Mirror of the contract's block; `test/long_press_cases_test.dart` runs the shared table
/// and compares the numbers with the artifact.
library;

/// How long a finger must stay down for a press to become a long one, in milliseconds.
const int kLongPressMs = 450;

/// How far a finger may move from the point of touch (logical pixels) before the press is neither a long press nor a
/// press: it scrolls or drags. The sheet drag starts from the same number.
const double kLongPressSlop = 10;

/// The props of a node that carry the long press and its name.
const String kLongPressKey = 'longPress';
const String kLongPressLabelKey = 'longPressLabel';

/// What a press of a node with a long press comes to.
enum LongPressOutcome { longPress, press, none }

/// What the press comes to: the long press at the threshold, the press on release, or nothing.
///
/// [moved] is the farthest the finger went from the point of touch BEFORE the threshold. A node without a long press
/// answers as it always did: a long hold released in place is a press.
LongPressOutcome longPressOutcome({
  required double heldMs,
  required double moved,
  required bool cancelled,
  required bool hasLongPress,
  required bool hasAction,
}) {
  if (cancelled || moved > kLongPressSlop) return LongPressOutcome.none;
  if (hasLongPress && heldMs >= kLongPressMs) return LongPressOutcome.longPress;
  return hasAction ? LongPressOutcome.press : LongPressOutcome.none;
}

/// Whether a key on a focused node performs the long press at once: the context menu key, or Shift+F10.
bool isLongPressKey({required String key, required bool shift}) => key == 'ContextMenu' || (key == 'F10' && shift);

/// Mirror of the scalar rows of `x-longPress`; checked against the artifact by a test.
const Map<String, Object> kLongPressRules = {
  'doesSomething': 'a type that is not «none», or «none» with «track»; otherwise the field is no long press',
  'fires': 'at the threshold while the finger is still down — not at release',
  'movedBeyondSlop': 'before the threshold — neither the long press nor the press: the finger scrolls or drags',
  'cancelled': 'nothing',
  'afterFire': 'releasing the finger does nothing; «action» is not run',
  'releasedEarlier': 'the press of «action» as before 9.26.0',
  'withoutLongPress': 'a long hold released in place is a press, as before 9.26.0',
  'secondaryButton': 'not a long press',
  'disabled': 'a container has no disabled state',
};
