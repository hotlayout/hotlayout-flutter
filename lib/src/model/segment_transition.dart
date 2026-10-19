import 'dart:math' as math;

import 'progress_rules.dart';

/// THE STEPS OF A BAR DURING A TRANSITION (schema 9.25.0, `x-segmentsTransition`).
///
/// At rest the steps are whole (`filledSegments`). While the value of the bar runs a transition (`animateChanges` or
/// `animateIn`) the filled steps are a NUMBER WITH A FRACTION: `U(from) + (U(to) - U(from)) * e`, where `U(r)` is the
/// number of whole steps at rest for the ratio `r` and `e` is the eased share of the curve of the value transition.
/// Both ends are pictures at rest, so nothing jumps when the transition ends. The step that is filling is cut at its
/// share, with the radius of the step kept.

/// The steps filled at a moment of a transition from [fromRatio] to [toRatio]: a number from 0 to [segments].
/// [eased] is clamped to 0…1.
double segmentUnitsAt({
  required double fromRatio,
  required double toRatio,
  required int segments,
  required double eased,
}) {
  final from = filledSegments(fromRatio, segments);
  final to = filledSegments(toRatio, segments);
  final share = eased.clamp(0.0, 1.0);
  final units = from + (to - from) * share;
  return units.clamp(0.0, segments.toDouble());
}

/// The fill of every step, 0…1, from its logical start: `clamp(units - index, 0, 1)`.
List<double> segmentFills(double units, int segments) => [
  for (var i = 0; i < segments; i += 1) (units - i).clamp(0.0, 1.0),
];

/// The current step: the first one that is not full. `null` when every step is full.
int? segmentCurrentOf(List<double> fills) {
  for (var i = 0; i < fills.length; i += 1) {
    if (fills[i] < 1) return i;
  }
  return null;
}

/// The length of the gradient line along the drawn fill: the end of the fill of the last step with any fill,
/// `units * step + (ceil(units) - 1) * gap`; the gaps are cut out. Zero when nothing is filled.
double segmentFillInline(double units, {required double step, required double gap}) {
  if (!(units > 0) || !units.isFinite) return 0;
  return units * step + (units.ceil() - 1) * gap;
}

/// The eased share recovered from the value that is SHOWN: for a reader that knows the shown value of the scale and
/// not the moment of the curve. Equal ends mean the transition is over; the result is clamped to 0…1.
double transitionShareOf(num from, num to, num shown) {
  if (from == to) return 1;
  return math.max(0.0, math.min(1.0, (shown - from) / (to - from))).toDouble();
}
