/// A radial gradient that is a circle of any box: its radius is a share of the distance from its centre to the
/// farthest corner of the box.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The numbers of a radial gradient on a box of [width] x [height]: the contract counts them once for every
/// reader, and the table of the shared cases checks them to 1e-6.
///
/// [centerX] and [centerY] are shares of the box (0, 0 the top left, y grows downwards); [radius] is the share of the
/// distance to the farthest corner. [flutterRadius] is the radius as Flutter's `RadialGradient.radius` wants it, a
/// share of the SHORTER side of the box.
@immutable
class RadialMetrics {
  const RadialMetrics({
    required this.farthestCorner,
    required this.radiusPx,
    required this.flutterRadius,
    required this.flutterCenter,
  });

  /// The distance from the centre to the farthest of the four corners, in pixels.
  final double farthestCorner;

  /// The radius of the circle in pixels: [farthestCorner] times the share.
  final double radiusPx;

  final double flutterRadius;

  /// The centre as Flutter's `Alignment` (-1 to 1) names it.
  final Alignment flutterCenter;
}

/// The radial gradient numbers of a box. A box with no area has no circle (every number is zero).
RadialMetrics radialGradientMetrics({
  required double width,
  required double height,
  required double centerX,
  required double centerY,
  required double radius,
}) {
  final cx = centerX * width;
  final cy = centerY * height;
  final farthest = math.sqrt(
    math.max(math.max(cx * cx, (width - cx) * (width - cx)) + math.max(cy * cy, (height - cy) * (height - cy)), 0),
  );
  final shortest = math.min(width, height);
  final radiusPx = radius * farthest;
  return RadialMetrics(
    farthestCorner: farthest,
    radiusPx: radiusPx,
    flutterRadius: shortest > 0 ? radiusPx / shortest : 0,
    flutterCenter: Alignment(2 * centerX - 1, 2 * centerY - 1),
  );
}

/// A RADIAL gradient whose radius is counted from the box it is drawn on (9.36.0).
///
/// Flutter's [RadialGradient] takes its radius as a share of the SHORTER side, so one value cannot be a share of the
/// farthest corner in a box of any proportions. This one keeps the share and works the radius out of the rectangle at
/// the moment it makes the shader: a circle (never an ellipse), stops as shares of the radius, the colour of the first
/// stop before it and of the last after it. The centre is physical: it is not mirrored in right-to-left writing.
class RadialBoxGradient extends RadialGradient {
  RadialBoxGradient({
    required this.centerX,
    required this.centerY,
    required this.share,
    required super.colors,
    required List<double> super.stops,
  }) : super(center: Alignment(2 * centerX - 1, 2 * centerY - 1), radius: share);

  final double centerX;
  final double centerY;

  /// The radius as a share of the distance from the centre to the farthest corner.
  final double share;

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    final metrics = radialGradientMetrics(
      width: rect.width,
      height: rect.height,
      centerX: centerX,
      centerY: centerY,
      radius: share,
    );
    // A degenerate box has no circle to draw; the shader of an empty rectangle is never painted anyway.
    final radiusPx = metrics.radiusPx > 0 ? metrics.radiusPx : 1e-6;
    return ui.Gradient.radial(
      Offset(rect.left + centerX * rect.width, rect.top + centerY * rect.height),
      radiusPx,
      colors,
      stops,
      TileMode.clamp,
    );
  }

  @override
  RadialBoxGradient scale(double factor) => RadialBoxGradient(
    centerX: centerX,
    centerY: centerY,
    share: share,
    colors: [for (final color in colors) Color.lerp(null, color, factor)!],
    stops: stops!,
  );

  @override
  bool operator ==(Object other) =>
      other is RadialBoxGradient &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.share == share &&
      listEquals(other.colors, colors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(centerX, centerY, share, Object.hashAll(colors), Object.hashAll(stops!));
}
