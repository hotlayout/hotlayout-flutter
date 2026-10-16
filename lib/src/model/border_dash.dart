/// A dashed border (schema 9.22.0, `style.border.style: 'dashed'`): mirror of the builder's `border-dash.ts`.
///
/// "Dashed" without numbers is drawn as three different patterns by three readers: a browser fits the dash to
/// every side and breaks it at a corner, and Flutter has no dashed border at all. So the contract gives the
/// numbers: a dash is three border widths and a gap two, the line is the CENTRE line of the border (half a width
/// inside the outer edge) with arcs at the corners, and the number of dashes is the perimeter over the step,
/// rounded, so the pattern closes without a seam. The shared table is
/// `assets/contract/fixtures/border-dash/border-dash-cases.json`.
library;

import 'dart:math' as math;

/// The only word of the contract; a solid border is the absence of the field.
const String kDashedBorderWord = 'dashed';

/// A dash and a gap, in border widths.
const double kBorderDash = 3;
const double kBorderGap = 2;

/// The corner radii in LOGICAL corners: start and end are the sides of the writing direction.
typedef DashRadii = ({double topStart, double topEnd, double bottomEnd, double bottomStart});

/// The whole box of a border: the outer edge, the border width and the outer corner radii.
typedef DashedBox = ({double width, double height, double border, DashRadii radii});

/// The centre line of a dashed border and its fitted pattern.
typedef DashedLine = ({DashRadii radii, double perimeter, int count, double dash, double gap});

/// Whether the border says `dashed`. Anything else, an unknown word of a newer minor included, is solid.
bool isDashedBorderWord(Object? raw) => raw == kDashedBorderWord;

/// The radii scaled down by one factor when neighbours do not fit into a side (the CSS rule).
DashRadii _fittedRadii(DashedBox box) {
  double clamp(double value) => value.isFinite && value > 0 ? value : 0;
  final r = box.radii;
  final topStart = clamp(r.topStart);
  final topEnd = clamp(r.topEnd);
  final bottomEnd = clamp(r.bottomEnd);
  final bottomStart = clamp(r.bottomStart);
  double ratio(double side, double a, double b) => a + b > side ? side / (a + b) : 1;
  final factor = [
    ratio(box.width, topStart, topEnd),
    ratio(box.width, bottomStart, bottomEnd),
    ratio(box.height, topStart, bottomStart),
    ratio(box.height, topEnd, bottomEnd),
  ].reduce(math.min);
  return (
    topStart: topStart * factor,
    topEnd: topEnd * factor,
    bottomEnd: bottomEnd * factor,
    bottomStart: bottomStart * factor,
  );
}

/// The centre line of the border and the pattern fitted to it.
DashedLine dashedLineOf(DashedBox box) {
  final border = math.max(0.0, box.border);
  final outer = _fittedRadii(box);
  final half = border / 2;
  double inner(double radius) => math.max(0.0, radius - half);
  final radii = (
    topStart: inner(outer.topStart),
    topEnd: inner(outer.topEnd),
    bottomEnd: inner(outer.bottomEnd),
    bottomStart: inner(outer.bottomStart),
  );
  final width = math.max(0.0, box.width - border);
  final height = math.max(0.0, box.height - border);
  final sum = radii.topStart + radii.topEnd + radii.bottomEnd + radii.bottomStart;
  final perimeter = math.max(0.0, 2 * (width + height) - 2 * sum + (math.pi / 2) * sum);
  final step = (kBorderDash + kBorderGap) * border;
  if (!(step > 0) || !(perimeter > 0)) {
    return (radii: radii, perimeter: perimeter, count: 0, dash: 0, gap: 0);
  }
  // `Math.round` of the reference is half up; the quotient is positive, so `floor(x + 0.5)`.
  final count = math.max(1, (perimeter / step + 0.5).floor());
  final stretch = perimeter / (count * step);
  return (
    radii: radii,
    perimeter: perimeter,
    count: count,
    dash: kBorderDash * border * stretch,
    gap: kBorderGap * border * stretch,
  );
}

/// The corner points of the centre line, left to right (the logical frame of left-to-right writing).
typedef DashedFrame = ({double left, double top, double right, double bottom, DashRadii radii});

DashedFrame dashedFrameOf(DashedBox box) {
  final half = math.max(0.0, box.border) / 2;
  return (
    left: half,
    top: half,
    right: math.max(half, box.width - half),
    bottom: math.max(half, box.height - half),
    radii: dashedLineOf(box).radii,
  );
}

/// The path of the centre line as an SVG string, from the inline start of the top edge toward the inline end, in
/// box coordinates for left-to-right writing (the table's `pathCases`). The drawing is mirrored for right-to-left
/// by the caller.
String dashedPathOf(DashedBox box) {
  final frame = dashedFrameOf(box);
  final (:left, :top, :right, :bottom, :radii) = frame;
  String n(double value) {
    final rounded = (value * 1000).round() / 1000;
    return rounded == rounded.truncateToDouble() ? rounded.toInt().toString() : rounded.toString();
  }

  String arc(double r, double x, double y) => r > 0 ? 'A${n(r)} ${n(r)} 0 0 1 ${n(x)} ${n(y)}' : 'L${n(x)} ${n(y)}';
  final a = radii.topStart;
  final b = radii.topEnd;
  final c = radii.bottomEnd;
  final d = radii.bottomStart;
  return [
    'M${n(left + a)} ${n(top)}',
    'L${n(right - b)} ${n(top)}',
    arc(b, right, top + b),
    'L${n(right)} ${n(bottom - c)}',
    arc(c, right - c, bottom),
    'L${n(left + d)} ${n(bottom)}',
    arc(d, left, bottom - d),
    'L${n(left)} ${n(top + a)}',
    arc(a, left + a, top),
    'Z',
  ].join(' ');
}
