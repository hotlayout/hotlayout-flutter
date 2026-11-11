/// THE INNER SHADOW AND THE SHADOW OF A TEXT (schema 9.39.0): the shared table
/// `assets/contract/fixtures/shadow-effects/shadow-effects-cases.json`, every row run, and the frame
/// `shadow-effects-screens`.
///
///  * `insetCases.css` -- the layers a reader gets from the list (their order, the flag, the numbers), as the CSS of the
///    row says them;
///  * `insetCases.geometry` -- the clip and the hole of an inner layer, to 1e-6;
///  * `insetCases.document` and `insetCases.themeElevation` -- what the reader does with each document row;
///  * `textShadowCases` -- the layers of `TextStyle.shadows`, bottom first, and which widgets read the field;
///  * the frame -- inner layers inside boxes, shadows of glyphs, the copy under a gradient heading.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/render/inner_shadow.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table =
    jsonDecode(File('assets/contract/fixtures/shadow-effects/shadow-effects-cases.json').readAsStringSync()) as _Json;

_Json get _inset => _table['insetCases']! as _Json;
_Json get _text => _table['textShadowCases']! as _Json;

List<_Json> _rows(_Json group, String key) => (group[key]! as List<Object?>).cast<_Json>();

double _n(Object? value) => (value! as num).toDouble();

/// Colours of the CSS rows are own hex values without opacity.
Color _hex(String text) => Color(0xFF000000 | int.parse(text.substring(1), radix: 16));

/// One layer of a CSS list: `[inset] x y blur [spread] #rrggbb`, `px` and the zero spread as the table writes them.
typedef _Css = ({bool inset, double x, double y, double blur, double spread, Color color});

List<_Css> _parseCss(String css) => [
  for (final layer in css.split(', '))
    () {
      final parts = layer.split(' ');
      final inset = parts.first == 'inset';
      final numbers = [
        for (final part in parts.skip(inset ? 1 : 0).takeWhile((part) => !part.startsWith('#')))
          double.parse(part.replaceAll('px', '')),
      ];
      return (
        inset: inset,
        x: numbers[0],
        y: numbers[1],
        blur: numbers[2],
        spread: numbers.length > 3 ? numbers[3] : 0.0,
        color: _hex(parts.last),
      );
    }(),
];

Map<String, Object?> _boxWith(Object? shadow, {Map<String, Object?> extra = const {}}) => {
  'id': 'n',
  'type': 'Container',
  'props': {'gap': 'none'},
  'style': {'shadow': shadow, ...extra},
  'children': [textNode('in', id: 'inner')],
};

/// The painter of the inner layers of the node, if it has one.
InnerShadowPainter? _painterOf(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final painter = paint.painter;
    if (painter is InnerShadowPainter) return painter;
  }
  return null;
}

