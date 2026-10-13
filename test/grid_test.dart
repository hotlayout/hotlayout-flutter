import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';

import 'support/fixtures.dart';

/// The grid (8.5.0) is the first contract container that says HOW MANY children go
/// in a row.
///
/// Until then two-dimensional layout was expressed only by `Row{wrap}`, which is the opposite
/// statement: wrapping says "as many as fit" and depends on natural
/// widths, i.e. on the font and text. The grid names a number - which is why it
/// can be checked by equality rather than inequality.
void main() {
  Map<String, Object?> grid(
    List<Map<String, Object?>> children, {
    Object? columns = 2,
    String gap = 'none',
    String? padding,
  }) => {
    'id': 'grid',
    'type': 'Grid',
    'props': {'columns': columns, 'gap': gap},
    // 9.0.0: the grid fields live in `style`, as on any node.
    if (padding != null) 'style': {'padding': padding},
    'children': children,
  };

  List<Map<String, Object?>> cells(int count) => [
    for (var index = 0; index < count; index += 1)
      textNode('К$index', id: 'cell-$index'),
  ];

  Rect rectOf(WidgetTester tester, String text) => tester.getRect(find.text(text));

  group('model', () {
    GridNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([node])).whereType<GridNode>().single;

    test('the column count comes from the document', () {
      expect(parse(grid(cells(3), columns: 3)).columns, 3);
    });

    test('a number outside the contract bounds is clamped, not rejected', () {
      // A document with nine columns DESCRIBES a grid, and painting it with the
      // maximum is closer to the intent than painting a single column.
      expect(parse(grid(cells(3), columns: 9)).columns, kGridMaxColumns);
      expect(parse(grid(cells(3), columns: 1)).columns, kGridMinColumns);
    });

    test('a non-numeric value is bad data, and the schema default is used', () {
      expect(parse(grid(cells(3), columns: 'три')).columns, kGridDefaultColumns);
      expect(parse(grid(cells(3), columns: null)).columns, kGridDefaultColumns);
    });
  });

  group('layout', () {
    testWidgets('two columns: the cells share the width equally', (tester) async {
      await pumpDocument(tester, docWith([grid(cells(2))]));

      final first = rectOf(tester, 'К0');
      final second = rectOf(tester, 'К1');

      expect(first.top, second.top);
      expect(first.width, second.width);
      // The second starts exactly where the first ends: there is no gap.
      expect(second.left, closeTo(first.right, 0.01));
    });

    testWidgets('the fourth child goes to the second row instead of squeezing the first', (tester) async {
      await pumpDocument(tester, docWith([grid(cells(4))]));

      final topLeft = rectOf(tester, 'К0');
      final topRight = rectOf(tester, 'К1');
      final bottomLeft = rectOf(tester, 'К2');

      expect(topRight.top, topLeft.top);
      expect(bottomLeft.top, greaterThan(topLeft.top));
      // The cell width does not depend on the number of ROWS.
      expect(bottomLeft.width, closeTo(topLeft.width, 0.01));
      // Cells of one column stand one under another.
      expect(bottomLeft.left, closeTo(topLeft.left, 0.01));
    });

    /*
     * The main trap of the grid, and it costs exactly here: without empty cells
     * `Expanded` would hand the last incomplete row's children the WHOLE width, and
     * the bottom cell would turn out twice as wide as the top one - the grid
     * would stop being a grid exactly on the last row.
     */
    testWidgets('an incomplete last row does not stretch its cells', (tester) async {
      await pumpDocument(tester, docWith([grid(cells(3))]));

      expect(rectOf(tester, 'К2').width, closeTo(rectOf(tester, 'К0').width, 0.01));
      expect(rectOf(tester, 'К2').left, closeTo(rectOf(tester, 'К0').left, 0.01));
    });

    testWidgets('one gap for both axes, as the contract says', (tester) async {
      await pumpDocument(tester, docWith([grid(cells(4), gap: 'md')]));

      final topLeft = rectOf(tester, 'К0');
      final topRight = rectOf(tester, 'К1');
      final bottomLeft = rectOf(tester, 'К2');

      final columnGap = topRight.left - topLeft.right;
      final rowGap = bottomLeft.top - topLeft.bottom;

      expect(columnGap, greaterThan(0));
      expect(rowGap, closeTo(columnGap, 0.01));
    });

    testWidgets('a hidden child takes no cell', (tester) async {
      // A condition the data does not satisfy: the node is not built at all,
      // so the row is filled by the NEXT child instead of leaving a hole.
      final hidden = textNode(
        'К1',
        id: 'cell-1',
        visibleIf: {'path': 'task.completed', 'op': 'isTrue'},
      );
      await pumpDocument(
        tester,
        docWith([
          grid([textNode('К0', id: 'cell-0'), hidden, textNode('К2', id: 'cell-2')]),
        ]),
        data: const {'task': {'completed': false}},
      );

      expect(find.text('К1'), findsNothing);
      // The third child became the second cell of the FIRST row.
      expect(rectOf(tester, 'К2').top, rectOf(tester, 'К0').top);
    });

    testWidgets('an empty grid draws nothing and does not break the screen', (tester) async {
      await pumpDocument(tester, docWith([grid(const [])]));

      expect(tester.takeException(), isNull);
      expect(find.bySubtype<Row>(), findsNothing);
    });
  });
}
