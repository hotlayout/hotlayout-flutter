/// APP BAR FROM THE MOCKUP AND AN OWN GLYPH SIZE (schema 9.16.0).
///
/// The tests read the NEW groups of the table
/// `assets/contract/fixtures/media-chrome/media-chrome-cases.json` (a copy of
/// `contract/fixtures/media-chrome/media-chrome-cases.json`, 140 rows of 9.16.0):
///
///  1. `appBarLeadingCases` (48) -- app bar zones with a node in the leading zone: formula
///     and REAL layout in both writing directions, `rtlLeft` from the left edge;
///  2. `appBarLeadingShownCases` (6), `appBarChildrenCases` (10),
///     `appBarPlaceCases` (9) -- which node is the zone node, which are actions, what is drawn;
///  3. `appBar916DocumentCases` (16) -- a document the schema accepts, the reader draws
///     and does not crash;
///  4. `glyphCases` (32) -- box and glyph of `Icon` and `IconButton`: formula and
///     real widget;
///  5. `appBar916RuleCases` (19) -- the data blocks `appBarLeading`, `appBarTitle`,
///     `ownGlyphSize`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/render/app_bar_layout.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = (json.decode(File('assets/contract/fixtures/media-chrome/media-chrome-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final _Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map).cast<String, Object?>();

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);

void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

({String type, BarZone? zone}) _kind(Object? raw) {
  final map = _obj(raw);
  return (type: map['type']! as String, zone: barZoneOf(map['zone']));
}

_Json _literal(String text) => {'kind': 'literal', 'value': text};

/// A node of the given type with minimally complete props -- for rows that name only the type.
_Json _node(Object? raw, String id) {
  final map = _obj(raw);
  final type = map['type']! as String;
  return {
    'id': id,
    'type': type,
    'props': switch (type) {
      'Button' => {'label': _literal('Вийти'), 'variant': 'secondary', 'action': {'type': 'navigate.back'}, 'fullWidth': false},
      'IconButton' => {'icon': 'info', 'label': _literal('Інфо'), 'action': {'type': 'none'}},
      'Icon' => {'name': 'trophy', 'size': 'md'},
      _ => <String, Object?>{},
    },
    if (map.containsKey('zone')) 'zone': map['zone'],
    if (map.containsKey('glyphSize')) 'props2': null,
  }..remove('props2');
}

