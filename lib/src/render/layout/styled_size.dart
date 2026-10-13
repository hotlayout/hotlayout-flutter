// The box of a node with a declared size: exact, minimum and maximum sides.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../model/tokens.dart';

/// The size of a box from a node's style.
///
/// Not a `ConstrainedBox`, and the difference is not cosmetic. `ConstrainedBox` clamps its
/// constraints into the parent's, so where the parent gives a TIGHT width (a grid cell, a
/// stretched repeater instance) `style.width` would have no effect at all. Here the axis on which
/// the style names an upper bound is LOOSENED: the node takes its own width and sits at the start
/// of the space it was given, like a block with `width` in CSS.
///
/// Only the axis the style said something about is loosened: a chart column with a weight and a
/// set height keeps its whole share of the width.
///
/// The node never becomes larger than the space the parent gave, so in the infinite width of a
/// scroll view or a `Wrap` there is nothing to crash on.
///
/// [stretchAlign]: the node is a STRETCHED column child and the parent gave it a TIGHT width.
/// Then `minWidth` / `maxWidth` limit the STRETCHED width (`constrainedStretch:
/// 'clamp-then-same-align'`): the node takes `clamp(space, minWidth, maxWidth)` whole, not its
/// natural width, and if that comes out narrower than the space it is placed by the parent's
/// `align`. Without a tight width (infinity, free space) the field changes nothing.
class StyledSize extends SingleChildRenderObjectWidget {
  const StyledSize({super.key, required this.limits, this.stretchAlign, required Widget super.child});

  final BoxConstraints limits;
  final AlignToken? stretchAlign;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderStyledSize(
    limits: limits,
    stretchAlign: stretchAlign,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderStyledSize renderObject) {
    renderObject
      ..limits = limits
      ..stretchAlign = stretchAlign
      ..textDirection = Directionality.of(context);
  }
}

class RenderStyledSize extends RenderShiftedBox {
  RenderStyledSize({
    required BoxConstraints limits,
    required TextDirection textDirection,
    AlignToken? stretchAlign,
  }) : _limits = limits,
       _textDirection = textDirection,
       _stretchAlign = stretchAlign,
       super(null);

  AlignToken? _stretchAlign;
  set stretchAlign(AlignToken? value) {
    if (_stretchAlign == value) return;
    _stretchAlign = value;
    markNeedsLayout();
  }

  BoxConstraints _limits;
  BoxConstraints get limits => _limits;
  set limits(BoxConstraints value) {
    if (_limits == value) return;
    _limits = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// The constraints of one axis for the child.
  static (double, double) _axis(double min, double max, double parentMin, double parentMax) {
    // The style named an upper bound, so the parent's lower bound no longer applies.
    if (max.isFinite) return (math.min(min, parentMax), math.min(max, parentMax));
    return (math.max(parentMin, math.min(min, parentMax)), parentMax);
  }

  BoxConstraints _childConstraints(BoxConstraints parent) {
    var (minWidth, maxWidth) = _axis(_limits.minWidth, _limits.maxWidth, parent.minWidth, parent.maxWidth);
    // A stretched column child: the width is the space clamped to `minWidth` / `maxWidth`, but
    // never more than the space itself.
    if (_stretchAlign != null && parent.hasBoundedWidth && parent.minWidth == parent.maxWidth) {
      minWidth = maxWidth = math.min(_limits.constrainWidth(parent.maxWidth), parent.maxWidth);
    }
    final (minHeight, maxHeight) = _axis(
      _limits.minHeight,
      _limits.maxHeight,
      parent.minHeight,
      parent.maxHeight,
    );
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _limits.constrainWidth(super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _limits.constrainWidth(super.computeMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _limits.constrainHeight(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _limits.constrainHeight(super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.constrain(_childConstraints(constraints).smallest);
    return constraints.constrain(child.getDryLayout(_childConstraints(constraints)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(_childConstraints(constraints).smallest);
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
    // The start of the allotted space is logical: in right-to-left writing it is the right edge.
    // A stretched column child narrower than the space is placed by the parent's `align` (the same
    // logical measure).
    final free = size.width - child.size.width;
    final fromStart = switch (_stretchAlign) {
      null || AlignToken.start => 0.0,
      AlignToken.center => 0.5,
      AlignToken.end => 1.0,
    };
    (child.parentData! as BoxParentData).offset = Offset(
      free * (_textDirection == TextDirection.rtl ? 1 - fromStart : fromStart),
      0,
    );
  }
}
