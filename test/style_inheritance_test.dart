import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// Foreground inheritance (9.0.0) and the own style of widgets with a role.
///
/// `color` and `typography` flow DOWN the tree: a card with `style.color:
/// onBrand` paints all its captions at once. The rules here are the contract's
/// (`x-style`), and they are checked by what is drawn: the colour and size
/// of the resulting `Text`, not what lies in the model.
void main() {
  final theme = RenderTheme.fallback();

  Map<String, Object?> card(
    List<Map<String, Object?>> children, {
    Map<String, Object?>? style,
    List<Map<String, Object?>>? styleWhen,
    String id = 'card',
  }) => {
    'id': id,
    'type': 'Container',
    'props': {'gap': 'none'},
    'style': ?style,
    'styleWhen': ?styleWhen,
    'children': children,
  };

  Map<String, Object?> icon({Map<String, Object?>? style}) => {
    'id': 'icon',
    'type': 'Icon',
    'props': {'name': 'trophy', 'size': 'md'},
    'style': ?style,
  };

  TextStyle styleOf(WidgetTester tester, String label) => tester.widget<Text>(find.text(label)).style!;
  Color iconColor(WidgetTester tester, Finder finder) => iconColorOf(tester, finder);
  final trophy = findIcon(IconToken.trophy);

  group('root and own style', () {
    testWidgets('text and icon that nobody told anything - onSurface and bodyM', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([textNode('Напис'), icon()]), theme: theme);

      expect(styleOf(tester, 'Напис').color, theme.color(ColorToken.onSurface));
      expect(styleOf(tester, 'Напис').fontSize, theme.text(TypographyToken.bodyM).fontSize);
      expect(iconColor(tester, trophy), theme.color(ColorToken.onSurface));
    });

    testWidgets('a node own style: every form of reference reaches the text', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          textNode('Токен', id: 'a', style: {'color': 'accent', 'typography': 'titleM'}),
          textNode('Відтінок', id: 'b', style: {'color': {'token': 'accent', 'opacity': 0.5}}),
          textNode('Власний', id: 'c', style: {'color': {'value': '#ff7a59'}}),
          textNode('Правки', id: 'd', style: {
            'typography': {'token': 'titleM', 'fontSize': 28, 'fontWeight': 400, 'letterSpacing': 1},
          }),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Токен').color, theme.color(ColorToken.accent));
      expect(styleOf(tester, 'Токен').fontSize, theme.text(TypographyToken.titleM).fontSize);
      expect(styleOf(tester, 'Відтінок').color, theme.color(ColorToken.accent).withValues(alpha: 0.5));
      expect(styleOf(tester, 'Власний').color, const Color(0xFFFF7A59));
      final edited = styleOf(tester, 'Правки');
      expect(edited.fontSize, 28);
      expect(edited.fontWeight, FontWeight.w400);
      expect(edited.letterSpacing, 1);
      expect(edited.fontFamily, theme.text(TypographyToken.titleM).fontFamily);
      expect(edited.height, theme.text(TypographyToken.titleM).height, reason: 'the multiplier was not edited');
    });
  });

  group('inheritance down the tree', () {
    testWidgets('a card paints all captions and icons in it - at any depth', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'primary', 'typography': 'titleS'},
            [
              textNode('Близько', id: 'a'),
              card(id: 'inner', [textNode('Глибоко', id: 'b'), icon()]),
            ],
          ),
          textNode('Поза карткою', id: 'c'),
        ]),
        theme: theme,
      );

      for (final label in ['Близько', 'Глибоко']) {
        expect(styleOf(tester, label).color, theme.color(ColorToken.primary), reason: label);
        expect(styleOf(tester, label).fontSize, theme.text(TypographyToken.titleS).fontSize);
      }
      expect(iconColor(tester, trophy), theme.color(ColorToken.primary));
      // Inheritance goes down, not sideways: the card neighbour stayed root-coloured.
      expect(styleOf(tester, 'Поза карткою').color, theme.color(ColorToken.onSurface));
    });

    testWidgets('the nearest ancestor wins, and each field is inherited separately', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'primary', 'typography': 'titleM'},
            [
              card(id: 'inner', style: {'color': 'danger'}, [
                textNode('Колір ближчого, шрифт дальшого', id: 'a'),
                textNode('Свій колір', id: 'b', style: {'color': 'success'}),
              ]),
            ],
          ),
        ]),
        theme: theme,
      );

      final mixed = styleOf(tester, 'Колір ближчого, шрифт дальшого');
      expect(mixed.color, theme.color(ColorToken.danger));
      expect(mixed.fontSize, theme.text(TypographyToken.titleM).fontSize);
      expect(styleOf(tester, 'Свій колір').color, theme.color(ColorToken.success));
    });

    testWidgets('the font is inherited WHOLE: ancestor edits do not land on a descendant token', (tester) async {
      // `{token: titleM, fontSize: 22}` on the ancestor and `caption` on the descendant give
      // `caption`, not "caption at size 22".
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {
              'typography': {'token': 'titleM', 'fontSize': 22},
            },
            [
              textNode('Успадкував правку', id: 'a'),
              textNode('Назвав свій', id: 'b', style: {'typography': 'caption'}),
            ],
          ),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Успадкував правку').fontSize, 22);
      expect(styleOf(tester, 'Назвав свій').fontSize, theme.text(TypographyToken.caption).fontSize);
    });

    testWidgets('an icon does not read the font, the screen is an ancestor just like a card', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(
          [textNode('Напис'), icon()],
          style: {'color': 'accent', 'typography': 'displayL'},
        ),
        theme: theme,
      );

      expect(styleOf(tester, 'Напис').color, theme.color(ColorToken.accent));
      expect(styleOf(tester, 'Напис').fontSize, theme.text(TypographyToken.displayL).fontSize);
      final glyph = tester.widget<IconGlyph>(trophy);
      expect(glyph.color, theme.color(ColorToken.accent));
      expect(glyph.size, theme.iconSize(IconSizeToken.md), reason: 'icon size is set by props.size');
    });

    testWidgets('inheritance passes through a repeater, grid, stack and tab', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'success'},
            [
              {
                'id': 'rep',
                'type': 'Repeater',
                'props': {'source': 'items', 'item': 'item', 'gap': 'none'},
                'children': [
                  {
                    'id': 'row-text',
                    'type': 'Text',
                    'props': {
                      'content': {'kind': 'binding', 'path': 'item.name', 'fallback': ''},
                    },
                  },
                ],
              },
              {
                'id': 'grid',
                'type': 'Grid',
                'props': {'columns': 2, 'gap': 'none'},
                'children': [textNode('У сітці', id: 'g')],
              },
              {
                'id': 'stack',
                'type': 'Stack',
                'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
                'children': [textNode('У стосі', id: 's')],
              },
            ],
          ),
        ]),
        data: const {
          'items': [
            {'name': 'Запис'},
          ],
        },
        theme: theme,
      );

      for (final label in ['Запис', 'У сітці', 'У стосі']) {
        expect(styleOf(tester, label).color, theme.color(ColorToken.success), reason: label);
      }
    });
  });

  group('unknownInheritedToken: keep-parent', () {
    testWidgets('a token the theme does not know is not applied and does not become context', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'primary', 'typography': 'titleM'},
            [
              card(
                id: 'broken',
                style: {'color': 'colorFromFuture', 'typography': 'fontFromFuture'},
                [textNode('Під битим предком', id: 'a')],
              ),
              textNode('Сам із битим', id: 'b', style: {'color': 'colorFromFuture'}),
            ],
          ),
          textNode('Битий на корені', id: 'c', style: {'color': 'colorFromFuture'}),
        ]),
        theme: theme,
      );

      expect(tester.takeException(), isNull);
      // The parent one applies - not black, not `onSurface` and not a "similar" token.
      final under = styleOf(tester, 'Під битим предком');
      expect(under.color, theme.color(ColorToken.primary));
      expect(under.fontSize, theme.text(TypographyToken.titleM).fontSize);
      expect(styleOf(tester, 'Сам із битим').color, theme.color(ColorToken.primary));
      expect(styleOf(tester, 'Битий на корені').color, theme.color(ColorToken.onSurface));
    });

    testWidgets('an unknown token is NOT named as a colour: the composed widget stays built-in', (
      tester,
    ) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'colorFromFuture'},
            [listTileNode('Рядок', subtitle: 'Підпис')],
          ),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Рядок').color, theme.color(ColorToken.onSurface));
      expect(styleOf(tester, 'Підпис').color, theme.color(ColorToken.muted));
    });
  });

  group('named colour in composed widgets (`x-style.colorParts`)', () {
    Color secondary(Color color) => color.withValues(alpha: color.a * 0.6);

    testWidgets('until a colour is named - built-in colours, as before 9.0.0', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          appBarNode('Панель', subtitle: 'Під панеллю', background: null),
          listTileNode(
            'Рядок',
            subtitle: 'Підпис',
            leading: const {'kind': 'icon', 'icon': 'trophy'},
            trailing: const {
              'kind': 'text',
              'text': {'kind': 'literal', 'value': '+100'},
            },
          ),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Панель').color, theme.color(ColorToken.onSurface));
      expect(styleOf(tester, 'Під панеллю').color, theme.color(ColorToken.muted));
      expect(styleOf(tester, 'Рядок').color, theme.color(ColorToken.onSurface));
      expect(styleOf(tester, 'Підпис').color, theme.color(ColorToken.muted));
      // REVERSED by schema 9.5.0 (`listTileTrailingColor`):
      // the row trailing text is `onSurface`, not the muted `muted`.
      // The contract used to be silent, this reader chose `muted`, the canvas the title
      // colour; now the answer is named by data. The subtitle stays muted.
      expect(styleOf(tester, '+100').color, theme.color(ColorToken.onSurface));
      expect(iconColor(tester, trophy), theme.color(ColorToken.primary));
    });

    testWidgets('ListTile on a coloured card: primary - the colour, secondary - x 0.6', (tester) async {
      final named = theme.color(ColorToken.onPrimary);
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'onPrimary', 'background': {'kind': 'color', 'color': 'primary'}},
            [
              listTileNode(
                'Рядок',
                id: 'with-text',
                subtitle: 'Підпис',
                leading: const {'kind': 'icon', 'icon': 'trophy'},
                trailing: const {
                  'kind': 'text',
                  'text': {'kind': 'literal', 'value': '+100'},
                  'icon': 'star',
                },
              ),
              listTileNode('Із шевроном', id: 'with-chevron', trailing: const {'kind': 'chevron'}),
            ],
          ),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Рядок').color, named);
      expect(styleOf(tester, 'Підпис').color, secondary(named));
      // There is no disc under the icon (the phone is the truth), so `leadingIcon` is
      // a primary part of `x-style.colorParts`: without a disc a glyph on a coloured
      // card would otherwise be invisible. (Between two contract versions this
      // row changed twice; now it is final: "primary part".)
      expect(iconColor(tester, trophy), named, reason: 'leadingIcon is a primary part');
      expect(styleOf(tester, '+100').color, named, reason: 'trailingText is a primary part');
      expect(iconColor(tester, findIcon(IconToken.star)), named);
      expect(iconColor(tester, findIcon(IconToken.chevron)), secondary(named));
      // A composed widget does NOT inherit the font: the row title stays titleS.
      expect(styleOf(tester, 'Рядок').fontSize, theme.text(TypographyToken.titleS).fontSize);
    });

    testWidgets('a colour named on the node ITSELF acts the same as an inherited one', (tester) async {
      final named = theme.color(ColorToken.danger);
      await pumpDocument(
        tester,
        docWith([
          {...listTileNode('Рядок', subtitle: 'Підпис'), 'style': {'color': 'danger'}},
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Рядок').color, named);
      expect(styleOf(tester, 'Підпис').color, secondary(named));
    });

    testWidgets('an explicitly named onSurface is also NAMED: the flag is asked, not the colour', (tester) async {
      // Were the reader to compare the colour with the root one, this line would stay
      // "unnamed", and the subtitle would come out `muted` instead of onSurface x 0.6.
      final named = theme.color(ColorToken.onSurface);
      await pumpDocument(
        tester,
        docWith([
          card(style: {'color': 'onSurface'}, [listTileNode('Рядок', subtitle: 'Підпис')]),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Підпис').color, secondary(named));
      expect(styleOf(tester, 'Підпис').color, isNot(theme.color(ColorToken.muted)));
    });

    testWidgets('AppBar: title and arrow - the colour, subtitle - x 0.6', (tester) async {
      final named = theme.color(ColorToken.onPrimary);
      await pumpDocument(
        tester,
        docWith([
          {
            ...appBarNode('Панель', subtitle: 'Під панеллю', background: null),
            'style': {'color': 'onPrimary', 'background': {'kind': 'color', 'color': 'primary'}},
          },
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Панель').color, named);
      expect(styleOf(tester, 'Під панеллю').color, secondary(named));
      expect(iconColor(tester, findAppBarBack), named);
    });

    testWidgets('opacities multiply: the secondary part of a token tint', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': {'token': 'primary', 'opacity': 0.5}},
            [listTileNode('Рядок', subtitle: 'Підпис')],
          ),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Рядок').color!.a, closeTo(0.5, 1e-6));
      expect(styleOf(tester, 'Підпис').color!.a, closeTo(0.3, 1e-6));
    });

    testWidgets('Accordion and Tab: the active title - the colour, inactive and chevron - x 0.6', (
      tester,
    ) async {
      final named = theme.color(ColorToken.success);
      Map<String, Object?> tab(String id, String title, {Map<String, Object?>? style}) => {
        'id': id,
        'type': 'Tab',
        'props': {
          'title': {'kind': 'literal', 'value': title},
        },
        'style': ?style,
        'children': [textNode('Панель $title', id: '$id-body')],
      };

      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'success'},
            [
              {
                'id': 'acc',
                'type': 'Accordion',
                'props': {
                  'title': {'kind': 'literal', 'value': 'Розділ'},
                  'initiallyExpanded': false,
                },
                'children': <Object?>[],
              },
              {
                'id': 'tabs',
                'type': 'Tabs',
                'props': {'initialTab': 0},
                'children': [
                  tab('a', 'Перша'),
                  tab('b', 'Друга'),
                  // A tab reads the colour in ITS OWN context.
                  tab('c', 'Третя', style: {'color': 'danger'}),
                ],
              },
            ],
          ),
        ]),
        theme: theme,
      );

      expect(styleOf(tester, 'Розділ').color, named);
      expect(iconColor(tester, findIcon(IconToken.chevron)), secondary(named));
      expect(styleOf(tester, 'Перша').color, named);
      expect(styleOf(tester, 'Друга').color, secondary(named));
      expect(styleOf(tester, 'Третя').color, secondary(theme.color(ColorToken.danger)));
      // The panel of the open tab inherited the card colour.
      expect(styleOf(tester, 'Панель Перша').color, named);
    });
  });

  group('Button and Badge: the theme role and own style', () {
    ButtonStyle filledStyle(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton)).style!;
    Color? labelColor(WidgetTester tester, String label) => styleOf(tester, label).color;

    Map<String, Object?> button(String label, {String variant = 'primary', Map<String, Object?>? style}) => {
      ...buttonNode(label, action: const {'type': 'none'}, variant: variant),
      'style': ?style,
    };

    Map<String, Object?> badge(String label, {String tone = 'success', Map<String, Object?>? style}) => {
      ...badgeNode(label, tone: tone),
      'style': ?style,
    };

    testWidgets('without a style - exactly the theme role, as before 9.0.0', (tester) async {
      await pumpDocument(tester, docWith([button('Кнопка'), badge('Бейдж')]), theme: theme);

      final style = filledStyle(tester);
      expect(style.backgroundColor!.resolve({}), theme.color(ColorToken.primary));
      expect(style.foregroundColor!.resolve({}), theme.color(ColorToken.onPrimary));
      expect(style.backgroundBuilder, isNull);
      expect(badgeDecoration(tester, 'Бейдж').color, theme.color(ColorToken.success));
      expect(labelColor(tester, 'Бейдж'), theme.color(ColorToken.onPrimary));
    });

    testWidgets('an INHERITED colour does not override the role', (tester) async {
      // Otherwise a button on a coloured card would get the card text colour on
      // its own role background - and lose contrast.
      await pumpDocument(
        tester,
        docWith([
          card(
            style: {'color': 'danger', 'typography': 'displayL'},
            [button('Кнопка'), badge('Бейдж'), textNode('Сусід')],
          ),
        ]),
        theme: theme,
      );

      expect(filledStyle(tester).foregroundColor!.resolve({}), theme.color(ColorToken.onPrimary));
      expect(labelColor(tester, 'Бейдж'), theme.color(ColorToken.onPrimary));
      expect(styleOf(tester, 'Бейдж').fontSize, theme.text(TypographyToken.caption).fontSize);
      expect(styleOf(tester, 'Сусід').color, theme.color(ColorToken.danger));
    });

    testWidgets('each slot separately: an own background does not touch the caption colour, and vice versa', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          button('Тло', style: {'background': {'kind': 'color', 'color': 'accent'}}),
        ]),
        theme: theme,
      );
      expect(filledStyle(tester).backgroundColor!.resolve({}), theme.color(ColorToken.accent));
      expect(filledStyle(tester).foregroundColor!.resolve({}), theme.color(ColorToken.onPrimary));

      await pumpDocument(tester, docWith([button('Напис', style: {'color': 'warning'})]), theme: theme);
      expect(filledStyle(tester).backgroundColor!.resolve({}), theme.color(ColorToken.primary));
      expect(filledStyle(tester).foregroundColor!.resolve({}), theme.color(ColorToken.warning));
    });

    testWidgets('an own border, radius, padding and font land on the button ITSELF', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          button('Власна', style: {
            'border': {'width': 3, 'color': 'danger'},
            'radius': {'topStart': 24},
            'padding': {'start': 40, 'end': 'lg'},
            'typography': {'token': 'titleM', 'fontSize': 21},
          }),
        ]),
        theme: theme,
      );

      // There is a border -> `OutlinedButton`, as with a role border.
      final style = tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!;
      expect(style.side!.resolve({}), BorderSide(color: theme.color(ColorToken.danger), width: 3));
      expect(
        (style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,
        const BorderRadiusDirectional.only(topStart: Radius.circular(24)),
      );
      // The document padding (40 / 16) PLUS the border (3) on each side: the border eats
      // layout pixels, as with the node box and in CSS - the Material button draws
      // it over the padding, and without this a button with a border would be 2x3 dp smaller
      // than on the canvas.
      expect(style.padding!.resolve({}), const EdgeInsetsDirectional.fromSTEB(43, 3, 19, 3));
      expect(style.textStyle!.resolve({})!.fontSize, 21);
      // These paddings did not land a second time on the box AROUND the button.
      expect(
        find.ancestor(of: find.byType(OutlinedButton), matching: find.byType(DecoratedBox)).evaluate().where(
          (element) => ((element.widget as DecoratedBox).decoration as BoxDecoration).border != null,
        ),
        isEmpty,
      );
    });

    testWidgets('the role border is hairline, 1 dp; ghost with its own background becomes filled', (tester) async {
      await pumpDocument(tester, docWith([button('Друга', variant: 'secondary')]), theme: theme);
      final side = tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!.side!.resolve({})!;
      expect(side.width, 1);
      expect(side.color, theme.color(ColorToken.primary));

      await pumpDocument(tester, docWith([button('Привид', variant: 'ghost')]), theme: theme);
      expect(find.byType(TextButton), findsOneWidget);

      await pumpDocument(
        tester,
        docWith([
          button('Привид', variant: 'ghost', style: {'background': {'kind': 'color', 'color': 'secondary'}}),
        ]),
        theme: theme,
      );
      expect(filledStyle(tester).backgroundColor!.resolve({}), theme.color(ColorToken.secondary));
      expect(filledStyle(tester).foregroundColor!.resolve({}), theme.color(ColorToken.primary));
    });

    testWidgets('gradient and own shadow on a button are drawn as a layer under its content', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          button('Бренд', style: {
            'background': {
              'kind': 'gradient',
              'gradient': {
                'angle': 135,
                'stops': [
                  {'color': 'primary', 'position': 0},
                  {'color': 'accent', 'position': 1},
                ],
              },
            },
            'shadow': 'medium',
            'radius': 'pill',
          }),
        ]),
        theme: theme,
      );

      expect(tester.takeException(), isNull);
      final style = filledStyle(tester);
      expect(style.backgroundBuilder, isNotNull);
      expect(style.backgroundColor!.resolve({}), Colors.transparent);
      final decoration = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: find.byType(FilledButton), matching: find.byType(DecoratedBox)),
          )
          .map((box) => box.decoration as BoxDecoration)
          .firstWhere((decoration) => decoration.gradient != null);
      expect(decoration.gradient, isA<CornerGradient>());
      expect(decoration.boxShadow, theme.elevation(ElevationToken.medium));
    });

    testWidgets('margin, sizes and opacity - a box around, as everywhere', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          button('Коробка', style: {'margin': {'top': 'xl'}, 'width': 200, 'opacity': 0.5}),
        ]),
        theme: theme,
      );

      final rect = tester.getRect(find.byType(FilledButton));
      expect(rect.width, 200);
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(
        tester.widget<Opacity>(find.ancestor(of: find.byType(FilledButton), matching: find.byType(Opacity))).opacity,
        0.5,
      );
    });

    testWidgets('a state repaints a button the same as any node', (tester) async {
      final document = docWith([
        {
          ...button('Стан'),
          'styleWhen': [
            {
              'when': {'path': 'task.locked', 'op': 'isTrue'},
              'style': {'background': {'kind': 'color', 'color': 'locked'}, 'color': 'surface'},
            },
          ],
        },
      ]);

      await pumpDocument(tester, document, data: const {'task.locked': false}, theme: theme);
      expect(filledStyle(tester).backgroundColor!.resolve({}), theme.color(ColorToken.primary));

      await pumpDocument(tester, document, data: const {'task.locked': true}, theme: theme);
      expect(filledStyle(tester).backgroundColor!.resolve({}), theme.color(ColorToken.locked));
      expect(filledStyle(tester).foregroundColor!.resolve({}), theme.color(ColorToken.surface));
    });

    testWidgets('an own field with an UNKNOWN token does not override the role', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          button('Кнопка', style: {
            'background': {'kind': 'color', 'color': 'colorFromFuture'},
            'color': 'colorFromFuture',
            'border': {'width': 2, 'color': 'colorFromFuture'},
            'radius': 'radiusFromFuture',
          }),
          badge('Бейдж', style: {'background': {'kind': 'gradient', 'gradient': 'gradientFromFuture'}}),
        ]),
        theme: theme,
      );

      expect(tester.takeException(), isNull);
      final style = filledStyle(tester);
      expect(style.backgroundColor!.resolve({}), theme.color(ColorToken.primary));
      expect(style.foregroundColor!.resolve({}), theme.color(ColorToken.onPrimary));
      expect(badgeDecoration(tester, 'Бейдж').color, theme.color(ColorToken.success));
    });

    testWidgets('badge: each surface slot separately', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          badge('Свій', style: {
            'background': {'kind': 'color', 'color': {'token': 'primary', 'opacity': 0.1}},
            'color': 'primary',
            'border': {'width': 2, 'color': 'primary'},
            'radius': 4,
            'padding': {'start': 20},
            'typography': 'titleS',
            'shadow': 'low',
          }),
        ]),
        theme: theme,
      );

      final decoration = badgeDecoration(tester, 'Свій');
      expect(decoration.color, theme.color(ColorToken.primary).withValues(alpha: 0.1));
      expect((decoration.border! as Border).top.width, 2);
      expect(decoration.borderRadius, const BorderRadiusDirectional.all(Radius.circular(4)));
      expect(decoration.boxShadow, theme.elevation(ElevationToken.low));
      expect(labelColor(tester, 'Свій'), theme.color(ColorToken.primary));
      expect(styleOf(tester, 'Свій').fontSize, theme.text(TypographyToken.titleS).fontSize);
      // Padding: 2 (border) + 20 on the left, 2 on top - the own padding replaced the built-in one entirely.
      expect(tester.getTopLeft(find.text('Свій')), const Offset(22, 2));
    });

    testWidgets('no role in the theme - neutral, but the own style acts then too', (tester) async {
      final withoutSuccess = RenderTheme.fromJson({
        'id': 'x',
        'color': {'onSurface': '#010203', 'accent': '#0369a1'},
        'roles': {
          'badgeTone': {
            'neutral': {'foreground': 'onSurface'},
          },
          'buttonVariant': {
            'primary': {'foreground': 'onSurface'},
          },
        },
      });

      await pumpDocument(
        tester,
        docWith([
          badge('Без ролі', style: {'background': {'kind': 'color', 'color': 'accent'}}),
        ]),
        theme: withoutSuccess,
      );

      expect(badgeDecoration(tester, 'Без ролі').color, const Color(0xFF0369A1));
      expect(labelColor(tester, 'Без ролі'), const Color(0xFF010203));
    });
  });

  group('Screen.props.gap', () {
    testWidgets('the gap between root children - from the document, default sm', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Перша', id: 'a'), textNode('Друга', id: 'b')], gap: null),
        theme: theme,
      );
      final first = tester.getRect(find.text('Перша'));
      expect(tester.getTopLeft(find.text('Друга')).dy, first.bottom + theme.space(SpacingToken.sm));

      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Перша', id: 'a'), textNode('Друга', id: 'b')], gap: 20),
        theme: theme,
      );
      expect(tester.getTopLeft(find.text('Друга')).dy, tester.getRect(find.text('Перша')).bottom + 20);

      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Перша', id: 'a'), textNode('Друга', id: 'b')]),
        theme: theme,
      );
      expect(tester.getTopLeft(find.text('Друга')).dy, tester.getRect(find.text('Перша')).bottom);
    });
  });
}
