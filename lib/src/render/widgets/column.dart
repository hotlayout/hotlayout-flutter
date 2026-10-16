/// Column-like parents: column, container, accordion and the shared column of
/// children.
library;

import 'package:flutter/material.dart';

import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/tokens.dart';
import '../accordion_block.dart';
import '../layout/stretch_column.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import 'node_box.dart';
import 'row.dart';

extension ColumnWidgets on NodeRenderer {
  Widget buildColumn(ColumnNode node, NodeStyle? own, Slot slot) => buildChildColumn(
    node.children,
    gap: theme.fieldSpacing(node.gap),
    align: node.align,
    justify: node.justify,
    freeHeight: _hasColumnHeight(own, slot),
    pullParent: node,
  );

  /// Whether the column HAS A SOURCE OF HEIGHT larger than its content (schema 9.15.0,
  /// `alignment.main.column.heightSources`): a full-stack layer, an effective `style.height` or
  /// `style.minHeight`. Nothing else: a grid cell, a row, a tab and a repeater give no height,
  /// and a column must not be stretched "to make `justify` work". Mirrors
  /// `columnHeightSourceOf` (`layout_rules.dart`); the parent is not known here, but only a
  /// stack sets `Slot.fill` (`effectiveFill`).
  bool _hasColumnHeight(NodeStyle? own, Slot slot) =>
      slot == Slot.fill || dimension(own?.height) != null || dimension(own?.minHeight) != null;

  /// A card. Since schema 8.1.0 it says how it lays out its content (`direction`).
  ///
  /// The default `column` is what a container has always done, so a document without the field
  /// is drawn exactly as before 8.1.0.
  ///
  /// **The axis is KNOWN, not assumed.** The document dictates it and it reaches the children:
  /// text alignment depends on it, and the builder uses it to compute the correct divider axis
  /// (`axis_mismatch`). The reader still draws a divider LITERALLY by its own `orientation`:
  /// guessing would mean drawing something other than what the document says.
  ///
  /// Since schema 9.0.0 a container has no look of its own: padding, radius, background, shadow,
  /// border and height live in the shared `style`, and `nodeBox` draws them as for any other
  /// node. A container without a style is just a column or a row; the document makes a "card"
  /// out of it.
  Widget buildContainer(ContainerNode node, NodeStyle? own, Slot slot, {bool naturalRow = false}) =>
      switch (node.direction) {
        ContainerDirectionToken.column => buildChildColumn(
          node.children,
          gap: theme.fieldSpacing(node.gap),
          align: node.align,
          justify: node.justify,
          freeHeight: _hasColumnHeight(own, slot),
          pullParent: node,
        ),
        ContainerDirectionToken.row => _containerRow(node, naturalRow: naturalRow),
      };

  /// A container row.
  ///
  /// Unlike `Row`, it has no `wrap` of its own; `align` and `justify` follow the container
  /// contract (the cross axis is vertical).
  ///
  /// The children's width is computed by the same code as in `Row`, and this is not just saving
  /// lines: a container row accepts weights by the same contract rule (`acceptsWeightedChildren`),
  /// since it has no `wrap` or `scrollable`, so its width is always finite. Two separate pieces
  /// of code would drift apart on the first change of the rule.
  Widget _containerRow(ContainerNode node, {bool naturalRow = false}) => flexibleRow(
    visibleNodes(node.children),
    pullParent: node,
    naturalRow: naturalRow,
    gap: theme.fieldSpacing(node.gap),
    justify: node.justify,
    align: node.align,
    // The row's cross space is the height of the CONTENT box when one is named (`style.height`,
    // a `fill` layer: a tight constraint), otherwise the tallest child: `style.minHeight` gives
    // no space (`alignment.cross.inline.boxHeight`).
    crossIsContent: true,
  );