void main() {
  final tokens = _obj(_table['tokens']);
  final tokens916 = _obj(_table['tokens916']);

  test('table 9.16.0: seven groups, 140 rows', () {
    const counts = {
      'appBarLeadingCases': 48,
      'appBarLeadingShownCases': 6,
      'appBarChildrenCases': 10,
      'appBarPlaceCases': 9,
      'appBar916DocumentCases': 16,
      'glyphCases': 32,
      'appBar916RuleCases': 19,
    };
    for (final entry in counts.entries) {
      expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
    }
    expect(counts.values.reduce((a, b) => a + b), 140);
  });

  // ───────────────────────────── appBarLeadingCases ─────────────────────────────

  group('appBarLeadingCases: app bar zones with a node in the leading zone', () {
    for (final row in _rows('appBarLeadingCases')) {
      final expected = _obj(row['expect']);
      final sides = [for (final side in row['actionSides']! as List<Object?>) _num(side)];
      final width = _num(row['width']);
      final leadingNatural = row['leadingNatural'] == null ? null : _num(row['leadingNatural']);
      final showBack = row['showBack']! as bool;

      AppBarZones zones() => appBarZones(
        width: width,
        showBack: showBack,
        backSide: _num(tokens['backSide']),
        actionSides: sides,
        gap: _num(tokens['gap']),
        actionGap: _num(tokens['actionGap']),
        titleNatural: _num(row['titleNatural']),
        leadingNatural: leadingNatural,
        titleAlign: row['titleAlign'],
      );

      test('formula: ${row['name']}', () {
        final z = zones();
        expect(z.leadingShown.name, expected['leadingShown']);
        expect(z.leadingWidth, _near(_num(expected['leadingWidth'])));
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
          final shown = expected['leadingShown']! as String;
          final hasLeading = shown != 'none';
          await tester.pumpWidget(
            Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: AppBarLayout(
                    hasBack: hasLeading,
                    leadingIsNode: shown == 'node',
                    titleAlign: titleAlignOf(row['titleAlign']),
                    backSide: _num(tokens['backSide']),
                    gap: _num(tokens['gap']),
                    actionGap: _num(tokens['actionGap']),
                    children: [
                      if (shown == 'node') SizedBox(width: leadingNatural, height: 40),
                      if (shown == 'back') const SizedBox.square(dimension: 24),
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
          // The app bar height is that of the tallest of the three zones.
          final tallest = [
            if (shown == 'node') 40.0,
            if (shown == 'back') 24.0,
            20.0,
            ...sides,
          ].reduce(math.max);
          expect(render.size.height, tallest);
          expect(render.size.width, width);

          double fromStart(Offset offset, Size size) =>
              direction == TextDirection.ltr ? offset.dx : width - offset.dx - size.width;
          var index = 0;
          if (hasLeading) {
            expect(fromStart(offsets[index], boxes[index]), _near(0), reason: 'the leading zone is at the start of the row');
            if (shown == 'node') {
              expect(boxes[index].width, _near(_num(expected['leadingWidth'])), reason: 'node width (clamped to half)');
            }
            index += 1;
          }
          expect(fromStart(offsets[index], boxes[index]), _near(_num(expected['titleStart'])), reason: 'title start');
          expect(boxes[index].width, _near(_num(expected['titleWidth'])), reason: 'title width');
          index += 1;
          final starts = (expected['actionStarts']! as List<Object?>).map(_num).toList();
          for (var i = 0; i < starts.length; i += 1) {
            expect(fromStart(offsets[index + i], boxes[index + i]), _near(starts[i]), reason: 'action $i');
          }
          for (var i = 0; i < offsets.length; i += 1) {
            expect(offsets[i].dy, _near((tallest - boxes[i].height) / 2), reason: 'centred across');
          }

          // `rtlLeft`: the same layout as offsets from the LEFT edge in right-to-left writing.
          final rtl = row['rtlLeft'];
          if (rtl != null && direction == TextDirection.rtl) {
            final left = _obj(rtl);
            var i = 0;
            if (hasLeading) {
              expect(offsets[i].dx, _near(_num(left['leading'])), reason: 'rtlLeft: leading zone');
              i += 1;
            } else {
              expect(left['leading'], isNull);
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
  });

  // ───────────────────────────── shown / children / place ─────────────────────────────

  group('what is in the leading zone, which node, which actions, where a child goes', () {
    for (final row in _rows('appBarLeadingShownCases')) {
      test('shown: ${row['name']}', () {
        expect(appBarLeadingShown(row['nodeVisible'] as bool?, row['showBack']! as bool).name, row['expect']);
      });
    }
    for (final row in _rows('appBarChildrenCases')) {
      test('children: ${row['name']}', () {
        final kinds = [for (final child in row['children']! as List<Object?>) _kind(child)];
        expect(appBarLeadingIndex(kinds), row['leading']);
        expect(appBarActionIndexes(kinds), (row['actions']! as List<Object?>).cast<int>());
      });
    }
    for (final row in _rows('appBarPlaceCases')) {
      test('place: ${row['name']}', () {
        final siblings = [for (final child in row['siblings']! as List<Object?>) _kind(child)];
        expect(appBarPlaceOf(siblings, _kind(row['child'])), row['expect']);
      });
    }
  });

  // ───────────────────────────── appBar916DocumentCases ─────────────────────────────

  group('appBar916DocumentCases: what the structure accepts, the reader draws and does not crash', () {
    for (final row in _rows('appBar916DocumentCases')) {
      if (row['schema'] != true) continue;
      testWidgets(row['name']! as String, (tester) async {
        _view(tester, 393, 800);
        var counter = 0;
        final barChildren = row['appBarChildren'] as List<Object?>?;
        final bodyChildren = row['bodyChildren'] as List<Object?>?;
        final children = <_Json>[
          if (barChildren != null || row['appBarProps'] != null)
            {
              'id': 'bar',
              'type': 'AppBar',
              'props': {
                'title': _literal('Заголовок'),
                'showBack': true,
                ...?(row['appBarProps'] as Map?)?.cast<String, Object?>(),
              },
              'children': [for (final child in barChildren ?? const []) _node(child, 'b${counter++}')],
            },
          for (final child in bodyChildren ?? const []) _node(child, 'c${counter++}'),
        ];
        await pumpDocument(tester, UiDocumentBuilder.bare(children));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ───────────────────────────── glyphCases ─────────────────────────────

  group('glyphCases: box and glyph of Icon and IconButton', () {
    const defaultPadding = {'sm': 4, 'md': 8, 'lg': 12};
    for (final row in _rows('glyphCases')) {
      final expected = _obj(row['expect']);
      final typography = _obj(row['typography']);
      final style = _obj(row['style']);
      final isButton = row['widget'] == 'IconButton';

      test('formula: ${row['name']}', () {
        final padding = _num(row['padding']);
        final input = (
          font: _num(typography['fontSize']),
          line: _num(typography['lineHeight']),
          border: _num(row['border']),
        );
        final geometry = isButton
            ? iconButtonGeometryOf(
                glyphSize: row['glyphSize'],
                fontSize: input.font,
                lineHeight: input.line,
                paddingInline: 2 * padding,
                paddingBlock: 2 * padding,
                borderWidth: input.border,
                width: style['width'] == null ? null : _num(style['width']),
                height: style['height'] == null ? null : _num(style['height']),
              )
            : iconGeometryOf(
                glyphSize: row['glyphSize'],
                fontSize: input.font,
                lineHeight: input.line,
                paddingInline: 2 * padding,
                paddingBlock: 2 * padding,
                borderWidth: input.border,
                width: style['width'] == null ? null : _num(style['width']),
                height: style['height'] == null ? null : _num(style['height']),
              );
        expect(geometry.glyph, _near(_num(expected['glyph'])));
        expect(geometry.contentInline, _near(_num(_obj(expected['content'])['inline'])));
        expect(geometry.contentBlock, _near(_num(_obj(expected['content'])['block'])));
        expect(geometry.boxInline, _near(_num(_obj(expected['box'])['inline'])));
        expect(geometry.boxBlock, _near(_num(_obj(expected['box'])['block'])));
        expect(geometry.own, expected['own']);
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, 393, 800);
        final padding = _num(row['padding']);
        final wordPadding = isButton ? (defaultPadding[row['size']]!).toDouble() : 0.0;
        final nodeStyle = <String, Object?>{
          ...style,
          if (padding != wordPadding) 'padding': padding,
          if (_num(row['border']) > 0) 'border': {'color': 'border', 'width': _num(row['border'])},
        };
        final node = <String, Object?>{
          'id': 'g',
          'type': isButton ? 'IconButton' : 'Icon',
          'props': {
            if (isButton) ...{'icon': 'info', 'label': _literal('Інфо'), 'variant': 'primary', 'action': {'type': 'none'}},
            if (!isButton) 'name': 'trophy',
            'size': row['size'],
            if (row.containsKey('glyphSize')) 'glyphSize': row['glyphSize'],
          },
          'style': nodeStyle.isEmpty ? null : nodeStyle,
        }..removeWhere((key, value) => key == 'style' && value == null);
        await pumpDocument(tester, UiDocumentBuilder.bare([node]));
        expect(tester.takeException(), isNull);

        final column = tester.renderObject<RenderStretchColumn>(find.byType(StretchColumn).first);
        final box = column.firstChild!.size;
        expect(box.width, _near(_num(_obj(expected['box'])['inline'])), reason: 'node width');
        expect(box.height, _near(_num(_obj(expected['box'])['block'])), reason: 'node height');

        // Content box: where a side is NOT named, it is the glyph box itself. Where named,
        // the content box is the named side without padding and border; the glyph sits at its centre.
        final drawing = find.byWidgetPredicate((w) => w is IconBox || w is OwnGlyphBox);
        final content = tester.getSize(drawing);
        if (style['width'] == null) {
          expect(content.width, _near(_num(_obj(expected['content'])['inline'])), reason: 'content box width');
        }
        if (style['height'] == null) {
          expect(content.height, _near(_num(_obj(expected['content'])['block'])), reason: 'content box height');
        }
        final glyphFinder = find.byType(IconGlyph);
        final glyph = tester.getSize(glyphFinder);
        expect(glyph.width, _near(_num(expected['glyph'])), reason: 'glyph side');
        if (style.isNotEmpty && _num(expected['glyph']) > 0) {
          // The glyph is at the centre of the content box: for a named axis that is the node centre (padding
          // and border are symmetric).
          final nodeRect = Rect.fromLTWH(0, 0, box.width, box.height);
          final column = tester.getTopLeft(find.byType(StretchColumn).first);
          final centre = tester.getCenter(glyphFinder) - column;
          if (style['width'] != null) expect(centre.dx, _near(nodeRect.center.dx), reason: 'glyph at the box centre (x)');
          if (style['height'] != null) expect(centre.dy, _near(nodeRect.center.dy), reason: 'glyph at the box centre (y)');
        }
      });
    }

    testWidgets('a number is not multiplied by the system font scale, a word is', (tester) async {
      Future<Size> glyphAt(Map<String, Object?> props) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: renderDocument(
                  UiDocumentBuilder.bare([
                    {
                      'id': 'g',
                      'type': 'Icon',
                      'props': {'name': 'trophy', 'size': 'md', ...props},
                    },
                  ]),
                  theme: RenderTheme.fallback(),
                  data: const {},
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byType(IconGlyph));
      }

      final word = await glyphAt({});
      final own = await glyphAt({'glyphSize': 32});
      expect(own.width, 32, reason: 'number: logical pixels');
      expect(word.width, 36, reason: 'a word grows with the scale: 18 × 2');
    });
  });

  // ───────────────────────────── appBar916RuleCases ─────────────────────────────

  group('appBar916RuleCases: data blocks of 9.16.0', () {
    final layout = _obj(_obj(_schema['x-style'])['layout']);
    Object? at(String path) {
      Object? current = layout;
      for (final part in path.split('.')) {
        current = (current! as Map)[part];
      }
      return current;
    }

    for (final row in _rows('appBar916RuleCases')) {
      test('${row['rule']} — ${row['name']}', () => expect(at(row['rule']! as String), row['expect']));
    }

    test('the code numbers are the ones in the artifact', () {
      expect(kAppBarLeadingMaxShare, at('appBarLeading.maxShare'));
      expect(tokens916['maxShare'], kAppBarLeadingMaxShare);
      expect(kGlyphSizeMin, at('ownGlyphSize.range.min'));
      expect(kGlyphSizeMax, at('ownGlyphSize.range.max'));
      expect(tokens['backSide'], isNotNull);
    });

    test('the reader knows every key of the appBarLeading, appBarTitle, ownGlyphSize blocks', () {
      expect(_obj(layout['appBarLeading']).keys.toSet(), {
        'widget', 'field', 'value', 'on', 'types', 'is', 'max', 'extra', 'order', 'countsAsAction', 'replacesBack', 'hidden',
        'action', 'look', 'width', 'maxShare', 'shrinks', 'tight', 'gap', 'crossAlign', 'height', 'elsewhere', 'unknown',
        'before916',
      });
      expect(_obj(layout['appBarTitle']).keys.toSet(), {'widget', 'field', 'values', 'default', 'center', 'start', 'direction', 'room', 'overflow', 'unknown'});
      expect(_obj(layout['ownGlyphSize']).keys.toSet(), {
        'field', 'on', 'unit', 'range', 'overrides', 'glyph', 'align', 'icon', 'iconButton', 'namedBox', 'textScale', 'unreadable', 'before916',
      });
    });
  });
}
