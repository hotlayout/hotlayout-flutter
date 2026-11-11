/// The inner shadow of a box (`inset: true` on a layer of an own shadow): inside the border, over the background,
/// under the content.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/inner_shadow_layer.dart';

export '../theme/inner_shadow_layer.dart' show InnerShadow;

/// Where an inner layer is cut and where its hole is.
///
/// The CLIP is the padding box: the box less the border on every side, each corner radius less the border width and
/// never below zero. The HOLE is that clip moved by the offset and narrowed by the spread (a negative spread widens it);
/// its sides are never below zero, a corner radius is the radius of the clip less the spread and never below zero, and a
/// square corner stays square. What is painted is everything INSIDE the clip and OUTSIDE the hole, blurred.
({RRect clip, RRect hole}) insetShadowGeometry({
  required Size size,
  required BorderRadius radius,
  required double borderWidth,
  required Offset offset,
  required double spread,
}) {
  Radius inner(Radius corner) {
    final value = math.max(0.0, corner.x - borderWidth);
    return Radius.circular(value);
  }

  final clip = RRect.fromLTRBAndCorners(
    borderWidth,
    borderWidth,
    math.max(borderWidth, size.width - borderWidth),
    math.max(borderWidth, size.height - borderWidth),
    topLeft: inner(radius.topLeft),
    topRight: inner(radius.topRight),
    bottomLeft: inner(radius.bottomLeft),
    bottomRight: inner(radius.bottomRight),
  );
  Radius narrowed(Radius corner) => corner.x == 0 ? Radius.zero : Radius.circular(math.max(0.0, corner.x - spread));

  final left = clip.left + offset.dx + spread;
  final top = clip.top + offset.dy + spread;
  final width = math.max(0.0, clip.width - 2 * spread);
  final height = math.max(0.0, clip.height - 2 * spread);
  final hole = RRect.fromLTRBAndCorners(
    left,
    top,
    left + width,
    top + height,
    topLeft: narrowed(clip.tlRadius),
    topRight: narrowed(clip.trRadius),
    bottomLeft: narrowed(clip.blRadius),
    bottomRight: narrowed(clip.brRadius),
  );
  return (clip: clip, hole: hole);
}

/// Paints the inner layers of a box (the first layer of the document is the nearest and on top, so the list given
/// here is in PAINT order: the last first).
///
/// Each layer fills the clip with its colour everywhere but the hole, blurred with the same conversion of the blur
/// that the outer shadows of the reader use, and is cut to the clip.
class InnerShadowPainter extends CustomPainter {
  const InnerShadowPainter({required this.shadows, required this.radius, required this.borderWidth});

  final List<InnerShadow> shadows;
  final BorderRadius radius;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return;
    for (final layer in shadows) {
      final geometry = insetShadowGeometry(
        size: size,
        radius: radius,
        borderWidth: borderWidth,
        offset: layer.offset,
        spread: layer.spreadRadius,
      );
      final sigma = Shadow.convertRadiusToSigma(layer.blurRadius);
      // The area to fill is the clip and a margin the blur and the moved hole cannot reach past.
      final reach = layer.offset.distance + layer.spreadRadius.abs() + 3 * sigma + 4;
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(geometry.clip.outerRect.inflate(reach))
        ..addRRect(geometry.hole);
      canvas
        ..save()
        ..clipRRect(geometry.clip)
        ..drawPath(
          outside,
          Paint()
            ..color = layer.color
            ..maskFilter = sigma > 0 ? MaskFilter.blur(BlurStyle.normal, sigma) : null,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(InnerShadowPainter old) =>
      !listEquals(old.shadows, shadows) || old.radius != radius || old.borderWidth != borderWidth;
}