  Widget buildAccordion(AccordionNode node) => AccordionBlock(
    title: text(node.title),
    titleStyle: theme
        .text(TypographyToken.titleS)
        .copyWith(color: partColor(ColorToken.onSurface)),
    iconColor: partColor(ColorToken.muted, secondary: true),
    initiallyExpanded: node.initiallyExpanded,
    chevronSize: theme.iconSize(IconSizeToken.md),
    gap: theme.space(SpacingToken.sm),
    body: buildChildColumn(node.children, gap: theme.space(SpacingToken.sm), align: AlignToken.start),
  );

  /// A column of children, shared by `Screen`, `Column`, `Container{column}`, `Tab`, `Accordion`,
  /// `ChoiceGroup` and an unknown node: exactly `x-style.layout.column.parents`.
  ///
  /// CHILD WIDTH (`columnChildWidth: 'stretch-unless-natural'`): tight, equal to the parent's
  /// content width minus the node's own `margin` (the margins lie INSIDE the tight width, so they
  /// are subtracted automatically). Only a node with its own `style.width` (`ownWidth`) and the
  /// widgets on the [hasNaturalColumnWidth] list keep their natural width and are placed by
  /// [align]: the column leaves them free width and positions them by `crossAxisAlignment`. The
  /// list lives here, in the column itself, not inside the widgets, as in the artifact.
  ///
  /// Stretching is done by [StretchColumn], not `CrossAxisAlignment.stretch`: on an INFINITE
  /// width (a column in a row whose neighbor has a weight) the latter is an assertion failure,
  /// not just an ugly look. Without a bound the children keep their natural width.
  ///
  /// [pullParent] is the node whose children may be pulled (`pull`, schema 9.10.0): `Screen`,
  /// `Column` and a column `Container` pass it. Other parents (tab, accordion, choice group) do
  /// not accept pulling, and the field is not read on their children. [firstPullRead] `false`: the `pull` of the
  /// first node is not read (the top zone of a screen, 9.24.0).
  Widget buildChildColumn(
    List<ChildNode> source, {
    required double gap,
    required AlignToken align,
    JustifyToken justify = JustifyToken.start,
    bool freeHeight = false,
    UiNode? pullParent,
    bool firstPullRead = true,
  }) {
    final nodes = visibleNodes(source);
    final children = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0 && gap > 0) children.add(FlowGap(child: SizedBox(height: gap)));
      final node = nodes[i];
      final child = _staysNaturalInColumn(node)
          ? renderNode(node, flow: Axis.vertical)
          : ColumnStretch(child: renderNode(node, flow: Axis.vertical, stretchAlign: align));
      final pull = i == 0 && !firstPullRead ? 0.0 : pullOf(node, pullParent);
      children.add(pull > 0 ? FlowPull(pull: pull, child: child) : child);
    }
    return StretchColumn(align: align, justify: justify, freeHeight: freeHeight, children: children);
  }

  /// By how many logical pixels a node is pulled in its parent's flow (`pull`, schema 9.10.0):
  /// 0 when the field does not apply (out of flow, a weight, unreadable) or the token is unknown
  /// to the theme (`tokenWithoutFieldDefault: 'omit-field'`).
  double pullOf(ChildNode node, UiNode? parent) {
    final ref = effectivePull(node, parent);
    return ref == null ? 0 : (theme.resolveSpacing(ref) ?? 0);
  }

  /// Does a column child keep its natural width (`ownWidth` or `naturalWidth`)?
  ///
  /// The own width is the EFFECTIVE `style.width` after the state and after validating a value
  /// from data: an out-of-range width without a fallback counts as absent ([dimension]). An
  /// unknown node ignores style entirely.
  bool _staysNaturalInColumn(ChildNode node) {
    if (hasNaturalColumnWidth(node)) return true;
    if (node is UnknownNode) return false;
    final own = resolveNodeStyle(node.style, node.styleWhen, data, applicable: theme.applicableStyle);
    return dimension(own?.width) != null;
  }
}
