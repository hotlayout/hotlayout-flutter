import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';

import 'support/fixtures.dart';

/// `Container.direction` (8.1.0): the container states how it lays out its content.
///
/// Before 8.1.0 the axis inside a card was an ASSUMPTION: there was no option
/// other than vertical, so a divider in it could only be horizontal.
/// Now the document dictates the axis, and two things depend on it:
/// how the children are laid out and which divider axis is correct.
void main() {
  Map<String, Object?> container(
    List<Map<String, Object?>> children, {
    String? direction,
    String gap = 'none',
  }) => {
    'id': 'card',
    'type': 'Container',
    'props': {
      // There is NO field when `direction == null`: that is what a document looked like before
      // 8.1.0, and that case must still render as before.
      'direction': ?direction,
      'gap': gap,
    },
    'style': {'radius': 'md', 'background': colorBackground()},
    'children': children,
  };

  Rect rectOf(WidgetTester tester, String text) => tester.getRect(find.text(text));

  group('model', () {
    test('no field: reads as column, i.e. what it always was', () {
      final node = flattenDocument(
        docWith([container([textNode('А', id: 'a')])]),
      ).whereType<ContainerNode>().single;

      expect(node.direction, ContainerDirectionToken.column);
    });

    test('an unknown value degrades to column instead of breaking the node', () {
      // Rule 1: an unknown token falls back to the field default with a log. A container with a
      // direction from the future must remain a card rather than vanish.
      final node = flattenDocument(
        docWith([
          container([textNode('А', id: 'a')], direction: 'diagonal'),
        ]),
      ).whereType<ContainerNode>().single;

      expect(node.direction, ContainerDirectionToken.column);
    });

    test('row reads as row', () {
      final node = flattenDocument(
        docWith([
          container([textNode('А', id: 'a')], direction: 'row'),
        ]),
      ).whereType<ContainerNode>().single;

      expect(node.direction, ContainerDirectionToken.row);
    });
  });

  group('layout', () {
    testWidgets('column: children one under another, as before 8.1.0', (tester) async {
      // Both documents must produce the SAME result: no field and `column`.
      for (final direction in [null, 'column']) {
        await pumpDocument(
          tester,
          docWith([
            container(
              [textNode('Перший', id: 'a'), textNode('Другий', id: 'b')],
              direction: direction,
            ),
          ]),
        );

        final first = rectOf(tester, 'Перший');
        final second = rectOf(tester, 'Другий');
        expect(second.top, greaterThanOrEqualTo(first.bottom), reason: 'direction=$direction');
        expect(second.left, first.left, reason: 'direction=$direction');
      }
    });

    testWidgets('row: children side by side, centred on height', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          container(
            [textNode('Перший', id: 'a'), textNode('Другий', id: 'b')],
            direction: 'row',
          ),
        ]),
      );

      final first = rectOf(tester, 'Перший');
      final second = rectOf(tester, 'Другий');
      expect(second.left, greaterThanOrEqualTo(first.right));
      // The contract says exactly this: in a row the children are centred on height.
      expect(second.center.dy, closeTo(first.center.dy, 0.5));
    });

    testWidgets('gap in a row becomes a HORIZONTAL gap', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          container(
            [textNode('Перший', id: 'a'), textNode('Другий', id: 'b')],
            direction: 'row',
            gap: 'lg',
          ),
        ]),
      );

      final first = rectOf(tester, 'Перший');
      final second = rectOf(tester, 'Другий');
      expect(second.left - first.right, greaterThan(8));
      expect(second.center.dy, closeTo(first.center.dy, 0.5));
    });
  });

  group('the axis reaches the children', () {
    testWidgets('in a column the text stretches, in a row it does not', (tester) async {
      // This is not cosmetic but proof that `flow` is computed from `direction` rather than
      // hard-coded: in a vertical flow `align != start` stretches the label to the full
      // width, in a horizontal one it does not (otherwise the row would break).
      Future<double> widthIn(String? direction) async {
        await pumpDocument(
          tester,
          docWith([
            container([
              textNode('Напис', id: 'a', extra: const {'align': 'center'}),
            ], direction: direction),
          ]),
        );
        return tester.getRect(find.text('Напис')).width;
      }

      final inColumn = await widthIn('column');
      final inRow = await widthIn('row');

      expect(inColumn, greaterThan(inRow));
    });

    testWidgets('divider is drawn on ITS OWN axis, not on the card axis',
        (tester) async {
      // Renderer rule 2: it is literal. A vertical line in a row is
      // what 8.1.0 finally made expressible, and the renderer draws exactly it;
      // the axis correctness is ensured by the builder validator (`axis_mismatch`),
      // not by a guess here.
      await pumpDocument(
        tester,
        docWith([
          container(
            [
              textNode('Ліворуч', id: 'a'),
              {
                'id': 'sep',
                'type': 'Divider',
                'props': {'color': 'border', 'spacing': 'sm', 'orientation': 'vertical'},
              },
              textNode('Праворуч', id: 'b'),
            ],
            direction: 'row',
          ),
        ]),
      );

      final line = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width == 1)
          .toList();
      expect(line, hasLength(1), reason: 'the vertical line must be 1 wide');
      expect(rectOf(tester, 'Праворуч').left, greaterThan(rectOf(tester, 'Ліворуч').right));
    });
  });
}
