import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/progress_cap.dart';
import '../model/progress_rules.dart';

/// Painting of the progress bar and ring (schema 9.7.0, `x-style.layout.progress`).
///
/// Both are painted directly from the numbers of [progressRules] (rules live in
/// `model/progress_rules.dart`; the paint is already resolved against the theme by
/// `RenderTheme.resolveProgressPaint`). The stock Material `LinearProgressIndicator` and
/// `CircularProgressIndicator` do not follow the contract: their ring stroke straddles the
/// boundary (a 48 ring has an outer diameter of 56), the bar's fill ends in a square cut, and
/// there is no gradient or own track under the fill.

/// Fill paint: a solid colour or a gradient (stops at positions 0…1 along the FILLED part).
@immutable
final class ProgressFill {
  const ProgressFill.solid(Color this.color) : colors = null, positions = null;
  const ProgressFill.gradient(List<Color> this.colors, List<double> this.positions) : color = null;

  final Color? color;
  final List<Color>? colors;
  final List<double>? positions;

  bool get isGradient => colors != null;

  @override
  bool operator ==(Object other) =>
      other is ProgressFill &&
      other.color == color &&
      listEquals(other.colors, colors) &&
      listEquals(other.positions, positions);

  @override
  int get hashCode => Object.hash(color, Object.hashAll(colors ?? const []), Object.hashAll(positions ?? const []));
}

/// A bar's track with its fill.
///
/// It has no natural width of its own (`unweightedStretchInRow`): in a row of natural width a
/// bar without a caption is zero wide, and with a caption it is as wide as the caption; it
/// takes the width from its parent. The height is the thickness.
///
/// The fill grows from the LOGICAL start ([textDirection]); the track and fill radius is
/// [pillRadius], clamped to half the shorter side, and the track clips the fill
/// (`bar.fillClip`).
class ProgressTrack extends LeafRenderObjectWidget {
  const ProgressTrack({
    super.key,
    required this.ratio,
    required this.thickness,
    required this.pillRadius,
    required this.trackColor,
    required this.fill,
    this.segments,
    this.segmentGap = 0,
    this.currentColor,
    this.roundEnds = false,
  });

  /// Round ends (schema 9.21.0, `cap: 'round'`): half circles of half the thickness on the track, the fill and
  /// every step, whatever the theme's `pill` is.
  final bool roundEnds;

  final double ratio;
  final double thickness;
  final double pillRadius;
  final Color trackColor;
  final ProgressFill fill;

  /// Steps (`segments` 2…12); `null` means a continuous bar. A step narrower than a pixel also
  /// gives a continuous bar (`belowMinSegment`), visible only at layout time.
  final int? segments;

  /// Gap between steps (token `xs`).
  final double segmentGap;

  /// Colour of the current step; `null` means the same as an unfilled one.
  final Color? currentColor;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderProgressTrack(
    ratio: ratio,
    thickness: thickness,
    pillRadius: pillRadius,
    trackColor: trackColor,
    fill: fill,
    segments: segments,
    segmentGap: segmentGap,
    currentColor: currentColor,
    roundEnds: roundEnds,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderProgressTrack renderObject) {
    renderObject
      ..ratio = ratio
      ..thickness = thickness
      ..pillRadius = pillRadius
      ..trackColor = trackColor
      ..fill = fill
      ..segments = segments
      ..segmentGap = segmentGap
      ..currentColor = currentColor
      ..roundEnds = roundEnds
      ..textDirection = Directionality.of(context);
  }
}

class RenderProgressTrack extends RenderBox {
  RenderProgressTrack({
    required double ratio,
    required double thickness,
    required double pillRadius,
    required Color trackColor,
    required ProgressFill fill,
    required TextDirection textDirection,
    int? segments,
    double segmentGap = 0,
    Color? currentColor,
    bool roundEnds = false,
  }) : _segments = segments,
       _roundEnds = roundEnds,
       _segmentGap = segmentGap,
       _currentColor = currentColor,
       _ratio = ratio,
       _thickness = thickness,
       _pillRadius = pillRadius,
       _trackColor = trackColor,
       _fill = fill,
       _textDirection = textDirection;

