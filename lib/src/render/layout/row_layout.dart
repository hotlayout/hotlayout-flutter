// The row layout of the contract: natural, weighted and tight children, with
// margins counted into the shares.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../model/tokens.dart';

/// How a row child takes its width when the document gave it no share.
enum RowChildWidth {
  /// Natural width: the content on one line, but no wider than the row. When the children do not
  /// fit together, it shrinks in proportion to its natural width.
  natural,

  /// Natural width that does not shrink: a widget as wide as its own content (a badge, an icon, a
  /// ring...). No wider than the row.
  rigid,

  /// The node itself named the width (`style.width`). It does not shrink and the row does not
  /// bound it: a row that cannot fit such children overflows.
  named,
}

/// A mark on a [RowLayout] child.
///
/// [share] is the share of the remainder (a weight from the document, or 1 for stretching
/// content); with it [width] is not consulted: the row gives the width, and gives it TIGHT.
class RowSlot extends ParentDataWidget<RowLayoutParentData> {
  const RowSlot({
    super.key,
    this.share,
    this.width = RowChildWidth.natural,
    this.pull = 0,
    required super.child,
  });

  final int? share;
  final RowChildWidth width;

  /// Pull toward the row start, in logical pixels (schema 9.10.0).
  final double pull;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as RowLayoutParentData;
    if (data.share == share && data.width == width && data.pull == pull) return;
    data
      ..share = share
      ..width = width
      ..pull = pull;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RowLayout;
}

class RowLayoutParentData extends ContainerBoxParentData<RenderBox> {
  int? share;
  RowChildWidth width = RowChildWidth.natural;

  /// How far the child is pulled toward the row start (`pull`, schema 9.10.0). A weight is
  /// stronger: a child with a share is never pulled (`pullWithWeight`).
  double pull = 0;
}

/// A ROW OF THE DOCUMENT'S CHILDREN: `Row` without `wrap` and `scrollable`, and
/// `Container{direction: row}`.
///
/// Not a `Row` with `Flexible` / `Expanded`, and the difference is not cosmetic. In a Flutter flex
/// a child is either inflexible (and then gets an axis WITHOUT BOUNDS, so a long label sticks out)
/// or flexible (and then space is divided among the flexible ones EQUALLY, however much each
/// needs). If every child without a weight were a `Flexible(loose)`, two of them would get at most
/// half the row each, and a chip with a date next to a short counter would wrap the date onto two
/// lines despite plenty of room. In the other readers (CSS flex) that does not happen: a child
/// without a weight takes its NATURAL width and shrinks only when the row really does not fit.
/// An overflow test cannot see the difference.
///
/// THE ORDER, the same as in the other readers:
///
///  1. a child with a NAMED width ([RowChildWidth.named]) takes it;
///  2. a NATURAL-width child is measured at the bound "the whole row". A widget as wide as its
///     content ([RowChildWidth.rigid]) stays that way;
///  3. the rest ([RowChildWidth.natural]), when together they lack room, SHRINK IN PROPORTION TO
///     THEIR NATURAL WIDTH. That is why they are measured twice: the first time the row learns how
///     much each needs, the second time it gives as much as there is. If they fit, the second
///     measurement is unnecessary;
///  4. the REMAINDER is divided among children with a share ([RowSlot.share]) with a tight width,
///     like `Expanded`; the share includes the node's `margin`, which lies inside. A child
///     without a share "divides nothing" (schema 8.17.0): it takes none of the remainder;
///  5. free space, if there are no shares, is distributed by [justify].
///
/// `IntrinsicWidth` does not work here: the subtree contains a `LayoutBuilder`, which computes no
/// intrinsics. So the natural width comes from a real layout.
///
/// WITHOUT A FINITE WIDTH (infinity from the parent) there is nothing to divide: each child is
/// measured on its own, shares do not apply and the row is as wide as its content; an `Expanded`
/// there would be a Flutter assertion failure. [hugsContent] says the same about a row given its
/// width ONLY AS A BOUND (`rowInUnboundedWidth`): it is as wide as its content, and `justify`
/// distributes nothing in it (`justifyInNaturalRow`).
class RowLayout extends MultiChildRenderObjectWidget {
  const RowLayout({
    super.key,
    required this.gap,
    required this.justify,
    required this.align,
    this.hugsContent = false,
    this.crossIsContent = false,
    super.children,
  });

