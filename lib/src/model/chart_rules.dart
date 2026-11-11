/// The chart (schema 9.37.0, `x-chart`): how a record becomes a point, the scale, the highlighted point, the bars,
/// the line, the monotone curve and the label boxes. Pure numbers, no widgets.
///
/// Units are logical pixels in the content box of the node. `width` is the width the parent gave (the chart fills
/// it); `height` is the height of the PLOT AREA, the content box without the band of labels. The origin is the
/// top-left corner and y grows downwards.
///
/// Every function here is checked row by row against `fixtures/chart/chart-cases.json`.
library;

import 'dart:math' as math;

import 'record_scope.dart';

/// `x-chart.points`: at least two points make a chart, and at most 31 are read.
const int kChartPointsMin = 2;
const int kChartPointsMax = 31;

/// `x-chart.box.defaultHeight`: the height of a chart without `style.height`.
const double kChartDefaultHeight = 120;

/// `x-chart.lineWidth`: the stroke of the line, clamped to this range.
const double kChartLineWidthMin = 1;
const double kChartLineWidthMax = 8;
const double kChartDefaultLineWidth = 2;

/// `x-chart.area.topOpacity`: the opacity of the area under the line at the top of the plot area.
const double kChartAreaTopOpacity = 0.24;

/// `x-chart.highlight.dotExtra`: the dot of a highlighted point is the stroke plus this.
const double kChartDotExtra = 2;

/// `x-chart.labels.minWidth`: a label slot narrower than this thins the labels out.
const double kChartLabelMinWidth = 28;

/// `x-chart.defaults` and `x-chart.labels`: the tokens of the fields that name none.
const String kChartDefaultColor = 'primary';
const String kChartDefaultHighlightColor = 'accent';
const String kChartDefaultBarRadius = 'sm';
const String kChartDefaultBarGap = 'xs';
const String kChartLabelTypography = 'caption';
const String kChartLabelColor = 'muted';
const String kChartLabelGap = 'xs';

/// One point of the chart: its value (never negative) and its label (empty when it has none).
final class ChartPoint {
  const ChartPoint(this.value, this.label);

  final double value;
  final String label;

  @override
  bool operator ==(Object other) => other is ChartPoint && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'ChartPoint($value, "$label")';
}

/// The value of a point: a finite number is itself, a negative one is zero, anything else is zero. The point keeps its
/// place, so labels and neighbours do not move and the line has no gaps.
double chartValueOf(Object? raw) => raw is num && raw.isFinite ? math.max(0, raw.toDouble()) : 0;

/// The label of a point: a string is itself, anything else is an empty label.
String chartLabelOf(Object? raw) => raw is String ? raw : '';

/// The records of a collection by its name; `null` means the data has no such collection.
typedef ChartRecordsOf = List<Object?>? Function(String source);

/// The points of the `data` field. A collection gives the first [kChartPointsMax] records in the order of the data,
/// and a record that is not an object is a record without fields. Fewer than two points, or a shape of `data` this
/// reader does not know, is an EMPTY chart: nothing is drawn and the box stays.
List<ChartPoint> chartPointsOf(Object? data, ChartRecordsOf recordsOf) {
  final points = _rawPointsOf(data, recordsOf);
  final kept = points.length > kChartPointsMax ? points.sublist(0, kChartPointsMax) : points;
  return kept.length < kChartPointsMin ? const [] : kept;
}

List<ChartPoint> _rawPointsOf(Object? data, ChartRecordsOf recordsOf) {
  if (data is! Map) return const [];
  switch (data['kind']) {
    case 'literal':
      final points = data['points'];
      if (points is! List) return const [];
      return [
        for (final point in points.take(kChartPointsMax))
          point is Map ? ChartPoint(chartValueOf(point['value']), chartLabelOf(point['label'])) : const ChartPoint(0, ''),
      ];
    case 'collection':
      final source = data['source'];
      final item = data['item'];
      final valueField = data['valueField'];
      if (source is! String || item is! String || valueField is! String) return const [];
      final labelField = data['labelField'];
      final records = recordsOf(source) ?? const <Object?>[];
      return [
        for (final record in records.take(kChartPointsMax))
          _pointOf(record is Map ? instanceRecord(item, record) : const <String, Object?>{}, valueField, labelField),
      ];
    default:
      return const [];
  }
}

ChartPoint _pointOf(Map<String, Object?> scope, String valueField, Object? labelField) => ChartPoint(
  chartValueOf(scope[valueField]),
  labelField is String ? chartLabelOf(scope[labelField]) : '',
);

