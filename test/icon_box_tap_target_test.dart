import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/tap_target.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// Two reader-rule clarifications with no change to the document shape:
/// the icon box and the touch target.
///
///  * icon box - the box of `Icon` is the token line height tall and the font size wide,
///    not a square of the font size;
///  * touch target - the touch area is not smaller than 48 x 48 dp, but the look and layout
///    stay the same.
void main() {
  final theme = RenderTheme.fallback();

  Map<String, Object?> icon(String size, {String id = 'icon'}) => {
    'id': '$id-$size',
    'type': 'Icon',
    'props': {'name': 'trophy', 'size': size},
  };

  Map<String, Object?> button(String label, {String? id}) => {
    'id': id ?? 'btn-$label',
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': label},
      'variant': 'primary',
      'action': {'type': 'submit', 'params': {'which': label}},
      'fullWidth': false,
    },
  };

  Rect rectOfButton(WidgetTester tester, String label) =>
      tester.getRect(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()));

  group('icon box: token line height tall, font size wide', () {
    Size boxOf(TypographyToken token) {
      final style = theme.text(token);
      return Size(style.fontSize!, style.fontSize! * style.height!);
    }

    testWidgets('sm / md / lg -> font size x line bodyS / titleM / displayL', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([icon('sm'), icon('md'), icon('lg')]),
        theme: theme,
      );

      final sizes = tester.widgetList<IconBox>(find.byType(IconBox)).map((b) => b.box).toList();
      expect(sizes, [boxOf(TypographyToken.bodyS), boxOf(TypographyToken.titleM), boxOf(TypographyToken.displayL)]);

      final rendered = tester.widgetList(find.byType(IconBox)).map((w) => tester.getSize(find.byWidget(w))).toList();
      for (final (i, token) in [TypographyToken.bodyS, TypographyToken.titleM, TypographyToken.displayL].indexed) {
        expect(rendered[i].width, closeTo(boxOf(token).width, 0.01), reason: '$token: width is the font size');
        expect(rendered[i].height, closeTo(boxOf(token).height, 0.01), reason: '$token: height is the token line');
        expect(rendered[i].height, greaterThan(rendered[i].width), reason: '$token: the box is not a square');
      }
    });

    testWidgets('the glyph is square at the font size and centred in the box', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([icon('md')]), theme: theme);

      final box = tester.getRect(find.byType(IconBox));
      final glyph = tester.getRect(find.byType(IconGlyph));
      expect(glyph.width, closeTo(theme.iconSize(IconSizeToken.md), 0.01));
      expect(glyph.height, closeTo(glyph.width, 0.01));
      expect(glyph.center.dx, closeTo(box.center.dx, 0.01));
      expect(glyph.center.dy, closeTo(box.center.dy, 0.01));
    });

    testWidgets('a row with an md icon is not shorter than a titleM row', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([icon('md')]), theme: theme);
      expect(
        tester.getSize(find.byType(IconBox)).height,
        closeTo(theme.text(TypographyToken.titleM).fontSize! * theme.text(TypographyToken.titleM).height!, 0.01),
      );
    });

    testWidgets('both box sides grow with the system font scale', (tester) async {
      final doc = UiDocumentBuilder.bare([icon('md')]);
      Future<Size> at(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: renderDocument(doc, theme: theme, data: const {})),
            ),
          ),
        );
        return tester.getSize(find.byType(IconBox));
      }

      final base = await at(1);
      final doubled = await at(2);
      expect(doubled.width, closeTo(base.width * 2, 0.01));
      expect(doubled.height, closeTo(base.height * 2, 0.01));
      expect(tester.getSize(find.byType(IconGlyph)).width, closeTo(base.width * 2, 0.01), reason: 'the glyph grows with it');
    });

    testWidgets('ListTile part icons: leading md, trailing sm - also in boxes', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          listTileNode(
            'Приз',
            leading: {'kind': 'icon', 'icon': 'trophy'},
            trailing: {'kind': 'text', 'text': {'kind': 'literal', 'value': '+100'}, 'icon': 'star'},
          ),
        ]),
        theme: theme,
      );

      final boxes = tester.widgetList<IconBox>(find.byType(IconBox)).map((b) => b.box).toList();
      expect(boxes, [theme.iconBox(IconSizeToken.md), theme.iconBox(IconSizeToken.sm)]);
      final leading = tester.getSize(find.byType(IconBox).first);
      expect(leading.height, closeTo(boxOf(TypographyToken.titleM).height, 0.01));
    });

    testWidgets('the chevron and the AppBar arrow are not IconBox: the icon box rule is silent about them', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          listTileNode('Рядок', trailing: {'kind': 'chevron'}),
        ]),
        theme: theme,
      );
      expect(find.byType(IconBox), findsNothing);
      expect(find.byType(IconGlyph), findsOneWidget);
    });
  });

  group('touch target: 48 x 48 dp area without a layout change', () {
    testWidgets('a tap 3 dp above a 40-tall button fires', (tester) async {
      final actions = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Над'), button('Далі'), textNode('Під', id: 'txt3')], gap: 'sm'),
        theme: theme,
        onAction: (action, _) => actions.add('${action.params['which']}'),
      );
      final rect = rectOfButton(tester, 'Далі');
      expect(rect.height, 40, reason: 'precondition: the button is shorter than 48');

      await tester.tapAt(Offset(rect.center.dx, rect.top - 3));
      expect(actions, ['Далі']);

      await tester.tapAt(Offset(rect.center.dx, rect.bottom + 3));
      expect(actions, ['Далі', 'Далі'], reason: 'the strip works on the lower side too');
    });

    testWidgets('the strip works where the neighbour has no gap: the column asks children from the last', (tester) async {
      final actions = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Над'), button('Далі'), textNode('Під', id: 'txt3')]),
        theme: theme,
        onAction: (action, _) => actions.add('${action.params['which']}'),
      );
      final rect = rectOfButton(tester, 'Далі');
      // 3 dp under the button is the box of the text "Під", not empty space.
      await tester.tapAt(Offset(rect.center.dx, rect.bottom + 3));
      expect(actions, ['Далі']);
    });

    testWidgets('beyond 48 dp the button does not take the touch', (tester) async {
      final actions = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Над'), textNode('Ще', id: 'txt2'), button('Далі')]),
        theme: theme,
        onAction: (action, _) => actions.add('x'),
      );
      final rect = rectOfButton(tester, 'Далі');
      await tester.tapAt(Offset(rect.center.dx, rect.top - 6));
      expect(actions, isEmpty, reason: 'the zone is 4 dp at height 40, no more');
    });

    testWidgets('layout unchanged: button size and the gap to the neighbour', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([button('Перша'), button('Друга')], gap: 'md'),
        theme: theme,
      );
      final first = rectOfButton(tester, 'Перша');
      final second = rectOfButton(tester, 'Друга');
      final label = tester.getSize(find.text('Перша'));

      expect(first.height, closeTo(label.height + 2 * theme.space(SpacingToken.sm), 0.01));
      expect(second.top - first.bottom, closeTo(theme.space(SpacingToken.md), 0.01),
          reason: 'the gap comes from the document, not 48 dp');
      // The touch area box is the same as the button: nothing was added.
      expect(tester.getRect(find.byType(TapTarget).first), first);
    });

    testWidgets('two buttons flush: in its own box each catches its own touch', (tester) async {
      final actions = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([button('Верхня'), button('Нижня')]),
        theme: theme,
        onAction: (action, _) => actions.add('${action.params['which']}'),
      );
      final upper = rectOfButton(tester, 'Верхня');
      final lower = rectOfButton(tester, 'Нижня');
      expect(lower.top, closeTo(upper.bottom, 0.01), reason: 'precondition: flush');

      // 2 dp inside each box - the neighbour strip reaches here, but
      // the own box is stronger.
      await tester.tapAt(Offset(upper.center.dx, upper.bottom - 2));
      await tester.tapAt(Offset(lower.center.dx, lower.top + 2));
      expect(actions, ['Верхня', 'Нижня']);

      // Top and bottom edge of the page: strips outward from the pair.
      await tester.tapAt(Offset(upper.center.dx, upper.top + 1));
      await tester.tapAt(Offset(lower.center.dx, lower.bottom - 1));
      expect(actions, ['Верхня', 'Нижня', 'Верхня', 'Нижня']);
    });

    testWidgets('a disclosure block header and a list row with an action also have a strip', (tester) async {
      final actions = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          textNode('Над'),
          listTileNode('Приз', action: {'type': 'submit', 'params': {'which': 'tile'}}),
          textNode('Під', id: 'txt3'),
        ], gap: 'sm'),
        theme: theme,
        onAction: (action, _) => actions.add('${action.params['which']}'),
      );
      final tile = tester.getRect(find.byType(TapTarget).first);
      expect(tile.height, lessThan(48), reason: 'precondition: the row is shorter than 48');
      await tester.tapAt(Offset(tile.center.dx, tile.bottom + (48 - tile.height) / 2 - 1));
      expect(actions, ['tile']);
    });

    testWidgets('AppBar arrow: a strip around the square', (tester) async {
      final actions = <String>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          textNode('Над'),
          {
            'id': 'bar',
            'type': 'AppBar',
            'props': {'title': {'kind': 'literal', 'value': 'Заголовок'}, 'showBack': true},
          },
        ], gap: 'sm'),
        theme: theme,
        onAction: (action, _) => actions.add(action.type),
      );
      final target = tester.getRect(find.byType(TapTarget).first);
      expect(target.height, lessThan(48), reason: 'precondition: the arrow is shorter than 48');
      expect(target.width, lessThan(48), reason: 'precondition: the arrow is narrower than 48');
      // Above the square, in the strip that completes it to 48.
      await tester.tapAt(Offset(target.center.dx, target.top - (48 - target.height) / 2 + 1));
      expect(actions, [ButtonAction.navigateBack]);
    });
  });
}
