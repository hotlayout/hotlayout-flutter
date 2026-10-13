import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// The five 8.11.0 fields: things layouts already do but the contract could
/// not yet express. Two of them, the border and the card's fixed height, moved
/// since 9.0.0 from `Container.props` into the shared `style`
/// (`border: {width, color}` and `height`), so every node has them now; the
/// assertions about them are unchanged. No new widget is among them: the same
/// tree that already parses simply describes itself more precisely.
///
/// The tests look at the RENDER, not only at parsing: a field that reached the
/// model but not the pixel is the quietest possible contract breakage.
void main() {
  Map<String, Object?> row(
    List<Map<String, Object?>> children, {
    bool wrap = false,
    bool? scrollable,
  }) => {
    'id': 'row',
    'type': 'Row',
    'props': {
      'gap': 'none',
      'align': 'center',
      'justify': 'start',
      'wrap': wrap,
      'scrollable': ?scrollable,
    },
    'children': children,
  };

  Map<String, Object?> card(
    List<Map<String, Object?>> children, {
    Object? border,
    Object? height,
  }) => {
    'id': 'card',
    'type': 'Container',
    'props': {'gap': 'none'},
    'style': {
      'background': colorBackground('surface'),
      'border': ?border,
      'height': ?height,
    },
    'children': children,
  };

  group('Row.scrollable', () {
    RowNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([node])).whereType<RowNode>().single;

    test('no field: the row does not scroll, as before 8.11.0', () {
      expect(parse(row([textNode('А')])).scrollable, isFalse);
    });

    testWidgets('a scrollable row yields a scroll view', (tester) async {
      await pumpDocument(tester, docWith([row([textNode('А')], scrollable: true)]));

      expect(find.byType(SingleChildScrollView), findsWidgets);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).last,
      );
      expect(scroll.scrollDirection, Axis.horizontal);
    });

    /*
     * The `scrollable + wrap` pair is contradictory and the builder does not
     * produce it. But someone else may have authored the document, and here
     * the pair does not just look odd, it CRASHES: `Wrap` with infinite width
     * has nowhere to wrap. So the check is not "how it looks" but that the
     * screen is alive at all.
     */
    testWidgets('the contradictory pair does not crash the screen: scrolling wins', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          row([textNode('А', id: 'a'), textNode('Б', id: 'b')], wrap: true, scrollable: true),
        ]),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Wrap), findsNothing);
      expect(find.text('А'), findsOneWidget);
    });
  });

  /*
   * Nodes render without keys, so the card is found by its decoration: the
   * `DecoratedBox` with the card's background color is the box whose height
   * the document sets (size in the box model includes border and padding).
   */
  double cardHeight(WidgetTester tester) => tester.getSize(
    find.byWidgetPredicate(
      (widget) => widget is DecoratedBox && (widget.decoration as BoxDecoration).color != null,
    ).last,
  ).height;

  group('Container.border and Container.height', () {
    ContainerNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([node])).whereType<ContainerNode>().single;

    test('without the fields both are null: no border and no height, not "zero"', () {
      final node = parse(card([textNode('А')]));
      expect(node.style!.border, isNull);
      expect(node.style!.height, isNull);
    });

    test('the border reads as width and color, the height as a number', () {
      final node = parse(
        card([textNode('А')], border: {'width': 1, 'color': 'border'}, height: 140),
      );
      expect(node.style!.border!.color, const ColorRef.token('border'));
      expect(node.style!.border!.width, 1);
      expect(node.style!.height, isNotNull);
    });

    testWidgets('the set height is EXACT, not a minimum', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card([textNode('Довгий підпис картки')], height: 40),
        ]),
      );

      expect(cardHeight(tester), 40);
    });

    testWidgets('the height comes from DATA the same way as from a literal', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            [textNode('А')],
            height: {'kind': 'binding', 'path': 'task.progress', 'fallback': 60},
          ),
        ]),
        data: const {'task': {'progress': 90}},
      );

      expect(cardHeight(tester), 90);
    });
  });

  group('Image.fit', () {
    test('no field: cover, i.e. what was always done', () {
      final node = flattenDocument(
        docWith([
          {
            'id': 'im',
            'type': 'Image',
            'props': {
              'source': {'kind': 'url', 'url': 'https://cdn.example.com/a.png'},
            },
          },
        ]),
      ).whereType<ImageNode>().single;

      expect(node.fit, ImageFitToken.cover);
    });

    testWidgets('contain reaches the Image itself, not only the model', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'im',
            'type': 'Image',
            'props': {
              'source': {'kind': 'url', 'url': 'https://cdn.example.com/a.png'},
              'fit': 'contain',
            },
          },
        ]),
      );

      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    });
  });

  group('ListTile.trailing.icon', () {
    Map<String, Object?> tile(Map<String, Object?> trailing) => {
      'id': 'tile',
      'type': 'ListTile',
      'props': {
        'title': {'kind': 'literal', 'value': 'Рядок'},
        'trailing': trailing,
      },
    };

    test('the icon is optional: without it the variant stays the same', () {
      final node = flattenDocument(
        docWith([
          tile({
            'kind': 'text',
            'text': {'kind': 'literal', 'value': '+100'},
          }),
        ]),
      ).whereType<ListTileNode>().single;

      expect((node.trailing as TrailingText).icon, isNull);
    });

    testWidgets('"+100 ◆": the icon is painted AFTER the text', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          tile({
            'kind': 'text',
            'text': {'kind': 'literal', 'value': '+100'},
            'icon': 'star',
          }),
        ]),
      );

      final text = tester.getRect(find.text('+100'));
      final icon = tester.getRect(findIcon(IconToken.star));
      expect(icon.left, greaterThan(text.right - 1));
    });
  });
}
