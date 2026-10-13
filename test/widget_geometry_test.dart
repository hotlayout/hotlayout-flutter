import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// BUILT-IN GEOMETRY OF COMPOSITE WIDGETS - the same as on the builder canvas.
///
/// The contract says WHAT these widgets contain (title, arrow, chevron) but not
/// how much space sits between the parts or which font size they use. Each
/// reader filled the silence its own way: the renderer with Material geometry
/// and its own numbers, the canvas with theme tokens. The contract 9 showcase,
/// laid side by side with the canvas, showed the difference on every screen:
/// buttons of another size, a bar next to the screen edge, a "How it works"
/// block 18 dp taller.
///
/// The numbers here mirror `canvas.css` and `product-metrics.ts` of the builder
/// (`BUTTON_*_SPACING`, `APP_BAR_*`, `ACCORDION_GAP_SPACING`, `TILE_*`).
/// Button geometry is also artifact data (`x-style.layout.buttonPadding`,
/// `buttonTypography`, `buttonSize` - mirrored in `column_width_test.dart`);
/// `AppBar`, `Accordion` and `ListTile` are described in prose by the contract's
/// rendering rules, and the numbers
/// below are checked against it and the canvas.
void main() {
  final theme = RenderTheme.fallback();
  double lineOf(TypographyToken token) => theme.text(token).fontSize! * theme.text(token).height!;
  double space(SpacingToken token) => theme.space(token);

  Map<String, Object?> button(String label, {String variant = 'primary', Map<String, Object?>? style}) => {
    'id': 'btn-$label',
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': label},
      'variant': variant,
      'action': {'type': 'submit'},
      'fullWidth': false,
    },
    'style': ?style,
  };

  group('button: label, padding, border - and nothing else', () {
    Size buttonSize(WidgetTester tester, String label) =>
        tester.getSize(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()));

    testWidgets('without own style - sm / md padding and titleS label', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([button('Далі')]), theme: theme);

      final label = tester.getSize(find.text('Далі'));
      expect(label.height, closeTo(lineOf(TypographyToken.titleS), 0.01), reason: 'button label is titleS');
      final size = buttonSize(tester, 'Далі');
      // Neither the 64×40 minimum size nor a 48 dp touch target around it.
      expect(size.height, closeTo(label.height + 2 * space(SpacingToken.sm), 0.01));
      expect(size.width, closeTo(label.width + 2 * space(SpacingToken.md), 0.01));
    });

    testWidgets('a short button does not grow to the Material minimum size', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([button('OK')]), theme: theme);

      final label = tester.getSize(find.text('OK'));
      expect(label.width, lessThan(40), reason: 'otherwise the test checks nothing');
      expect(buttonSize(tester, 'OK').width, closeTo(label.width + 2 * space(SpacingToken.md), 0.01));
    });

    testWidgets('own padding applies exactly as written', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          button('Місії', style: {'padding': {'top': 'md', 'end': 'sm', 'bottom': 'md', 'start': 'sm'}}),
        ]),
        theme: theme,
      );

      final label = tester.getSize(find.text('Місії'));
      final size = buttonSize(tester, 'Місії');
      expect(size.height, closeTo(label.height + 2 * space(SpacingToken.md), 0.01));
      expect(size.width, closeTo(label.width + 2 * space(SpacingToken.sm), 0.01));
    });

    testWidgets('the role border adds to the size, as in CSS', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([button('Друга', variant: 'secondary')]), theme: theme);

      expect(find.byType(OutlinedButton), findsOneWidget, reason: 'the secondary role has a border');
      final label = tester.getSize(find.text('Друга'));
      final size = buttonSize(tester, 'Друга');
      expect(size.height, closeTo(label.height + 2 * space(SpacingToken.sm) + 2, 0.01));
      expect(size.width, closeTo(label.width + 2 * space(SpacingToken.md) + 2, 0.01));
    });
  });

  group('top bar', () {
    const surface = Size(800, 600);
    final padding = {'top': 'md', 'end': 'lg', 'bottom': 'xl', 'start': 'lg'};

    Future<void> pump(WidgetTester tester, {String? subtitle, bool showBack = true}) => pumpDocument(
      tester,
      UiDocumentBuilder.bare(
        [
          appBarNode('Панель', subtitle: subtitle, showBack: showBack, background: null),
          textNode('Вміст'),
        ],
        style: {'padding': padding},
        gap: 'lg',
      ),
      theme: theme,
    );

    testWidgets('sits INSIDE the screen padding, and the content follows after the screen gap below it', (tester) async {
      await pump(tester);

      final back = tester.getRect(findAppBarBack);
      expect(back.left, greaterThanOrEqualTo(space(SpacingToken.lg)), reason: 'the arrow does not touch the edge');
      final title = tester.getRect(find.text('Панель'));
      // A bar without a subtitle is as tall as the arrow slot (`xl`) or the title
      // line - whichever is larger.
      final barHeight = [lineOf(TypographyToken.titleM), space(SpacingToken.xl)].reduce((a, b) => a > b ? a : b);
      expect(title.center.dy, closeTo(space(SpacingToken.md) + barHeight / 2, 0.01));
      expect(
        tester.getTopLeft(find.text('Вміст')).dy,
        closeTo(space(SpacingToken.md) + barHeight + space(SpacingToken.lg), 0.01),
      );
      expect(tester.getTopLeft(find.text('Вміст')).dx, space(SpacingToken.lg));
    });

    testWidgets('the title is centred in the BAR, with the arrow too', (tester) async {
      await pump(tester);
      expect(tester.getCenter(find.text('Панель')).dx, closeTo(surface.width / 2, 0.01));

      await pump(tester, showBack: false);
      expect(tester.getCenter(find.text('Панель')).dx, closeTo(surface.width / 2, 0.01));
    });

    testWidgets('the subtitle is bodyS, an xs gap below the title', (tester) async {
      await pump(tester, subtitle: 'Підзаголовок');

      final title = tester.getRect(find.text('Панель'));
      final subtitle = tester.getRect(find.text('Підзаголовок'));
      expect(subtitle.height, closeTo(lineOf(TypographyToken.bodyS), 0.01));
      expect(subtitle.top, closeTo(title.bottom + space(SpacingToken.xs), 0.01));
      expect(subtitle.center.dx, closeTo(surface.width / 2, 0.01));
    });
  });

  group('accordion', () {
    Map<String, Object?> accordion({required bool expanded}) => {
      'id': 'acc',
      'type': 'Accordion',
      'props': {
        'title': {'kind': 'literal', 'value': 'Як це працює'},
        'initiallyExpanded': expanded,
      },
      'children': [textNode('Правило')],
    };

    testWidgets('a collapsed block is as tall as the title line - no built-in padding', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([accordion(expanded: false), textNode('Після', id: 'after')]),
        theme: theme,
      );

      expect(tester.getTopLeft(find.text('Як це працює')).dy, 0);
      expect(tester.getTopLeft(find.text('Після')).dy, closeTo(lineOf(TypographyToken.titleS), 0.01));
    });

    testWidgets('expanded: content after an sm gap, no padding below the content', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([accordion(expanded: true), textNode('Після', id: 'after')]),
        theme: theme,
      );

      final header = lineOf(TypographyToken.titleS);
      final rule = tester.getRect(find.text('Правило'));
      expect(rule.top, closeTo(header + space(SpacingToken.sm), 0.01));
      expect(tester.getTopLeft(find.text('Після')).dy, closeTo(rule.bottom, 0.01));
    });
  });

  group('list row with a photo', () {
    testWidgets('thumbnail is two xl units, the name follows after an sm gap', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          listTileNode('Колонка', leading: {
            'kind': 'image',
            'source': {'kind': 'asset', 'asset': 'banner'},
          }),
        ]),
        theme: theme,
      );

      final thumbnail = tester.getRect(find.byType(ClipRRect).first);
      expect(thumbnail.size, Size.square(2 * space(SpacingToken.xl)));
      expect(tester.getTopLeft(find.text('Колонка')).dx, closeTo(thumbnail.right + space(SpacingToken.sm), 0.01));
    });
  });
}
