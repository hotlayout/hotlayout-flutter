// Keeps a held key from counting as repeated presses.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyRepeatEvent, LogicalKeyboardKey;

/// Key auto-repeat is not a press (`x-style.layout` `keyAutoRepeat: 'not-a-press'`).
///
/// A held activation key (Enter, space) sends a `KeyDownEvent` and then a `KeyRepeatEvent`
/// roughly every 30 ms, and `Shortcuts` → the Material button's `ActivateIntent` would run
/// `onPressed` on every repeat: one held key would mean ten analytics events and ten
/// `openUrl` calls. This swallows the repeat of an activation key BEFORE it reaches the
/// `Shortcuts` above the button; the first press (`KeyDownEvent`) and the release pass through
/// unchanged. A double press is two presses, and guarding against it is up to the host.
///
/// `Focus` without a focus of its own: it is not part of the Tab traversal, but it sees the
/// key events travelling up the focus tree from the button.
class KeyRepeatGuard extends StatelessWidget {
  const KeyRepeatGuard({super.key, required this.child});

  final Widget child;

  static bool _isActivation(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.select;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) =>
        event is KeyRepeatEvent && _isActivation(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
    child: child,
  );
}

