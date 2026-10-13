import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Composite widget boxes moved into the DOCUMENT (contract 9).
///
/// The accordion was a card in secret, while the list row and the bar had a vertical
/// `sm` padding from the reader code. Now this is the builder registry's `defaultStyle`,
/// which it WRITES into the node `style`. The reader adds nothing of its own: a node without
/// `style` has no such padding (otherwise it would be painted twice).
void main() {
  final theme = RenderTheme.fallback();
  final sm = theme.space(SpacingToken.sm);
  const verticalSm = {
    'padding': {'top': 'sm', 'bottom': 'sm'},
  };

  Map<String, Object?> withStyle(Map<String, Object?> node, Map<String, Object?>? style) => {
    ...node,
    'style': ?style,
  };

  Future<void> pump(WidgetTester tester, List<Map<String, Object?>> children) =>
      pumpDocument(tester, UiDocumentBuilder.bare(children), theme: theme);

  group('ListTile: the document supplies the vertical padding', () {
    testWidgets('without `style` the row sits flush against its neighbours', (tester) async {
      await pump(tester, [
        withStyle(listTileNode('Рядок', id: 'a'), null),
        textNode('Далі', id: 'next'),
      ]);

      final row = tester.getRect(find.text('Рядок'));
      expect(row.top, 0, reason: 'the built-in `sm` on top is gone');
      expect(tester.getTopLeft(find.text('Далі')).dy, closeTo(row.bottom, 0.5));
    });

    testWidgets('with `style.padding` {top, bottom} - exactly as much as the document named', (
      tester,
    ) async {
      await pump(tester, [
        withStyle(listTileNode('Рядок', id: 'a'), verticalSm),
        textNode('Далі', id: 'next'),
      ]);

      final row = tester.getRect(find.text('Рядок'));
      expect(row.top, sm);
      expect(tester.getTopLeft(find.text('Далі')).dy, closeTo(row.bottom + sm, 0.5));
    });
  });

  group('AppBar: the document supplies the vertical padding', () {
    testWidgets('without `style` the bar has no padding, with a style it does', (tester) async {
      await pumpDocument(
        tester,
        docWith([appBarNode('Панель', background: null), textNode('Вміст')]),
        theme: theme,
      );
      final bare = tester.getRect(find.text('Панель')).top;

      await pumpDocument(
        tester,
        docWith([
          {...appBarNode('Панель', background: null), 'style': verticalSm},
          textNode('Вміст'),
        ]),
        theme: theme,
      );
      expect(tester.getRect(find.text('Панель')).top - bare, sm);
    });
  });

  group('Accordion: `style` makes the card, as for any node', () {
    Map<String, Object?> accordion({Map<String, Object?>? style}) => {
      'id': 'acc',
      'type': 'Accordion',
      'props': {
        'title': {'kind': 'literal', 'value': 'Правила'},
        'initiallyExpanded': true,
      },
      'style': ?style,
      'children': [textNode('Текст правил', id: 'body')],
    };

    testWidgets('without `style` - no background, radius, shadow or padding', (tester) async {
      await pump(tester, [accordion()]);

      expect(
        find.ancestor(of: find.text('Правила'), matching: find.byType(DecoratedBox)),
        findsNothing,
        reason: 'an accordion is not a card until the document says otherwise',
      );
      expect(tester.getTopLeft(find.text('Правила')).dx, 0);
    });

    testWidgets('with a card `style`: padding, radius, background and shadow act on the WHOLE block', (tester) async {
      await pump(tester, [
        accordion(
          style: {
            'padding': 'md',
            'radius': 'md',
            'background': {'kind': 'color', 'color': 'surface'},
            'shadow': 'low',
          },
        ),
      ]);

      final decoration = tester
          .widget<DecoratedBox>(
            find.ancestor(of: find.text('Правила'), matching: find.byType(DecoratedBox)).first,
          )
          .decoration as BoxDecoration;
      expect(decoration.color, theme.color(ColorToken.surface));
      expect(decoration.borderRadius, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
      expect(tester.getTopLeft(find.text('Правила')).dx, theme.padding(SpacingToken.md).left);
      // The content of the expanded panel is inside the same card.
      expect(
        find.ancestor(of: find.text('Текст правил'), matching: find.byType(DecoratedBox)),
        findsWidgets,
      );
    });
  });
}
