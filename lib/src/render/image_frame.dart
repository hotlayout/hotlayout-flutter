import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The image box (`x-style.layout.image`, schema 9.9.0).
///
/// The image's box is the NODE's box; there is no second, inner "frame":
///
///  * width is the one the parent gave (a named `style.width` has already clamped the outer
///    constraints, a column stretches, a row divides);
///  * height is tight from `style.height` when it is named (the aspect ratio then does NOT
///    apply: a 56 x 56 avatar with `16:9` stays 56 x 56); otherwise "width / ratio", clamped
///    by the node's `minHeight` / `maxHeight`, which also arrive as constraints (the minimum
///    is stronger; `_axisLimits` does that);
///  * the ratio computes ONLY the height from the width, never the reverse: an image with a
///    named height and no named width takes the parent's width. Flutter's `AspectRatio` under
///    a bounded height would shrink the WIDTH, which is not this rule;
///  * the file's natural size is never read: the box has the same size before loading,
///    during it and after (the "loading" and "unavailable" states occupy the same box).
///
/// The computation is [imageBoxOf], checked against the `imageBoxCases` table; here it is only
/// applied to the constraints. The picture is laid into the box by `fit`, centred (Flutter:
/// `BoxFit` plus centre), and the node's radius clips it, which the shared node box does.
class ImageFrame extends SingleChildRenderObjectWidget {
  const ImageFrame({super.key, required this.ratio, required super.child});

  /// "Width / height".
  final double ratio;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderImageFrame(ratio: ratio);

  @override
  void updateRenderObject(BuildContext context, covariant RenderImageFrame renderObject) {
    renderObject.ratio = ratio;
  }
}

class RenderImageFrame extends RenderProxyBox {
  RenderImageFrame({required double ratio}) : _ratio = ratio;

  double _ratio;
  set ratio(double value) {
    if (_ratio == value) return;
    _ratio = value;
    markNeedsLayout();
  }

  Size _sizeFor(BoxConstraints constraints) {
    // An image does not fill an infinite width: it has no width of its own.
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth;
    final height = constraints.hasTightHeight
        ? constraints.maxHeight
        : constraints.constrainHeight(width / _ratio);
    return constraints.constrain(Size(width, height));
  }

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
  double computeMinIntrinsicHeight(double width) => math.max(0, width) / _ratio;

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(0, width) / _ratio;
}
