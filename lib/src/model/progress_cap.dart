import 'dart:math' as math;

/// ROUND ENDS OF A SCALE (schema 9.21.0, `x-style.layout.progressCap`): the `cap` field of the bar and the
/// ring. The block names the keys of `x-style.layout.progress` it refines and does not change them: a node
/// without the field is drawn exactly as before.
///
/// WHAT THE WORD `round` SAYS:
///  * the RING: the ends of the fill arc are half circles of the thickness, kept INSIDE the filled part, so
///    the arc goes neither before 0 % nor past the value. The centres of the ends stand at the angle
///    `thetaC = thickness / (diameter - thickness)` radians from their edges (half the thickness over the
///    middle radius). A share too small for the two ends to part (the arc is at most `2 thetaC`) is a DOT of
///    the thickness centred at `thetaC`; a full scale is the whole ring with no ends and no seam;
///  * the BAR: the ends of the track, the fill and every step are half circles, radius half the thickness,
///    whatever the theme's `pill` is. A non-empty fill is never shorter than the thickness (a dot, not a
///    flattened oval) and never longer than the track;
///  * a gradient runs along the filled part as without the field, and an end or a dot takes the colour of
///    the gradient at its own centre.
enum ProgressCap {
  round('round');

  const ProgressCap(this.wire);

  final String wire;

  /// The word of the document, or `null`: an absent field, an unknown word and a value that is not a string
  /// all mean "as before 9.21.0".
  static ProgressCap? parse(Object? raw) {
    for (final cap in values) {
      if (cap.wire == raw) return cap;
    }
    return null;
  }
}

/// What to draw over the ring's track.
enum RingCapKind { none, dot, arc, full }

/// The ends of the ring's fill arc (`progressCap.ring`), in degrees from the top clockwise.
final class RingCapGeometry {
  const RingCapGeometry({required this.kind, required this.capAngle, required this.startDeg, required this.endDeg});

  final RingCapKind kind;

  /// `thetaC` in radians.
  final double capAngle;

  /// The centre of the start end (or of the dot).
  final double startDeg;

  /// The centre of the finishing end; for a dot, the same as [startDeg].
  final double endDeg;
}

const double _fullTurnDeg = 360;
const double _radiansToDeg = 180 / math.pi;

/// The reference function of the ring: [ratio] is the share of the scale, [diameter] and [thickness] are in
/// logical pixels. The thickness is clamped to half the diameter, like the ring itself.
RingCapGeometry ringCapGeometry(double ratio, double diameter, double thickness) {
  final share = ratio.clamp(0.0, 1.0);
  final stroke = math.min(thickness, diameter / 2);
  final capAngle = diameter - stroke > 0 ? stroke / (diameter - stroke) : math.pi;
  final capDeg = capAngle * _radiansToDeg;
  if (share <= 0 || stroke <= 0) {
    return RingCapGeometry(kind: RingCapKind.none, capAngle: capAngle, startDeg: 0, endDeg: 0);
  }
  if (share >= 1) {
    return RingCapGeometry(kind: RingCapKind.full, capAngle: capAngle, startDeg: 0, endDeg: _fullTurnDeg);
  }
  final sweep = _fullTurnDeg * share;
  if (sweep <= 2 * capDeg) {
    return RingCapGeometry(kind: RingCapKind.dot, capAngle: capAngle, startDeg: capDeg, endDeg: capDeg);
  }
  return RingCapGeometry(kind: RingCapKind.arc, capAngle: capAngle, startDeg: capDeg, endDeg: sweep - capDeg);
}

/// The length of the fill of a bar with round ends: the share of the track, a non-empty one not shorter than
/// the thickness and not longer than the track (`progressCap.bar.fill`).
double barCapFillInline(double trackInline, double thickness, double ratio) {
  final share = ratio.clamp(0.0, 1.0);
  if (share <= 0) return 0;
  return math.min(trackInline, math.max(thickness, trackInline * share));
}

/// The radius of the ends of a bar with round ends: half the thickness, no theme token.
double barCapRadius(double thickness) => math.max(0, thickness / 2);

/// Mirror of `x-style.layout.progressCap` (scalar rows); checked against the artifact by a test.
const Map<String, Object> kProgressCapRules = {
  'prop': 'cap',
  'unknownWord': 'field-is-absent',
};
