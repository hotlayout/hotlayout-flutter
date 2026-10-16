import 'node.dart';
import 'tokens.dart';

/// THE FEEDBACK OF A PRESSED NODE (schema 9.25.0, `pressFeedback` and `x-pressFeedback`).
///
/// A node that performs the action of a press sinks a little under the finger: a card or a row to 0.97, a button to
/// 0.96, and an icon button, a ghost button and a navigation item fade to 0.7. It is a paint transform only: the
/// layout does not change, the keyboard gives no feedback, and a disabled button gives none. Mirror of the contract's
/// block; `test/press_feedback_cases_test.dart` compares the numbers with the artifact and runs the shared table.

/// How a pressed node answers the finger.
enum PressFeedbackKind {
  /// A pressable container, a list row, an option and any other node that acts on press: scale 0.97.
  card,

  /// A `Button` that is not `ghost`: scale 0.96.
  button,

  /// An `IconButton`, a `ghost` button and a `NavItem`: opacity 0.7, no scale.
  fade,
}

/// The pose of a node while it is pressed.
final class PressPose {
  const PressPose({required this.scale, required this.opacity});

  final double scale;
  final double opacity;

  @override
  bool operator ==(Object other) => other is PressPose && other.scale == scale && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(scale, opacity);

  @override
  String toString() => 'PressPose(scale: $scale, opacity: $opacity)';
}

/// The pressed opacity of a node that fades, and of every kind under "reduce motion".
const double kPressFadeOpacity = 0.7;

/// The pressed pose of [kind]. Under "reduce motion" every kind only fades to [kPressFadeOpacity]: no scale.
PressPose pressPoseOf(PressFeedbackKind kind, {bool reduceMotion = false}) {
  if (reduceMotion) return const PressPose(scale: 1, opacity: kPressFadeOpacity);
  return switch (kind) {
    PressFeedbackKind.card => const PressPose(scale: 0.97, opacity: 1),
    PressFeedbackKind.button => const PressPose(scale: 0.96, opacity: 1),
    PressFeedbackKind.fade => const PressPose(scale: 1, opacity: kPressFadeOpacity),
  };
}

/// Going down: 80 ms along `(0.2, 0, 0, 1)`. Coming back: 160 ms along `(0.34, 1.56, 0.64, 1)`, which passes 1 once
/// (the node grows a little over its size and settles).
const int kPressDownMs = 80;
const int kPressUpMs = 160;
const List<double> kPressDownCurve = [0.2, 0, 0, 1];
const List<double> kPressUpCurve = [0.34, 1.56, 0.64, 1];

/// The only word of the node field `pressFeedback`: it turns the feedback off.
const String kPressFeedbackNone = 'none';

/// The kind of feedback of [node] when it performs a press, or `null` when it gives none: the node turned it off, or
/// it is a disabled control, or a button that confirms by a drag (the gesture has its own).
PressFeedbackKind? pressFeedbackKindOf(ChildNode node, {bool disabled = false}) {
  if (node.pressFeedbackOff || disabled) return null;
  return switch (node) {
    ButtonNode(:final confirmBySwipe, :final variant) =>
      confirmBySwipe ? null : (variant == ButtonVariantToken.ghost ? PressFeedbackKind.fade : PressFeedbackKind.button),
    IconButtonNode() || NavItemNode() => PressFeedbackKind.fade,
    _ => PressFeedbackKind.card,
  };
}

/// Mirror of the scalar rows of `x-pressFeedback`; checked against the artifact by a test.
const Map<String, Object> kPressFeedbackRules = {
  'field': 'pressFeedback',
  'words': [kPressFeedbackNone],
  'keyboard': 'no feedback: Enter and Space act at once',
  'disabled': 'no feedback',
  'swipeConfirm': 'no feedback: the gesture has its own',
  'layout': 'none: the scale is painting only, neighbours do not move',
};
