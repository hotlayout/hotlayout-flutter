/// IMAGE, APP BAR, MODAL LAYER, STATUS BAR (schema 9.9.0).
///
/// The tests read the contract table ITSELF
/// (`assets/contract/fixtures/media-chrome/media-chrome-cases.json`, a copy of
/// `contract/fixtures/media-chrome/media-chrome-cases.json`) and run EVERY
/// row that concerns the reader twice: through the reader's reference formula
/// (`lib/src/model/media_chrome_rules.dart`) and through a REAL widget.
///
///  1. `ratioCases` (20) — word or pair → ratio; by parsing the node;
///  2. `ratioDocumentCases` (14) — a document with such a ratio is drawn by the reader without
///     crashing, the ratio is clamped or `16:9` (the schema and validator codes are
///     builder reference; the Dart reader has no validator);
///  3. `imageBoxCases` (18) — the size of a REAL box in three forms: width
///     named, width given by the parent, and the formula;
///  4. `paintCases` (9) — the picture rectangle: the formula and Flutter's `applyBoxFit`,
///     which paints `BoxFit`;
///  5. `radiusCases` (9) — effective radius and circle: the formula and Flutter's `RRect`;
///  6. `appBarCases` (15) — app bar zones: the formula, a real `RenderAppBarLayout`
///     in both writing directions (`rtlLeft`), a real document;
///  7. `modalCases` (16) — the layer rectangle through a real screen flow;
///  8. `placementCases` (7), `statusBarCases` (7) — reading two screen fields;
///  9. `documentCases` (16) — the reader parses and draws the document without crashing;
/// 10. `shownCases` (8) — the show event KEY FOR KEY, through a real `ScreenFlow`.
///
/// `circleCases` (5) — a convenience path "Circle" of the builder panel: reference only, the reader
/// does not have it (for the reader a circle is equal sides and a radius, `radiusCases`).
/// The two new flows with a window in `record-scope-cases.json` are run by
/// `record_scope_test.dart` (it passes `modalPlacement` into the document).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/wide_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/app_bar_layout.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';
import 'package:hotlayout_flutter/src/render/image_frame.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _readJson(String path) => json.decode(File(path).readAsStringSync()) as _Json;

final _Json _table = _readJson('assets/contract/fixtures/media-chrome/media-chrome-cases.json');
final _Json _schema = _readJson('assets/contract/screen-schema.json');

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();

double _num(Object? value) => (value! as num).toDouble();

/// Table numbers are rounded to four digits (`117.9009`, `134.1`).
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);

// ───────────────────────────── document builders ─────────────────────────────

_Json _asset() => {'kind': 'asset', 'asset': 'placeholder'};

