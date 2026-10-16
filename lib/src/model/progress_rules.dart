import 'dart:math' as math;

import 'progress_cap.dart';
import 'segment_transition.dart';
import 'style_values.dart';

/// Progress bar and ring: geometry and selection rules (schema 9.7.0, `x-style.layout.progress`).
///
/// Mirror of the builder's `progress-rules.ts`. Only NUMBERS and rules are here, with no theme and no
/// widgets: resolving colors and gradients against the theme lives in `RenderTheme`, painting in
/// `render/progress_paint.dart`. The functions cannot drift from the reference implementation:
/// `test/progress_cases_test.dart` reads the case table itself
/// (`fixtures/progress/progress-cases.json`) and runs each of its rows.
///
/// Before 9.7.0 the contract described only the shape of the props of these widgets, and the Flutter
/// reader kept its own numbers, which diverged from the web reader: a ring of 48 had an outer diameter
/// of 56 (the stroke sat in the middle of the boundary), a bar with a maximum of `0` was full, and the
/// end of a bar's fill was a flat cut.

/// Upper bound of a numeric thickness (`SpacingRef`): an integer 0..128.
const int kMaxProgressThickness = 128;

/// Thickness when the field is not named or not readable (`defaultThickness`).
const String kDefaultProgressThickness = 'sm';

/// Track color when the field is not named or not readable (`defaultTrackColor`).
const String kDefaultProgressTrackColor = 'secondary';

/// The ring diameter is measured in units of this spacing token (`ring.sizeUnit`).
const String kRingSizeUnit = 'xl';

/// Diameter multipliers by size word (`ring.sizes`).
const Map<String, double> kRingSizeScale = {'sm': 2, 'md': 3, 'lg': 4};

/// Size word when the field is missing or the word is unknown (`ring.defaultSize`).
const String kDefaultRingSize = 'md';

/// Radius of the bar that it asks of the theme (`bar.trackRadius` / `fillRadius`).
const String kBarRadiusToken = 'pill';

/// Fill ratio of the scale (`progress.ratio`, 0..1).
///
/// A maximum that is not a positive number means NO scale (ratio 0), not a full bar: there is nothing
/// to divide by. A non-number (no data, `NaN`, a string) is also 0. It accepts raw values because that
/// is how the case table asks the question; the widget passes already resolved numbers.
double progressRatio(Object? value, Object? max) {
  if (value is! num || max is! num) return 0;
  final v = value.toDouble();
  final m = max.toDouble();
  if (!v.isFinite || !m.isFinite) return 0;
  if (m <= 0) return 0;
  return (v / m).clamp(0.0, 1.0).toDouble();
}

/// Thickness from the document: a spacing token (string) or an integer 0..128.
///
/// A fraction, an out-of-range number or a string with "px" is the wrong shape: `null`, and the default
/// thickness applies (`tokenWithoutFieldDefault: 'omit-field'`). Read one field at a time: a broken
/// thickness does not cancel the rest.
ScaleRef? readProgressThickness(Object? raw) {
  if (raw is String) return isTokenName(raw) ? ScaleRef.token(raw) : null;
  if (raw is num && raw.isFinite && raw == raw.roundToDouble() && raw >= 0 && raw <= kMaxProgressThickness) {
    return ScaleRef.value(raw.toDouble());
  }
  return null;
}

/// The ring size word to draw with: an unknown or missing one gives `md`.
double ringSizeScaleOf(String? size) => kRingSizeScale[size] ?? kRingSizeScale[kDefaultRingSize]!;

/// Input of the ring geometry: what the style named and what it consumes inside.
///
/// Six size fields, only those the reader APPLIES: under a row weight the three width fields do not
/// apply, and for a layer over the whole stack none does (`weightOverridesWidth`,
/// `fillOverridesSize`).
final class RingBoxInput {
  const RingBoxInput({
    required this.unit,
    required this.thickness,
    this.size,
    this.width,
    this.minWidth,
    this.maxWidth,
    this.height,
    this.minHeight,
    this.maxHeight,
    this.paddingInline = 0,
    this.paddingBlock = 0,
    this.border = 0,
  });

