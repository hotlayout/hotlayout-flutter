/// The row: flexible, wrapping and scrolling, and how a child takes its width.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/tokens.dart';
import '../layout/quiet_flex.dart';
import '../layout/row_layout.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import 'carousel.dart';
import 'column.dart';
import 'node_box.dart';
import 'render_tokens.dart';

extension RowWidgets on NodeRenderer {
  Widget buildRow(RowNode node, NodeStyle? own, {bool naturalRow = false}) {
    final gap = theme.fieldSpacing(node.gap);
    /*
     * Sideways scroll (schema 8.11.0): wrapping then does NOT APPLY.
     *
     * The pair `scrollable + wrap` is contradictory and the builder's validator rejects such a
     * document. But a document may come from elsewhere, and here the pair does not just "look
     * odd": a `Wrap` inside a scroll view asks where to wrap at infinite width, and Flutter
     * crashes. So SCROLLING takes priority over wrapping: the user sees a long row they can swipe
     * instead of a red screen.
     */
    if (node.scrollable) {
      final carousel = node.carousel;
      if (carousel != null) {
        return buildCarousel(
          carousel,
          own,
          gap: gap,
          align: node.align,
          nodeId: node.id,
          items: [for (final child in visibleNodes(node.children)) (this, child)],
        );
      }
      /*
       * `LayoutBuilder` exists only for the row's own width: it becomes the WIDEST width of each
       * child (see `_scrollRow`).
       *
       * The row's padding lies INSIDE the scroll view (which is why `styledNode` does not put it
       * on the box): content must scroll under the row's edge, not under the padding.
       */
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: theme.resolveBoxSpacing(own?.padding),
          // `_flexRow` with `Flexible` does not work inside a scroll view: there is nothing to
          // stretch into. So children take their natural width and the row shrinks to their sum.
          //
          // Width shares (schema 8.17.0) are IGNORED here, which is why the contract rejects them
          // in a scrolling row: infinity cannot be divided, and `Expanded` inside it is a crash,
          // not just an ugly look. A document with such a pair may not come from the builder, so
          // the reader survives it silently, just like the `scrollable + wrap` pair above.
          child: _scrollRow(node, gap, viewport: constraints.maxWidth),
        ),
      );
    }
    return node.wrap ? _wrapRow(node, gap) : _flexRow(node, gap, naturalRow: naturalRow);
  }

  /// The content of a scrolling row.
  ///
  /// A CHILD'S WIDTH IS BOUNDED BY THE ROW'S OWN WIDTH ([viewport]), and this is not decoration.
  /// A scroll view gives children an INFINITE width, and half of the contract's widgets do not
  /// just "look odd" on it but crash: a full-width button, a horizontal divider, a progress bar,
  /// an image with an aspect ratio, a grid, a list row all ask "how much room is there". The
  /// answer "as much as the row itself" is the one CSS gives (`width: 100%` in a scrolling
  /// container is the container's width), so a carousel of full-width cards works without a
  /// single number in the document.
  ///
  /// A child that NAMES its own width (`style.width`, `minWidth`) may be wider than the row: a
  /// panorama scrolled sideways. So its bound is the larger of the two.
  Widget _scrollRow(RowNode node, double gap, {required double viewport}) {
    final nodes = visibleNodes(node.children);
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0 && gap > 0) children.add(SizedBox(width: gap));
      children.add(scrollChild(nodes[i], viewport));
    }
    return QuietRow(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis(node.align),
      children: children,
    );
  }

  /// A child of a scrolling row with its width bound (see [_scrollRow]).
  Widget scrollChild(ChildNode node, double viewport) {
    // A row child in a scroll view has no width (`rowInUnboundedWidth`): weights do not apply in
    // it, even though the `ConstrainedBox` below gives it an upper bound.
    final child = renderNode(node, flow: Axis.horizontal, naturalRow: true);
    // A row that itself sits in infinite width cannot give a bound, so children stay as they
    // are.
    if (!viewport.isFinite) return child;
    // THE CHILD'S WIDEST WIDTH is `max(viewport, own width)` (`scrollableRow.childMaxWidth`).
    final widest = math.max(viewport, declaredWidth(node));
    /*
     * Stretching content (exactly the five `stretchToViewport` conditions) takes this width
     * WHOLE: it has no natural width. Everything else takes its natural width, but no wider than
     * the bound. A node with an OWN width is by construction not on the list: its width is already
     * named.
     */
    return stretchesToRowViewport(node) && !namesOwnWidth(node)
        ? SizedBox(width: widest, child: child)
        : ConstrainedBox(constraints: BoxConstraints(maxWidth: widest), child: child);
  }

  /// The card's side margin: its `margin` lies ON TOP of the box width.
  double marginInline(ChildNode node) {
    final own = resolveNodeStyle(node.style, node.styleWhen, data, applicable: theme.applicableStyle);
    return theme.resolveBoxSpacing(own?.margin)?.horizontal ?? 0;
  }

  Widget _wrapRow(RowNode node, double gap) => Wrap(
    spacing: gap,
    runSpacing: gap,
    alignment: wrapAlign(node.justify),
    crossAxisAlignment: wrapCross(node.align),
    // Inside a `Wrap` a child gets its natural width, so there are neither shares nor manual
    // gaps here.
    //
    // A ROW child (a chip made of two captions) too: `Wrap` gives it the width only as an upper
    // bound, and a row not given a tight width is as wide as its content (see [flexibleRow]).
    // Otherwise a pill like "Member since" would become a bar across the whole card.
    children: [
      for (final child in visibleNodes(node.children)) renderNode(child, flow: Axis.horizontal),
    ],
  );

  Widget _flexRow(RowNode node, double gap, {bool naturalRow = false}) => flexibleRow(
    visibleNodes(node.children),
    pullParent: node,
    naturalRow: naturalRow,
    gap: gap,
    justify: node.justify,
    align: node.align,
  );

  /// A row without wrapping and without scrolling, shared by `Row` and
  /// `Container{direction: row}`.
  ///
  /// [RowLayout] computes the children's widths; what is decided here is only what it cannot
  /// know: WHETHER SHARES APPLY. `rowInUnboundedWidth: 'natural-width-ignore-weights'`: shares
  /// apply only in a row that was GIVEN a width. It is not given in three cases, and in all of
  /// them the row is as wide as its content, while a child with a weight is measured as if it had
  /// none and keeps its own `style.width`:
  ///
  ///  * there is no bound at all (infinity from the parent);
  ///  * the contract says to treat it as not given ([naturalRow]: a row child without a weight, a
  ///    stack layer, a child of a scrolling row);
  ///  * the width arrived only as an UPPER BOUND, not tight. This is how a wrapping row (`Wrap`)
  ///    gives width, and how a column without its own width asks for the natural width
  ///    ([StretchColumn], the first measurement, `childWidthWithoutDefiniteParent:
  ///    'widest-natural'`): a row that answered "all the room" would inflate the column to the
  ///    whole screen. The "of 5" label in a ring's center would then sit at the screen's left
  ///    edge instead of under the number. In its second measurement the column gives the row a
  ///    tight "widest child" width, and then shares apply.
  ///
  /// `LayoutBuilder` exists just for this question: the child's SLOT depends on the answer
  /// (`Slot.weighted` removes the box's own width), and the slot is decided at build time, not
  /// at layout time.
  Widget flexibleRow(
    List<ChildNode> nodes, {
    required UiNode pullParent,
    bool naturalRow = false,
    required double gap,
    JustifyToken justify = JustifyToken.start,
    required AlignToken align,
    bool crossIsContent = false,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final bounded = constraints.hasBoundedWidth;
      final weightsAct = constraints.hasTightWidth && bounded && !naturalRow;
      return RowLayout(
        gap: gap,
        justify: justify,
        align: align,
        crossIsContent: crossIsContent,
        // Natural width is the sum of the children's widths, not all the allotted space.
        hugsContent: !weightsAct,
        children: [
          for (final node in nodes) _rowChild(node, weightsAct: weightsAct, pull: pullOf(node, pullParent)),
        ],
      );
    },
  );

  /// A row child: HOW it shares width with its neighbors. [RowLayout] does the arithmetic; here a
  /// document node becomes one of its four kinds.
  ///
  ///  * SHARE: the document named a `weight` (schema 8.17.0) and shares apply ([weightsAct]). The
  ///    child gets a TIGHT width, exactly its share of the remainder, regardless of content; this
  ///    is why a weight beats the node's own width (`x-style.weightOverridesWidth`): the slot
  ///    tells the box that the parent has already set the width. The share includes the node's
  ///    `margin`, which lies inside it;
  ///  * NAMED WIDTH: the node itself says `style.width`. Neighbors do not change it, and a row
  ///    that cannot fit such children overflows instead of shrinking them;
  ///  * NATURAL, NON-SHRINKING: widgets on the `x-style.layout.column.naturalWidth` list
  ///    ([hasNaturalColumnWidth]): a badge, a non-full-width button, an icon, a ring, a vertical
  ///    line and a spacer. Their width is the content width and there is nothing to divide;
  ///  * STRETCHING WITHOUT A WEIGHT: the five `stretchToViewport` conditions
  ///    ([stretchesToRowViewport]). They have no natural width, so in a row that divides its width
  ///    ([weightsAct]) they take the remainder as a share of weight 1 (`unweightedStretchInRow:
  ///    'share-of-one'`). They cannot be measured "naturally": a progress bar answers "how much do
  ///    you need" with "everything", and the neighboring label would be squeezed into wrapping. In
  ///    a NATURAL-width row (width given only as a bound) the share, like the weight, does not
  ///    apply: the node takes its content width. That is its caption plus padding for a button,
  ///    its label for a bar with a label, and zero for a bar without a label, a horizontal line
  ///    or a spacer;
  ///  * everything else has a NATURAL width, which shrinks proportionally when the row does not
  ///    fit.
  ///
  /// A child without a weight is also a natural-width row when it is itself a row
  /// (`rowInUnboundedWidth`): a chip like "Member since" would otherwise take everything left, and
  /// the parent's `justify: between` would have nothing to distribute.
  ///
  /// [weightsAct]: the row received a TIGHT finite width and is not natural. Without it there is
  /// nothing to divide: each child is measured on its own.
  Widget _rowChild(ChildNode node, {required bool weightsAct, double pull = 0}) {
    final weight = weightsAct ? node.weight : null;
    if (weight != null) {
      return RowSlot(
        share: weight,
        child: renderNode(node, flow: Axis.horizontal, slot: Slot.weighted),
      );
    }
    final child = renderNode(node, flow: Axis.horizontal, naturalRow: true);
    if (namesOwnWidth(node)) return RowSlot(width: RowChildWidth.named, pull: pull, child: child);
    if (hasNaturalColumnWidth(node)) return RowSlot(width: RowChildWidth.rigid, pull: pull, child: child);
    if (stretchesToRowViewport(node)) {
      if (weightsAct) return RowSlot(share: 1, pull: pull, child: child);
      // A natural-width row: the share does not apply and the node is measured by its CONTENT
      // (`unweightedStretchInRow`): a button its caption plus padding, a bar its label, a bar
      // without a label, a line and a spacer zero. They cannot be asked "how much do you need"
      // directly: they would answer "everything". `Grid` has a `LayoutBuilder` (it computes no
      // intrinsics) and stays as it is.
      if (node is! GridNode) return RowSlot(pull: pull, child: IntrinsicWidth(child: child));
    }
    return RowSlot(pull: pull, child: child);
  }
}
