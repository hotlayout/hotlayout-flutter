/// What the long press (schema 9.26.0, `x-longPress`) needs besides the pointer: the trace of one hold, the keys that
/// perform it at once, and the name a screen reader gives it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// What one hold of a finger came to, written by [PressFeedback] and read by the tap of the same node.
///
/// The long press fires at the threshold while the finger is still down, and then the lifted finger must not press
/// ("`action` is not run after it"). A finger that went farther than the touch slop before it fired is neither a
/// long press nor a press: it scrolls or drags. The trace is reset by the next finger that goes down on the node.
class HoldTrace {
  bool fired = false;
  bool movedFar = false;

  void begin() {
    fired = false;
    movedFar = false;
  }

  /// Whether the tap that follows this hold must be dropped.
  bool get suppressTap => fired || movedFar;
}

/// The intent behind the keys that perform the long press of the focused node.
class LongPressIntent extends Intent {
  const LongPressIntent();
}

/// The context menu key and Shift+F10 (`accessibility.keys`), at once, with no threshold. Enter and Space stay the
/// press of `action`.
const Map<ShortcutActivator, Intent> kLongPressKeyBindings = {
  SingleActivator(LogicalKeyboardKey.contextMenu): LongPressIntent(),
  SingleActivator(LogicalKeyboardKey.contextMenu, shift: true): LongPressIntent(),
  SingleActivator(LogicalKeyboardKey.f10, shift: true): LongPressIntent(),
};

/// The semantics of a node with a long press: a named custom action when the document gave an audible name
/// (`longPressLabel`), the platform's own long press action otherwise.
({VoidCallback? onLongPress, Map<CustomSemanticsAction, VoidCallback>? custom}) longPressSemantics({
  required VoidCallback? onLongPress,
  required String? name,
}) {
  if (onLongPress == null) return (onLongPress: null, custom: null);
  if (name == null || name.isEmpty) return (onLongPress: onLongPress, custom: null);
  return (onLongPress: null, custom: {CustomSemanticsAction(label: name): onLongPress});
}