  /// Size word (`props.size`).
  final String? size;

  /// Value of the [kRingSizeUnit] token in the theme being drawn with.
  final double unit;

  final double? width;
  final double? minWidth;
  final double? maxWidth;
  final double? height;
  final double? minHeight;
  final double? maxHeight;

  /// Sum of the paddings along the row and across it.
  final double paddingInline;
  final double paddingBlock;

  /// Border thickness of the node (equal on all sides).
  final double border;

  /// Arc thickness as the theme resolved it (before clamping).
  final double thickness;
}

/// Ring geometry: diameter, arc thickness, the node's own box.
final class RingGeometry {
  const RingGeometry({
    required this.diameter,
    required this.thickness,
    required this.boxInline,
    required this.boxBlock,
  });

  /// Outer diameter of the ring.
  final double diameter;

  /// The thickness to draw with: no more than half the diameter (`maxThickness`).
  final double thickness;

  /// The node's box with padding and border, given by ITS OWN style. The parent may give a larger one
  /// (weight, stack layer); the ring is then centered.
  final double boxInline;
  final double boxBlock;
}

/// A box side if it is named: the size, or the natural side, within bounds.
///
/// The bounds use the same rule as everywhere: a `minWidth` larger than `maxWidth` wins
/// (`invertedSizeRange: 'min-wins'`).
double? _namedSide(double? size, double? min, double? max, double natural) {
  if (size == null && min == null && max == null) return null;
  final lower = min ?? 0;
  var upper = max ?? double.infinity;
  if (lower > upper) upper = lower;
  return (size ?? natural).clamp(lower, upper).toDouble();
}

/// RING GEOMETRY (`ring.diameter`, `namedSide`, `unnamedSide`, `maxThickness`).
///
/// The diameter is the smaller of the NAMED sides of the content box (side minus padding and border);
/// if none is named, the size word. An unnamed side of the box equals the diameter.
RingGeometry ringGeometry(RingBoxInput input) {
  final bySize = ringSizeScaleOf(input.size) * input.unit;
  final frame = 2 * input.border;

  final boxInline = _namedSide(
    input.width,
    input.minWidth,
    input.maxWidth,
    bySize + input.paddingInline + frame,
  );
  final boxBlock = _namedSide(
    input.height,
    input.minHeight,
    input.maxHeight,
    bySize + input.paddingBlock + frame,
  );

  final content = <double>[
    ?(boxInline == null ? null : math.max(0, boxInline - input.paddingInline - frame)),
    ?(boxBlock == null ? null : math.max(0, boxBlock - input.paddingBlock - frame)),
  ];
  final diameter = content.isEmpty ? bySize : content.reduce(math.min);

  return RingGeometry(
    diameter: diameter,
    thickness: input.thickness.clamp(0.0, diameter / 2).toDouble(),
    boxInline: boxInline ?? diameter + input.paddingInline + frame,
    boxBlock: boxBlock ?? diameter + input.paddingBlock + frame,
  );
}

/// Radius of a bar end: the `pill` token, clamped to half the shorter side (`bar.radiusClamp`), which
/// is how CSS reads a `border-radius` larger than the box.
double barFillRadius(double fillInline, double thickness, double pill) =>
    math.max(0, math.min(pill, math.min(fillInline / 2, thickness / 2)));

/// Bar geometry: the track over the whole given length, the fill a part of it from the LOGICAL start;
/// both with the `pill` radius clamped to half the shorter side.
final class BarGeometry {
  const BarGeometry({
    required this.trackBlock,
    required this.fillInline,
    required this.trackRadius,
    required this.fillRadius,
  });

