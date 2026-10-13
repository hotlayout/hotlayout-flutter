// Places a list marker at the end of its column.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The END of a list marker's column (schema 9.17.0, `listMarker.markerAlign: 'column-end'`,
/// `overflow: 'visible-toward-start'`): the child is pushed against the END of the column (the
/// right edge in left-to-right writing, the left edge in right-to-left). A child wider than
/// the column grows toward the START and is not clipped. The child does not change the column's
/// height and passes its baseline on, so the marker sits on the text's first baseline.
///
/// Not `OverflowBox`: that takes everything the parent allows, and in a baseline-aligned row
/// inside a scroll view there is no bounded height.
class MarkerColumnEnd extends SingleChildRenderObjectWidget {
  const MarkerColumnEnd({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMarkerColumnEnd(textDirection: Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, covariant RenderMarkerColumnEnd renderObject) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class RenderMarkerColumnEnd extends RenderShiftedBox {
  RenderMarkerColumnEnd({required TextDirection textDirection}) : _textDirection = textDirection, super(null);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  Size _size(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(Size(constraints.hasTightWidth ? constraints.maxWidth : childSize.width, childSize.height));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _size(constraints, child.getDryLayout(const BoxConstraints()));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(const BoxConstraints(), parentUsesSize: true);
    size = _size(constraints, child.size);
    (child.parentData! as BoxParentData).offset = Offset(
      _textDirection == TextDirection.ltr ? size.width - child.size.width : 0,
      0,
    );
  }
}