  double _ratio;
  set ratio(double value) {
    if (value == _ratio) return;
    _ratio = value;
    markNeedsPaint();
  }

  double _thickness;
  set thickness(double value) {
    if (value == _thickness) return;
    _thickness = value;
    markNeedsLayout();
  }

  double _pillRadius;
  set pillRadius(double value) {
    if (value == _pillRadius) return;
    _pillRadius = value;
    markNeedsPaint();
  }

  Color _trackColor;
  set trackColor(Color value) {
    if (value == _trackColor) return;
    _trackColor = value;
    markNeedsPaint();
  }

  ProgressFill _fill;
  set fill(ProgressFill value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  int? _segments;
  set segments(int? value) {
    if (value == _segments) return;
    _segments = value;
    markNeedsLayout();
  }

  double _segmentGap;
  set segmentGap(double value) {
    if (value == _segmentGap) return;
    _segmentGap = value;
    markNeedsLayout();
  }

  bool _roundEnds;
  set roundEnds(bool value) {
    if (value == _roundEnds) return;
    _roundEnds = value;
    markNeedsPaint();
  }

  Color? _currentColor;
  set currentColor(Color? value) {
    if (value == _currentColor) return;
    _currentColor = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  /// Own minimum width: for a bar with steps it is `(N - 1) x gap` in BOTH looks (steps and the
  /// continuous substitute); without steps it is zero. The look does not depend on it: it is
  /// decided by the width the place gave (see [paint]).
  double get _ownMinInline {
    final steps = _segments;
    return steps == null ? 0 : segmentsMinInline(steps, _segmentGap);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _ownMinInline;

  @override
  double computeMaxIntrinsicWidth(double height) => _ownMinInline;

  @override
  double computeMinIntrinsicHeight(double width) => _thickness;

  @override
  double computeMaxIntrinsicHeight(double width) => _thickness;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(constraints.hasBoundedWidth ? constraints.maxWidth : math.max(constraints.minWidth, _ownMinInline), _thickness),
  );

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final thickness = size.height;
    if (thickness <= 0 || size.width <= 0) return;
    final steps = _segments;
    if (steps != null) {
      final cut = segmentGeometry(
        trackInline: size.width,
        thickness: thickness,
        ratio: _ratio,
        segments: steps,
        gap: _segmentGap,
        pill: _pillRadius,
        roundEnds: _roundEnds,
      );
      // A step narrower than a pixel is not a step: a continuous bar (`belowMinSegment`).
      if (cut != null) {
        _paintSegments(context.canvas, offset, cut);
        return;
      }
    }
    final geometry = BarGeometry.of(
      trackInline: size.width,
      thickness: thickness,
      ratio: _ratio,
      pill: _pillRadius,
      roundEnds: _roundEnds,
    );
    final canvas = context.canvas;
    final track = RRect.fromRectAndRadius(
      offset & size,
      Radius.circular(geometry.trackRadius),
    );
    canvas.drawRRect(track, Paint()..color = _trackColor);
    if (geometry.fillInline <= 0) return;

    final rtl = _textDirection == TextDirection.rtl;
    final left = rtl ? offset.dx + size.width - geometry.fillInline : offset.dx;
    final fillRect = Rect.fromLTWH(left, offset.dy, geometry.fillInline, thickness);
    final paint = Paint();
    final colors = _fill.colors;
    if (colors == null) {
      paint.color = _fill.color!;
    } else {
      // The gradient line runs from the start of the fill to its end in the writing direction
      // (`bar.gradientLine`); position 1 is the end of the FILL.
      final y = fillRect.center.dy;
      paint.shader = ui.Gradient.linear(
        Offset(rtl ? fillRect.right : fillRect.left, y),
        Offset(rtl ? fillRect.left : fillRect.right, y),
        colors,
        _fill.positions,
      );
    }
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, Radius.circular(geometry.fillRadius)),
      paint,
    );
    canvas.restore();
  }

  /// Steps (schema 9.11.0). There is no track UNDER the gaps: the background shows through. A
  /// step is filled entirely or not at all; in right-to-left writing the first step is on the
  /// right. The gradient runs along the FILLED steps as along one fill (from the start of the
  /// first to the end of the last filled step), gaps cut out: one shader for all, each filled
  /// step a separate rectangle on top.
  void _paintSegments(Canvas canvas, Offset offset, SegmentGeometry cut) {
    final rtl = _textDirection == TextDirection.rtl;
    final y = offset.dy;
    final colors = _fill.colors;
    Paint? filledPaint;
    if (colors == null) {
      filledPaint = Paint()..color = _fill.color!;
    } else if (cut.filled > 0) {
      final startX = rtl ? offset.dx + size.width : offset.dx;
      final endX = rtl ? offset.dx + size.width - cut.filledInline : offset.dx + cut.filledInline;
      filledPaint = Paint()
        ..shader = ui.Gradient.linear(Offset(startX, y), Offset(endX, y), colors, _fill.positions);
    }
    for (var i = 0; i < cut.starts.length; i += 1) {
      final start = cut.starts[i];
      final left = rtl ? offset.dx + size.width - start - cut.inline : offset.dx + start;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y, cut.inline, size.height),
        Radius.circular(cut.radius),
      );
      final state = cut.states[i];
      canvas.drawRRect(
        rect,
        state == SegmentState.filled
            ? filledPaint!
            : (Paint()..color = state == SegmentState.current ? (_currentColor ?? _trackColor) : _trackColor),
      );
    }
  }
}