  /// The gap between neighboring children.
  final double gap;
  final JustifyToken justify;

  /// The cross axis: where a child shorter than the row goes.
  final AlignToken align;

  /// The row is as wide as its content, not all the allotted space.
  final bool hugsContent;

  /// The cross space is the tallest child when the row's height is not given TIGHT (a container
  /// row, schema 9.15.0): `style.minHeight` raises the box but does not center the children in it.
  /// `Row` is unchanged.
  final bool crossIsContent;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderRowLayout(
    gap: gap,
    justify: justify,
    align: align,
    hugsContent: hugsContent,
    crossIsContent: crossIsContent,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, covariant RenderRowLayout renderObject) {
    renderObject
      ..gap = gap
      ..justify = justify
      ..align = align
      ..hugsContent = hugsContent
      ..crossIsContent = crossIsContent
      ..textDirection = Directionality.of(context);
  }
}

class RenderRowLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, RowLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, RowLayoutParentData> {
  RenderRowLayout({
    required double gap,
    required JustifyToken justify,
    required AlignToken align,
    required bool hugsContent,
    bool crossIsContent = false,
    required TextDirection textDirection,
  }) : _gap = gap,
       _justify = justify,
       _align = align,
       _hugsContent = hugsContent,
       _crossIsContent = crossIsContent,
       _textDirection = textDirection;

  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  JustifyToken _justify;
  set justify(JustifyToken value) {
    if (_justify == value) return;
    _justify = value;
    markNeedsLayout();
  }

  AlignToken _align;
  set align(AlignToken value) {
    if (_align == value) return;
    _align = value;
    markNeedsLayout();
  }

  bool _crossIsContent;
  set crossIsContent(bool value) {
    if (_crossIsContent == value) return;
    _crossIsContent = value;
    markNeedsLayout();
  }

  bool _hugsContent;
  set hugsContent(bool value) {
    if (_hugsContent == value) return;
    _hugsContent = value;
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
    if (child.parentData is! RowLayoutParentData) child.parentData = RowLayoutParentData();
  }

  /// Floating-point tolerance: a sum of widths that "did not fit" by a millionth of a pixel is no
  /// reason to shrink the children and measure them again.
  static const double _slack = 0.001;