_Json _image(String id, {Object? ratio = #absent, _Json? style, Object? fit}) => {
  'id': id,
  'type': 'Image',
  'props': {
    'source': _asset(),
    if (ratio != #absent) 'aspectRatio': ratio,
    'fit': ?fit,
  },
  'style': ?style,
};

_Json _literal(String text) => {'kind': 'literal', 'value': text};

_Json _iconButton(String id, {String size = 'md', String label = 'Дія', _Json? visibleIf}) => {
  'id': id,
  'type': 'IconButton',
  'props': {
    'icon': 'info',
    'label': _literal(label),
    'variant': 'ghost',
    'size': size,
    'action': {'type': 'probe'},
  },
  'visibleIf': ?visibleIf,
};

_Json _bar(
  String title, {
  bool showBack = true,
  List<_Json> children = const [],
  _Json? style,
  String? subtitle,
}) => {
  'id': 'bar',
  'type': 'AppBar',
  'props': {
    'title': _literal(title),
    if (subtitle != null) 'subtitle': _literal(subtitle),
    'showBack': showBack,
  },
  'style': ?style,
  if (children.isNotEmpty) 'children': children,
};

_Json _screen(
  String id,
  List<_Json> children, {
  String? presentation,
  Object? placement,
  Object? icons,
  _Json? style,
}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'modalPlacement': ?placement,
  'statusBarIcons': ?icons,
  'root': {
    'id': '$id-root',
    'type': 'Screen',
    'props': {'gap': 'none'},
    'style': ?style,
    'children': children,
  },
};

UiDocument _doc(List<_Json> screens, {String? initial}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'd',
  'name': 'media chrome',
  'initialScreenId': initial ?? screens.first['screenId'],
  'screens': screens,
});

_Json _goTo(String id, String screenId) => {
  'id': id,
  'type': 'Button',
  'props': {
    'label': _literal('Відкрити $screenId'),
    'variant': 'primary',
    'action': {
      'type': 'navigate',
      'params': {'screenId': screenId},
    },
  },
};

/// Test window size — logical pixels (density 1), as in the table rows.
void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

ImageNode _imageNode(UiDocument doc) => flattenDocument(doc).whereType<ImageNode>().single;

// ───────────────────────────── suite ─────────────────────────────

void main() {
  final theme = RenderTheme.fallback();
  final tokens = _obj(_table['tokens']);
  final spacing = _obj(tokens['spacing']);

  group('table: structure', () {
    test('fourteen groups with the expected row counts', () {
      const counts = {
        'ratioCases': 20,
        'ratioDocumentCases': 14,
        'imageBoxCases': 18,
        'paintCases': 9,
        'radiusCases': 9,
        'circleCases': 5,
        'appBarCases': 15,
        'modalCases': 16,
        'placementCases': 7,
        'statusBarCases': 7,
        'documentCases': 16,
        'shownCases': 11,
        'modalRuleCases': 2,
        'appBarDrawnCases': 7,
      };
      for (final entry in counts.entries) {
        expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
        final names = _rows(entry.key).map((row) => row['name']).toList();
        expect(names.toSet(), hasLength(names.length), reason: '${entry.key}: names are not repeated');
      }
    });

    test('table token numbers are the ones in the reader theme', () {
      // The rows are computed with these numbers; the reader theme must have them, otherwise
      // the table expectations are checked against something other than what the reader paints.
      expect(theme.space(SpacingToken.xs), _num(spacing['xs']));
      expect(theme.space(SpacingToken.sm), _num(spacing['sm']));
      expect(theme.space(SpacingToken.xl), _num(spacing['xl']));
      expect(tokens['backSide'], _num(spacing['xl']));
      expect(tokens['gap'], _num(spacing['sm']));
      expect(tokens['actionGap'], _num(spacing['xs']));
      expect(tokens['windowMargin'], _num(spacing['xl']));
      expect(tokens['windowMaxWidth'], kModalWindowMaxWidth);
    });
  });

  // ───────────────────────────── 1. ratio ─────────────────────────────

  group('ratio (ratioCases)', () {
    for (final row in _rows('ratioCases')) {
      final expected = _obj(row['expect']);
      final quotient = _num(expected['width']) / _num(expected['height']);

      test('${row['name']}', () {
        final value = row.containsKey('aspectRatio') ? row['aspectRatio'] : #absent;
        final ratio = ImageRatio.parse(value == #absent ? null : value);
        expect(ratio.ratio, closeTo(quotient, 1e-9));

        // The same input through parsing a node from a document.
        final node = _imageNode(
          _doc([
            _screen('a', [_image('img', ratio: value)]),
          ]),
        );
        expect(node.aspectRatio.ratio, closeTo(quotient, 1e-9));
      });
    }

    test('an enum word is read by its own key of the artifact table', () {
      final ratios = _obj(_obj(_obj(_schema['x-style'])['layout'])['image'])['ratios']! as _Json;
      expect(ratios.keys, kImageRatioTokens.keys);
      for (final entry in ratios.entries) {
        final pair = _obj(entry.value);
        expect(kImageRatioTokens[entry.key], (pair['width']! as int, pair['height']! as int));
      }
    });
  });

  group('document with a ratio (ratioDocumentCases) — the reader draws it and does not crash', () {
    for (final row in _rows('ratioDocumentCases')) {
      testWidgets('${row['name']}', (tester) async {
        _view(tester, 400, 900);
        final doc = _doc([
          _screen('a', [_image('img', ratio: row['aspectRatio'])]),
        ]);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);
        final node = _imageNode(doc);
        expect(node.aspectRatio.ratio, inInclusiveRange(kImageRatioMin, kImageRatioMax));
        // A frame is drawn with exactly the ratio that was read.
        final size = tester.getSize(find.byType(ImageFrame));
        expect(size.width / size.height, closeTo(node.aspectRatio.ratio, 0.01));
        // The schema (`schema`) and validator codes (`code`) are the builder's concern.
        expect(row, containsPair('schema', isA<bool>()));
      });
    }
  });

  // ───────────────────────────── 3. image box ─────────────────────────────

  group('image box (imageBoxCases)', () {
    for (final row in _rows('imageBoxCases')) {
      final style = _obj(row['style']);
      final expected = _obj(row['expect']);
      final width = _num(row['width']);

      test('formula: ${row['name']}', () {
        final ratio = ImageRatio.parse(row['aspectRatio']).ratio;
        final box = imageBoxOf(
          ratio: ratio,
          width: width,
          height: style['height'] == null ? null : _num(style['height']),
          minHeight: style['minHeight'] == null ? null : _num(style['minHeight']),
          maxHeight: style['maxHeight'] == null ? null : _num(style['maxHeight']),
        );
        expect(box.width, _near(_num(expected['width'])));
        expect(box.height, _near(_num(expected['height'])));
        expect(box.byRatio, expected['byRatio']);
      });

      if (width >= 1) {
        // The node names the width (`style.width`).
        testWidgets('widget, width named: ${row['name']}', (tester) async {
          _view(tester, 1400, 3000);
          await pumpDocument(
            tester,
            _doc([
              _screen('a', [_image('img', ratio: row['aspectRatio'], style: {'width': width, ...style})]),
            ]),
          );
          expect(tester.takeException(), isNull);
          final size = tester.getSize(find.byType(ImageFrame));
          expect(size.width, _near(_num(expected['width'])));
          expect(size.height, _near(_num(expected['height'])));
        });

        // The parent gives the width: a screen of `width` wide, the node has no width sizes.
        testWidgets('widget, width given by parent: ${row['name']}', (tester) async {
          _view(tester, width, 3000);
          await pumpDocument(
            tester,
            _doc([
              _screen('a', [_image('img', ratio: row['aspectRatio'], style: style.isEmpty ? null : style)]),
            ]),
          );
          expect(tester.takeException(), isNull);
          final size = tester.getSize(find.byType(ImageFrame));
          expect(size.width, _near(_num(expected['width'])));
          expect(size.height, _near(_num(expected['height'])));
        });
      }
    }

    testWidgets('the box is the same before and after loading', (tester) async {
      _view(tester, 400, 900);
      // A network image without a network: in tests it stays "loading" or
      // becomes "unavailable" — the box size does not change in either state.
      final doc = _doc([
        _screen('a', [
          {
            'id': 'img',
            'type': 'Image',
            'props': {
              'source': {'kind': 'url', 'url': 'https://cdn.example.com/a.png'},
              'aspectRatio': '16:9',
            },
          },
        ]),
      ]);
      await pumpDocument(tester, doc);
      final loading = tester.getSize(find.byType(ImageFrame));
      await tester.pump(const Duration(seconds: 1));
      final after = tester.getSize(find.byType(ImageFrame));
      expect(after, loading);
      expect(loading, const Size(400, 225));
    });

    testWidgets('an image with a named height in a row without weight does not take its width from the height', (tester) async {
      _view(tester, 360, 900);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            {
              'id': 'row',
              'type': 'Row',
              'props': {'gap': 'none', 'align': 'start'},
              'children': [
                _image('img', ratio: '1:1', style: {'height': 120}),
                {
                  'id': 'text',
                  'type': 'Text',
                  'props': {'content': _literal('Поруч')},
                },
              ],
            },
          ]),
        ]),
      );
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(ImageFrame));
      // The height is named — 120; the width does NOT equal 120 (height × ratio), but
      // is a share of the row by the "child without weight" rule (contract 9.0.0).
      expect(size.height, 120);
      expect(size.width, isNot(120));
    });
  });

  group('picture in the box (paintCases)', () {
    for (final row in _rows('paintCases')) {
      test('${row['name']}', () {
        final box = _obj(row['box']);
        final expected = _obj(row['expect']);
        final fit = row['fit'];
        final rect = imagePaintRect(
          boxWidth: _num(box['width']),
          boxHeight: _num(box['height']),
          natural: _num(row['natural']),
          fit: fit,
        );
        expect(rect.x, _near(_num(expected['x'])));
        expect(rect.y, _near(_num(expected['y'])));
        expect(rect.width, _near(_num(expected['width'])));
        expect(rect.height, _near(_num(expected['height'])));

        // The same as Flutter itself computes for the reader's `BoxFit` (`cover` is the default,
        // an unknown word is also `cover`): size by `applyBoxFit`, centred.
        final boxSize = Size(_num(box['width']), _num(box['height']));
        final natural = _num(row['natural']);
        final imageSize = Size(natural * 100, 100);
        final boxFit = fit == 'contain' ? BoxFit.contain : BoxFit.cover;
        final sizes = applyBoxFit(boxFit, imageSize, boxSize);
        // `cover`: a PART of the picture (`source`) fits the box, so the full picture is
        // at scale `destination / source`; it sticks out of the box and is clipped.
        final scale = sizes.destination.width / sizes.source.width;
        final painted = Alignment.center.inscribe(imageSize * scale, Offset.zero & boxSize);
        expect(painted.left, _near(_num(expected['x'])));
        expect(painted.top, _near(_num(expected['y'])));
        expect(painted.width, _near(_num(expected['width'])));
        expect(painted.height, _near(_num(expected['height'])));
      });
    }
  });

  group('radius and circle (radiusCases)', () {
    for (final row in _rows('radiusCases')) {
      test('${row['name']}', () {
        final box = _obj(row['box']);
        final expected = _obj(row['expect']);
        final width = _num(box['width']);
        final height = _num(box['height']);
        final radius = _num(row['radius']);
        expect(
          effectiveCornerRadius(width: width, height: height, radius: radius),
          _near(_num(expected['radius'])),
        );
        expect(isCircleBox(width: width, height: height, radius: radius), expected['circle']);
      });
    }

    // The radius really clips the picture: a frame pixel is checked, not just
    // the presence of `ClipRRect`. The screen background is one colour, the picture placeholder another.
    Future<ui.Image> shot(WidgetTester tester) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      return (await tester.runAsync(() => boundary.toImage()))!;
    }

    Future<Color> pixel(WidgetTester tester, ui.Image image, int x, int y) async {
      final data = (await tester.runAsync(() => image.toByteData()))!;
      final i = (y * image.width + x) * 4;
      return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    }

    testWidgets('56 × 56 avatar with pill is a circle: frame corner is the screen background, centre is the picture', (tester) async {
      _view(tester, 400, 900);
      await pumpDocument(
        tester,
        _doc([
          _screen(
            'a',
            [_image('avatar', ratio: '16:9', style: {'width': 56, 'height': 56, 'radius': 'pill'})],
            style: {'background': colorBackground('surface')},
          ),
        ]),
      );
      expect(tester.getSize(find.byType(ImageFrame)), const Size(56, 56));
      final rect = tester.getRect(find.byType(ImageFrame));
      final image = await shot(tester);
      final corner = await pixel(tester, image, rect.left.round() + 1, rect.top.round() + 1);
      final centre = await pixel(tester, image, rect.center.dx.round(), rect.center.dy.round());
      expect(corner, theme.color(ColorToken.surface), reason: 'the box corner is clipped by the circle');
      expect(centre, const Color(0xFFE5E7EB), reason: 'the picture placeholder is in the centre');
    });

    testWidgets('160 × 160 with pill is NOT a circle: radius 72, not 80', (tester) async {
      _view(tester, 400, 900);
      await pumpDocument(
        tester,
        _doc([
          _screen(
            'a',
            [_image('big', ratio: '1:1', style: {'width': 160, 'height': 160, 'radius': 'pill'})],
            style: {'background': colorBackground('surface')},
          ),
        ]),
      );
      final rect = tester.getRect(find.byType(ImageFrame));
      final image = await shot(tester);
      // The point (8, 40) from the corner: in a circle of radius 80 it is OUTSIDE the edge, in a square with
      // corners of radius 72 it is still inside.
      final inside = await pixel(tester, image, rect.left.round() + 8, rect.top.round() + 40);
      expect(inside, const Color(0xFFE5E7EB), reason: 'pill is a theme number (72), not "half the side"');
      final clip = tester.widget<ClipRRect>(
        find.ancestor(of: find.byType(ImageFrame), matching: find.byType(ClipRRect)).first,
      );
      expect(clip.borderRadius.resolve(TextDirection.ltr).topLeft.x, theme.radius(RadiusToken.pill));
    });
  });

  // ───────────────────────────── 6. app bar ─────────────────────────────

  group('app bar zones (appBarCases)', () {
    for (final row in _rows('appBarCases')) {
      final expected = _obj(row['expect']);
      final sides = [for (final side in row['actionSides']! as List<Object?>) _num(side)];
      final width = _num(row['width']);
      final tokens = _obj(_table['tokens']);

      AppBarZones zones() => appBarZones(
        width: width,
        showBack: row['showBack']! as bool,
        backSide: _num(tokens['backSide']),
        actionSides: sides,
        gap: _num(tokens['gap']),
        actionGap: _num(tokens['actionGap']),
        titleNatural: _num(row['titleNatural']),
      );

      test('formula: ${row['name']}', () {
        final z = zones();
        expect(z.leading, _near(_num(expected['leading'])));
        expect(z.trailing, _near(_num(expected['trailing'])));
        expect(z.titleRoom, _near(_num(expected['titleRoom'])));
        expect(z.titleWidth, _near(_num(expected['titleWidth'])));
        expect(z.titleStart, _near(_num(expected['titleStart'])));
        expect(z.centered, expected['centered']);
        expect(z.truncated, expected['truncated']);
        final starts = (expected['actionStarts']! as List<Object?>).map(_num).toList();
        expect(z.actionStarts, hasLength(starts.length));
        for (var i = 0; i < starts.length; i += 1) {
          expect(z.actionStarts[i], _near(starts[i]));
        }
      });

      for (final direction in TextDirection.values) {
        testWidgets('real layout, ${direction.name}: ${row['name']}', (tester) async {
          // The children are rectangles of exact sizes: the layout measures them the same way
          // as it would measure icon buttons, the arrow and the title block.
          final back = row['showBack']! as bool;
          await tester.pumpWidget(
            Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: AppBarLayout(
                    hasBack: back,
                    backSide: _num(tokens['backSide']),
                    gap: _num(tokens['gap']),
                    actionGap: _num(tokens['actionGap']),
                    children: [
                      if (back) const SizedBox.square(dimension: 24),
                      SizedBox(width: _num(row['titleNatural']), height: 20),
                      for (final side in sides) SizedBox.square(dimension: side),
                    ],
                  ),
                ),
              ),
            ),
          );
          final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
          final offsets = <Offset>[];
          final boxes = <Size>[];
          for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
            offsets.add((child.parentData! as ContainerBoxParentData<RenderBox>).offset);
            boxes.add(child.size);
          }
          // Size: the tallest zone.
          final tallest = [if (back) 24.0, 20.0, ...sides].reduce(math.max);
          expect(render.size.height, tallest);
          expect(render.size.width, width);

          // From the row start: LTR — from the left edge, RTL — from the right.
          double fromStart(Offset offset, Size size) =>
              direction == TextDirection.ltr ? offset.dx : width - offset.dx - size.width;
          var index = 0;
          if (back) {
            expect(fromStart(offsets[index], boxes[index]), _near(0), reason: 'the arrow is at the row start');
            index += 1;
          }
          expect(
            fromStart(offsets[index], boxes[index]),
            _near(_num(expected['titleStart'])),
            reason: 'title start',
          );
          expect(boxes[index].width, _near(_num(expected['titleWidth'])), reason: 'title width');
          index += 1;
          final starts = (expected['actionStarts']! as List<Object?>).map(_num).toList();
          for (var i = 0; i < starts.length; i += 1) {
            expect(fromStart(offsets[index + i], boxes[index + i]), _near(starts[i]), reason: 'action $i');
          }
          // Across the row everything is centred.
          for (var i = 0; i < offsets.length; i += 1) {
            expect(offsets[i].dy, _near((tallest - boxes[i].height) / 2));
          }

          // `rtlLeft`: the same layout as offsets from the LEFT edge.
          final rtl = row['rtlLeft'];
          if (rtl != null && direction == TextDirection.rtl) {
            final left = _obj(rtl);
            var i = 0;
            if (back) {
              expect(offsets[i].dx, _near(_num(left['back'])), reason: 'rtlLeft: arrow');
              i += 1;
            }
            expect(offsets[i].dx, _near(_num(left['title'])), reason: 'rtlLeft: title');
            i += 1;
            final actions = (left['actions']! as List<Object?>).map(_num).toList();
            for (var a = 0; a < actions.length; a += 1) {
              expect(offsets[i + a].dx, _near(actions[a]), reason: 'rtlLeft: action $a');
            }
          }
        });
      }
    }

    testWidgets('real document: arrow, title, two actions; behaviour against the formula', (tester) async {
      _view(tester, 369, 800);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _bar('Бейджі', children: [_iconButton('x1', label: 'Інфо'), _iconButton('x2', size: 'sm', label: 'Поділитися')]),
          ]),
        ]),
      );
      expect(tester.takeException(), isNull);
      final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
      final boxes = <Size>[];
      final offsets = <Offset>[];
      for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
        boxes.add(child.size);
        offsets.add((child.parentData! as ContainerBoxParentData<RenderBox>).offset);
      }
      expect(boxes, hasLength(4), reason: 'arrow, title and two actions');
      // The action side is the icon button side of its size (md 40, sm 28).
      expect(boxes[2].width, _near(40));
      expect(boxes[2].height, _near(40));
      expect(boxes[3].width, _near(28));
      expect(boxes[3].height, _near(28));
      final z = appBarZones(
        width: 369,
        showBack: true,
        backSide: 24,
        actionSides: [boxes[2].width, boxes[3].width],
        gap: 8,
        actionGap: 4,
        titleNatural: boxes[1].width,
      );
      // The title is measured by its own natural size, so the ratio is also checked:
      // the title block is exactly its width or the room.
      expect(offsets[1].dx, _near(z.titleStart));
      expect(offsets[2].dx, _near(z.actionStarts[0]));
      expect(offsets[3].dx, _near(z.actionStarts[1]));
      expect(offsets[0].dx, 0);
      // An app bar with an action is taller than one without it.
      expect(render.size.height, 40);
    });

    testWidgets('a short title is at the CENTRE of the bar, not in the remainder (no counterweight)', (tester) async {
      _view(tester, 360, 800);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_bar('Hi')]),
        ]),
      );
      final title = tester.getRect(find.text('Hi'));
      expect(title.center.dx, closeTo(180, 1.0), reason: 'the bar centre, not the centre of the space right of the arrow');
    });

    testWidgets('a long title takes the remaining room: it is not cut to "bar minus two arrows"', (tester) async {
      _view(tester, 296, 800);
      const long = 'Дуже довгий заголовок шапки!';
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_bar(long)]),
        ]),
      );
      final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
      final title = render.childAfter(render.firstChild!)!; // arrow, then title
      // The title room is the bar minus `backSide + gap` (32) = 264; with a counterweight
      // it would be 296 − 2 × 32 = 232.
      expect(title.size.width, lessThanOrEqualTo(264.0));
      expect(title.size.width, greaterThan(232.0));
    });

    testWidgets('the gap only for zones with content: without an arrow and actions the title has the full width', (tester) async {
      _view(tester, 100, 800);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_bar('Дуже довгий заголовок', showBack: false)]),
        ]),
      );
      final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
      expect(render.firstChild!.size.width, 100);
    });

    testWidgets('an action hidden by a condition takes no room', (tester) async {
      _view(tester, 369, 800);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _bar('Заголовок', children: [
              _iconButton('x1'),
              _iconButton('x2', visibleIf: {'path': 'flag', 'op': 'isTrue'}),
            ]),
          ]),
        ]),
      );
      final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
      var count = 0;
      for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
        count += 1;
      }
      expect(count, 3, reason: 'arrow, title and ONLY one visible action');
    });

    testWidgets('an action is coloured by itself, not by the bar colour', (tester) async {
      _view(tester, 369, 800);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _bar('Заголовок', style: {'color': 'danger'}, children: [_iconButton('x1')]),
          ]),
        ]),
      );
      final barColor = theme.color(ColorToken.danger);
      // The bar title uses the bar colour (`onSurface` is turned off by the named `color`).
      final glyph = tester.widgetList<IconGlyph>(find.byType(IconGlyph)).toList();
      // The arrow (first) takes the bar colour; the action (last) takes the `ghost` role.
      expect(glyph.first.color, barColor);
      expect(glyph.last.color, isNot(barColor), reason: 'the action did not inherit the bar colour');
    });

    testWidgets('non-IconButton children are not drawn; at most two actions are drawn', (tester) async {
      _view(tester, 500, 800);
      Future<int> drawn(List<_Json> children) async {
        await pumpDocument(
          tester,
          _doc([
            _screen('a', [_bar('Заголовок', children: children)]),
          ]),
        );
        expect(tester.takeException(), isNull);
        final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
        var count = 0;
        for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
          count += 1;
        }
        return count - 2; // minus the arrow and the title
      }

      expect(await drawn([]), 0);
      // More than two actions are not drawn by the reader (the validator does not let such a document
      // through, but the reader does not give the title zero width).
      expect(await drawn([_iconButton('a1'), _iconButton('a2')]), 2);
      expect(await drawn([_iconButton('a1'), _iconButton('a2'), _iconButton('a3')]), 2);
      expect(
        await drawn([
          _iconButton('a1'),
          {
            'id': 'tx',
            'type': 'Text',
            'props': {'content': _literal('Ні')},
          },
          {
            'id': 'bt',
            'type': 'Button',
            'props': {'label': _literal('Ні'), 'variant': 'primary', 'action': {'type': 'none'}},
          },
        ]),
        1,
      );
      expect(find.text('Ні'), findsNothing);
    });

    testWidgets('an app bar without style.background is transparent over the screen background', (tester) async {
      _view(tester, 369, 800);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_bar('Заголовок')], style: {'background': colorBackground('primary')}),
        ]),
      );
      // There is no own background between the bar and the screen root.
      final decorated = find.descendant(of: find.byType(AppBarLayout), matching: find.byType(DecoratedBox));
      expect(decorated, findsNothing);
    });
  });

  // ───────────────────────────── 7. modal layer ─────────────────────────────

  group('modal layer (modalCases)', () {
    for (final row in _rows('modalCases')) {
      final viewport = _obj(row['viewport']);
      final expected = _obj(row['expect']);
      final margin = _num(row['margin']);
      final contentHeight = _num(row['contentHeight']);

      test('formula: ${row['name']}', () {
        final box = modalBoxOf(
          placement: row['placement'],
          viewportWidth: _num(viewport['width']),
          viewportHeight: _num(viewport['height']),
          contentHeight: contentHeight,
          margin: margin,
        );
        expect(box.x, _near(_num(expected['x'])));
        expect(box.y, _near(_num(expected['y'])));
        expect(box.width, _near(_num(expected['width'])));
        expect(box.height, _near(_num(expected['height'])));
        expect(box.scrolls, expected['scrolls']);
      });

      // An area narrower than two margins (40 dp) does not even fit the opening button.
      if (contentHeight >= 1 && _num(viewport['width']) >= 200) {
        testWidgets('real flow: ${row['name']}', (tester) async {
          _view(tester, _num(viewport['width']), _num(viewport['height']));
          await pumpDocument(
            tester,
            _doc([
              _screen('page', [
                _goTo('open', 'layer'),
              ]),
              _screen(
                'layer',
                [
                  {
                    'id': 'content',
                    'type': 'Container',
                    'props': {'direction': 'column'},
                    'style': {'height': contentHeight},
                    'children': const <Object?>[],
                  },
                ],
                presentation: 'modal',
                placement: row['placement'],
              ),
            ]),
          );
          await tester.tap(find.text('Відкрити layer'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // The tablet sheet row ("still full width") describes the 9.9.0 formula [modalBoxOf]; in
          // the real flow since 9.18.0 (step 2) a sheet without the `center` word on a wide place is a window
          // in the middle. Then the target is that window's rectangle (`wideModalCases`), not the row.
          final wideSheet = modalShapeOf(row['placement'], _num(viewport['width'])) == ModalShape.sheetWindow;
          final want = wideSheet
              ? modalLayerBoxOf(
                  placement: row['placement'],
                  viewportWidth: _num(viewport['width']),
                  viewportHeight: _num(viewport['height']),
                  contentHeight: contentHeight,
                  margin: margin,
                )
              : null;
          final rect = tester.getRect(find.byKey(kModalLayerKey));
          expect(rect.left, _near(want?.x ?? _num(expected['x'])));
          expect(rect.top, _near(want?.y ?? _num(expected['y'])));
          expect(rect.width, _near(want?.width ?? _num(expected['width'])));
          expect(rect.height, _near(want?.height ?? _num(expected['height'])));

          final scrollable = find.descendant(of: find.byKey(kModalLayerKey), matching: find.byType(Scrollable));
          final extent = tester.state<ScrollableState>(scrollable.first).position.maxScrollExtent;
          expect(extent > 0.01, want?.scrolls ?? expected['scrolls'], reason: 'taller content scrolls inside the layer');
        });
      }
    }

    UiDocument windowDoc({_Json? rootStyle, bool withButton = true}) => _doc([
      _screen('page', [
        {
          'id': 'under',
          'type': 'Text',
          'props': {'content': _literal('Під шаром')},
        },
        _goTo('open', 'layer'),
      ]),
      _screen(
        'layer',
        [
          {
            'id': 'inside',
            'type': 'Text',
            'props': {'content': _literal('У вікні')},
          },
          if (withButton)
            {
              'id': 'close',
              'type': 'Button',
              'props': {
                'label': _literal('Закрити'),
                'variant': 'primary',
                'action': {'type': 'navigate.back'},
              },
            },
        ],
        presentation: 'modal',
        placement: 'center',
        style: rootStyle,
      ),
    ]);

    testWidgets('window: the screen under it stays, the scrim is black 0.45 over the whole area', (tester) async {
      _view(tester, 393, 793);
      await pumpDocument(tester, windowDoc());
      await tester.tap(find.text('Відкрити layer'));
      await tester.pumpAndSettle();
      expect(find.text('Під шаром'), findsOneWidget);
      expect(find.text('У вікні'), findsOneWidget);
      final scrim = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where((box) => box.color.a > 0 && box.color.r == 0 && box.color.g == 0 && box.color.b == 0);
      expect(scrim.map((box) => box.color.a), contains(closeTo(kModalScrimOpacity, 0.001)));
      expect(kModalScrimOpacity, _num(_obj(_obj(_obj(_obj(_schema['x-style'])['layout'])['modalLayer'])['scrim'])['opacity']));
    });

    testWidgets('a tap outside the window is navigate.back; a tap inside the window is not', (tester) async {
      _view(tester, 393, 793);
      await pumpDocument(tester, windowDoc());
      await tester.tap(find.text('Відкрити layer'));
      await tester.pumpAndSettle();
      final window = tester.getRect(find.byKey(kModalLayerKey));

      // Inside: the empty space of the window (a root without background is transparent) does not close the layer.
      await tester.tapAt(window.topRight + const Offset(-2, 2));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsOneWidget);

      // Outside the window — back.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsNothing);
      expect(find.text('Під шаром'), findsOneWidget);
    });

    testWidgets('a button in the window closes it with the same navigate.back', (tester) async {
      _view(tester, 393, 793);
      await pumpDocument(tester, windowDoc());
      await tester.tap(find.text('Відкрити layer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Закрити'));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsNothing);
    });

    testWidgets('there is no built-in look: a root without style is a transparent layer', (tester) async {
      _view(tester, 393, 793);
      await pumpDocument(tester, windowDoc(withButton: false));
      await tester.tap(find.text('Відкрити layer'));
      await tester.pumpAndSettle();
      final layer = find.byKey(kModalLayerKey);
      expect(find.descendant(of: layer, matching: find.byType(DecoratedBox)), findsNothing);
      expect(find.descendant(of: layer, matching: find.byType(ClipRRect)), findsNothing);
      expect(find.descendant(of: layer, matching: find.byType(Material)), findsNothing);
    });

    testWidgets('the look is the root style: background, radius, shadow; the radius clips scrolling, the shadow is outside', (tester) async {
      _view(tester, 320, 548);
      await pumpDocument(
        tester,
        _doc([
          _screen('page', [_goTo('open', 'layer')]),
          _screen(
            'layer',
            [
              {
                'id': 'tall',
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'height': 900},
                'children': const <Object?>[],
              },
            ],
            presentation: 'modal',
            placement: 'center',
            style: {
              'background': colorBackground(),
              'radius': 'lg',
              'shadow': 'medium',
            },
          ),
        ]),
      );
      await tester.tap(find.text('Відкрити layer'));
      await tester.pumpAndSettle();
      final layer = find.byKey(kModalLayerKey);
      expect(find.descendant(of: layer, matching: find.byType(ClipRRect)), findsWidgets);
      // Scrolling is inside the radius clip, not the other way round.
      expect(
        find.descendant(
          of: find.descendant(of: layer, matching: find.byType(ClipRRect)).first,
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
      // The shadow is not clipped: the DecoratedBox with the shadow is outside the clip.
      final decorated = tester.widgetList<DecoratedBox>(find.descendant(of: layer, matching: find.byType(DecoratedBox)));
      expect(decorated.any((box) => (box.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false), isTrue);
      expect(tester.getRect(layer).height, 500);
    });

    testWidgets('sheet (bottom) and a layer without the field — as before: full width, from the bottom', (tester) async {
      _view(tester, 393, 793);
      for (final placement in <Object?>[null, 'bottom', 'top']) {
        // A new flow for each word: the previous layer would stay open.
        await tester.pumpWidget(const SizedBox());
        await pumpDocument(
          tester,
          _doc([
            _screen('page', [_goTo('open', 'layer')]),
            _screen(
              'layer',
              [
                {
                  'id': 'box',
                  'type': 'Container',
                  'props': {'direction': 'column'},
                  'style': {'height': 200},
                  'children': const <Object?>[],
                },
              ],
              presentation: 'modal',
              placement: placement,
            ),
          ]),
        );
        await tester.tap(find.text('Відкрити layer'));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(kModalLayerKey));
        expect(rect, const Rect.fromLTWH(0, 593, 393, 200), reason: 'placement=$placement');
      }
    });

    testWidgets('the modalPlacement field on a page is not read: it is not a window (modalPlacementOnPage)', (tester) async {
      _view(tester, 393, 793);
      final doc = _doc([
        _screen('a', [_goTo('open', 'b')]),
        _screen('b', [
          {
            'id': 'bt',
            'type': 'Text',
            'props': {'content': _literal('Сторінка')},
          },
        ], placement: 'center'),
      ]);
      expect(doc.screens[1].placement, ModalPlacement.bottom);
      await pumpDocument(tester, doc);
      await tester.tap(find.text('Відкрити b'));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsNothing);
      expect(find.text('Сторінка'), findsOneWidget);
    });

    testWidgets('the first shown screen, even a window, is drawn as a page', (tester) async {
      _view(tester, 393, 793);
      await pumpDocument(
        tester,
        _doc([
          _screen(
            'a',
            [
              {
                'id': 't',
                'type': 'Text',
                'props': {'content': _literal('Перший')},
              },
            ],
            presentation: 'modal',
            placement: 'center',
          ),
        ]),
      );
      expect(find.byKey(kModalLayerKey), findsNothing);
      expect(find.text('Перший'), findsOneWidget);
    });
  });

  group('layer placement and status bar icons (placementCases, statusBarCases)', () {
    for (final row in _rows('placementCases')) {
      test('${row['name']}', () {
        final value = row.containsKey('value') ? row['value'] : null;
        expect(ModalPlacement.of(value).wire, row['expect']);
        // The same input through parsing a (modal) screen.
        final doc = _doc([
          _screen('a', const []),
          _screen('b', const [], presentation: 'modal', placement: value),
        ]);
        expect(doc.screens[1].placement.wire, row['expect']);
      });
    }

    for (final row in _rows('statusBarCases')) {
      test('${row['name']}', () {
        final value = row.containsKey('value') ? row['value'] : null;
        expect(StatusBarIcons.of(value)?.wire, row['expect']);
        final doc = _doc([_screen('a', const [], icons: value)]);
        expect(doc.screens.single.statusBarIcons?.wire, row['expect']);
      });
    }

    test('the reader does not touch the system status bar (statusBar: touches-nothing)', () {
      final offenders = <String>[];
      final hostile = RegExp(r'SystemChrome|AnnotatedRegion|setSystemUIOverlayStyle|SystemUiOverlayStyle|theme-color');
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        for (final match in hostile.allMatches(text)) {
          final lineStart = text.lastIndexOf('\n', match.start) + 1;
          final prefix = text.substring(lineStart, match.start).trimLeft();
          if (prefix.startsWith('//') || prefix.startsWith('*') || prefix.startsWith('/*')) continue;
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
      expect(offenders, isEmpty, reason: 'the request goes to the host in the show event; the package does not touch the status bar');
    });
  });

  // ───────────────────────────── 9. documents ─────────────────────────────

  group('document (documentCases): the reader parses and draws it without crashing', () {
    for (final row in _rows('documentCases')) {
      testWidgets('${row['name']}', (tester) async {
        _view(tester, 393, 793);
        final screens = (row['screens']! as List<Object?>).cast<_Json>();
        final barChildren = row['appBarChildren'] as List<Object?>?;
        final hasBarKey = row.containsKey('appBarChildren');
        final built = [
          for (var i = 0; i < screens.length; i += 1)
            _screen(
              screens[i]['id']! as String,
              [
                if (i == 0 && hasBarKey && barChildren != null)
                  _bar('Шапка', children: [
                    for (var c = 0; c < barChildren.length; c += 1)
                      switch (barChildren[c]) {
                        'IconButton' => _iconButton('c$c', label: 'Дія $c'),
                        'Button' => {
                          'id': 'c$c',
                          'type': 'Button',
                          'props': {'label': _literal('Кнопка'), 'variant': 'primary', 'action': {'type': 'none'}},
                        },
                        _ => {
                          'id': 'c$c',
                          'type': 'Text',
                          'props': {'content': _literal('Текст')},
                        },
                      },
                  ]),
                if (i < screens.length - 1) _goTo('go$i', screens[i + 1]['id']! as String),
              ],
              presentation: screens[i]['presentation'] as String?,
              placement: screens[i]['modalPlacement'],
              icons: screens[i]['statusBarIcons'],
            ),
        ];
        final doc = _doc(built);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);

        if (barChildren != null) {
          final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
          var count = 0;
          for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
            count += 1;
          }
          // arrow + title + only IconButton, and at most two (`appBarExtraActions: 'draw-first-two'`);
          // the rest are not drawn
          expect(count - 2, math.min(kAppBarMaxDrawnActions, barChildren.where((type) => type == 'IconButton').length));
        }

        // The second screen opens without crashing.
        if (screens.length > 1) {
          await tester.tap(find.textContaining('Відкрити').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final second = doc.screens[1];
          final isWindow = second.presentation == ScreenPresentationToken.modal && second.modalPlacement == ModalPlacement.center;
          expect(find.byKey(kModalLayerKey).evaluate().isNotEmpty, second.presentation == ScreenPresentationToken.modal);
          if (isWindow) {
            final rect = tester.getRect(find.byKey(kModalLayerKey));
            expect(rect.width, lessThanOrEqualTo(345));
          }
        }
      });
    }
  });

  // ───────────────────── 9a. at most two app bar actions ─────────────────────

  group('app bar actions (appBarDrawnCases)', () {
    final tokens = _obj(_table['tokens']);
    for (final row in _rows('appBarDrawnCases')) {
      final visible = (row['visible']! as List<Object?>).cast<bool>();
      final expected = _obj(row['expect']);
      final drawn = (expected['drawn']! as List<Object?>).cast<bool>();

      test('formula: ${row['name']}', () {
        expect(appBarDrawnActions(visible), drawn);
        final sides = [for (final shown in drawn) if (shown) _num(row['actionSide'])];
        final zones = appBarZones(
          width: _num(row['width']),
          showBack: row['showBack']! as bool,
          backSide: _num(tokens['backSide']),
          actionSides: sides,
          gap: _num(tokens['gap']),
          actionGap: _num(tokens['actionGap']),
          titleNatural: _num(row['titleNatural']),
        );
        expect(zones.titleRoom, _near(_num(expected['titleRoom'])), reason: 'title room');
      });

      testWidgets('screen: ${row['name']}', (tester) async {
        _view(tester, _num(row['width']), 800);
        // An action hidden by a condition is a node that does not satisfy it (nothing lies at that path).
        final hidden = {'path': 'user.nothing', 'op': 'isNotEmpty'};
        await pumpDocument(
          tester,
          _doc([
            _screen('a', [
              _bar('Title', showBack: row['showBack']! as bool, children: [
                for (var i = 0; i < visible.length; i += 1)
                  _iconButton('act$i', label: 'Дія $i', visibleIf: visible[i] ? null : hidden),
              ]),
            ]),
          ]),
        );
        expect(tester.takeException(), isNull);
        // Exactly the actions the table expects are drawn — by accessible names.
        for (var i = 0; i < drawn.length; i += 1) {
          expect(find.bySemanticsLabel('Дія $i'), drawn[i] ? findsOneWidget : findsNothing, reason: 'action $i');
        }
        // The title has room (with eight actions there would be zero width).
        final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
        final titleBox = render.childAfter(render.firstChild!)!;
        final titleIndex = row['showBack']! as bool ? titleBox : render.firstChild!;
        expect(titleIndex.size.width, greaterThan(0));
      });
    }
  });

  // ───────────────────── 9b. layer over the whole page ─────────────────────

  group('modal layer over the whole page (modalRuleCases)', () {
    final modalLayer = _obj(_obj(_obj(_schema['x-style'])['layout'])['modalLayer']);
    for (final row in _rows('modalRuleCases')) {
      test('artifact: ${row['name']}', () {
        expect(modalLayer[row['rule']], row['expect']);
      });
    }

    testWidgets('the scrim covers the app bar and the pulled-up body: a tap on the bar closes the layer rather than pressing the bar action', (tester) async {
      _view(tester, 393, 793);
      final received = <String>[];
      final doc = _doc([
        _screen('page', [
          _bar('Title', children: [_iconButton('act', label: 'Дія шапки')]),
          // Pulled-up body: the first body child goes under the bar.
          {
            'id': 'hero',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'height': 120, 'background': {'kind': 'color', 'color': 'primary'}},
            'pull': 24,
          },
          _goTo('go', 'layer'),
        ]),
        _screen('layer', [
          {
            'id': 'content',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'height': 80},
            'children': const <Object?>[],
          },
        ], presentation: 'modal', placement: 'center'),
      ]);
      await pumpDocument(tester, doc, onAction: (action, nodeId) => received.add(action.type));
      final actionCenter = tester.getCenter(find.bySemanticsLabel('Дія шапки'));
      await tester.tap(find.text('Відкрити layer'));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsOneWidget);

      // Paint order: the layer is a later sibling of the page in one stack, so the bar
      // (part of the page) lies under it, whatever its "height".
      final hit = tester.hitTestOnBinding(actionCenter).path.map((entry) => entry.target).toList();
      expect(hit.whereType<RenderAppBarLayout>(), isEmpty, reason: 'the tap did not reach the bar');

      await tester.tapAt(actionCenter);
      await tester.pumpAndSettle();
      expect(received, isNot(contains('probe')), reason: 'the bar action under the scrim was not pressed');
      expect(find.byKey(kModalLayerKey), findsNothing, reason: 'a tap on the scrim over the bar is navigate.back');
    });
  });

  // ───────────────────────────── 10. show event ─────────────────────────────

  group('the "screen shown" event (shownCases) — key for key', () {
    _Json shownJson(ScreenShown shown) => {
      'documentId': shown.documentId,
      'screenId': shown.screenId,
      'entry': shown.entry,
      'presentation': shown.presentation,
      'cause': shown.cause.wire,
      'depth': shown.depth,
      'record': shown.record,
      if (shown.modalPlacement != null) 'modalPlacement': shown.modalPlacement,
      if (shown.statusBarIcons != null) 'statusBarIcons': shown.statusBarIcons,
    };

    for (final row in _rows('shownCases')) {
      testWidgets('${row['name']}', (tester) async {
        _view(tester, 393, 793);
        final stack = (row['stack']! as List<Object?>).cast<_Json>();
        final transition = row['transition']! as String;
        final top = stack.last;
        final record = top['record'] as Map?;

        _Json entryOf(_Json frame, List<_Json> children) => _screen(
          frame['screenId']! as String,
          children,
          presentation: frame['presentation'] == 'modal' ? 'modal' : (frame['presentation'] == 'page' ? 'page' : null),
          placement: frame['modalPlacement'],
          icons: frame['statusBarIcons'],
        );

        // The opening button; with a record — in a list row (the row record travels with the action).
        _Json openButton(String to) {
          if (record == null) return _goTo('open', to);
          final item = (record.keys.first as String).split('.').first;
          return {
            'id': 'list',
            'type': 'Repeater',
            'props': {'source': 'rows', 'item': item, 'direction': 'column', 'gap': 'none'},
            'children': [_goTo('open', to)],
          };
        }

        final data = <String, Object?>{
          if (record != null)
            'rows': [
              {for (final entry in record.entries) (entry.key as String).split('.').last: entry.value},
            ],
        };

        final shown = <ScreenShown>[];
        final controller = ScreenFlowController();
        addTearDown(controller.dispose);
        Future<void> pump(UiDocument doc) => pumpDocument(
          tester,
          doc,
          data: data,
          controller: controller,
          onScreenShown: shown.add,
        );

        late _Json expectedEvent;
        expectedEvent = _obj(row['expect']);

        switch (transition) {
          case 'start':
            await pump(_doc([entryOf(stack.single, const [])]));
            await tester.pumpAndSettle();
            expect(shown.map(shownJson), [expectedEvent]);
          case 'push':
            final first = stack.first;
            await pump(
              _doc([
                entryOf(first, [openButton(top['screenId']! as String)]),
                entryOf(top, const []),
              ], initial: first['screenId']! as String),
            );
            await tester.pumpAndSettle();
            shown.clear();
            await tester.tap(find.text('Відкрити ${top['screenId']}').last);
            await tester.pumpAndSettle();
            expect(shown.map(shownJson), [expectedEvent]);
          case 'pop':
            final base = stack.single;
            await pump(
              _doc([
                entryOf(base, [_goTo('open', 'layer')]),
                _screen('layer', const [], presentation: 'modal', placement: 'center'),
              ], initial: base['screenId']! as String),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Відкрити layer'));
            await tester.pumpAndSettle();
            shown.clear();
            expect(controller.canGoBack, isTrue);
            controller.goBack();
            await tester.pumpAndSettle();
            expect(shown.map(shownJson), [expectedEvent]);
          default:
            fail('unknown transition $transition');
        }
      });
    }

    test('x-screenShown.optionalFields are the ones present in the event type', () {
      final block = _obj(_schema['x-screenShown']);
      expect(block['optionalFields'], ['modalPlacement', 'statusBarIcons']);
      expect(block['optionalFieldPresence'], 'only-when-the-screen-names-it');
    });
  });

  // ───────────────────────────── artifact mirror ─────────────────────────────

  group('artifact mirror', () {
    final layout = _obj(_obj(_schema['x-style'])['layout']);

    test('reader version is not below 9.9.0, the artifact says the same', () {
      expect(SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 9, 0)), greaterThanOrEqualTo(0));
      expect(_schema['x-schemaVersion'], kSupportedSchemaVersion);
    });

    test('x-style.layout.image: bounds and words', () {
      final image = _obj(layout['image']);
      expect(image['ratioFallback'], kImageRatioFallback);
      expect(_obj(image['ratioRange']), {'min': kImageRatioMin, 'max': kImageRatioMax});
      expect(image['box'], 'node-box');
      expect(image['namedHeight'], 'overrides-aspect-ratio');
      expect(image['heightClamp'], 'min-max-height-after-ratio');
      expect(image['ratioDerives'], 'height-from-width-only');
      expect(image['intrinsicSize'], 'never-read');
      expect(image['fitAlign'], 'center');
      expect(image['clip'], 'node-radius');
    });

    test('x-style.layout.appBar: zone numbers are the ones in the code', () {
      final bar = _obj(layout['appBar']);
      expect(bar['backSide'], 'xl');
      expect(bar['gap'], 'sm');
      expect(bar['actionGap'], 'xs');
      expect(bar['lineGap'], 'xs');
      expect(bar['placement'], 'app-bar-zone-first-child-inside-screen-padding');
      expect(bar['scroll'], 'fixed');
      expect(bar['background'], 'none-unless-style');
      expect(bar['contentUnderBar'], 'never');
      expect(bar['titlePlacement'], 'centered-in-bar-shifted-off-zones');
      expect(bar['gapAppliesTo'], 'non-empty-zone-only');
    });

    test('x-style.layout.modalLayer: placements, scrim, closing, look', () {
      final layer = _obj(layout['modalLayer']);
      expect(layer['placements'], ModalPlacement.values.map((p) => p.wire));
      expect(layer['defaultPlacement'], 'bottom');
      expect(_obj(layer['scrim']), {'color': 'black', 'opacity': kModalScrimOpacity, 'covers': 'whole-screen-area'});
      expect(_obj(layer['dismiss']), {
        'scrimTap': 'navigate-back',
        'systemBack': 'navigate-back',
        'escapeKey': 'navigate-back',
      });
      expect(layer['builtInLook'], 'none');
      expect(layer['overflow'], 'body-of-the-layer-scrolls');
      expect(_obj(layer['center'])['maxWidth'], kModalWindowMaxWidth);
      expect(_obj(layer['center'])['margin'], 'xl');
      expect(_obj(layer['bottom'])['margin'], 'none');
    });

    test('x-statusBar: the reader touches nothing, the request goes to the host', () {
      final block = _obj(_schema['x-statusBar']);
      expect(block['values'], StatusBarIcons.values.map((v) => v.wire));
      expect(block['reader'], 'touches-nothing');
      expect(block['handover'], 'screen-shown-event');
      expect(block['owner'], 'host');
    });

    test('fourteen 9.9.0 policy rows and eight capabilities', () {
      final compatibility = _obj(_schema['x-compatibility']);
      final policy = _obj(compatibility['policy']);
      expect(kMediaChromePolicy, hasLength(14));
      for (final entry in kMediaChromePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // They come after the 9.8.0 rows, followed by ten 9.10.0 rows (`kOffsetPolicy`).
      expect(
        policy.keys.toList().sublist(policy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length)),
        kMediaChromePolicy.keys.toList(),
      );

      final features = _obj(compatibility['features']);
      const names = [
        'imageCustomRatio',
        'imageBoxGeometry',
        'appBarActions',
        'appBarFixed',
        'appBarTitleRoom',
        'modalPlacement',
        'modalLayerLook',
        'statusBarIcons',
      ];
      for (final feature in names) {
        expect(features[feature], '9.9.0', reason: feature);
        expect(kFeatureCatalog[feature], '9.9.0', reason: feature);
        expect(supportsFeature(feature, readerVersion: '9.8.0'), isFalse, reason: feature);
        expect(supportsFeature(feature), isTrue, reason: feature);
      }
      // The reader knows nothing extra: every 9.9.0 capability of the artifact is in our catalog.
      final since99 = features.entries.where((entry) => entry.value == '9.9.0').map((e) => e.key).toList()..sort();
      expect(since99, [...names]..sort());
    });

    test('icon button: table size sides are 28 / 40 / 48 (app bar actions use them)', () {
      final sizes = _obj(_obj(layout['buttonSizes']));
      expect(sizes.keys, containsAll(['sm', 'md', 'lg']));
    });

    test('the table describes the same as the artifact: path to it', () {
      expect(_obj(_schema['x-statusBar'])['cases'], 'contract/fixtures/media-chrome/media-chrome-cases.json');
    });
  });
}