/// Paints the ring: the track under the WHOLE scale, the fill arc on top.
///
/// The arc lies INSIDE the circle (`ring.strokeAlign: 'inside'`): the outer diameter equals the
/// diameter, and the radius of the stroke's centre line is "(diameter - thickness) / 2". It
/// starts at the top and grows clockwise in any writing direction: the ring is a dial, not a
/// line of text; the ends are square cuts.
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.ratio,
    required this.thickness,
    required this.trackColor,
    required this.fill,
    this.roundEnds = false,
  });

  final double ratio;

  /// Round ends of the arc (schema 9.21.0, `cap: 'round'`): see [ringCapGeometry].
  final bool roundEnds;

  /// Thickness already clamped to half the diameter ([ringGeometry]).
  final double thickness;
  final Color trackColor;
  final ProgressFill fill;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = math.min(size.width, size.height);
    if (thickness <= 0 || diameter <= 0) return;
    final center = size.center(Offset.zero);
    final radius = (diameter - thickness) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = trackColor,
    );
    final arc = ringArc(ratio);
    if (arc.sweepDeg <= 0) return;

    final sweep = arc.sweepDeg * math.pi / 180;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    final colors = fill.colors;
    if (colors == null) {
      paint.color = fill.color!;
    } else {
      // The gradient runs along the arc: conic from its start to its end. The seam is at the top
      // (GradientRotation by a quarter turn), positions are as in the document because the gradient
      // is already compressed by the angle `endAngle`.
      paint.shader = SweepGradient(
        startAngle: 0,
        endAngle: sweep,
        colors: colors,
        stops: fill.positions,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(Offset.zero & size);
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (!roundEnds) {
      canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
      return;
    }
    _paintRoundArc(canvas, center, rect, radius, sweep, paint);
  }

  /// The arc with round ends (`progressCap.ring`): a square-ended arc between the centres of the two ends, and the
  /// ends as circles of the thickness. A full scale is the whole ring (no ends, no seam). A solid fill lets
  /// the stroke round its own ends; a gradient paints each end with the colour of the gradient at its centre.
  void _paintRoundArc(Canvas canvas, Offset center, Rect rect, double radius, double sweep, Paint paint) {
    final diameter = radius * 2 + thickness;
    final cap = ringCapGeometry(ratio, diameter, thickness);
    switch (cap.kind) {
      case RingCapKind.none:
        return;
      case RingCapKind.full:
        canvas.drawCircle(center, radius, paint);
      case RingCapKind.dot:
        canvas.drawCircle(_onRing(center, radius, cap.capAngle), thickness / 2, _endPaint(sweep, cap.capAngle));
      case RingCapKind.arc:
        final end = sweep - cap.capAngle;
        if (fill.colors == null) {
          canvas.drawArc(rect, -math.pi / 2 + cap.capAngle, end - cap.capAngle, false, paint..strokeCap = StrokeCap.round);
        } else {
          canvas.drawArc(rect, -math.pi / 2 + cap.capAngle, end - cap.capAngle, false, paint);
          canvas
            ..drawCircle(_onRing(center, radius, cap.capAngle), thickness / 2, _endPaint(sweep, cap.capAngle))
            ..drawCircle(_onRing(center, radius, end), thickness / 2, _endPaint(sweep, end));
        }
    }
  }

  /// The point of the middle line of the stroke at [angle] radians clockwise from the top.
  Offset _onRing(Offset center, double radius, double angle) =>
      center + Offset(math.sin(angle), -math.cos(angle)) * radius;

  /// The paint of an end or a dot centred at [angle] of an arc of [sweep] radians: the fill colour, or the
  /// gradient colour at that share of the filled part.
  Paint _endPaint(double sweep, double angle) {
    final colors = fill.colors;
    return Paint()
      ..color = colors == null ? fill.color! : gradientColorAt(colors, fill.positions!, (angle / sweep).clamp(0.0, 1.0));
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.ratio != ratio ||
      old.thickness != thickness ||
      old.trackColor != trackColor ||
      old.fill != fill ||
      old.roundEnds != roundEnds;
}

/// The ring stands in the CENTRE of the place it was given (`ring.placement`), and takes its
/// size from the diameter, not from the parent (`ring.unnamedSide`).
///
/// A tight constraint from the parent (a row weight, a layer over the whole stack, an own
/// `width` larger than the diameter) would otherwise stretch the ring into an ellipse. The
/// natural size is the diameter, so in a row of natural width it is exactly that wide.
class RingPlacement extends SingleChildRenderObjectWidget {
  const RingPlacement({super.key, required this.diameter, required Widget super.child});

  final double diameter;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderRingPlacement(diameter);

  @override
  void updateRenderObject(BuildContext context, RenderRingPlacement renderObject) {
    renderObject.diameter = diameter;
  }
}

class RenderRingPlacement extends RenderShiftedBox {
  RenderRingPlacement(double diameter) : _diameter = diameter, super(null);

  double _diameter;
  set diameter(double value) {
    if (value == _diameter) return;
    _diameter = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => _diameter;

  @override
  double computeMaxIntrinsicWidth(double height) => _diameter;

  @override
  double computeMinIntrinsicHeight(double width) => _diameter;

  @override
  double computeMaxIntrinsicHeight(double width) => _diameter;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.square(_diameter));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    final box = child;
    if (box == null) return;
    box.layout(BoxConstraints.tight(Size.square(_diameter)), parentUsesSize: false);
    (box.parentData! as BoxParentData).offset = Offset(
      (size.width - _diameter) / 2,
      (size.height - _diameter) / 2,
    );
  }
}

/// The colour of a gradient with [colors] at [positions] (ascending, 0…1) at the share [at] of the way, linear in
/// the stops like a Flutter gradient: before the first stop the first colour, after the last the last.
Color gradientColorAt(List<Color> colors, List<double> positions, double at) {
  if (at <= positions.first) return colors.first;
  for (var i = 1; i < colors.length; i += 1) {
    if (at <= positions[i]) {
      final span = positions[i] - positions[i - 1];
      return Color.lerp(colors[i - 1], colors[i], span <= 0 ? 1 : (at - positions[i - 1]) / span)!;
    }
  }
  return colors.last;
}