  /// The single layout for the real and the dry pass, as in [RenderStretchColumn]: [measure]
  /// measures a child, [place] positions it.
  Size _arrange(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) measure,
    void Function(RenderBox child, Offset offset)? place,
  ) {
    final limit = constraints.maxWidth;
    final bounded = limit.isFinite;
    // The row does not impose a height on its children: the cross axis is `start` / `center` /
    // `end`, and the contract has no height stretching.
    BoxConstraints upTo(double width) => BoxConstraints(maxWidth: width, maxHeight: constraints.maxHeight);
    BoxConstraints exactly(double width) =>
        BoxConstraints(minWidth: width, maxWidth: width, maxHeight: constraints.maxHeight);

    final sizes = <RenderBox, Size>{};
    final shrinkable = <RenderBox>[];
    final sharing = <RenderBox>[];
    var count = 0;
    var fixedTotal = 0.0;
    var naturalTotal = 0.0;
    var shareTotal = 0;
    // The sum of the children's `pull` (schema 9.10.0). In a CSS flex a negative margin reduces
    // the node's outer size, so the row's free space grows by exactly that much and the content
    // gets shorter; it is the same here.
    var pullTotal = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      count++;
      final data = child.parentData! as RowLayoutParentData;
      final share = bounded ? data.share : null;
      pullTotal += data.pull;
      if (share != null) {
        sharing.add(child);
        shareTotal += share;
        continue;
      }
      if (!bounded || data.width != RowChildWidth.natural) {
        final size = measure(child, upTo(data.width == RowChildWidth.named ? double.infinity : limit));
        sizes[child] = size;
        fixedTotal += size.width;
      } else {
        final size = measure(child, upTo(limit));
        sizes[child] = size;
        shrinkable.add(child);
        naturalTotal += size.width;
      }
    }

    final gaps = _gap * math.max(0, count - 1);
    var used = fixedTotal + naturalTotal + gaps - pullTotal;
    if (bounded) {
      final room = math.max(0.0, limit - gaps - fixedTotal + pullTotal);
      if (naturalTotal > room + _slack) {
        final factor = room / naturalTotal;
        for (final child in shrinkable) {
          sizes[child] = measure(child, exactly(sizes[child]!.width * factor));
        }
        naturalTotal = room;
      }
      final pool = math.max(0.0, room - naturalTotal);
      for (final child in sharing) {
        final share = (child.parentData! as RowLayoutParentData).share!;
        sizes[child] = measure(child, exactly(pool * share / shareTotal));
      }
      used = fixedTotal + naturalTotal + gaps - pullTotal + (sharing.isEmpty ? 0 : pool);
    }
    // The row is never shorter than zero (`parentSize`).
    used = math.max(0.0, used);

    var height = 0.0;
    for (final size in sizes.values) {
      height = math.max(height, size.height);
    }
    final size = constraints.constrain(Size(_hugsContent || !bounded ? used : limit, height));
    if (place == null) return size;
    // The band in which a child is placed by `align`: the box when its height is given TIGHT,
    // otherwise the tallest child (`style.minHeight` gives no room).
    final band = _crossIsContent && !constraints.hasTightHeight ? height : size.height;

    // Free space. A negative value means the row overflows: children stay at the start and the
    // excess is clipped by [paint].
    final free = math.max(0.0, size.width - used);
    final (leading, between) = switch (_justify) {
      JustifyToken.start => (0.0, 0.0),
      JustifyToken.center => (free / 2, 0.0),
      JustifyToken.end => (free, 0.0),
      JustifyToken.between => (0.0, count > 1 ? free / (count - 1) : 0.0),
    };
    final cross = switch (_align) {
      AlignToken.start => 0.0,
      AlignToken.center => 0.5,
      AlignToken.end => 1.0,
    };
    // The measure is logical: in right-to-left writing the start is the right edge.
    final rtl = _textDirection == TextDirection.rtl;
    var x = leading;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final childSize = sizes[child]!;
      // `pull` (schema 9.10.0): the child starts earlier by that much, and so does everything after it.
      x -= (child.parentData! as RowLayoutParentData).pull;
      place(
        child,
        Offset(
          rtl ? size.width - x - childSize.width : x,
          (band - childSize.height) * cross,
        ),
      );
      x += childSize.width + _gap + between;
    }
    return size;
  }

  @override
  void performLayout() {
    size = _arrange(
      constraints,
      (child, childConstraints) {
        child.layout(childConstraints, parentUsesSize: true);
        return child.size;
      },
      (child, offset) => (child.parentData! as RowLayoutParentData).offset = offset,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, (child, childConstraints) => child.getDryLayout(childConstraints), null);

  double _sumOf(double Function(RenderBox child) measure) {
    var result = 0.0;
    var count = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result += measure(child);
      count++;
    }
    return result + _gap * math.max(0, count - 1);
  }

  double _highestOf(double Function(RenderBox child) measure) {
    var result = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      result = math.max(result, measure(child));
    }
    return result;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _sumOf((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => _sumOf((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _highestOf((child) => child.getMinIntrinsicHeight(double.infinity));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _highestOf((child) => child.getMaxIntrinsicHeight(double.infinity));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  /// As in [_QuietRenderFlex]: content that sticks out past the edge (named widths wider than the
  /// row; a box with a set height) is clipped silently: `sizedBoxOverflow: 'clip'`.
  @override
  void paint(PaintingContext context, Offset offset) {
    var pulled = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if ((child.parentData! as RowLayoutParentData).pull > 0) pulled = true;
    }
    if (size.isEmpty && !pulled) return;
    var overflows = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final origin = (child.parentData! as RowLayoutParentData).offset;
      const slack = 0.01;
      // Along the pull axis an overhang is legal (see `RenderStretchColumn.paint`).
      if ((!pulled && origin.dx < -slack) ||
          origin.dy < -slack ||
          (!pulled && origin.dx + child.size.width > size.width + slack) ||
          origin.dy + child.size.height > size.height + slack) {
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