void main() {
  final theme = RenderTheme.fallback();

  test('the table has its groups, every row with a unique name', () {
    for (final (group, key) in [
      (_inset, 'css'),
      (_inset, 'geometry'),
      (_inset, 'document'),
      (_inset, 'themeElevation'),
      (_text, 'css'),
      (_text, 'document'),
    ]) {
      final rows = _rows(group, key);
      expect(rows.length, greaterThan(1), reason: key);
      expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: key);
    }
  });

  group('insetCases.css -- the layers the reader gets', () {
    for (final row in _rows(_inset, 'css')) {
      test(row['name']! as String, () {
        final layers = _parseCss(row['css']! as String);
        // The numbers of the CSS row are the numbers of the layers of the document.
        final documentLayers = _rows(row, 'layers');
        expect(layers, hasLength(documentLayers.length));
        for (final (index, layer) in documentLayers.indexed) {
          expect((layer['inset'] == true), layers[index].inset);
          expect(_n(layer['offsetX']), layers[index].x);
          expect(_n(layer['offsetY']), layers[index].y);
          expect(_n(layer['blur']), layers[index].blur);
          expect(_n(layer['spread']), layers[index].spread);
        }

        final ref = ShadowRef.tryParse(documentLayers)!;
        final outer = theme.resolveShadow(ref)!;
        final inner = theme.resolveInnerShadow(ref);
        // The first layer of the document is the nearest and on top: both lists are in PAINT order, the last first.
        final expectedOuter = [for (final layer in layers.where((layer) => !layer.inset)) layer].reversed.toList();
        final expectedInner = [for (final layer in layers.where((layer) => layer.inset)) layer].reversed.toList();
        expect(outer, hasLength(expectedOuter.length));
        for (final (index, shadow) in outer.indexed) {
          final want = expectedOuter[index];
          expect(
            (shadow.offset, shadow.blurRadius, shadow.spreadRadius, shadow.color),
            (Offset(want.x, want.y), want.blur, want.spread, want.color),
          );
        }
        expect(inner, hasLength(expectedInner.length));
        for (final (index, shadow) in inner.indexed) {
          final want = expectedInner[index];
          expect(
            (shadow.offset, shadow.blurRadius, shadow.spreadRadius, shadow.color),
            (Offset(want.x, want.y), want.blur, want.spread, want.color),
          );
        }
      });
    }

    testWidgets('a node draws every inner layer of its list, and an outer shadow only for the outer ones', (
      tester,
    ) async {
      for (final row in _rows(_inset, 'css')) {
        final layers = _rows(row, 'layers');
        await pumpDocument(tester, docWith([_boxWith(layers)]));
        final innerCount = layers.where((layer) => layer['inset'] == true).length;
        final painter = _painterOf(tester);
        expect(painter?.shadows.length ?? 0, innerCount, reason: row['name']! as String);
        final outerCount = layers.length - innerCount;
        final boxes = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>();
        final shadowed = boxes.where((box) => box.boxShadow != null && box.boxShadow!.isNotEmpty);
        expect(shadowed.isNotEmpty || find.byType(CustomPaint).evaluate().isNotEmpty, isTrue);
        if (outerCount == 0) expect(shadowed, isEmpty, reason: row['name']! as String);
      }
    });
  });

  group('insetCases.geometry -- the clip and the hole', () {
    for (final row in _rows(_inset, 'geometry')) {
      test(row['name']! as String, () {
        final box = row['box']! as _Json;
        final layer = row['layer']! as _Json;
        final geometry = insetShadowGeometry(
          size: Size(_n(box['width']), _n(box['height'])),
          radius: BorderRadius.circular(_n(box['radius'])),
          borderWidth: _n(box['borderWidth']),
          offset: Offset(_n(layer['offsetX']), _n(layer['offsetY'])),
          spread: _n(layer['spread']),
        );
        void check(RRect actual, _Json want) {
          expect(actual.left, closeTo(_n(want['x']), 1e-6));
          expect(actual.top, closeTo(_n(want['y']), 1e-6));
          expect(actual.width, closeTo(_n(want['width']), 1e-6));
          expect(actual.height, closeTo(_n(want['height']), 1e-6));
          expect(actual.tlRadius.x, closeTo(_n(want['radius']), 1e-6));
          expect(actual.brRadius.x, closeTo(_n(want['radius']), 1e-6));
        }

        check(geometry.clip, row['clip']! as _Json);
        check(geometry.hole, row['hole']! as _Json);
      });
    }
  });

  group('insetCases.document -- what the reader does with each row', () {
    for (final row in _rows(_inset, 'document')) {
      final name = row['name']! as String;
      test(name, () {
        final raw = (row['shadow']! as List<Object?>).cast<_Json>();
        final ref = ShadowRef.tryParse(raw);
        if (raw.length > kMaxShadowLayers) {
          expect(ref, isNull, reason: 'more layers than the bound: no shadow');
          return;
        }
        expect(ref, isNotNull);
        final inner = theme.resolveInnerShadow(ref!);
        // Only the flag `true` makes a layer inner; `false` and a string are no flag, the layer stays outer.
        expect(inner.length, raw.where((layer) => layer['inset'] == true).length);
        // A number beyond its bound is clamped like any literal: 65 gives 64.
        if (name.contains('beyond the offset bound')) expect(inner.single.offset.dx, 64);
      });
    }
  });

  group('insetCases.themeElevation -- the theme has no inner shadow', () {
    for (final row in _rows(_inset, 'themeElevation')) {
      test(row['name']! as String, () {
        final base = jsonDecode(readThemeContract()) as _Json;
        final light = Map<String, Object?>.from(((base['contract']! as _Json)['themes']! as _Json)['light']! as _Json);
        final layer = Map<String, Object?>.from(row['layer']! as _Json);
        light['elevation'] = {
          ...(light['elevation']! as _Json),
          'low': [layer],
        };
        final themed = RenderTheme.fromJsonRaw(light);
        // A layer with the flag never turns into an inner one: the theme resolves only outer layers.
        expect(themed.elevations['low'], isNotNull);
        expect(themed.resolveInnerShadow(const TokenShadowRef('low')), isEmpty);
      });
    }
  });

  test('the hue of the background tints the inner layers too (shadowColor: background)', () {
    final style = {
      'background': {
        'kind': 'color',
        'color': {'value': '#336699'},
      },
      'shadowColor': 'background',
      'shadow': [
        {
          'offsetX': 0,
          'offsetY': 2,
          'blur': 0,
          'spread': 0,
          'color': {'value': '#ffffff', 'opacity': 0.5},
          'inset': true,
        },
      ],
    };
    final node = rootOf(
      docWith([
        {'id': 'n', 'type': 'Container', 'style': style},
      ]),
    ).children.single;
    final inner = theme.resolveNodeInnerShadow(node.style!);
    expect(inner.single.color, const Color(0xFF336699).withValues(alpha: 0.5));
  });

  group('the painter of the inner layers', () {
    Future<List<int>> paintOf(WidgetTester tester, InnerShadow layer, {double border = 0}) async {
      late List<int> out;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        const size = Size(40, 20);
        InnerShadowPainter(
          shadows: [layer],
          radius: BorderRadius.zero,
          borderWidth: border,
        ).paint(ui.Canvas(recorder), size);
        final image = recorder.endRecording().toImageSync(40, 20);
        out = (await image.toByteData())!.buffer.asUint8List().toList();
        image.dispose();
      });
      return out;
    }

    int alphaAt(List<int> pixels, int x, int y) => pixels[(y * 40 + x) * 4 + 3];

    testWidgets('a sharp layer offset down paints a band at the TOP edge inside the box and nothing in the middle', (
      tester,
    ) async {
      final pixels = await paintOf(tester, const InnerShadow(color: Color(0xFF000000), offset: Offset(0, 4)));
      expect(alphaAt(pixels, 20, 1), 255, reason: 'inside, at the top');
      expect(alphaAt(pixels, 20, 3), 255);
      expect(alphaAt(pixels, 20, 10), 0, reason: 'the middle is the hole');
      expect(alphaAt(pixels, 20, 18), 0, reason: 'the bottom is the hole too');
    });

    testWidgets('nothing leaves the box, and the border width keeps the layer off the border', (tester) async {
      final pixels = await paintOf(
        tester,
        const InnerShadow(color: Color(0xFF000000), offset: Offset(0, 8)),
        border: 2,
      );
      expect(alphaAt(pixels, 20, 1), 0, reason: 'the border is not shaded');
      expect(alphaAt(pixels, 20, 3), 255);
    });

    testWidgets('a blurred layer fades from the edge inwards', (tester) async {
      final pixels = await paintOf(tester, const InnerShadow(color: Color(0xFF000000), blurRadius: 8, spreadRadius: 2));
      expect(alphaAt(pixels, 20, 0), greaterThan(alphaAt(pixels, 20, 4)));
      expect(alphaAt(pixels, 20, 4), greaterThan(alphaAt(pixels, 20, 10)));
    });
  });

  group('textShadowCases.css -- TextStyle.shadows', () {
    for (final row in _rows(_text, 'css')) {
      test(row['name']! as String, () {
        final layers = _rows(row, 'layers');
        final ref = TextShadowRef.tryParse(layers)!;
        final shadows = theme.resolveTextShadow(ref)!;
        final css = _parseCss(row['css']! as String);
        // `bottomFirst` lists the layers of the document in the order Flutter paints them: the bottom one first.
        final order = (row['bottomFirst']! as List<Object?>).cast<int>();
        expect(shadows, hasLength(order.length));
        for (final (index, shadow) in shadows.indexed) {
          final want = css[order[index]];
          expect((shadow.offset, shadow.blurRadius, shadow.color), (Offset(want.x, want.y), want.blur, want.color));
        }
      });

      testWidgets('on screen: ${row['name']}', (tester) async {
        await pumpDocument(
          tester,
          docWith([
            textNode('Rewards', style: {'textShadow': row['layers']}),
          ]),
        );
        final style = tester.widget<Text>(find.text('Rewards')).style!;
        final order = (row['bottomFirst']! as List<Object?>).cast<int>();
        expect(style.shadows, hasLength(order.length));
        final css = _parseCss(row['css']! as String);
        for (final (index, shadow) in style.shadows!.indexed) {
          expect(shadow.offset, Offset(css[order[index]].x, css[order[index]].y));
        }
      });
    }
  });

  group('textShadowCases.document -- which widgets read the field and what a broken list gives', () {
    for (final row in _rows(_text, 'document')) {
      final name = row['name']! as String;
      testWidgets(name, (tester) async {
        final type = row['type']! as String;
        final style = {'textShadow': row['textShadow']};
        final node = switch (type) {
          'Button' => {
            ...buttonNode('Rewards', action: {'type': 'none'}),
            'style': style,
          },
          'Container' => {
            'id': 'n',
            'type': 'Container',
            'style': style,
            'children': [textNode('Rewards', id: 'inner')],
          },
          _ => textNode('Rewards', style: style),
        };
        await pumpDocument(tester, docWith([node]));
        expect(tester.takeException(), isNull);
        final shadows = tester.widget<Text>(find.text('Rewards')).style?.shadows;
        final layers = (row['textShadow']! as List<Object?>);
        if (type != 'Text' || layers.isEmpty || layers.length > kMaxTextShadowLayers) {
          expect(shadows, isNull, reason: 'a widget that does not read the field, or a list that is no shadow');
          return;
        }
        expect(shadows, hasLength(layers.length));
        // A number beyond its bound is clamped (blur 129 gives 128); `spread` and `inset` are no fields here.
        for (final shadow in shadows!) {
          expect(shadow.blurRadius, lessThanOrEqualTo(128));
        }
      });
    }

    testWidgets('the text of a Container below a node with the field gets none: the field is read off the own style', (
      tester,
    ) async {
      final node = {
        'id': 'box',
        'type': 'Container',
        'style': {
          'textShadow': [
            {
              'offsetX': 0,
              'offsetY': 2,
              'blur': 4,
              'color': {'value': '#000000'},
            },
          ],
        },
        'children': [textNode('inner text')],
      };
      await pumpDocument(tester, docWith([node]));
      expect(tester.widget<Text>(find.text('inner text')).style?.shadows, isNull);
    });

    testWidgets('a layer that does not resolve gives no shadow, and a state with such a list keeps the base one', (
      tester,
    ) async {
      final good = [
        {
          'offsetX': 0,
          'offsetY': 2,
          'blur': 4,
          'color': {'value': '#000000'},
        },
      ];
      final bad = [
        {'offsetX': 0, 'offsetY': 1, 'blur': 1, 'color': 'noSuchColour'},
      ];
      await pumpDocument(
        tester,
        docWith([
          textNode('lone', style: {'textShadow': bad}),
        ]),
      );
      expect(tester.widget<Text>(find.text('lone')).style?.shadows, isNull);
      final node = textNode('stated', style: {'textShadow': good});
      node['styleWhen'] = [
        {
          'when': {'path': 'flag', 'op': 'isTrue'},
          'style': {'textShadow': bad},
        },
      ];
      await pumpDocument(tester, docWith([node]), data: {'flag': true});
      expect(tester.widget<Text>(find.text('stated')).style?.shadows, hasLength(1));
    });

    testWidgets(
      'with a gradient on the glyphs: a silent copy under the gradient carries the shadow, the gradient does not',
      (tester) async {
        final node = textNode(
          'Rewards',
          style: {
            'textShadow': [
              {
                'offsetX': 0,
                'offsetY': 2,
                'blur': 4,
                'color': {'value': '#000000'},
              },
            ],
            'textGradient': {
              'angle': 90,
              'stops': [
                {
                  'color': {'value': '#ff0000'},
                  'position': 0,
                },
                {
                  'color': {'value': '#0000ff'},
                  'position': 1,
                },
              ],
            },
          },
        );
        await pumpDocument(tester, docWith([node]));
        final texts = tester.widgetList<Text>(find.text('Rewards', skipOffstage: false)).toList();
        expect(texts, hasLength(2), reason: 'the copy under the gradient and the masked one');
        final copy = texts.firstWhere((text) => text.style?.shadows != null);
        expect(copy.style!.color, Colors.transparent);
        final masked = tester.widget<ShaderMask>(find.byType(ShaderMask));
        expect((masked.child! as Text).style?.shadows, isNull, reason: 'the mask carries no shadow');
        // The copy is outside the tree of a screen reader.
        expect(
          find.descendant(of: find.byType(ExcludeSemantics), matching: find.text('Rewards', skipOffstage: false)),
          findsWidgets,
        );
      },
    );

    testWidgets('the shadow of a text takes no room: the text is measured as without it', (tester) async {
      await pumpDocument(tester, docWith([textNode('Rewards', id: 'plain')]));
      final plain = tester.getSize(find.text('Rewards'));
      await pumpDocument(
        tester,
        docWith([
          textNode(
            'Rewards',
            style: {
              'textShadow': [
                {
                  'offsetX': 30,
                  'offsetY': 30,
                  'blur': 40,
                  'color': {'value': '#000000'},
                },
              ],
            },
          ),
        ]),
      );
      expect(tester.getSize(find.text('Rewards')), plain);
    });

    testWidgets('parts and the marker of a list item carry the shadow of their text', (tester) async {
      final shadow = [
        {
          'offsetX': 0,
          'offsetY': 2,
          'blur': 4,
          'color': {'value': '#000000'},
        },
      ];
      final parts = {
        'id': 'p',
        'type': 'Text',
        'props': {
          'content': {
            'kind': 'template',
            'template': 'a {n} b',
            'values': {
              'n': {'kind': 'text', 'text': '77'},
            },
          },
          'align': 'start',
          'overflow': 'clip',
          'spans': {
            'n': {
              'color': {'value': '#ff0000'},
            },
          },
        },
        'style': {'textShadow': shadow},
      };
      await pumpDocument(tester, docWith([parts]));
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.text.style?.shadows, hasLength(1), reason: 'the paragraph carries it, the parts inherit it');
      final bullet = textNode('item', style: {'textShadow': shadow});
      (bullet['props']! as Map<String, Object?>)['marker'] = 'bullet';
      await pumpDocument(tester, docWith([bullet]));
      final marked = tester.widgetList<Text>(find.byType(Text)).where((text) => text.style?.shadows != null);
      expect(marked.length, 2, reason: 'the text and its marker');
    });
  });

  group('the frame shadow-effects-screens', () {
    const id = 'shadow-effects-screens';

    testWidgets(
      'draws inner layers inside the boxes and shadows of the glyphs, and the copy under the gradient heading',
      (tester) async {
        await pumpDocument(tester, loadFixture(id), theme: fixtureTheme(id));
        expect(tester.takeException(), isNull);
        final painters = [
          for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
            if (paint.painter is InnerShadowPainter) paint.painter! as InnerShadowPainter,
        ];
        expect(painters, isNotEmpty);
        final shadowed = tester
            .widgetList<Text>(find.byType(Text, skipOffstage: false))
            .where((text) => text.style?.shadows != null);
        expect(shadowed, isNotEmpty);
        expect(find.byType(ShaderMask), findsWidgets);
      },
    );
  });
}
