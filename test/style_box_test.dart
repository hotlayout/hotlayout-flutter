import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/image_frame.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Node box (9.0.0) - the RENDER of each style property.
///
/// One model for all types:
///
///     margin -> box (size, background, border, radius, shadow, opacity)
///            -> padding -> content
///
/// The tests look at what is drawn (rectangles and decoration), not at the
/// model: a field that reached `NodeStyle` and did not reach the pixel is the quietest
/// possible contract breakage. In most tests the screen has NO style
/// ([UiDocumentBuilder.bare]) - then coordinates count from zero.
void main() {
  final theme = RenderTheme.fallback();

  /// A node with a style and an anchor caption. It is a `Text`, not a container with
  /// text inside: then everything between the caption and the screen column is the box
  /// of THIS very node, and it can be found without keys.
  Map<String, Object?> box(
    String label, {
    Map<String, Object?>? style,
    String id = 'box',
    int? weight,
    bool fill = false,
  }) => {
    ...textNode(label, id: id, style: style),
    'weight': ?weight,
    if (fill) 'fill': true,
  };

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, Object?>> children, {
    Map<String, Object?> data = const {},
    String? locale,
  }) => pumpDocument(tester, UiDocumentBuilder.bare(children), data: data, locale: locale, theme: theme);

  /// The nearest widget of that type above the caption - within its node.
  T? nearest<T extends Widget>(WidgetTester tester, String label) {
    T? found;
    tester.element(find.text(label)).visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Flex) return false;
      if (widget is T) {
        found = widget;
        return false;
      }
      return true;
    });
    return found;
  }

  /// The rectangle of the decorated box of the node with this caption.
  Rect boxRect(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first,
  );

  const surface = {'kind': 'color', 'color': 'surface'};

  group('no hidden defaults', () {
    testWidgets('a container without a style - no background, padding, radius or shadow', (tester) async {
      await pump(tester, [
        {
          'id': 'card',
          'type': 'Container',
          'props': {'gap': 'none'},
          'children': [textNode('Вміст')],
        },
      ]);

      expect(find.ancestor(of: find.text('Вміст'), matching: find.byType(DecoratedBox)), findsNothing);
      expect(nearest<Padding>(tester, 'Вміст'), isNull);
      expect(nearest<ClipRRect>(tester, 'Вміст'), isNull);
      expect(nearest<Opacity>(tester, 'Вміст'), isNull);
      expect(tester.getTopLeft(find.text('Вміст')), Offset.zero);
    });

    testWidgets('an image without a style has square corners', (tester) async {
      await pump(tester, [
        {
          'id': 'img',
          'type': 'Image',
          'props': {
            'source': {'kind': 'asset', 'asset': 'banner'},
            'aspectRatio': '16:9',
          },
        },
      ]);

      expect(find.byType(ClipRRect), findsNothing);
    });
  });

  group('padding', () {
    testWidgets('one value for all sides: a token and a number', (tester) async {
      await pump(tester, [
        box('Токен', id: 'a', style: {'padding': 'lg', 'background': surface}),
        box('Число', id: 'b', style: {'padding': 20, 'background': surface}),
      ]);

      expect(tester.getTopLeft(find.text('Токен')), const Offset(16, 16));
      final second = boxRect(tester, 'Число');
      expect(tester.getTopLeft(find.text('Число')) - second.topLeft, const Offset(20, 20));
      expect(second.height, tester.getSize(find.text('Число')).height + 40);
    });

    testWidgets('by sides: an unnamed side is zero', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'padding': {'top': 20, 'start': 'lg'},
          'background': surface,
        }),
      ]);

      final outer = boxRect(tester, 'Вміст');
      final inner = tester.getRect(find.text('Вміст'));
      expect(inner.left - outer.left, 16);
      expect(inner.top - outer.top, 20);
      expect(outer.right - inner.right, 0);
      expect(outer.bottom - inner.bottom, 0);
    });

    testWidgets('sides are LOGICAL: in right-to-left writing `start` is the right edge', (tester) async {
      final children = [
        box('نص', style: {
          'padding': {'start': 'xl', 'end': 'xs'},
          'background': surface,
          'width': 200,
        }),
      ];

      await pump(tester, children);
      var outer = boxRect(tester, 'نص');
      var inner = tester.getRect(find.text('نص'));
      expect(inner.left - outer.left, 24, reason: 'LTR: start on the left');

      await pump(tester, children, locale: 'ar');
      outer = boxRect(tester, 'نص');
      inner = tester.getRect(find.text('نص'));
      expect(outer.right - inner.right, 24, reason: 'RTL: start on the right');
      expect(inner.left - outer.left, greaterThanOrEqualTo(4), reason: 'RTL: end on the left');
    });
  });

  group('margin', () {
    testWidgets('lies OUTSIDE the box: the background does not reach it', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'margin': {'top': 'lg', 'start': 'md'},
          'padding': 'sm',
          'background': surface,
        }),
      ]);

      final outer = boxRect(tester, 'Вміст');
      expect(outer.topLeft, const Offset(12, 16));
      expect(tester.getTopLeft(find.text('Вміст')), const Offset(20, 24));
    });

    testWidgets('logical, like padding', (tester) async {
      await pump(tester, [
        box('نص', style: {
          'margin': {'start': 'xl'},
          'background': surface,
        }),
      ], locale: 'ar');

      // The screen is 800 wide: in RTL the box is pressed to the right, the margin is on the right.
      expect(boxRect(tester, 'نص').right, 800 - 24);
    });

    testWidgets('neighbours move apart by the margin', (tester) async {
      await pump(tester, [
        box('Перша', id: 'a', style: {'margin': {'bottom': 'xl'}}),
        box('Друга', id: 'b'),
      ]);

      final first = tester.getRect(find.text('Перша'));
      expect(tester.getTopLeft(find.text('Друга')).dy, first.bottom + 24);
    });
  });

  group('size', () {
    testWidgets('width and height - the exact size of the BOX, with margins and border', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'width': 120,
          'height': 80,
          'padding': 'md',
          'border': {'width': 2, 'color': 'border'},
          'background': surface,
        }),
      ]);

      expect(boxRect(tester, 'Вміст').size, const Size(120, 80));
      // The content starts after the border and padding: 2 + 12.
      expect(tester.getTopLeft(find.text('Вміст')), const Offset(14, 14));
    });

    testWidgets('minWidth / minHeight stretch, maxWidth shrinks', (tester) async {
      await pump(tester, [
        box('К', id: 'a', style: {'minWidth': 150, 'minHeight': 60, 'background': surface}),
        box(
          'Дуже довгий підпис, якому тісно в цій коробці',
          id: 'b',
          style: {'maxWidth': 100, 'background': surface},
        ),
      ]);

      // A column child is STRETCHED (`columnChildWidth`), and `minWidth` bounds the
      // stretched width from below: 150 < the screen width, so the box spans the whole row.
      // `minHeight` stretches the height, as before.
      expect(boxRect(tester, 'К').size, const Size(800, 60));
      // `maxWidth` bounds the stretched width from above; a box narrower than its parent
      // stands at the start (`constrainedStretch`).
      expect(boxRect(tester, 'Дуже довгий підпис, якому тісно в цій коробці').width, 100);
    });

    testWidgets('width is clamped between min and max', (tester) async {
      await pump(tester, [
        box('А', id: 'a', style: {'width': 50, 'minWidth': 90, 'background': surface}),
        box('Б', id: 'b', style: {'width': 300, 'maxWidth': 140, 'background': surface}),
      ]);

      expect(boxRect(tester, 'А').width, 90);
      expect(boxRect(tester, 'Б').width, 140);
    });

    testWidgets('invertedSizeRange: min-wins - min larger than max wins', (tester) async {
      // `BoxConstraints` in Flutter THROWS on `min > max`; CSS silently takes
      // the minimum. So both take the minimum.
      await pump(tester, [
        box('Вміст', style: {
          'minWidth': 200,
          'maxWidth': 100,
          'minHeight': 90,
          'maxHeight': 40,
          'background': surface,
        }),
      ]);

      expect(tester.takeException(), isNull);
      expect(boxRect(tester, 'Вміст').size, const Size(200, 90));
    });

    testWidgets('size from DATA; not a number or out of bounds - the fallback value', (tester) async {
      final children = [
        box('Стовпчик', style: {
          'height': {'kind': 'binding', 'path': 'rank.height', 'fallback': 60},
          'background': surface,
        }),
      ];

      await pump(tester, children, data: const {'rank': {'height': 90}});
      expect(boxRect(tester, 'Стовпчик').height, 90);

      // A string with a number is also a number: the backend often sends exactly that.
      await pump(tester, children, data: const {'rank': {'height': '75'}});
      expect(boxRect(tester, 'Стовпчик').height, 75);

      for (final broken in <Object?>[null, 'високо', -20, 0, 99999, double.nan, double.infinity]) {
        await pump(tester, children, data: {'rank': {'height': broken}});
        expect(tester.takeException(), isNull, reason: '$broken');
        expect(boxRect(tester, 'Стовпчик').height, 60, reason: '$broken -> fallback');
      }

      await pump(tester, children);
      expect(boxRect(tester, 'Стовпчик').height, 60, reason: 'no data');
    });

    testWidgets('content taller than the set height is clipped without a layout error', (tester) async {
      await pump(tester, [
        {
          'id': 'card',
          'type': 'Container',
          'props': {'gap': 'sm'},
          'style': {'height': 40, 'background': surface},
          'children': [
            textNode('Перший рядок', id: 'a'),
            textNode('Другий рядок', id: 'b'),
            textNode('Третій рядок', id: 'c'),
          ],
        },
        textNode('Після картки', id: 'after'),
      ]);

      expect(tester.takeException(), isNull);
      expect(boxRect(tester, 'Перший рядок').height, 40);
      // The neighbour stands right under the box, not under its overflowing content.
      expect(tester.getTopLeft(find.text('Після картки')).dy, 40);
    });

    testWidgets('a row still centres children across the whole set height', (tester) async {
      await pump(tester, [
        {
          'id': 'card',
          'type': 'Container',
          'props': {'direction': 'row', 'gap': 'none'},
          'style': {'height': 100, 'background': surface},
          'children': [textNode('По центру')],
        },
      ]);

      final label = tester.getRect(find.text('По центру'));
      expect(label.center.dy, closeTo(50, 0.5));
    });

    testWidgets('size acts on ANY widget, not only on a container', (tester) async {
      await pump(tester, [
        textNode('Напис', style: {'width': 160, 'height': 50, 'background': surface}),
        {
          'id': 'img',
          'type': 'Image',
          'props': {
            'source': {'kind': 'asset', 'asset': 'banner'},
            'aspectRatio': '1:1',
            'alt': 'Квадрат',
          },
          'style': {'width': 64},
        },
      ]);

      expect(boxRect(tester, 'Напис').size, const Size(160, 50));
      expect(tester.getSize(find.byType(ImageFrame)), const Size(64, 64));
    });
  });

  group('who sets the size: the node or the parent', () {
    Map<String, Object?> row(List<Map<String, Object?>> children, {Map<String, Object?> props = const {}}) => {
      'id': 'row',
      'type': 'Row',
      'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, ...props},
      'children': children,
    };

    testWidgets('a weight beats style.width; the height stays with the node', (tester) async {
      // `x-style.weightOverridesWidth`. A chart column: the width share is
      // from the row, the height from the style.
      await pump(tester, [
        row([
          box('А', id: 'a', weight: 3, style: {'width': 40, 'height': 70, 'background': surface}),
          box('Б', id: 'b', weight: 1, style: {'maxWidth': 10, 'background': surface}),
        ]),
      ]);

      expect(boxRect(tester, 'А').size, const Size(600, 70));
      expect(boxRect(tester, 'Б').width, 200);
    });

    testWidgets('a child without a weight takes its style.width, the weight divides the remainder', (tester) async {
      await pump(tester, [
        row([
          box('Своя', id: 'a', style: {'width': 200, 'background': surface}),
          box('Решта', id: 'b', weight: 1, style: {'background': surface}),
        ]),
      ]);

      expect(boxRect(tester, 'Своя').width, 200);
      // "A child without a weight divides nothing: it takes its natural width, and the shares
      // divide the REMAINDER". Previously a child without a weight sat in `Flexible(loose)` and
      // took a whole share out of the split, so its neighbour got 400, not 600.
      expect(boxRect(tester, 'Решта').width, 600);
    });

    testWidgets('a weighted child subtracts the margin from its share', (tester) async {
      await pump(tester, [
        row([
          box('А', id: 'a', weight: 1, style: {'margin': {'end': 'xl'}, 'background': surface}),
          box('Б', id: 'b', weight: 1, style: {'background': surface}),
        ]),
      ]);

      expect(boxRect(tester, 'А').width, 400 - 24);
      expect(boxRect(tester, 'Б').left, 400);
    });

    testWidgets('a layer stretched over the stack takes the stack size, not its own', (tester) async {
      await pump(tester, [
        {
          'id': 'stack',
          'type': 'Stack',
          'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
          'children': [
            box('Основа', id: 'base', style: {'height': 120}),
            box('Шар', id: 'layer', fill: true, style: {'width': 10, 'height': 10, 'background': surface}),
          ],
        },
      ]);

      expect(boxRect(tester, 'Шар').size, const Size(800, 120));
    });

    testWidgets('a stack where ALL layers are stretched does not crash the screen', (tester) async {
      // There is nothing to measure such a stack with; the builder rejects it, but the document
      // could have been built by something else. In Flutter this is infinite height in a scroll.
      await pump(tester, [
        {
          'id': 'stack',
          'type': 'Stack',
          'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
          'children': [
            box('Перший', id: 'a', fill: true, style: {'background': surface}),
            box('Другий', id: 'b', fill: true),
          ],
        },
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('Перший'), findsOneWidget);
      expect(find.text('Другий'), findsOneWidget);
    });

    testWidgets('in a grid cell style.width acts, and the node stands at the START of the cell', (tester) async {
      final children = [
        {
          'id': 'grid',
          'type': 'Grid',
          'props': {'columns': 2, 'gap': 'none'},
          'children': [
            box('Вузька', id: 'a', style: {'width': 100, 'background': surface}),
            box('Повна', id: 'b', style: {'background': surface}),
          ],
        },
      ];

      await pump(tester, children);
      expect(boxRect(tester, 'Вузька'), const Rect.fromLTWH(0, 0, 100, 20));
      // A cell without a set width - as it was: the full column width.
      expect(boxRect(tester, 'Повна').left, 400);

      await pump(tester, children, locale: 'ar');
      expect(boxRect(tester, 'Вузька').right, 800, reason: 'RTL: the cell start is on the right');
    });

    testWidgets('a set height alone does NOT relax the width', (tester) async {
      // Exactly the axis the style said something about is relaxed: a chart column
      // with a weight and a height stays at its whole width share.
      await pump(tester, [
        {
          'id': 'grid',
          'type': 'Grid',
          'props': {'columns': 2, 'gap': 'none'},
          'children': [
            box('Висока', id: 'a', style: {'height': 90, 'background': surface}),
          ],
        },
      ]);

      expect(boxRect(tester, 'Висока').size.height, 90);
      // A container in a cell takes the content width (as without a style), but the cell
      // neither shrinks nor stretches it differently than without a height.
      await pump(tester, [
        {
          'id': 'grid',
          'type': 'Grid',
          'props': {'columns': 2, 'gap': 'none'},
          'children': [
            box('Висока', id: 'a', style: {'background': surface}),
          ],
        },
      ]);
      final without = boxRect(tester, 'Висока').width;
      await pump(tester, [
        {
          'id': 'grid',
          'type': 'Grid',
          'props': {'columns': 2, 'gap': 'none'},
          'children': [
            box('Висока', id: 'a', style: {'height': 90, 'background': surface}),
          ],
        },
      ]);
      expect(boxRect(tester, 'Висока').width, without);
    });
  });

  group('radius', () {
    testWidgets('clips the background AND the content; the shadow lies outside the clip', (tester) async {
      await pump(tester, [
        box('Вміст', style: {'radius': 24, 'background': surface, 'shadow': 'low'}),
      ]);

      final decoration = nodeDecoration(tester, 'Вміст');
      expect(decoration.borderRadius, const BorderRadiusDirectional.all(Radius.circular(24)));
      final clip = nearest<ClipRRect>(tester, 'Вміст')!;
      expect(clip.borderRadius, decoration.borderRadius);
      // The clip is a DESCENDANT of the decorated box: otherwise the shadow would vanish together
      // with what is beyond the edge.
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Вміст'), matching: find.byType(DecoratedBox)).first,
          matching: find.byType(ClipRRect),
        ),
        findsOneWidget,
      );
      expect(decoration.boxShadow, isNotEmpty);
    });

    testWidgets('the radius clips a background image too', (tester) async {
      await pump(tester, [
        box('Фото', style: {
          'radius': 'lg',
          'padding': 'lg',
          'background': {
            'kind': 'image',
            'source': {'kind': 'asset', 'asset': 'banner'},
            'fit': 'cover',
          },
        }),
      ]);

      final clip = find.ancestor(of: find.text('Фото'), matching: find.byType(ClipRRect)).first;
      expect(
        find.descendant(of: clip, matching: find.byType(Positioned)),
        findsOneWidget,
        reason: 'the image layer lies UNDER the clip',
      );
    });

    testWidgets('per corner: logical, mirrored in RTL', (tester) async {
      final children = [
        box('Вміст', style: {
          'radius': {'topStart': 24, 'bottomEnd': 'sm'},
          'background': surface,
        }),
      ];

      await pump(tester, children);
      final radius = nodeDecoration(tester, 'Вміст').borderRadius!;
      expect(
        radius,
        const BorderRadiusDirectional.only(
          topStart: Radius.circular(24),
          bottomEnd: Radius.circular(8),
        ),
      );
      expect(radius.resolve(TextDirection.ltr).topLeft, const Radius.circular(24));

      await pump(tester, children, locale: 'ar');
      expect(tester.takeException(), isNull);
      final context = tester.element(find.text('Вміст'));
      expect(
        nodeDecoration(tester, 'Вміст').borderRadius!.resolve(Directionality.of(context)).topRight,
        const Radius.circular(24),
      );
    });

    testWidgets('a radius larger than half the box does not break drawing', (tester) async {
      await pump(tester, [
        box('Пігулка', style: {'radius': 'pill', 'padding': 'xs', 'background': surface}),
        box('Найбільший', id: 'b', style: {'radius': 256, 'height': 4, 'background': surface}),
      ]);

      expect(tester.takeException(), isNull);
    });
  });

  group('border', () {
    testWidgets('thickness and colour; the border eats layout pixels', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'border': {'width': 3, 'color': {'token': 'primary', 'opacity': 0.5}},
        }),
      ]);

      final border = nodeDecoration(tester, 'Вміст').border! as Border;
      expect(border.top.width, 3);
      expect(border.top.color, theme.color(ColorToken.primary).withValues(alpha: 0.5));
      expect(border.isUniform, isTrue);
      expect(tester.getTopLeft(find.text('Вміст')), const Offset(3, 3));
    });

    testWidgets('an equal border with DIFFERENT corner radii is drawn without an exception', (tester) async {
      // A different side thickness with rounding is not drawn in Flutter - which is why
      // the contract has no such shape. But an equal thickness with different corners
      // exists, and it must simply work.
      await pump(tester, [
        box('Вміст', style: {
          'border': {'width': 4, 'color': 'primary'},
          'radius': {'topStart': 32, 'topEnd': 0, 'bottomEnd': 'pill', 'bottomStart': 4},
          'padding': 'lg',
          'background': surface,
          'shadow': 'medium',
        }),
      ]);

      expect(tester.takeException(), isNull);
      expect(nodeDecoration(tester, 'Вміст').border, isNotNull);
    });

    testWidgets('hairline border (0.5) and the thickest (16)', (tester) async {
      await pump(tester, [
        box('Тонка', id: 'a', style: {'border': {'width': 0.5, 'color': 'border'}}),
        box('Товста', id: 'b', style: {'border': {'width': 16, 'color': 'border'}}),
      ]);

      expect(tester.takeException(), isNull);
      expect((nodeDecoration(tester, 'Тонка').border! as Border).top.width, 0.5);
      expect((nodeDecoration(tester, 'Товста').border! as Border).top.width, 16);
    });

    testWidgets('the border over a background image, not under it', (tester) async {
      await pump(tester, [
        box('Фото', style: {
          'border': {'width': 2, 'color': 'primary'},
          'background': {
            'kind': 'image',
            'source': {'kind': 'asset', 'asset': 'banner'},
            'fit': 'cover',
          },
        }),
      ]);

      final framed = tester.widget<DecoratedBox>(
        find.ancestor(of: find.text('Фото'), matching: find.byType(DecoratedBox)).first,
      );
      expect(framed.position, DecorationPosition.foreground);
      expect((framed.decoration as BoxDecoration).border, isNotNull);
    });
  });

  group('shadow', () {
    testWidgets('shadow token', (tester) async {
      await pump(tester, [box('Вміст', style: {'shadow': 'medium', 'background': surface})]);

      expect(nodeDecoration(tester, 'Вміст').boxShadow, theme.elevation(ElevationToken.medium));
    });

    testWidgets('an own shadow of several layers - drawn without a background too', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'shadow': [
            {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0, 'color': {'token': 'onSurface', 'opacity': 0.1}},
            {'offsetX': 0, 'offsetY': 16, 'blur': 32, 'spread': -8, 'color': {'value': '#000000', 'opacity': 0.2}},
          ],
        }),
      ]);

      final shadows = nodeDecoration(tester, 'Вміст').boxShadow!;
      expect(shadows, hasLength(2));
      expect(shadows.first.blurRadius, 32, reason: 'the first contract layer is drawn last');
      expect(shadows.last.blurRadius, 2);
    });

    testWidgets('token `none` - no shadow, and no extra decoration either', (tester) async {
      await pump(tester, [box('Вміст', style: {'shadow': 'none'})]);

      expect(find.ancestor(of: find.text('Вміст'), matching: find.byType(DecoratedBox)), findsNothing);
    });
  });

  group('opacity', () {
    testWidgets('acts on the WHOLE box - with background, border, shadow and content', (tester) async {
      await pump(tester, [
        box('Вміст', style: {'opacity': 0.4, 'background': surface, 'shadow': 'low', 'margin': 'md'}),
      ]);

      final opacity = nearest<Opacity>(tester, 'Вміст')!;
      expect(opacity.opacity, 0.4);
      // The decoration (with the shadow) is a DESCENDANT of the opacity...
      expect(
        find.descendant(of: find.byWidget(opacity), matching: find.byType(DecoratedBox)),
        findsOneWidget,
      );
      // ...and the margin is outside: it is not a box, there is nothing to paint in it.
      expect(tester.getTopLeft(find.byWidget(opacity)), const Offset(12, 12));
    });

    testWidgets('zero is legal: the node is invisible, but it takes its place', (tester) async {
      await pump(tester, [
        box('Невидимий', id: 'a', style: {'opacity': 0, 'height': 50}),
        box('Сусід', id: 'b'),
      ]);

      expect(tester.takeException(), isNull);
      expect(nearest<Opacity>(tester, 'Невидимий')!.opacity, 0);
      expect(tester.getTopLeft(find.text('Сусід')).dy, 50);
    });

    testWidgets('one wraps nothing', (tester) async {
      await pump(tester, [box('Вміст', style: {'opacity': 1, 'padding': 'sm'})]);

      expect(nearest<Opacity>(tester, 'Вміст'), isNull);
    });
  });

  group('a token the theme does not declare: the property is not applied', () {
    testWidgets('each field separately - and the rest of the style stays', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'padding': 'spaceFromFuture',
          'margin': 'spaceFromFuture',
          'radius': 'radiusFromFuture',
          'shadow': 'shadowFromFuture',
          'border': {'width': 2, 'color': 'colorFromFuture'},
          'background': {'kind': 'color', 'color': 'colorFromFuture'},
          'width': 120,
        }),
      ]);

      expect(tester.takeException(), isNull);
      // None of the six drew anything: neither a "similar" colour nor a border
      // without a colour (a transparent border would eat pixels).
      expect(find.ancestor(of: find.text('Вміст'), matching: find.byType(DecoratedBox)), findsNothing);
      expect(nearest<Padding>(tester, 'Вміст'), isNull);
      expect(nearest<ClipRRect>(tester, 'Вміст'), isNull);
      expect(tester.getTopLeft(find.text('Вміст')), Offset.zero);
      // And the neighbouring field, which needs no token, acts.
      expect(tester.getSize(find.text('Вміст')).width, lessThanOrEqualTo(120));
    });

    testWidgets('an unknown token in ONE side - it is zero, the rest acts', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'padding': {'top': 'spaceFromFuture', 'start': 'lg'},
          'radius': {'topStart': 'radiusFromFuture', 'bottomEnd': 'md'},
          'background': surface,
        }),
      ]);

      expect(tester.getTopLeft(find.text('Вміст')), const Offset(16, 0));
      expect(
        nodeDecoration(tester, 'Вміст').borderRadius,
        const BorderRadiusDirectional.only(bottomEnd: Radius.circular(12)),
      );
    });

    testWidgets('a gradient and a shadow with an unknown token are not drawn WHOLE', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'background': {
            'kind': 'gradient',
            'gradient': {
              'angle': 90,
              'stops': [
                {'color': 'primary', 'position': 0},
                {'color': 'colorFromFuture', 'position': 1},
              ],
            },
          },
          'shadow': [
            {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0, 'color': 'onSurface'},
            {'offsetX': 0, 'offsetY': 4, 'blur': 8, 'spread': 0, 'color': 'colorFromFuture'},
          ],
        }),
      ]);

      expect(find.ancestor(of: find.text('Вміст'), matching: find.byType(DecoratedBox)), findsNothing);
    });

    testWidgets('an unordered own gradient - `omit-field`', (tester) async {
      await pump(tester, [
        box('Вміст', style: {
          'padding': 'sm',
          'background': {
            'kind': 'gradient',
            'gradient': {
              'angle': 90,
              'stops': [
                {'color': 'primary', 'position': 1},
                {'color': 'accent', 'position': 0},
              ],
            },
          },
        }),
      ]);

      expect(nodeDecoration(tester, 'Вміст').gradient, isNull);
      expect(nodePadding(tester, 'Вміст'), const EdgeInsetsDirectional.all(8));
    });
  });

  group('screen and scrollable row: padding is inside the scroll', () {
    testWidgets('screen padding scrolls together with the content', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(
          [textNode('Вміст')],
          style: {
            'padding': {'top': 'xl', 'start': 'lg'},
            'background': surface,
          },
        ),
      );

      final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first);
      expect(scroll.padding, const EdgeInsetsDirectional.only(top: 24, start: 16));
      expect(tester.getTopLeft(find.text('Вміст')), const Offset(16, 24));
      // The background is under the whole screen area, not under the content.
      expect(tester.getSize(find.byType(DecoratedBox).last), const Size(800, 600));
    });

    testWidgets('`margin` in a screen state (`styleWhen`) is ignored too', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(
          [textNode('Вміст')],
          style: {'background': surface},
          styleWhen: [
            {
              'when': {'path': 'user.vip', 'op': 'isEmpty'},
              'style': {'margin': 'xl', 'height': 50},
            },
          ],
        ),
      );

      expect(tester.getTopLeft(find.text('Вміст')), Offset.zero);
      expect(tester.getSize(find.byType(DecoratedBox).last), const Size(800, 600));
    });

    testWidgets('sizes on the screen do not act: it takes the place the host gave', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(
          [textNode('Вміст')],
          style: {'width': 100, 'height': 100, 'maxWidth': 50, 'background': surface},
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DecoratedBox).last), const Size(800, 600));
    });

    testWidgets('`margin` on the screen is ignored, the rest of the box works: border, opacity', (tester) async {
      // `screenBoxFields: 'ignore'` (contract 9): the space around the screen root
      // belongs to the host. This test used to expect `margin: md` to push the
      // content by 12 dp; now the content starts right after the border.
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(
          [textNode('Вміст')],
          style: {
            'margin': 'md',
            'opacity': 0.9,
            'border': {'width': 2, 'color': 'border'},
            'radius': 'lg',
            'background': surface,
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Вміст')), const Offset(2, 2));
      expect(find.byType(Opacity), findsOneWidget);
    });

    testWidgets('padding of a scrollable row is a scroll parameter, not a wrapper', (tester) async {
      await pump(tester, [
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'center', 'justify': 'start', 'wrap': false, 'scrollable': true},
          'style': {'padding': 'lg', 'background': surface},
          'children': [textNode('Перша', id: 'a'), textNode('Друга', id: 'b')],
        },
      ]);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byWidgetPredicate(
          (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(scroll.padding, const EdgeInsetsDirectional.all(16));
      expect(tester.getTopLeft(find.text('Перша')), const Offset(16, 16));
    });
  });

  group('an unknown widget with a style', () {
    testWidgets('the style is ignored, children are drawn in the PARENT context', (tester) async {
      await pump(tester, [
        {
          'id': 'parent',
          'type': 'Container',
          'props': {'gap': 'none'},
          'style': {'color': 'success'},
          'children': [
            {
              'id': 'chart',
              'type': 'Chart',
              'props': <String, Object?>{},
              'style': {
                'color': 'danger',
                'typography': 'displayL',
                'padding': 'xl',
                'opacity': 0.1,
                'height': 10,
                'background': {'kind': 'color', 'color': 'accent'},
              },
              'children': [textNode('Усередині чужого')],
            },
          ],
        },
      ]);

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text('Усередині чужого'));
      // Colour and font are the parent own, not named by the unknown node.
      expect(text.style!.color, theme.color(ColorToken.success));
      expect(text.style!.fontSize, theme.text(TypographyToken.bodyM).fontSize);
      expect(find.byType(Opacity), findsNothing);
      // No `accent` colour box around the foreign node.
      final painted = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((widget) => (widget.decoration as BoxDecoration).color);
      expect(painted, isNot(contains(theme.color(ColorToken.accent))));
    });
  });
}
