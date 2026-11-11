/// The chart: bars or a line over a row of points, with the labels in a band under the plot area (schema 9.37.0).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/chart_rules.dart';
import '../../model/node.dart';
import '../../model/style_values.dart' show ScaleRef;
import '../../model/tokens.dart';
import '../../model/value_transition.dart';
import '../chart_paint.dart';
import '../node_renderer.dart';
import 'transition.dart' show recordIdentityOf;

extension ChartWidgets on NodeRenderer {
  /// The chart. The numbers are `chart_rules.dart`; this method turns the node into theme values (colours, radius, gap,
  /// label font) and hands them to [ChartView], which lays the plot area and the label band out inside the box the
  /// parent gave.
  ///
  /// It is ONE picture for a screen reader, named by `alt`: the labels and the drawing are out of the tree, and a
  /// chart without a name is hidden as a decorative picture. The points are not read out as a table.
  Widget buildChart(ChartNode node) {
    final points = chartPointsOf(node.data, (source) => data.listOf(source));
    final record = recordIdentityOf(data.record);
    final alt = node.alt == null ? '' : text(node.alt!);
    final labelStyle = theme.text(TypographyToken.caption).copyWith(color: theme.color(ColorToken.muted));
    final view = ChartView(
      // A new record of a list is a new node, and a new node is a show.
      key: record == null ? null : ValueKey('chart|${node.id}|$record'),
      points: points,
      line: node.line,
      smooth: node.smooth,
      area: node.area,
      labels: node.labels,
      highlight: node.highlight,
      lineWidth: node.lineWidth,
      color: theme.fieldColor(node.color),
      highlightColor: theme.fieldColor(node.highlightColor),
      barRadius: _scaleOr(node.barRadius, theme.resolveRadius, theme.radius(RadiusToken.sm)),
      barGap: _scaleOr(node.barGap, theme.resolveSpacing, theme.space(SpacingToken.xs)),
      labelStyle: labelStyle,
      labelGap: theme.space(SpacingToken.xs),
      animateIn: node.animateIn,
    );
    return alt.isEmpty
        ? ExcludeSemantics(child: view)
        : Semantics(label: alt, image: true, child: ExcludeSemantics(child: view));
  }

  /// A scale field, or the default of the field when there is none or the theme does not declare its token.
  double _scaleOr(ScaleRef? ref, double? Function(ScaleRef ref) resolve, double fallback) {
    if (ref == null) return fallback;
    return resolve(ref) ?? fallback;
  }
}

/// Draws a chart in the box it is given. A chart with `animateIn` grows its values from zero when it is shown, with the
/// curve and the time of a number that leads (`x-valueTransition`); the top of the scale stands at once. A
/// system request to reduce motion, and a change of data under a chart that is already shown, give the final chart at
/// once.
class ChartView extends StatefulWidget {
  const ChartView({
    super.key,
    required this.points,
    required this.line,
    required this.smooth,
    required this.area,
    required this.labels,
    required this.highlight,
    required this.lineWidth,
    required this.color,
    required this.highlightColor,
    required this.barRadius,
    required this.barGap,
    required this.labelStyle,
    required this.labelGap,
    required this.animateIn,
  });

  final List<ChartPoint> points;
  final bool line;
  final bool smooth;
  final bool area;
  final bool labels;
  final String highlight;
  final double lineWidth;
  final Color color;
  final Color highlightColor;
  final double barRadius;
  final double barGap;
  final TextStyle labelStyle;
  final double labelGap;
  final bool animateIn;

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kValueTransitionMs),
  );
  bool _started = false;
  bool _playing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _playing = widget.animateIn && !reduced && widget.points.isNotEmpty;
    if (_playing) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The share of the growth, 0 to 1: one when no appearance plays, and once it has finished.
  double get _shown => _playing ? transitionValueAt(from: 0, to: 1, t: _controller.value * kValueTransitionMs) : 1;

  /// The height of one line of the label font, measured on a character with no width: the band of labels is this
  /// line plus the gap, and it does not depend on whether a label is drawn. The text scale does not multiply it.
  double _labelLine(TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: '​', style: widget.labelStyle),
      textDirection: direction,
      textScaler: TextScaler.noScaling,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) => ChartFrame(
    child: LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _chart(context, constraints.biggest),
      ),
    ),
  );

  Widget _chart(BuildContext context, Size box) {
    final direction = Directionality.of(context);
    final labelLine = widget.labels ? _labelLine(direction) : 0.0;
    final plotHeight = chartPlotHeight(height: box.height, labels: widget.labels, labelLine: labelLine, labelGap: widget.labelGap);
    final values = [for (final point in widget.points) point.value];
    final ratios = chartRatios(values, _shown);
    final highlight = chartHighlightIndex(values, widget.highlight);
    final empty = widget.points.isEmpty;
    final bars = empty || widget.line
        ? null
        : chartBars(
            ratios: ratios,
            width: box.width,
            height: plotHeight,
            gap: widget.barGap,
            radius: widget.barRadius,
            highlight: highlight,
          );
    final line = empty || !widget.line
        ? null
        : chartLine(ratios: ratios, width: box.width, height: plotHeight, lineWidth: widget.lineWidth, highlight: highlight);
    final boxes = widget.labels && !empty
        ? chartLabelBoxes(centers: chartLabelCenters(bars: bars, line: line), width: box.width)
        : const <ChartLabelBox>[];
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: box.width,
          height: plotHeight,
          child: CustomPaint(
            painter: ChartPainter(
              bars: bars,
              line: line,
              smooth: widget.smooth,
              area: widget.area,
              color: widget.color,
              highlightColor: widget.highlightColor,
              lineWidth: widget.lineWidth,
              mirrored: direction == TextDirection.rtl,
            ),
          ),
        ),
        for (final label in boxes)
          PositionedDirectional(
            start: label.left,
            top: math.min(plotHeight + widget.labelGap, box.height),
            width: label.width,
            height: labelLine,
            child: Text(
              widget.points[label.index].label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: widget.labelStyle,
            ),
          ),
      ],
    );
  }
}
