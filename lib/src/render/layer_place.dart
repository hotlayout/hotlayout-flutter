import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/offset_rules.dart';
import '../model/tokens.dart';

/// Stack overlay (`layer`, schema 9.10.0): a layer placed RELATIVE to the stack's box —
/// aligned by its own word, offset along the stack's axes, rotated around its centre — which
/// never changes that box.
///
/// It is placed AS `Positioned.fill`: the stack is not sized by positioned children
/// (`sizing: overlay-does-not-size-the-stack`), and the overlay itself receives the stack's
/// tight box and puts the layer in it. This is not `Align` with `Transform.translate`, and the
/// difference is in hit testing: `Transform` paints the layer in one place but maps the touch
/// to another (`RenderStack` and ancestors reject a point outside their own box), whereas here
/// the layout itself knows where the layer is and the hit test goes through the same matrix as
/// painting. So a touch is caught where the layer is painted, within the stack's box
/// (`layerTaps`). The contract promises nothing about a part sticking out of the stack, and
/// this widget does not either: the stack's box bounds the ancestors' hit test.
///
/// The layer's HEIGHT is natural, NOT limited by the stack (`size`): a long caption wraps at
/// the stack's width, and a tall overlay is neither squeezed nor shows an overflow stripe, so
/// the child gets unbounded height, unlike `Positioned.fill(child: Align(…))`, which would
/// bound it too.
///
/// All numbers (angle, offsets, alignment) come from [layerGeometry], the reference
/// implementation also exercised by the `offset-cases.json` table.
class LayerPlace extends SingleChildRenderObjectWidget {
  const LayerPlace({
    super.key,
    required this.alignHorizontal,
    required this.alignVertical,
    this.offsetX,
    this.offsetY,
    this.rotate = 0,
    required super.child,
  });

  /// Alignment: the layer's own word or the stack's word (already chosen).
  final AlignToken alignHorizontal;
  final AlignToken alignVertical;

  /// Offset along the stack's axes in logical pixels; `null` means no offset on that axis.
  final LayerPixelOffset? offsetX;
  final LayerPixelOffset? offsetY;

  /// Whole degrees clockwise (the layout flips the sign in RTL).
  final int rotate;

  @override
  RenderLayerPlace createRenderObject(BuildContext context) => RenderLayerPlace(
    alignHorizontal: alignHorizontal,
    alignVertical: alignVertical,
    offsetX: offsetX,
    offsetY: offsetY,
    rotate: rotate,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderLayerPlace renderObject) {
    renderObject
      ..alignHorizontal = alignHorizontal
      ..alignVertical = alignVertical
      ..offsetX = offsetX
      ..offsetY = offsetY
      ..rotate = rotate
      ..textDirection = Directionality.of(context);
  }
}

/// Offset along one axis, already in pixels: a direction word (`start` / `end` or `top` /
/// `bottom`) and a magnitude.
@immutable
class LayerPixelOffset {
  const LayerPixelOffset(this.toward, this.by);

  final String toward;
  final double by;

  @override
  bool operator ==(Object other) => other is LayerPixelOffset && other.toward == toward && other.by == by;

  @override
  int get hashCode => Object.hash(toward, by);
}

class RenderLayerPlace extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  RenderLayerPlace({
    required AlignToken alignHorizontal,
    required AlignToken alignVertical,
    LayerPixelOffset? offsetX,
    LayerPixelOffset? offsetY,
    int rotate = 0,
    required TextDirection textDirection,
  }) : _alignHorizontal = alignHorizontal,
       _alignVertical = alignVertical,
       _offsetX = offsetX,
       _offsetY = offsetY,
       _rotate = rotate,
       _textDirection = textDirection;

  AlignToken _alignHorizontal;
  set alignHorizontal(AlignToken value) {
    if (_alignHorizontal == value) return;
    _alignHorizontal = value;
    markNeedsLayout();
  }

  AlignToken _alignVertical;
  set alignVertical(AlignToken value) {
    if (_alignVertical == value) return;
    _alignVertical = value;
    markNeedsLayout();
  }

  LayerPixelOffset? _offsetX;
  set offsetX(LayerPixelOffset? value) {
    if (_offsetX == value) return;
    _offsetX = value;
    markNeedsLayout();
  }

  LayerPixelOffset? _offsetY;
  set offsetY(LayerPixelOffset? value) {
    if (_offsetY == value) return;
    _offsetY = value;
    markNeedsLayout();
  }

  int _rotate;
  set rotate(int value) {
    if (_rotate == value) return;
    _rotate = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  LayerGeometry? _geometry;

  /// Where the layer stands after the last layout (reference geometry): the unrotated box in the
  /// stack's physical coordinates, the angle and whether it sticks out. `null` means the layer
  /// has not been measured yet or there is no child.
  LayerGeometry? get geometry => _geometry;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      _geometry = null;
      return;
    }
    // Width is at most the stack's, height is its own, even when larger than the stack's.
    child.layout(BoxConstraints(maxWidth: size.width), parentUsesSize: true);
    _geometry = layerGeometry(
      LayerGeometryInput(
        stack: size,
        layer: child.size,
        alignHorizontal: _alignHorizontal,
        alignVertical: _alignVertical,
        offsetXToward: _offsetX?.toward,
        offsetX: _offsetX?.by ?? 0,
        offsetYToward: _offsetY?.toward,
        offsetY: _offsetY?.by ?? 0,
        rotate: _rotate,
        rtl: _textDirection == TextDirection.rtl,
      ),
    );
  }

  /// The "layer box → overlay box" matrix: translation to the layer's place, rotation around the
  /// layer's CENTRE (the angle already accounts for RTL).
  Matrix4 get _paintMatrix {
    final geometry = _geometry!;
    final center = geometry.rect.center;
    return Matrix4.translationValues(center.dx, center.dy, 0)
      .multiplied(Matrix4.rotationZ(geometry.angle * math.pi / 180))
      .multiplied(Matrix4.translationValues(-center.dx, -center.dy, 0))
      .multiplied(Matrix4.translationValues(geometry.rect.left, geometry.rect.top, 0));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final geometry = _geometry;
    if (geometry == null) return;
    transform.multiply(_paintMatrix);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _geometry == null) return;
    final matrix = _paintMatrix;
    // The layer is painted without clipping to the stack's box: sticking out is legal.
    context.pushTransform(needsCompositing, offset, matrix, (context, offset) => context.paintChild(child, offset));
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null || _geometry == null) return false;
    return result.addWithPaintTransform(
      transform: _paintMatrix,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}
