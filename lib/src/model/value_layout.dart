/// What a node with a running number MEASURES and what it PAINTS (`x-valueLayout`): while a value runs a
/// transition or an appearance the node takes the place of its FINAL text, and the value between is only painted
/// there. The widgets realise this by structure (`render/widgets/transition.dart`); this is the pure rule they
/// are checked against, one row of the shared table at a time.
library;

import 'value_transition.dart';

/// A change of the value in a flow: the moment (milliseconds from the start of the flow) and the new final value.
final class ValueLayoutChange {
  const ValueLayoutChange({required this.at, required this.to});

  final num at;
  final num to;
}

/// The frame of a flow: [layout] is the value the node is measured by, [shown] the value it paints, [held] whether
/// the painted value lies over the place of the final one.
final class ValueLayoutFrame {
  const ValueLayoutFrame({required this.layout, required this.shown, required this.held});

  final double layout;
  final double shown;
  final bool held;
}

/// The frame at [t] of a flow that starts at [from] and receives [changes] (ascending by `at`). A change that
/// arrives during a motion interrupts it and leads from the value shown at that moment.
ValueLayoutFrame valueLayoutAt({
  required num from,
  required List<ValueLayoutChange> changes,
  required num t,
  int? digits,
  bool reducedMotion = false,
}) {
  ({double from, double to, num start})? run;
  for (final change in changes) {
    if (change.at > t) break;
    final shownAtChange = run == null
        ? from.toDouble()
        : transitionValueAt(from: run.from, to: run.to, t: change.at - run.start, digits: digits);
    run = (from: shownAtChange, to: change.to.toDouble(), start: change.at);
  }
  if (run == null) return ValueLayoutFrame(layout: from.toDouble(), shown: from.toDouble(), held: false);
  final elapsed = t - run.start;
  if (reducedMotion || run.from == run.to || elapsed >= kValueTransitionMs) {
    return ValueLayoutFrame(layout: run.to, shown: run.to, held: false);
  }
  return ValueLayoutFrame(
    layout: run.to,
    shown: transitionValueAt(from: run.from, to: run.to, t: elapsed, digits: digits),
    held: true,
  );
}