  factory BarGeometry.of({
    required double trackInline,
    required double thickness,
    required double ratio,
    required double pill,
    bool roundEnds = false,
  }) {
    // Round ends (9.21.0): half the thickness for the track and the fill, no theme token; a non-empty fill
    // is not shorter than the thickness.
    if (roundEnds) {
      return BarGeometry(
        trackBlock: thickness,
        fillInline: barCapFillInline(trackInline, thickness, ratio),
        trackRadius: barCapRadius(thickness),
        fillRadius: barCapRadius(thickness),
      );
    }
    final fillInline = trackInline * ratio.clamp(0.0, 1.0);
    return BarGeometry(
      trackBlock: thickness,
      fillInline: fillInline,
      trackRadius: barFillRadius(trackInline, thickness, pill),
      fillRadius: barFillRadius(fillInline, thickness, pill),
    );
  }

  final double trackBlock;
  final double fillInline;
  final double trackRadius;
  final double fillRadius;
}

/// The fill arc in degrees from the top clockwise, in any writing system (`ring.start`, `direction`,
/// `mirroredInRtl: false`).
({double startDeg, double sweepDeg}) ringArc(double ratio) =>
    (startDeg: 0, sweepDeg: 360 * ratio.clamp(0.0, 1.0));

/// A stop of the fill gradient on the SCALE: `at` is a share of the whole scale (bar) or of the full
/// turn (ring).
typedef ProgressGradientStop<T> = ({T color, double at});

/// Stops spread along the FILLED part (`gradient.spans`): position `p` becomes the scale share
/// `p x ratio`. The gradient angle is not read.
List<ProgressGradientStop<T>> progressGradientStops<T>(
  List<({T color, double position})> stops,
  double ratio,
) => [for (final stop in stops) (color: stop.color, at: stop.position * ratio)];

// -- Segmented bar (9.11.0) --

/// Bounds of `segments` (`x-style.layout.progressSegments.min` / `max`).
const int kMinProgressSegments = 2;
const int kMaxProgressSegments = 12;

/// Gap between steps is a spacing token (`progressSegments.gap`).
const String kProgressSegmentGap = 'xs';

/// How many decimal places the step count keeps before `floor` (`progressSegments.precision`):
/// `0.3 / 0.4 x 4` in double precision is `2.9999999999999996`, and that is three steps, not two.
const int kProgressSegmentPrecision = 6;

/// A step narrower than this is not a step: the bar is solid (`minSegment`).
const double kMinSegmentInline = 1;

/// The step count the reader draws with: an integer 2..12, otherwise `null`, a solid bar
/// (`unreadableSegments`). Mirror of the builder's `readSegments`.
int? readSegments(Object? raw) =>
    raw is num && raw.isFinite && raw == raw.roundToDouble() && raw >= kMinProgressSegments && raw <= kMaxProgressSegments
    ? raw.toInt()
    : null;

/// How many steps are filled for a scale ratio: `floor(round(ratio x N, 6))`.
int filledSegments(double ratio, int segments) {
  final scale = math.pow(10, kProgressSegmentPrecision).toDouble();
  final units = (ratio.clamp(0.0, 1.0) * segments * scale).roundToDouble() / scale;
  return units.floor().clamp(0, segments);
}

/// State of a step: filled, current (the first unfilled) or unfilled.
enum SegmentState { filled, current, unfilled }

/// Geometry of a segmented bar (`segmentGeometry`): the width and starts of the steps from the LOGICAL
/// start of the track, without rounding.
final class SegmentGeometry {
  const SegmentGeometry({
    required this.inline,
    required this.gap,
    required this.starts,
    required this.states,
    required this.filled,
    required this.current,
    required this.radius,
    required this.filledInline,
    required this.fills,
    required this.units,
  });

  final double inline;
  final double gap;
  final List<double> starts;
  final List<SegmentState> states;
  final int filled;

  /// Number of the current step; `null` means all are filled.
  final int? current;
  final double radius;

  /// End of the last filled step is the end of the gradient line; 0 with no filled steps.
  final double filledInline;

  /// The fill of every step, 0…1 from its logical start. All 0 or 1 at rest; one step has a fraction while a value
  /// leads (9.25.0, `x-segmentsTransition`).
  final List<double> fills;

