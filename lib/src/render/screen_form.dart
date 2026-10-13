// The form of a screen and the press of a disabled button.
library;

import 'package:flutter/material.dart';

import '../data/screen_data.dart';
import '../model/form_rules.dart';
import '../model/input_rules.dart';
import '../model/node.dart';

final class ScreenForm {
  ScreenForm({required this.root, required this.data});

  final UiNode root;
  final ScreenData data;
  bool? _filled;

  bool get filled => _filled ??= isFormFilled(root, data);
}

/// Disabled button: half transparent and not pressable, but still in the focus order.
/// A Material button with `onPressed: null` takes no focus itself, so this wrapper does.
///
/// It also SWALLOWS a press: the empty tap recognizer wins the gesture arena over a pressable card around
/// the button (schema 9.19.0, `pressable.press.disabledControlInside`), so neither the button nor the card
/// does anything. It does not describe itself to the screen reader: the button already says it is
/// unavailable.
class DisabledPress extends StatelessWidget {
  const DisabledPress({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: Opacity(opacity: kInputDisabledOpacity, child: child),
    ),
  );
}
