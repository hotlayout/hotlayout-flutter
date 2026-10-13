// The column layout of the contract: children stretch across unless they keep
// their natural width; gaps and pulls between neighbours.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../model/layout_rules.dart';
import '../../model/tokens.dart';

/// Marks "this column child is STRETCHED" (`columnChildWidth`). It measures nothing itself:
/// [StretchColumn] gives it its width and recognizes the mark by the render object's type.
class ColumnStretch extends SingleChildRenderObjectWidget {
  const ColumnStretch({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderColumnStretch();
}

class _RenderColumnStretch extends RenderProxyBox {}

/// A column of the document's children (`columnChildWidth: 'stretch-unless-natural'`).
///
/// Not `Column(crossAxisAlignment: stretch)`, for three reasons:
///
///  * `stretch` in `Column` is all or nothing, while here only the children outside the
///    `naturalWidth` list are stretched; the rest are placed by the parent's `align`;
///  * `stretch` pushes a child to the parent's `maxWidth` even when that is only an UPPER bound.
///    A column in a row without a weight would always take all the room although its content is
///    narrower; in CSS such an element is as wide as its content, and stretched children align to
///    the widest natural one. So when the parent did NOT give a tight width, the column measures
///    the children twice: natural widths first, then stretched to the widest;
///  * on an INFINITE width (a row where the neighbor has a weight) `stretch` is a Flutter
///    assertion failure, not just an ugly look. Here infinity simply yields the widest child's
///    natural width.
///
/// Stretched children are those wrapped in [ColumnStretch].
class StretchColumn extends MultiChildRenderObjectWidget {
  const StretchColumn({
    super.key,
    required this.align,
    this.justify = JustifyToken.start,
    this.freeHeight = false,
    super.children,
  });

  /// Where natural-width children go (`naturalWidthAlign`).
  final AlignToken align;

  /// The main axis (schema 9.15.0): where free space along the column goes.
  final JustifyToken justify;

  /// Whether this column CAN have free space: it has a source of height (`style.height`,
  /// `style.minHeight`, a full-stack layer) or it is the screen body. Without one, a tight height
  /// given by someone else (a grid cell, a tab) gives no room: the column does not stretch itself
  /// "to make it work".
  final bool freeHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderStretchColumn(
    align: align,
    justify: justify,
    freeHeight: freeHeight,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderStretchColumn renderObject) {
    renderObject
      ..align = align
      ..justify = justify
      ..freeHeight = freeHeight
      ..textDirection = Directionality.of(context);
  }
}

/// A GAP BETWEEN THE COLUMN'S CHILDREN: not a document child. The main axis (`justify`) counts
/// only real children and leaves the gap as the smallest distance between them.
class FlowGap extends ParentDataWidget<_StretchParentData> {
  const FlowGap({super.key, required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _StretchParentData;
    if (data.isGap) return;
    data.isGap = true;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => StretchColumn;
}

class _StretchParentData extends ContainerBoxParentData<RenderBox> {
  /// A gap between children, not a document child ([FlowGap]).
  bool isGap = false;

  /// How far the child is pulled toward the axis start (`pull`, schema 9.10.0); 0 means it stands
  /// where the flow put it.
  double pull = 0;
}

/// A PULLED COLUMN CHILD (`pull`, schema 9.10.0): the child's start is the previous child's end
/// plus the gap minus `pull`, everything after it follows, and the column gets shorter (not below
/// zero).
///
/// WHY A LAYOUT OF ITS OWN, not `Transform` or a "size minus pull" wrapper. Flutter has no
/// negative margin. `Transform.translate` paints the child in one place but hit-tests it in
/// another (and does not change the parent's size). A wrapper that tells the parent "own size
/// minus pull" and paints the child shifted back breaks when `pull` exceeds the child (a size
/// cannot be negative). So the layout subtracts `pull` from the position itself: the child LIES
/// where it is seen, and `defaultHitTestChildren` (last to first) gives the overlap strip to the
/// later child, exactly as `pullPaintOrder` says.
class FlowPull extends ParentDataWidget<_StretchParentData> {
  const FlowPull({super.key, required this.pull, required super.child});

  final double pull;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _StretchParentData;
    if (data.pull == pull) return;
    data.pull = pull;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => StretchColumn;
}

class RenderStretchColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<RenderBox, ContainerBoxParentData<RenderBox>> {
  RenderStretchColumn({
    required AlignToken align,
    JustifyToken justify = JustifyToken.start,
    bool freeHeight = false,
    required TextDirection textDirection,
  }) : _align = align,
       _justify = justify,
       _freeHeight = freeHeight,
       _textDirection = textDirection;

  JustifyToken _justify;
  set justify(JustifyToken value) {
    if (_justify == value) return;
    _justify = value;
    markNeedsLayout();
  }

  bool _freeHeight;
  set freeHeight(bool value) {
    if (_freeHeight == value) return;
    _freeHeight = value;
    markNeedsLayout();
  }

  AlignToken _align;
  set align(AlignToken value) {
    if (_align == value) return;
    _align = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StretchParentData) child.parentData = _StretchParentData();
  }

  bool get _hasPull {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if ((child.parentData! as _StretchParentData).pull > 0) return true;
    }
    return false;
  }

  /// The single layout for the real and the dry pass: [measure] measures a child under
  /// constraints, [place] positions it (there is none in the dry pass).
  Size _arrange(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) measure,
    void Function(RenderBox child, Offset offset)? place,
  ) {
    final tight = constraints.hasTightWidth;
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    final sizes = <RenderBox, Size>{};
    var width = constraints.maxWidth;
    if (!tight) {
      // First pass: the natural widths of all children. The widest is the column's width.
      var widest = 0.0;
      for (var child = firstChild; child != null; child = childAfter(child)) {
        final size = measure(child, loose);
        sizes[child] = size;
        widest = math.max(widest, size.width);
      }
      width = constraints.constrainWidth(widest);
    }
    // All measurements BEFORE placement: the main-axis shifts need the free space, which depends
    // on the height the column ends up with.
    final measured = <RenderBox, Size>{};
    var content = 0.0;
    var realCount = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final stretched = child is _RenderColumnStretch;
      final Size size;
      if (stretched) {
        size = measure(child, BoxConstraints.tightFor(width: width));
      } else if (tight) {
        size = measure(child, BoxConstraints(maxWidth: width));
      } else {
        size = sizes[child]!;
      }
      measured[child] = size;
      final data = child.parentData! as _StretchParentData;
      // `pull` (schema 9.10.0): the child starts earlier by that much, and so does everything after it.
      content += size.height - data.pull;
      if (!data.isGap) realCount++;
    }
    // The column is never shorter than zero (`parentSize`): a lone pulled child does not give a
    // negative height.
    final result = constraints.constrain(Size(width, math.max(0.0, content)));
    // FREE SPACE (schema 9.15.0, `alignment.main`): the column's height minus the content with
    // gaps, and only when the column has a source of height. Less than zero means "none" (the
    // content is taller than the box: children stay at the top). Shifts are not rounded, and
    // `between` with one child is `start`.
    final free = _freeHeight && result.height.isFinite ? math.max(0.0, result.height - math.max(0.0, content)) : 0.0;
    final shifts = mainAxisShifts(free, realCount, _justify);
    var y = 0.0;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _StretchParentData;
      final size = measured[child]!;
      y -= data.pull;
      final shift = data.isGap ? 0.0 : shifts[index++];
      if (place != null) {
        final stretched = child is _RenderColumnStretch;
        place(child, Offset(stretched ? 0 : _naturalX(width - size.width), y + shift));
      }
      y += size.height;
    }
    return result;
  }

  /// The offset of a natural-width child by `align`; the measure is logical, so in right-to-left
  /// writing the start is the right edge.
  double _naturalX(double free) {
    final fromStart = switch (_align) {
      AlignToken.start => 0.0,
      AlignToken.center => 0.5,
      AlignToken.end => 1.0,
    };
    return free * (_textDirection == TextDirection.rtl ? 1 - fromStart : fromStart);
  }

  @override
  void performLayout() {
    size = _arrange(
      constraints,
      (child, childConstraints) {
        child.layout(childConstraints, parentUsesSize: true);
        return child.size;
      },
      (child, offset) => (child.parentData! as ContainerBoxParentData<RenderBox>).offset = offset,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, (child, childConstraints) => child.getDryLayout(childConstraints), null);

  @override
  double computeMinIntrinsicWidth(double height) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result = math.max(result, child.getMinIntrinsicWidth(height));
    }
    return result;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result = math.max(result, child.getMaxIntrinsicWidth(height));
    }
    return result;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result += child.getMinIntrinsicHeight(width);
    }
    return result;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result += child.getMaxIntrinsicHeight(width);
    }
    return result;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  /// A pulled first child lies ABOVE the column's start (in the parent's top padding), and
  /// `RenderBox.hitTest` rejects everything outside its own size. So a column with a pulled child
  /// asks its children itself: the overlap strip above the screen's app bar (`body.paintOrder`)
  /// must catch taps instead of passing them to the app bar under it.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_hasPull) return super.hitTest(result, position: position);
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  /// As in [_QuietRenderFlex]: content that sticks out past the edge (a box with a set height,
  /// `sizedBoxOverflow: 'clip'`) is clipped silently.
  @override
  void paint(PaintingContext context, Offset offset) {
    // An empty column with a pulled child (`pull` larger than the content) still paints it: it
    // sticks out rather than disappearing.
    final pulled = _hasPull;
    if (size.isEmpty && !pulled) return;
    var overflows = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final origin = (child.parentData! as _StretchParentData).offset;
      const slack = 0.01;
      // Along the pull axis an overhang is legal: the first child starts before the parent's
      // start (in its padding), and an earlier one lies below the parent's end when `pull` is
      // larger than the next one. Clipping that would remove the pulled content. Across the axis
      // the old rule applies.
      if (origin.dx < -slack ||
          (!pulled && origin.dy < -slack) ||
          origin.dx + child.size.width > size.width + slack ||
          (!pulled && origin.dy + child.size.height > size.height + slack)) {
        overflows = true;
        break;
      }
    }
    if (!overflows) {
      defaultPaint(context, offset);
      return;
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, defaultPaint);
  }
}
