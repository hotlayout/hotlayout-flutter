import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// A stack as a row child (reader 0.7.0 clarification).
///
/// Defect: `_overlay` wrapped the stack in `SizedBox(width: double.infinity)`, so a
/// stack in a row took the whole row, the card grew, and the neighbouring column
/// vanished. The contract rule is different: a stack is sized by its non-stretched
/// layers; infinite width comes only from a stretching parent (column, row share,
/// grid cell). In a column the stack stays full width.
void main() {
  Map<String, Object?> box(String id, double side) => {
    'id': id,
    'type': 'Container',
    'props': {'gap': 'none'},
    'style': {'width': side, 'height': side},
    'children': [textNode('шар $id', id: '$id-t')],
  };

  Map<String, Object?> stack(String id, double side) => {
    'id': id,
    'type': 'Stack',
    'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
    'children': [box('$id-b', side)],
  };

  Map<String, Object?> row(List<Map<String, Object?>> children, {String gap = 'none'}) => {
    'id': 'row',
    'type': 'Row',
    'props': {'gap': gap, 'align': 'start', 'justify': 'start', 'wrap': false},
    'children': children,
  };

  Rect stackRect(WidgetTester tester, String id) => tester.getRect(
    find.ancestor(of: find.text('шар $id-b'), matching: find.byType(Stack)).first,
  );

  testWidgets('a stack in a row is as wide as its widest non-stretched layer', (tester) async {
    await pumpDocument(tester, docWith([row([stack('s', 144)])]));

    final rect = stackRect(tester, 's');
    expect(rect.width, closeTo(144, 0.01));
    expect(rect.height, closeTo(144, 0.01));
  });

  testWidgets('a neighbouring column with a weight gets the rest of the row width', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDocument(
      tester,
      docWith([
        row([
          stack('s', 144),
          {
            'id': 'col',
            'type': 'Column',
            'props': {'gap': 'none', 'align': 'start'},
            'weight': 1,
            'children': [textNode('Праворуч', id: 'right')],
          },
        ], gap: 'md'),
      ]),
    );

    final ring = stackRect(tester, 's');
    final right = tester.getRect(find.text('Праворуч'));
    expect(ring.width, closeTo(144, 0.01));
    // The weighted column did not vanish and sits to the right of the stack.
    expect(right.left, greaterThanOrEqualTo(ring.right));
    expect(right.width, greaterThan(0));
  });

  testWidgets('four stacks in a row stand side by side with the row gap', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDocument(
      tester,
      docWith([row([for (final i in ['a', 'b', 'c', 'd']) stack(i, 48)], gap: 'md')]),
    );

    final rects = [for (final i in ['a', 'b', 'c', 'd']) stackRect(tester, i)];
    final gap = rects[1].left - rects[0].right;
    expect(gap, greaterThan(0));
    for (var i = 0; i < 4; i++) {
      expect(rects[i].width, closeTo(48, 0.01));
      if (i > 0) expect(rects[i].left - rects[i - 1].right, closeTo(gap, 0.01));
    }
    // Not spread across the width: the whole row is four stacks and three gaps.
    expect(rects.last.right - rects.first.left, closeTo(48 * 4 + gap * 3, 0.01));
  });

  testWidgets('in a column the stack stays full width', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDocument(tester, docWith([stack('s', 144)]));

    expect(stackRect(tester, 's').width, greaterThan(144));
  });

  testWidgets('progress-screens at 390: the Weekly goal card is short, the column text is present', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 2100 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await pumpDocument(tester, loadFixture('progress-screens'));

    expect(find.textContaining('A white ring on a gradient'), findsWidgets);
    final card = tester.getRect(
      find.ancestor(of: find.text('Weekly goal').first, matching: find.byType(DecoratedBox)).first,
    );
    final text = tester.getRect(find.textContaining('A white ring on a gradient').first);
    expect(card.height, lessThan(250));
    expect(text.left, greaterThan(100));
    expect(text.right, lessThanOrEqualTo(390));
  });
}
