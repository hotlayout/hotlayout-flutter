/// A node whose action writes, as a control on the finished screen (schema 9.19.0, `x-choice`).
library;

import 'package:flutter/material.dart';

import '../../model/action.dart';
import '../../model/write_action.dart';
import '../node_renderer.dart';

extension WriteControlWidgets on NodeRenderer {
  /// The control a node with [action] is, from the action and the data it reads NOW (`null`: a plain button).
  /// Nothing is held in a widget: the state is recomputed on every build, which follows every write and every
  /// change of the data.
  WriteControl? controlOfAction(ButtonAction? action) => action == null ? null : writeControlOf(action, data.lookup);

  /// [child] (a button, an icon button, a list row) with the semantics of [control]: an option of a choice is a
  /// radio with a checked state, a toggle is a button with a toggled state. The look of "selected" is the
  /// document's (`styleWhen`); the reader adds none.
  ///
  /// The child's own semantics are replaced by one node that says the same thing (the [name], whether it is
  /// available, the press) plus the state: a Material button would add `button` to a radio.
  Widget withWriteControl({
    required WriteControl? control,
    required String name,
    required bool disabled,
    required VoidCallback? onPress,
    required Widget child,
  }) {
    if (control == null) return child;
    final toggle = control.role == WriteControlRole.toggle;
    return Semantics(
      container: true,
      label: name.isEmpty ? null : name,
      button: toggle,
      toggled: toggle ? control.on : null,
      inMutuallyExclusiveGroup: toggle ? null : true,
      checked: toggle ? null : control.on,
      enabled: !disabled,
      onTap: disabled ? null : onPress,
      child: ExcludeSemantics(child: child),
    );
  }
}
