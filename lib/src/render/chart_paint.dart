import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/chart_rules.dart';

/// The size of a chart: the width the parent gives (the chart fills it, as a progress bar does; a width that is not
/// bounded gives nothing to draw on), and the height the parent fixes, or [kChartDefaultHeight] when it fixes none.
/// It has no natural width and answers every question about its width with zero, like the bar.
class ChartFrame extends SingleChildRenderObjectWidget {
  const ChartFrame({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderChartFrame();
}

class RenderChartFrame extends RenderProxyBox {
  Size _sizeFor(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : 0,
      constraints.hasTightHeight ? constraints.maxHeight : math.min(kChartDefaultHeight, constraints.maxHeight),
    ),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    child?.layout(BoxConstraints.tight(size));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => kChartDefaultHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => kChartDefaultHeight;
}

/// What the plot area shows: bars or a line, with its colours. The numbers come from `chart_rules.dart`.
class ChartPainter extends CustomPainter {
  const ChartPainter({
    this.bars,
    this.line,
    this.smooth = false,
    this.area = false,
    required this.color,
    required this.highlightColor,
    required this.lineWidth,
    required this.mirrored,
  });

  final List<BarRect>? bars;
  final ChartLine? line;
  final bool smooth;
  final bool area;
  final Color color;
  final Color highlightColor;
  final double lineWidth;

  /// Right-to-left writing mirrors the whole drawing: the first point stands at the start of the reading direction.
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final bars = this.bars;
    if (bars != null) _paintBars(canvas, bars);
    final line = this.line;
    if (line != null && line.points.isNotEmpty) _paintLine(canvas, line);
  }

  void _paintBars(Canvas canvas, List<BarRect> bars) {
    final paint = Paint()..isAntiAlias = true;
    for (final bar in bars) {
      if (bar.height <= 0) continue;
      paint.color = bar.highlighted ? highlightColor : color;
      final radius = Radius.circular(bar.radius);
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          bar.x,
          bar.y,
          bar.x + bar.width,
          bar.y + bar.height,
          topLeft: radius,
          topRight: radius,
        ),
        paint,
      );
    }
  }

  /// The line through the points: segments, or one cubic Bezier per pair for the smooth curve (never a quadratic one or
  /// a Catmull-Rom spline: those overshoot the values).
  Path _linePath(List<ChartXY> points) {
    final path = Path()..moveTo(points.first.x, points.first.y);
    if (smooth && points.length >= 3) {
      for (final segment in smoothSegments(points)) {
        path.cubicTo(segment.c1.x, segment.c1.y, segment.c2.x, segment.c2.y, segment.to.x, segment.to.y);
      }
    } else {
      for (final point in points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
    }
    return path;
  }

  void _paintLine(Canvas canvas, ChartLine line) {
    final path = _linePath(line.points);
    if (area) {
      final last = line.points.last;
      final first = line.points.first;
      final fill = Path.from(path)
        ..lineTo(last.x, line.baseline)
        ..lineTo(first.x, line.baseline)
        ..close();
      // From the colour of the line at 0.24 of its opacity at the top of the plot area to transparent at the bottom;
      // the same colour at zero alpha, so the middle of the fade is not tinted grey.
      canvas.drawPath(
        fill,
        Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, line.baseline),
            [color.withValues(alpha: color.a * kChartAreaTopOpacity), color.withValues(alpha: 0)],
          ),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final dot = line.dot;
    if (dot != null) canvas.drawCircle(Offset(dot.x, dot.y), dot.radius, Paint()..isAntiAlias = true..color = highlightColor);
  }

  @override
  bool shouldRepaint(ChartPainter old) => true;
}