/// The shares of the height: each value divided by the largest value. All values zero gives all shares zero (an empty
/// chart without a division by zero). [shown] is the share of the appearance (`animateIn`, 0 to 1): the top of the
/// scale stands at once and the values grow.
List<double> chartRatios(List<double> values, [double shown = 1]) {
  final top = values.fold<double>(0, math.max);
  return [for (final value in values) top > 0 ? value / top * shown : 0];
}

/// The highlighted point: `last` is the last one; `max` is the LAST of the largest values (the fresher of equals), and
/// only when it is above zero; `none` and any other word give none.
int? chartHighlightIndex(List<double> values, Object? highlight) {
  if (values.isEmpty) return null;
  if (highlight == 'last') return values.length - 1;
  if (highlight != 'max') return null;
  final top = values.reduce(math.max);
  return top > 0 ? values.lastIndexOf(top) : null;
}

/// A bar: its box and the radius of its TOP corners (the bottom corners are square, a bar stands on zero).
final class BarRect {
  const BarRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.radius,
    required this.highlighted,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double radius;
  final bool highlighted;
}

/// The bars: n equal slots over the whole width with [gap] between them only. A gap that would make a bar narrower than
/// one dp becomes zero. The height is the share of [height]; a bar of height zero is not drawn. The radius of the top
/// corners is no more than half the width and no more than the height of the bar.
List<BarRect> chartBars({
  required List<double> ratios,
  required double width,
  required double height,
  required double gap,
  required double radius,
  int? highlight,
}) {
  final n = ratios.length;
  if (n == 0 || width <= 0) return const [];
  final wanted = math.max(0.0, gap);
  final usedGap = (width - wanted * (n - 1)) / n < 1 ? 0.0 : wanted;
  final barWidth = (width - usedGap * (n - 1)) / n;
  final plot = math.max(0.0, height);
  return [
    for (var index = 0; index < n; index += 1)
      () {
        final barHeight = math.max(0.0, ratios[index]) * plot;
        return BarRect(
          x: index * (barWidth + usedGap),
          y: plot - barHeight,
          width: barWidth,
          height: barHeight,
          radius: math.max(0.0, math.min(radius, math.min(barWidth / 2, barHeight))),
          highlighted: index == highlight,
        );
      }(),
  ];
}

/// A point of the drawing.
final class ChartXY {
  const ChartXY(this.x, this.y);

  final double x;
  final double y;
}

/// The dot of a highlighted point of a line.
final class ChartDot {
  const ChartDot(this.x, this.y, this.radius);

  final double x;
  final double y;
  final double radius;
}

/// The line: the points, the inset from the edges, the dot and the bottom of the area under it.
final class ChartLine {
  const ChartLine({required this.points, required this.inset, required this.dot, required this.baseline});

  final List<ChartXY> points;

  /// The distance from the edges, so that the stroke and the dot are not cut by the box.
  final double inset;

  /// The dot of the highlighted point; `null` when nothing is highlighted.
  final ChartDot? dot;

  /// The bottom of the fill under the line: the lower edge of the plot area.
  final double baseline;
}

/// The line. The inset is half the stroke, or with a highlight the radius of the dot (the stroke plus
/// [kChartDotExtra]) when that is larger. The points run from edge to edge: `x_k = i + k (W - 2i) / (n - 1)` and
/// `y_k = i + (1 - share_k) (H - 2i)`; zero lies at `H - i` and the top at `i`.
ChartLine chartLine({
  required List<double> ratios,
  required double width,
  required double height,
  required double lineWidth,
  int? highlight,
}) {
  final n = ratios.length;
  final plot = math.max(0.0, height);
  final dotRadius = lineWidth + kChartDotExtra;
  final inset = highlight == null ? lineWidth / 2 : math.max(lineWidth / 2, dotRadius);
  if (n < kChartPointsMin || width <= 0) return ChartLine(points: const [], inset: inset, dot: null, baseline: plot);
  final step = (width - 2 * inset) / (n - 1);
  final span = math.max(0.0, plot - 2 * inset);
  final points = [
    for (var index = 0; index < n; index += 1) ChartXY(inset + index * step, inset + (1 - math.max(0.0, ratios[index])) * span),
  ];
  final lit = highlight == null || highlight < 0 || highlight >= n ? null : points[highlight];
  return ChartLine(points: points, inset: inset, dot: lit == null ? null : ChartDot(lit.x, lit.y, dotRadius), baseline: plot);
}

double _sign(double value) => value > 0 ? 1 : (value < 0 ? -1 : 0);

