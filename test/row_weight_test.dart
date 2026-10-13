import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

/// ROW WIDTH SHARE (8.17.0).
///
/// Closes a hole open since 4.0.0 - the oldest one in the contract. Until then
/// `_flexRow` held a `Flexible(loose)` with the comment "renderer decision, not the
/// contract's": the schema was silent about the width of row children, but something had to
/// be drawn. So this was the one place where two readers were ALLOWED to diverge.
///
/// The tests below guard not "a new feature" but exactly this boundary: the document now
/// names the width, and where it does not, behaviour stayed exactly the same.
void main() {
  Map<String, Object?> card(String id, String label, {int? weight, String? height}) => {
    'id': id,
    'type': 'Container',
    'props': {
      'gap': 'none',
    },
    // 9.0.0: background and height live in `style`; a literal height there is just a number.
    'style': {
      'background': {'kind': 'color', 'color': 'surface'},
      if (height != null) 'height': double.parse(height),
    },
    'children': [textNode(label, id: '$id-text')],
    'weight': ?weight,
  };

  Map<String, Object?> row(List<Map<String, Object?>> children, {Map<String, Object?> props = const {}}) => {
    'id': 'row',
    'type': 'Row',
    'props': {
      'gap': 'none',
      'align': 'center',
      'justify': 'start',
      'wrap': false,
      ...props,
    },
    'children': children,
  };

  /// Width of the box that holds this very label.
  double widthOf(WidgetTester tester, String label) =>
      tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first).width;

  group('parsing', () {
    ContainerNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([row([node])])).whereType<ContainerNode>().single;

    test('no field - no weight, not one', () {
      // "No weight" and "weight 1" are DIFFERENT things: the first takes no part in the
      // split at all. A default of 1 would silently make every existing child a participant.
      expect(parse(card('c', 'А')).weight, isNull);
    });

    test('the number reaches the model as is', () {
      expect(parse(card('c', 'А', weight: 3)).weight, 3);
    });

    /*
     * The contract upper bound (4) applies: a positive value outside 1..4 is clamped, like any
     * numeric field (`literalOutOfRange: 'clamp'`, contract 9). Before 9.0.0 the renderer took
     * `weight: 7` as is - and split the row differently from the preview.
     */
    test('a weight above the contract bound is clamped to 1..4', () {
      expect(parse(card('c', 'А', weight: 7)).weight, kMaxNodeWeight);
      expect(parse(card('c', 'А', weight: 4)).weight, 4);
    });

    /*
     * But zero and negative are rejected, and not out of pedantry: `Expanded(flex: 0)` gives
     * the child ZERO pixels - the node stays in the document and vanishes from the screen.
     * That is exactly the silent loss the contract set a minimum of 1 against.
     */
    test('zero, negative and non-number are read as no weight', () {
      for (final broken in <Object?>[0, -2, 'два', 1.5, true]) {
        final node = parse(<String, Object?>{...card('c', 'А'), 'weight': broken});
        expect(node.weight, isNull, reason: 'weight $broken should degrade to its own width');
      }
      // Policy key: `invalidWeight: 'no-weight'` - there is NO weight, not the lower
      // bound 1 (unlike the other numeric fields).
    });
  });

  group('render', () {
    testWidgets('weights 3 and 1 split the row exactly three to one', (tester) async {
      await pumpDocument(tester, docWith([
        row([card('wide', 'Широка', weight: 3), card('narrow', 'Вузька', weight: 1)]),
      ]));

      final wide = widthOf(tester, 'Широка');
      final narrow = widthOf(tester, 'Вузька');

      expect(wide, closeTo(narrow * 3, 0.5));
      // And together they fill the row entirely: `Expanded` leaves no free space.
      expect(wide + narrow, closeTo(tester.getSize(find.byType(RowLayout).last).width, 0.5));
    });

    testWidgets('equal weights give equal widths', (tester) async {
      await pumpDocument(tester, docWith([
        row([card('a', 'Ліва', weight: 2), card('b', 'Права', weight: 2)]),
      ]));

      expect(widthOf(tester, 'Ліва'), closeTo(widthOf(tester, 'Права'), 0.5));
    });

    /*
     * THE MAIN REGRESSION TEST. The cost of a mistake here is not "the new feature works
     * differently" but "all existing screens shifted": rows without weights in authored
     * documents are exactly as many as there are rows at all.
     */
    testWidgets('without weights widths stay natural, as before 8.17.0', (tester) async {
      await pumpDocument(tester, docWith([
        row([card('a', 'Короткі'), card('b', 'Значно довший підпис')]),
      ]));

      final short = widthOf(tester, 'Короткі');
      final long = widthOf(tester, 'Значно довший підпис');

      // `Flexible(loose)` leaves the child its own width - which is why the longer
      // label is wider. With `Expanded` both would be equal.
      expect(long, greaterThan(short));
    });

    /*
     * A WEIGHT BEATS THE NODE'S OWN WIDTH - a CONTRACT rule, not an implementation detail:
     * `Expanded` gives the child a tight constraint, and an own size does not fit into it
     * but is replaced. The builder measures the preview the same way.
     */
    testWidgets('a weight beats the own width of a vertical spacer', (tester) async {
      Map<String, Object?> spacer({int? weight}) => {
        'id': 'sp',
        'type': 'Spacer',
        'props': {'size': 'md', 'orientation': 'vertical'},
        'weight': ?weight,
      };

      await pumpDocument(tester, docWith([row([spacer(), card('c', 'Текст')])]));
      final own = tester.getSize(find.byType(SizedBox).at(0)).width;

      await pumpDocument(tester, docWith([
        row([spacer(weight: 3), card('c', 'Текст', weight: 1)]),
      ]));
      final weighted = widthOf(tester, 'Текст');

      // The spacer's own width is the `md` gap, i.e. tens of pixels; with weight 3
      // it takes three quarters of the row, three times more than its neighbour.
      expect(own, lessThan(weighted));
    });

    /*
     * A container row accepts weights under the same contract rule: it has no `wrap`
     * or `scrollable` of its own, so its width is always finite. The rank diagram from
     * the mockup is drawn with containers of different weight - they need a
     * background.
     */
    testWidgets('a container row splits the width the same way as Row', (tester) async {
      await pumpDocument(tester, docWith([
        {
          'id': 'box',
          'type': 'Container',
          'props': {
            'direction': 'row',
            'gap': 'none',
          },
          'style': {
            'background': {'kind': 'color', 'color': 'surface'},
          },
          'children': [card('a', 'Ліва', weight: 3), card('b', 'Права', weight: 1)],
        },
      ]));

      expect(widthOf(tester, 'Ліва'), closeTo(widthOf(tester, 'Права') * 3, 0.5));
    });

    /*
     * A scrollable row does NOT accept weights - the contract rejects them there, since
     * infinite width cannot be divided and `Expanded` in it is a crash. A document with
     * such a pair could be built by something other than the builder, so the renderer must
     * SURVIVE it: children take natural width, and no exception.
     */
    testWidgets('in a scrollable row the weight is ignored, not crashing the screen', (tester) async {
      await pumpDocument(tester, docWith([
        row(
          [card('a', 'Ліва', weight: 3), card('b', 'Права', weight: 1)],
          props: const {'scrollable': true},
        ),
      ]));

      expect(tester.takeException(), isNull);
      expect(find.text('Ліва'), findsOneWidget);
      expect(find.text('Права'), findsOneWidget);
    });

    testWidgets('in a wrapping row the weight is ignored, not crashing the screen', (tester) async {
      await pumpDocument(tester, docWith([
        row(
          [card('a', 'Ліва', weight: 3), card('b', 'Права', weight: 1)],
          props: const {'wrap': true},
        ),
      ]));

      expect(tester.takeException(), isNull);
      expect(find.text('Ліва'), findsOneWidget);
      expect(find.text('Права'), findsOneWidget);
    });
  });
}
