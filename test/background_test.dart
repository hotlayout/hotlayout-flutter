import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/svg_image.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Node background -- a union `{kind, ...}` in `style.background`.
///
/// The union appeared in 7.0.0 as `props.background` of three widgets (`Screen`,
/// `Container`, `AppBar`), and this file guarded its bounds. Since 9.0.0 the background is a field
/// of the SHARED style: every node has it, it has a third branch (image), and
/// it has NO default anywhere. So half of the old assertions flipped: where an
/// unusable background used to "fall back to the schema default", there is now simply none.
void main() {
  NodeBackground? backgroundOf(UiNode node) => node.style?.background;

  group('union branches reach the model', () {
    test('kind: color -- a color reference', () {
      final root = rootOf(docWith(const [], background: colorBackground('secondary')));

      expect(backgroundOf(root), const ColorBackground(ColorRef.token('secondary')));
    });

    test('kind: gradient -- a gradient token, not a color', () {
      final root = rootOf(docWith(const [], background: gradientBackground()));

      expect(backgroundOf(root), const GradientBackground(TokenGradientRef('brandBackdrop')));
    });

    test('any node has the same background as the screen, not only Container', () {
      final nodes = flattenDocument(
        docWith([
          {
            'id': 'card',
            'type': 'Container',
            'props': {'gap': 'none'},
            'style': {'background': gradientBackground()},
            'children': const <Map<String, Object?>>[],
          },
          textNode('Напис', style: {'background': gradientBackground()}),
          {
            'id': 'row',
            'type': 'Row',
            'props': {'gap': 'none', 'align': 'center', 'justify': 'start', 'wrap': false},
            'style': {'background': gradientBackground()},
            'children': const <Map<String, Object?>>[],
          },
        ]),
      ).whereType<ChildNode>();

      expect(nodes, hasLength(3));
      for (final node in nodes) {
        expect(
          backgroundOf(node),
          const GradientBackground(TokenGradientRef('brandBackdrop')),
          reason: contractType(node),
        );
      }
    });

    test('a node without a background is `null`, not "color surface"', () {
      // Before 9.0.0 this was true only for the bar. Now for every node:
      // the reader has no hidden defaults, and the usual look is written by the builder.
      final nodes = flattenDocument(
        docWith([
          appBarNode('Без тла', background: null),
          {
            'id': 'card',
            'type': 'Container',
            'props': {'gap': 'none'},
            'children': const <Map<String, Object?>>[],
          },
        ]),
      ).whereType<ChildNode>();

      for (final node in nodes) {
        expect(node.style, isNull, reason: contractType(node));
      }
    });

    test('an unusable background is read as ABSENT -- there is no default any more', () {
      // Before 9.0.0 this test asserted the opposite: in `Screen` and `Container`
      // an unusable background fell back to the schema default (`surface`). The schema
      // has no default by construction (`x-style.hiddenDefaults: 'none'`), and
      // the reader has no right to invent one: a white rectangle where the document
      // said something unintelligible would look intended.
      const broken = <Object?>[
        null,
        'surface', // 6.x form: a token string
        {'kind': 'сяйво'}, // unknown kind -- the field is not applied
        {'kind': 'color'}, // branch without a value
        {'kind': 'color', 'color': '#ffffff'}, // raw hex instead of a reference
        {'kind': 'gradient'},
        {'kind': 'image'}, // image without a source
        42,
      ];
      for (final value in broken) {
        expect(NodeBackground.tryParse(value), isNull, reason: '$value');
      }
    });

    test('a gradient with its own name is a legal reference, not "unknown"', () {
      // Before 9.0.0 `sunset` was rejected during parsing: the gradient list
      // was closed. Now the theme declares the names, and parsing does not judge them.
      expect(
        NodeBackground.tryParse({'kind': 'gradient', 'gradient': 'sunset'}),
        const GradientBackground(TokenGradientRef('sunset')),
      );
    });

    testWidgets('a document of an old major with a string background does not break parsing', (tester) async {
      // The renderer will not let such a document through to display -- another major. But
      // the PARSER must reach the end in any case: the verdict on the version is
      // a separate decision, not a consequence of an exception in parsing.
      final doc = docWith([
        {
          'id': 'card',
          'type': 'Container',
          'props': {
            'padding': 'md',
            'gap': 'none',
            'radius': 'lg',
            'background': 'secondary',
            'elevation': 'low',
          },
          'children': const <Map<String, Object?>>[],
        },
      ], schemaVersion: '6.1.0');

      expect(doc.isSupportedVersion, isFalse);
      final card = flattenDocument(doc).whereType<ContainerNode>().single;
      expect(card.style, isNull);

      await pumpDocument(tester, doc);
      // A document of an OLDER major: the notice is neutral. It used to say
      // "Please update the app" -- advice that does not help such a document;
      // the assertion was flipped together with the decision (see `navigation_test.dart`).
      expect(find.text('This screen is not available right now.'), findsOneWidget);
      expect(find.textContaining('pdate the app'), findsNothing);
    });
  });

  group('the background reaches the pixels', () {
    testWidgets('a screen gradient is drawn as a gradient, not as a color', (tester) async {
      final theme = RenderTheme.fallback();
      await pumpDocument(
        tester,
        docWith([textNode('Вміст')], background: gradientBackground()),
        theme: theme,
      );

      final decoration = screenDecoration(tester);
      expect(decoration.color, isNull, reason: 'a gradient is not reduced to a color');
      expect(decoration.gradient, theme.gradient(GradientToken.brandBackdrop));
      expect(
        (decoration.gradient! as LinearGradient).colors,
        [const Color(0xFFEEF2FF), const Color(0xFFF0F9FF)],
      );
    });

    testWidgets('a screen color stays a color', (tester) async {
      final theme = RenderTheme.fallback();
      await pumpDocument(
        tester,
        docWith([textNode('Вміст')], background: colorBackground('secondary')),
        theme: theme,
      );

      final decoration = screenDecoration(tester);
      expect(decoration.color, theme.color(ColorToken.secondary));
      expect(decoration.gradient, isNull);
    });

    testWidgets('a background with an own value and with a token tint', (tester) async {
      final theme = RenderTheme.fallback();
      await pumpDocument(
        tester,
        docWith([
          textNode('Власне', id: 'a', style: {
            'background': {
              'kind': 'color',
              'color': {'value': '#ff7a59', 'opacity': 0.5},
            },
          }),
          textNode('Відтінок', id: 'b', style: {
            'background': {
              'kind': 'color',
              'color': {'token': 'primary', 'opacity': 0.1},
            },
          }),
        ]),
        theme: theme,
      );

      expect(nodeDecoration(tester, 'Власне').color, const Color(0xFFFF7A59).withValues(alpha: 0.5));
      expect(
        nodeDecoration(tester, 'Відтінок').color,
        theme.color(ColorToken.primary).withValues(alpha: 0.1),
      );
    });

    testWidgets('an own gradient from two brand tokens', (tester) async {
      final theme = RenderTheme.fallback();
      await pumpDocument(
        tester,
        docWith([
          textNode('Градієнт', style: {
            'background': {
              'kind': 'gradient',
              'gradient': {
                'angle': 180,
                'stops': [
                  {'color': 'primary', 'position': 0},
                  {'color': {'token': 'accent', 'opacity': 0.5}, 'position': 1},
                ],
              },
            },
          }),
        ]),
        theme: theme,
      );

      final gradient = nodeDecoration(tester, 'Градієнт').gradient! as LinearGradient;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors, [
        theme.color(ColorToken.primary),
        theme.color(ColorToken.accent).withValues(alpha: 0.5),
      ]);
      expect(gradient.stops, [0, 1]);
    });

    testWidgets('image background: a layer UNDER the content, with the same source as Image', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          textNode('Поверх фото', id: 'a', style: {
            'padding': 'lg',
            'background': {
              'kind': 'image',
              'source': {'kind': 'url', 'url': 'https://cdn.example.com/bg.png'},
              'fit': 'contain',
            },
          }),
          textNode('Поверх вектора', id: 'b', style: {
            'background': {
              'kind': 'image',
              'source': {'kind': 'url', 'url': 'https://cdn.example.com/bg.svg'},
              'fit': 'cover',
            },
          }),
        ]),
      );

      final image = tester.widget<Image>(
        find.descendant(
          of: find.ancestor(of: find.text('Поверх фото'), matching: find.byType(Stack)).first,
          matching: find.byType(Image),
        ),
      );
      expect((image.image as NetworkImage).url, 'https://cdn.example.com/bg.png');
      expect(image.fit, BoxFit.contain);
      // The image fills the whole node box -- with padding, not only under
      // the text.
      final layer = tester.getRect(
        find.ancestor(of: find.byWidget(image), matching: find.byType(Positioned)).first,
      );
      final label = tester.getRect(find.text('Поверх фото'));
      expect(layer.width, label.width + 32);
      expect(layer.height, label.height + 32);
      // SVG -- the same source, another decoder: a branch shared with the Image widget.
      expect(find.byType(NetworkSvg), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar without a background is transparent -- the screen gradient reaches the top', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          appBarNode('Прозора', background: null),
          textNode('Вміст'),
        ], background: gradientBackground()),
      );

      final bar = appBarDecoration(tester, 'Прозора');
      // The bar draws nothing, so what is under it shows: the screen background with its
      // gradient.
      expect(bar.color, isNull);
      expect(bar.gradient, isNull);
      expect(screenDecoration(tester).gradient, isNotNull);
    });

    testWidgets('a bar with a background draws its own', (tester) async {
      final theme = RenderTheme.fallback();
      await pumpDocument(
        tester,
        docWith([
          appBarNode('Непрозора', background: colorBackground()),
          textNode('Вміст'),
        ], background: gradientBackground()),
        theme: theme,
      );

      final bar = appBarDecoration(tester, 'Непрозора');
      expect(bar.color, theme.color(ColorToken.surface));
      expect(bar.gradient, isNull);
    });

    testWidgets('a screen WITHOUT style draws neither background nor padding', (tester) async {
      // The most visible consequence of "no hidden defaults": before 9.0.0 a screen without
      // padding had the `surface` background and `md` padding.
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([textNode('Вміст')]),
      );

      final decoration = screenDecoration(tester);
      expect(decoration.color, isNull);
      expect(decoration.gradient, isNull);
      expect(tester.getTopLeft(find.text('Вміст')), Offset.zero);
    });

    testWidgets('a gradient the theme does not declare is simply not drawn', (tester) async {
      // `tokenWithoutFieldDefault: 'omit-field'`. The node stays in place and
      // stays transparent -- the screen does not vanish over one theme value.
      // The gradient is a project-own name absent from every theme. The core
      // (`brandBackdrop`) does not fit here: a missing core gradient is
      // filled in by the theme from the built-in one (`partialThemeDefaults`), so "absent" applies
      // only to names outside the core.
      final withoutGradients = RenderTheme.fromJson({
        'id': 'без-градієнтів',
        'color': {'surface': '#ffffff', 'onSurface': '#000000'},
        'roles': {
          'badgeTone': {
            'neutral': {'background': 'secondary', 'foreground': 'onSurface'},
          },
          'buttonVariant': {
            'primary': {'background': 'primary', 'foreground': 'onPrimary'},
          },
        },
      });

      await pumpDocument(
        tester,
        docWith([textNode('Вміст')], background: gradientBackground('sunsetFromNowhere')),
        theme: withoutGradients,
      );

      final decoration = screenDecoration(tester);
      expect(decoration.gradient, isNull);
      expect(decoration.color, isNull);
      expect(find.text('Вміст'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a background color the theme does not declare is not replaced by a "similar" one', (tester) async {
      await pumpDocument(
        tester,
        docWith([textNode('Вміст')], background: colorBackground('brandCoral')),
      );

      expect(screenDecoration(tester).color, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('demo document', () {
    test('the details screen is a gradient, and the bar on it has no background of its own', () {
      // This is not "one more fixture": exactly this pair (gradient + transparent bar) is
      // what 7.0.0 changed the field shape for. If the document changes so
      // that the pair is gone, a test should say so, not a demo.
      final doc = loadFixture('reward-catalog-screens');
      final details = doc.screenById('item-details')!.root as ScreenNode;

      expect(backgroundOf(details), const GradientBackground(TokenGradientRef('brandBackdrop')));
      final bar = details.children.whereType<AppBarNode>().single;
      expect(backgroundOf(bar), isNull);
    });

    test('the catalog screen is a solid color and a bar with its own background', () {
      final doc = loadFixture('reward-catalog-screens');
      final catalog = doc.screenById('catalog')!.root as ScreenNode;

      expect(backgroundOf(catalog), const ColorBackground(ColorRef.token('secondary')));
      final bar = catalog.children.whereType<AppBarNode>().single;
      expect(backgroundOf(bar), const ColorBackground(ColorRef.token('surface')));
    });

    test('no background in the fixtures stayed in props or lost its shape', () {
      // A sync guard, on RAW JSON: a background of the wrong shape is silently read
      // by the model as absent, so it is invisible on the parsed tree -- but
      // visible on screen, and already at display.
      for (final id in fixtureIds) {
        final backgrounds = rawBackgrounds(jsonFixture(id)).toList();
        for (final background in backgrounds) {
          expect(
            background,
            isA<Map<Object?, Object?>>(),
            reason: '$id: background in the pre-7.0.0 shape',
          );
          expect(
            (background as Map<Object?, Object?>)['kind'],
            anyOf('color', 'gradient', 'image'),
            reason: '$id: foreign kind',
          );
          expect(NodeBackground.tryParse(background), isNotNull, reason: id);
        }
        // Every raw background reached the parsed tree -- i.e. none
        // stayed in `props`, where the model no longer looks for it.
        final parsed = flattenDocument(loadFixture(id)).expand(
          (node) => [
            if (node.style?.background != null) node.style!.background,
            for (final entry in node.styleWhen)
              if (entry.style.background != null) entry.style.background,
          ],
        );
        expect(parsed.length, backgrounds.length, reason: '$id: a background got lost on the way');
        // Backgrounds in width layers have the same shape, and the layer really replaces the background in the resolved tree.
        for (final background in rawLayerBackgrounds(jsonFixture(id))) {
          expect(NodeBackground.tryParse(background), isNotNull, reason: '$id: width layer background');
        }
      }
    });
  });
}