/// The tangents of the monotone cubic spline (Steffen, 1990: the same as `curveMonotoneX` of d3). The step h is equal;
/// the secant is `s_k = (y_{k+1} - y_k) / h`. Inside: `m_k = (sign s_{k-1} + sign s_k) min(|s_{k-1}|, |s_k|,
/// |s_{k-1} + s_k| / 4)`. At the ends: `m_0 = (3 s_0 - m_1) / 2` and `m_{n-1} = (3 s_{n-2} - m_{n-2}) / 2`. Secants of
/// opposite signs give a zero tangent, so a peak lies exactly on its point.
List<double> monotoneTangents(List<ChartXY> points) {
  final n = points.length;
  if (n < 3) return List<double>.filled(n, 0);
  final h = points[1].x - points[0].x;
  final secants = [for (var i = 0; i < n - 1; i += 1) h == 0 ? 0.0 : (points[i + 1].y - points[i].y) / h];
  final tangents = List<double>.filled(n, 0);
  for (var i = 1; i < n - 1; i += 1) {
    final before = secants[i - 1];
    final after = secants[i];
    tangents[i] = (_sign(before) + _sign(after)) * math.min(before.abs(), math.min(after.abs(), (before + after).abs() / 4));
  }
  tangents[0] = (3 * secants[0] - tangents[1]) / 2;
  tangents[n - 1] = (3 * secants[n - 2] - tangents[n - 2]) / 2;
  return tangents;
}

/// A cubic Bezier segment of the smooth curve: two control points and the end.
final class CubicSegment {
  const CubicSegment(this.c1, this.c2, this.to);

  final ChartXY c1;
  final ChartXY c2;
  final ChartXY to;
}

/// The smooth curve: a cubic Bezier between neighbours, `c1 = (x_k + h/3, y_k + m_k h/3)` and
/// `c2 = (x_{k+1} - h/3, y_{k+1} - m_{k+1} h/3)`. A monotone spline never leaves the values of its neighbours, so the
/// curve does not dive below zero or rise above the top. Two points are a straight segment.
List<CubicSegment> smoothSegments(List<ChartXY> points) {
  if (points.length < 3) {
    return [for (var i = 1; i < points.length; i += 1) CubicSegment(points[i - 1], points[i], points[i])];
  }
  final tangents = monotoneTangents(points);
  return [
    for (var i = 1; i < points.length; i += 1)
      () {
        final from = points[i - 1];
        final to = points[i];
        final third = (to.x - from.x) / 3;
        return CubicSegment(
          ChartXY(from.x + third, from.y + tangents[i - 1] * third),
          ChartXY(to.x - third, to.y - tangents[i] * third),
          to,
        );
      }(),
  ];
}

/// The box of one label: the index of its point, where it starts and how wide it is.
final class ChartLabelBox {
  const ChartLabelBox(this.index, this.left, this.width);

  final int index;
  final double left;
  final double width;
}

/// The label boxes. Each is `W / n` wide, centred under the middle of the bar or under the point of the line, and
/// shifted inside `[0, W]`. When `W / n` is narrower than [kChartLabelMinWidth], every k-th point is labelled,
/// `k = ceil(min / (W / n))`, counting from the LAST point (it is "today").
List<ChartLabelBox> chartLabelBoxes({required List<double> centers, required double width}) {
  final n = centers.length;
  if (n == 0 || width <= 0) return const [];
  final slot = width / n;
  final every = math.max(1, (kChartLabelMinWidth / slot - 1e-9).ceil());
  return [
    for (var index = 0; index < n; index += 1)
      if ((n - 1 - index) % every == 0)
        ChartLabelBox(index, math.min(math.max(centers[index] - slot / 2, 0.0), width - slot), slot),
  ];
}

/// The centres of the points for the labels: the middle of a bar, or the point of the line.
List<double> chartLabelCenters({List<BarRect>? bars, ChartLine? line}) {
  if (bars != null) return [for (final bar in bars) bar.x + bar.width / 2];
  return [for (final point in line?.points ?? const <ChartXY>[]) point.x];
}

/// The height of the plot area: the content box without the band of labels (a line of label text plus the gap), never
/// below zero.
double chartPlotHeight({required double height, required bool labels, required double labelLine, required double labelGap}) =>
    math.max(0.0, height - (labels ? labelLine + labelGap : 0));

/// The word of `highlight` as the reader reads it: an unknown word is `none`.
String readChartHighlight(Object? value) => value == 'last' || value == 'max' ? value! as String : 'none';

/// Whether the curve is smooth: any other word is a straight line.
bool readChartSmooth(Object? value) => value == 'smooth';

/// The stroke of the line within its range; anything that is not a finite number is the default.
double readChartLineWidth(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(kChartLineWidthMin, kChartLineWidthMax) : kChartDefaultLineWidth;
