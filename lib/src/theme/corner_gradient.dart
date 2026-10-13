/// A linear gradient that runs from corner to corner of its box, as CSS draws a
/// diagonal.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A DIAGONAL "CORNER TO CORNER" GRADIENT with the exact geometry of CSS `to <corner>`.
///
/// A plain `LinearGradient(begin: topLeft, end: bottomRight)` on a NON-SQUARE box does not draw
/// what CSS draws. Its start and end sit in the corners, but the lines of equal colour are
/// perpendicular to the diagonal, so the midpoint (50 %) on a 2:1 card does NOT pass through the
/// two other corners. In CSS `to bottom right` means exactly that: the 50 % isoline runs corner to
/// corner along the other diagonal. Two readers would draw the same card differently, visible only
/// with the screens side by side.
///
/// The solution is to draw the gradient in a UNIT square and stretch it onto the box with a
/// matrix. In the square both interpretations agree (isolines parallel to the other diagonal),
/// and non-uniform stretching preserves parallelism: the square's other diagonal maps onto the
/// box's other diagonal together with all the isolines.
///
/// [begin] and [end] remain the same corners; everything that asks the gradient about its
/// direction without painting it relies on them.
@immutable
class CornerGradient extends LinearGradient {
  const CornerGradient({
    required Alignment super.begin,
    required Alignment super.end,
    required super.colors,
    required List<double> super.stops,
  });

  /// The fraction of the gradient path (0..1) at a point of the box: the same formula the shader
  /// runs. Separate so the geometry can be checked numerically.
  double positionAt(Offset point, Size size) {
    final from = _unit(begin as Alignment);
    final to = _unit(end as Alignment);
    final axis = to - from;
    final local = Offset(point.dx / size.width, point.dy / size.height) - from;
    return (local.dx * axis.dx + local.dy * axis.dy) / axis.distanceSquared;
  }

  static Offset _unit(Alignment alignment) => Offset((alignment.x + 1) / 2, (alignment.y + 1) / 2);

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    // A degenerate box: there is nothing to stretch onto, and a matrix with a zero on the
    // diagonal is not invertible.
    if (rect.width <= 0 || rect.height <= 0 || !rect.isFinite) {
      return super.createShader(rect, textDirection: textDirection);
    }
    final matrix = Float64List(16)
      ..[0] = rect.width
      ..[5] = rect.height
      ..[10] = 1
      ..[12] = rect.left
      ..[13] = rect.top
      ..[15] = 1;
    return ui.Gradient.linear(
      _unit(begin as Alignment),
      _unit(end as Alignment),
      colors,
      stops,
      tileMode,
      matrix,
    );
  }
}

