/// The chart (9.37.0): bars or a line over a row of points.
part of '../node.dart';

/// A leaf that draws bars (`variant: 'bars'`) or a line (`'line'`) over the points of `data`.
///
/// The points are read at draw time ([chartPointsOf]) because a collection comes from the data, which changes without
/// the document being read again. Every field is read on its own: a field of the wrong shape is the field with no value
/// and the rest of the chart works.
final class ChartNode extends ChildNode {
  const ChartNode({
    required super.id,
    super.visibleIf,
    super.hiddenByClass,
    super.style,
    super.styleWhen,
    super.fill,
    super.weight,
    super.layer,
    super.motion,
    super.pull,
    super.pin,
    super.pinTop,
    super.pressFeedbackOff,
    required this.line,
    required this.data,
    required this.color,
    required this.highlightColor,
    this.highlight = 'none',
    this.labels = false,
    this.barRadius,
    this.barGap,
    this.lineWidth = kChartDefaultLineWidth,
    this.smooth = false,
    this.area = false,
    this.animateIn = false,
    this.alt,
  });

  /// `variant: 'line'`; any other word draws bars.
  final bool line;

  /// The `data` field as the document wrote it; [chartPointsOf] reads it, and an unknown shape is an empty chart.
  final Object? data;

  /// The colour of the bars, or of the line and the area under it.
  final FieldColor color;

  /// The colour of the highlighted point.
  final FieldColor highlightColor;

  /// `none`, `last` or `max`; an unknown word is `none`.
  final String highlight;

  /// Labels under the points: only the literal `true`.
  final bool labels;

  /// The radius of the top corners of a bar and the gap between bars (`bars` only); `null` is the default token.
  final ScaleRef? barRadius;
  final ScaleRef? barGap;

  /// The stroke of the line within 1 to 8 (`line` only).
  final double lineWidth;

  /// `curve: 'smooth'` (`line` only).
  final bool smooth;

  /// A fill under the line (`line` only): only the literal `true`.
  final bool area;

  /// The values grow from zero when the node is shown: only the literal `true`.
  final bool animateIn;

  /// The accessible name; without it the chart is hidden from a screen reader as a decorative picture.
  final BindableString? alt;
}

ChartNode _parseChart(_RawNode node, VisibilityCondition? visibleIf) {
  final props = node.props;
  return ChartNode(
    id: node.leafId(),
    visibleIf: visibleIf,
    hiddenByClass: node.hiddenByClass,
    style: node.style,
    styleWhen: node.styleWhen,
    fill: node.fill,
    weight: node.weight,
    layer: node.layer,
    motion: node.motion,
    pull: node.pull,
    pin: node.pin,
    pinTop: node.pinTop,
    pressFeedbackOff: node.pressFeedbackOff,
    line: props['variant'] == 'line',
    data: props['data'],
    color: FieldColor.parse(props['color'], fieldDefault: ColorToken.primary),
    highlightColor: FieldColor.parse(props['highlightColor'], fieldDefault: ColorToken.accent),
    highlight: readChartHighlight(props['highlight']),
    labels: props['labels'] == true,
    barRadius: ScaleRef.tryParse(props['barRadius'], max: kMaxRadiusPx),
    barGap: ScaleRef.tryParse(props['barGap'], max: kMaxSpacingPx),
    lineWidth: readChartLineWidth(props['lineWidth']),
    smooth: readChartSmooth(props['curve']),
    area: props['area'] == true,
    animateIn: props['animateIn'] == true,
    alt: _altOf(props['alt'], node.key('alt')),
  );
}
