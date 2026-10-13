/// The grid: a named number of children per row.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import 'node_box.dart';

extension GridWidgets on NodeRenderer {
  /// The grid: equal columns, their number named by the document.
  ///
  /// WHY NOT `GridView`. `GridView` requires ONE aspect ratio for all cells
  /// (`childAspectRatio`), while the contract says nothing about cell height: a cell may hold a
  /// one-line badge and another a four-line card. We would have to invent a number, that is, a
  /// layout the document does not have.
  ///
  /// So the grid is a column of rows with `Expanded` cells. The cell width is exactly what the
  /// other readers compute, `(width - gaps) / columns`, so readers agree on the number, not by
  /// eye.
  ///
  /// EMPTY CELLS IN THE LAST ROW ARE REQUIRED. Without them a row of two cells in a four-column
  /// grid would stretch each over half the screen, and the bottom row would not line up under
  /// the top one. That is not cosmetic: without them the grid stops being a grid.
  ///
  /// TOP ALIGNMENT, not `stretch`: a `Row` learns its height only after measuring its children,
  /// so in a layout unbounded in height there is nothing to stretch them to. Other readers do
  /// the same (`align-items: start`); otherwise they would show equal-height cards that a
  /// phone will not.
  Widget buildGrid(GridNode node) {
    final nodes = visibleNodes(node.children);
    if (nodes.isEmpty) return const SizedBox.shrink();

    return gridOf(
      // A grid cell has a DEFINITE width, so inside it a node behaves as in a column: hence
      // `flow: Axis.vertical`, which gives text alignment in the cell something to measure from.
      [for (final child in nodes) inTightSlot(child, flow: Axis.vertical, tight: true)],
      columns: node.columns,
      gap: theme.fieldSpacing(node.gap),
    );
  }

  /// A child in a slot that SETS its size itself (a `Grid` cell, an instance of a `Repeater`
  /// with `columns`): `naturalWidthInTightSlot: 'natural-start-top'`,
  /// `x-style.layout.tightSlotNaturalWidth: 'column.naturalWidth'`.
  ///
  /// A widget on the natural-width list ([hasNaturalColumnWidth]) without an EFFECTIVE own width
  /// takes its natural width (no wider than the cell) and sits at the logical start, at the top:
  /// `Align` under a tight `Expanded` loosens the constraints. Without it a badge pill would
  /// stretch across the whole cell, although in other readers it is as wide as its content. A
  /// node with its own size (`sizedChildInTightSlot`) and all other types stay as they are.
  /// With [tight] false (instances in a column) the slot is not tight and nothing changes.
  Widget inTightSlot(ChildNode node, {required Axis flow, required bool tight}) {
    final rendered = renderNode(node, flow: flow);
    if (!tight || !hasNaturalColumnWidth(node)) return rendered;
    final own = resolveNodeStyle(node.style, node.styleWhen, data, applicable: theme.applicableStyle);
    if (dimension(own?.width) != null) return rendered;
    return Align(alignment: AlignmentDirectional.topStart, child: rendered);
  }

  /// The grid layout over already built cells.
  ///
  /// Shared since schema 8.13.0: both `Grid` (cells are nodes of the DOCUMENT) and
  /// `Repeater.columns` (cells are instances of one template) ask for a grid. The layout is the
  /// same, and a second copy would drift from the first on the first edit.
  Widget gridOf(
    List<Widget> cells, {
    required int columns,
    required double gap,
  }) {
    final rows = <Widget>[];
    for (var start = 0; start < cells.length; start += columns) {
      final end = math.min(start + columns, cells.length);
      final row = <Widget>[];
      for (var index = start; index < end; index += 1) {
        if (index > start && gap > 0) row.add(SizedBox(width: gap));
        row.add(Expanded(child: cells[index]));
      }
      // Pad the row with empty cells; see the comment on [buildGrid].
      for (var index = end; index < start + columns; index += 1) {
        if (gap > 0) row.add(SizedBox(width: gap));
        row.add(const Expanded(child: SizedBox.shrink()));
      }
      if (rows.isNotEmpty && gap > 0) rows.add(SizedBox(height: gap));
      rows.add(QuietRow(crossAxisAlignment: CrossAxisAlignment.start, children: row));
    }

    return QuietColumn(mainAxisSize: MainAxisSize.min, children: rows);
  }
}
