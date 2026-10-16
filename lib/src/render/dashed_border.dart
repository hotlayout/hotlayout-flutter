/// The drawing of a dashed border (schema 9.22.0): dashes along the centre line of the border, following the
/// corner arcs. The numbers are the contract's (`model/border_dash.dart`); this file only draws them.
library;

import 'package:flutter/material.dart';

import '../model/border_dash.dart';

/// A border side that says "dashed". It carries the colour and width like any other side, so the layout (the
/// room a solid border takes) is computed from it unchanged; the surface sees the type and draws dashes instead
/// of a solid frame.
class DashedBorderSide extends BorderSide {
  const DashedBorderSide({required super.color, required super.width});
}

/// Draws the dashes OVER the child, inside the box: the line lies half a width inside the outer edge.
class DashedBorder extends StatelessWidget {
  const DashedBorder({super.key, required this.side, required this.radius, required this.child});

  final BorderSide side;
  final BorderRadiusGeometry? radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
        color: side.color,
        width: side.width,
        radius: radius?.resolve(direction) ?? BorderRadius.zero,
        direction: direction,
      ),
      child: child,
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    required this.width,
    required this.radius,
    required this.direction,
  });

  final Color color;
  final double width;

  /// The PHYSICAL radii of the box (already resolved for [direction]).
  final BorderRadius radius;
  final TextDirection direction;

  /// The logical corners: in right-to-left writing the start is the right side.
  DashRadii get _logical => direction == TextDirection.rtl
      ? (topStart: radius.topRight.x, topEnd: radius.topLeft.x, bottomEnd: radius.bottomLeft.x, bottomStart: radius.bottomRight.x)
      : (topStart: radius.topLeft.x, topEnd: radius.topRight.x, bottomEnd: radius.bottomRight.x, bottomStart: radius.bottomLeft.x);

  DashedBox _boxOf(Size size) => (width: size.width, height: size.height, border: width, radii: _logical);

  /// The centre line, from the inline start of the top edge to the inline end, in the coordinates of THIS box
  /// (mirrored for right-to-left writing).
  Path linePath(Size size) {
    final frame = dashedFrameOf(_boxOf(size));
    final (:left, :top, :right, :bottom, :radii) = frame;
    void arcTo(Path path, double r, double x, double y) {
      if (r > 0) {
        path.arcToPoint(Offset(x, y), radius: Radius.circular(r));
      } else {
        path.lineTo(x, y);
      }
    }

    final path = Path()
      ..moveTo(left + radii.topStart, top)
      ..lineTo(right - radii.topEnd, top);
    arcTo(path, radii.topEnd, right, top + radii.topEnd);
    path.lineTo(right, bottom - radii.bottomEnd);
    arcTo(path, radii.bottomEnd, right - radii.bottomEnd, bottom);
    path.lineTo(left + radii.bottomStart, bottom);
    arcTo(path, radii.bottomStart, left, bottom - radii.bottomStart);
    path.lineTo(left, top + radii.topStart);
    arcTo(path, radii.topStart, left + radii.topStart, top);
    path.close();
    if (direction == TextDirection.rtl) {
      // The mirror: x -> width - x.
      return path.transform(Matrix4(-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, size.width, 0, 0, 1).storage);
    }
    return path;
  }

  /// The dashes, one path each, in order from the start.
  List<Path> dashes(Size size) {
    final line = dashedLineOf(_boxOf(size));
    if (line.count == 0) return const [];
    final metrics = linePath(size).computeMetrics().toList();
    if (metrics.isEmpty) return const [];
    final contour = metrics.first;
    return [
      for (var index = 0; index < line.count; index += 1)
        contour.extractPath(index * (line.dash + line.gap), index * (line.dash + line.gap) + line.dash),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    for (final dash in dashes(size)) {
      canvas.drawPath(dash, paint);
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.width != width || old.radius != radius || old.direction != direction;
}