  /// The steps filled, with a fraction while a value leads; a whole number at rest.
  final double units;
}

/// The bar's own minimum width is ONE in both kinds (`progressSegments.minInlineSize: 'gaps'`,
/// formula `(segments - 1) * gap`): the solid replacement bar keeps the same width as the steps. The
/// kind is decided by the width the PLACE gives ([segmentsKindFor]), not by this measurement; otherwise
/// in a "width by content" place the steps would give 44, so step 0, so solid, so width 0, so steps
/// again, on every frame without end.
double segmentsMinInline(int segments, double gap) => (segments - 1) * gap;

/// The kind of bar in a place [placeInline] wide (`kindDecidedBy: 'width-the-place-gives'`): steps or
/// solid. The same at `max(placeInline, segmentsMinInline)`; its own minimum size does not change the
/// kind.
bool segmentsAreSteps(int segments, double gap, double placeInline) {
  final track = math.max(placeInline, segmentsMinInline(segments, gap));
  final inline = (track - (segments - 1) * gap) / segments;
  return inline.isFinite && inline >= kMinSegmentInline;
}

/// Step geometry. `null` means a step is narrower than [kMinSegmentInline]: a solid bar is drawn
/// (`belowMinSegment`).
SegmentGeometry? segmentGeometry({
  required double trackInline,
  required double thickness,
  required double ratio,
  required int segments,
  required double gap,
  required double pill,
  bool roundEnds = false,
  double? units,
}) {
  final inline = (trackInline - (segments - 1) * gap) / segments;
  if (!inline.isFinite || inline < kMinSegmentInline) return null;
  // [units] is the number of filled steps of a value that is leading (9.25.0); without it, whole steps at rest.
  final drawn = units ?? filledSegments(ratio, segments).toDouble();
  final fills = segmentFills(drawn, segments);
  final filled = fills.where((fill) => fill >= 1).length;
  final current = segmentCurrentOf(fills);
  return SegmentGeometry(
    inline: inline,
    gap: gap,
    starts: [for (var i = 0; i < segments; i += 1) i * (inline + gap)],
    states: [
      for (var i = 0; i < segments; i += 1)
        fills[i] >= 1 ? SegmentState.filled : (i == current ? SegmentState.current : SegmentState.unfilled),
    ],
    filled: filled,
    current: current,
    radius: roundEnds ? barCapRadius(thickness) : barFillRadius(inline, thickness, pill),
    filledInline: segmentFillInline(drawn, step: inline, gap: gap),
    fills: fills,
    units: drawn,
  );
}

/// The ten policy rows of 9.11.0 (`x-compatibility.policy`, from `carouselOutsideHost`). A mirror for
/// checking against the artifact; six of them are about the carousel (`model/carousel_rules.dart`) and
/// two about segments.
const Map<String, String> kSegmentsPolicy = {
  'unreadableSegments': 'continuous-bar',
  'segmentsSemantics': 'one-scale',
};

// -- Own style of the ring label (9.17.0) --

/// Mirror of `x-style.layout.progressLabel` (scalar rows); checked against the artifact.
///
/// The ring label does NOT grow with the diameter by itself, does not inherit the node's style, does not
/// change the box, and is not clipped by the ring. Without the fields it is exactly `caption` /
/// `onSurface`, as before 9.17.0.
const Map<String, Object> kRingLabelStyle = {
  'widget': 'CircularProgress',
  'props': {'typography': 'labelTypography', 'color': 'labelColor'},
  'defaultTypography': 'caption',
  'defaultColor': 'onSurface',
  'unknown': 'use-default',
  'scalesWithDiameter': false,
  'inherits': 'nothing',
  'lines': 1,
  'wrap': 'none',
  'placement': 'center',
  'box': 'does-not-size-ring',
  'overflow': 'not-clipped-by-ring',
  'textScale': 'applies',
  'before917': 'default-label-style',
};
