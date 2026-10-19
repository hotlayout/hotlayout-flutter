/// A list from data: one template drawn once per record of a collection.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/list_marker.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/repeater_group.dart';
import '../../model/tokens.dart';
import '../layout/quiet_flex.dart';
import '../list_budget.dart';
import '../node_renderer.dart';
import 'carousel.dart';
import 'grid.dart';
import 'render_tokens.dart';

extension RepeaterWidgets on NodeRenderer {
  /// A list from data: a template drawn once per record.
  ///
  /// AN EMPTY LIST GIVES AN EMPTY SPACE, NOT A PLACEHOLDER. The reader does not invent a "no
  /// data" message: what to show instead of the list is decided by the document, with a
  /// neighboring node that has a visibility condition. Otherwise every app would get our phrase
  /// in the middle of its screen.
  ///
  /// THE COUNT LIMIT COMES FROM THE CONTRACT, not from the reader. If each platform chose its
  /// own, the same document would show a different number of rows.
  Widget buildRepeater(RepeaterNode node, NodeStyle? own) {
    // The filter first, then the limit (schema 9.23.0): the records that did not pass do not exist for the layout, so
    // the grid has no holes, the carousel counts its stops by the drawn cards and the numbers follow the drawn rows.
    final records = listRecordsOf(node, data);
    // The budget of the screen (`x-listBudget`) cuts what this list may draw of its records; a renderer without a
    // plan draws them all.
    final count = math.min(records.length, budget?.allowed(node.id, instance) ?? records.length);
    if (count == 0 || node.children.isEmpty) return const SizedBox.shrink();

    final template = node.children.first;
    final columns = node.columns;
    final gap = theme.fieldSpacing(node.gap);

    /*
     * A TEMPLATE THAT IS A LIST ITEM (schema 9.17.0, `listMarker.number.repeaterTemplate`): a
     * numbered item that is the template of a list from data has its drawn INSTANCES as its
     * group. The number is how many instances in which the template is visible have been drawn
     * up to and including this one; the column width follows the number of drawn records.
     * Otherwise every row would be "1.".
     */
    final numberedTemplate = template is TextNode && template.marker == TextMarker.number;
    // A template under a condition (`visibleIf` on the repeater's child) is evaluated PER
    // RECORD: an instance where it is hidden is not drawn and takes no space, but it still
    // counts as a record in the numbering group (the column width follows the number of drawn
    // records).
    final templateVisible = [
      for (var index = 0; index < count; index += 1)
        !template.hasVisibilityRule || template.isVisible(data.withItem(node.item, records[index])),
    ];
    final shownIndexes = [
      for (var index = 0; index < count; index += 1)
        if (templateVisible[index]) index,
    ];
    final instanceNumbers = numberedTemplate ? listInstanceNumbers(templateVisible) : const <int?>[];
    NodeRenderer itemRenderer(int index) {
      final renderer = withListItem(node.source, node.item, records[index], index);
      final number = numberedTemplate ? instanceNumbers[index] : null;
      return number == null
          ? renderer
          : renderer.copy(listInstance: (template: template, number: number, groupSize: count.toInt()));
    }

    /*
     * THE CAROUSEL (schema 9.11.0): a list with a `carousel` field scrolls ON ITS OWN. It is the
     * only place where the field turns scrolling on; without the field a list laid out as a row
     * stays as it was. Cards are instances of the template, one per record, each with its own
     * record scope.
     */
    final carousel = node.carousel;
    if (carousel != null) {
      return buildCarousel(
        carousel,
        own,
        gap: gap,
        align: AlignToken.center,
        nodeId: node.id,
        items: [
          for (final index in shownIndexes) (itemRenderer(index), template),
        ],
      );
    }
    /*
     * GROUPS (schema 9.26.0, `x-repeaterGroup`): records that follow one another with the same value under `groupBy`
     * are one group, and the second child of the list, the header, is drawn before each group in the scope of its
     * FIRST record. The groups are made of the records the list draws (after the filter and the limit), in the order
     * of the data. A header hidden by its own condition takes no place, and its gap with it. The header is not a
     * list item: it has no number, and numbered items count records only.
     */
    final header = node.groupHeader;
    final groupBy = node.groupBy;
    final starts = header == null || groupBy == null
        ? const <int>{}
        : groupStartsOf([
            for (var index = 0; index < count; index += 1) data.withItem(node.item, records[index]).record?[groupBy],
          ]);
    Widget? headerAt(int index) {
      if (header == null || !starts.contains(index)) return null;
      final scoped = withListItem(node.source, node.item, records[index], index);
      if (header.hasVisibilityRule && !header.isVisible(scoped.data)) return null;
      return scoped.inTightSlot(header, flow: Axis.vertical, tight: false);
    }

    final items = <Widget>[
      for (var index = 0; index < count; index += 1) ...[
        ?headerAt(index),
        if (templateVisible[index])
          itemRenderer(index).inTightSlot(
            template,
            // In a grid the cell has a definite width, so the node inside behaves as in a
            // column, the same as in `Grid`.
            flow: columns == null ? flowOf(node.direction) : Axis.vertical,
            tight: columns != null,
          ),
      ],
    ];

    /*
     * A grid of instances (schema 8.13.0). It goes through THE SAME code as `Grid`: the cell
     * width, the empty cells in the last row and the top alignment are all properties of the
     * LAYOUT, not of where the cells came from.
     *
     * `direction` is not read at all here: a carousel and a grid are two statements about the
     * same axis, and the builder rejects a document with both.
     */
    if (columns != null) {
      return gridOf(items, columns: columns, gap: gap);
    }

    return node.direction == ContainerDirectionToken.row
        ? QuietRow(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: spacedItems(items, gap, Axis.horizontal),
          )
        : QuietColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spacedItems(items, gap, Axis.vertical),
          );
  }
}
