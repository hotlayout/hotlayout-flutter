/// ALIGNMENT OF CHILDREN ON BOTH AXES: COLUMN, CONTAINER, SCREEN (schema 9.15.0).
///
/// The tests read the contract table ITSELF
/// (`assets/contract/fixtures/align/align-cases.json`, a copy of
/// `contract/fixtures/align/align-cases.json`, 139 rows) and run the rows
/// that concern the reader through the reader's formula (`layout_rules.dart`) and a REAL
/// widget:
///
///  1. `readCases` (15) -- which axis is main and which words apply after "as if no field";
///  2. `heightSourceCases` (20) -- where a column gets a height greater than its content;
///  3. `shiftCases` (12) -- child shifts along the main axis;
///  4. `boxCases` (54) -- child rectangles: the formula and a real widget in both
///     writing directions;
///  5. `screenCases` (18) -- the screen body: a real screen with an app bar, a bar,
///     a pinned block and a modal layer;
///  6. `ruleCases` (20) -- the `x-style.layout.alignment` data block.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = (json.decode(File('assets/contract/fixtures/align/align-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final _Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);

void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// Table node -> the reader's parsed node (the `fill` node fields sit next to `type`).
UiNode _parse(_Json node, {String id = 'n'}) => UiNode.parse({'id': id, ...node});

AlignToken _alignOf(String wire) => AlignToken.values.firstWhere((v) => v.wire == wire);
JustifyToken _justifyOf(String wire) => JustifyToken.values.firstWhere((v) => v.wire == wire);

String _hex(int i) => '#11${(i + 16).toRadixString(16).padLeft(2, '0')}cc';
Color _color(int i) => Color(int.parse('ff${_hex(i).substring(1)}', radix: 16));

Finder _box(int i) => find.byWidgetPredicate(
  (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == _color(i),
  description: 'box ${_hex(i)}',
);

_Json _kid(int i, {required double height, double? width}) => {
  'id': 'k$i',
  'type': 'Container',
  'props': {'direction': 'column'},
  'style': {
    'background': {'kind': 'color', 'color': {'value': _hex(i)}},
    'height': height,
    'width': ?width,
  },
};

void main() {
  test('table: 139 rows in six groups', () {
    final counts = {
      'readCases': 15,
      'heightSourceCases': 20,
      'shiftCases': 12,
      'boxCases': 54,
      'screenCases': 18,
      'ruleCases': 20,
    };
    for (final entry in counts.entries) {
      expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
    }
    expect(counts.values.reduce((a, b) => a + b), 139);
  });

  // ───────────────────────────── readCases ─────────────────────────────

  group('readCases: words and the main axis', () {
    for (final row in _rows('readCases')) {
      test(row['name']! as String, () {
        final node = _parse(_obj(row['node']));
        final expected = _obj(row['expect']);
        final axis = alignmentMainAxisOf(node);
        expect(axis?.name, expected['mainAxis']);
        if (expected['mainAxis'] == null) return;
        expect(crossAlignOf(node).wire, expected['align']);
        expect(mainJustifyOf(node).wire, expected['justify']);
      });
    }
  });

  // ───────────────────────────── heightSourceCases ─────────────────────────────

  group('heightSourceCases: the column height source', () {
    for (final row in _rows('heightSourceCases')) {
      test(row['name']! as String, () {
        final node = _parse(_obj(row['node']));
        final parentType = row['parent'] as String?;
        final parent = parentType == null ? null : _parse({'type': parentType, 'props': <String, Object?>{}}, id: 'p');
        final own = _obj(row['own']);
        final expected = _obj(row['expect']);
        final source = node is ChildNode && alignmentMainAxisOf(node) == AlignmentMainAxis.block
            ? columnHeightSourceOf(node, parent, height: own['height'] == true, minHeight: own['minHeight'] == true)
            : null;
        expect(source?.wire, expected['source']);
        expect(
          mainAxisSpaceOf(node, parent, height: own['height'] == true, minHeight: own['minHeight'] == true),
          expected['space'],
        );
      });
    }
  });

  // ───────────────────────────── shiftCases ─────────────────────────────

  group('shiftCases: shifts along the main axis', () {
    for (final row in _rows('shiftCases')) {
      test(row['name']! as String, () {
        final shifts = mainAxisShifts(_num(row['free']), (row['count']! as num).toInt(), _justifyOf(row['justify']! as String));
        final expected = (row['expect']! as List<Object?>).cast<num>();
        expect(shifts, hasLength(expected.length));
        for (var i = 0; i < expected.length; i++) {
          expect(shifts[i], closeTo(expected[i].toDouble(), 1e-9), reason: 'child $i');
        }
      });
    }
  });

  // ───────────────────────────── boxCases ─────────────────────────────

  group('boxCases: child rectangles', () {
    for (final row in _rows('boxCases')) {
      final axis = row['axis'] == 'inline' ? AlignmentMainAxis.inline : AlignmentMainAxis.block;
      final children = _rows2(row['children']);
      final inline = _num(row['inline']);
      final block = row['block'] == null ? null : _num(row['block']);
      final minBlock = row['minBlock'] == null ? null : _num(row['minBlock']);
      final gap = _num(row['gap']);
      final align = _alignOf(row['align']! as String);
      final justify = _justifyOf(row['justify']! as String);
      final rtl = row['rtl'] == true;
      final expected = _obj(row['expect']);
      final rects = _rows2(expected['rects']);

      test('formula: ${row['name']}', () {
        final got = alignedChildRects(
          axis: axis,
          inline: inline,
          block: block,
          minBlock: axis == AlignmentMainAxis.block ? minBlock : null,
          gap: gap,
          align: align,
          justify: justify,
          rtl: rtl,
          children: [
            for (final child in children)
              AlignedChild(_num(child['width']), _num(child['height']), stretch: child['stretch'] == true),
          ],
        );
        expect(got.block, _near(_num(expected['block'])));
        expect(got.free, _near(_num(expected['free'])));
        expect(got.rects, hasLength(rects.length));
        for (var i = 0; i < rects.length; i++) {
          expect(got.rects[i].x, _near(_num(rects[i]['x'])), reason: 'x of child $i');
          expect(got.rects[i].y, _near(_num(rects[i]['y'])), reason: 'y of child $i');
          expect(got.rects[i].width, _near(_num(rects[i]['width'])), reason: 'width of child $i');
          expect(got.rects[i].height, _near(_num(rects[i]['height'])), reason: 'height of child $i');
        }
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, inline, 1600);
        final isRow = row['host'] == 'Container row';
        final style = <String, Object?>{
          'background': {'kind': 'color', 'color': {'value': _hex(99)}},
          'height': ?block,
          if (axis == AlignmentMainAxis.block) 'minHeight': ?minBlock,
        };
        final host = <String, Object?>{
          'id': 'host',
          'type': row['host'] == 'Column' ? 'Column' : 'Container',
          'props': {
            'gap': gap,
            'align': align.wire,
            'justify': justify.wire,
            if (row['host'] != 'Column') 'direction': isRow ? 'row' : 'column',
          },
          'style': style,
          'children': [
            for (var i = 0; i < children.length; i++)
              _kid(
                i,
                height: _num(children[i]['height']),
                // A stretched column child names no width; the rest are natural.
                width: axis == AlignmentMainAxis.block && children[i]['stretch'] == true ? null : _num(children[i]['width']),
              ),
          ],
        };
        await pumpDocument(tester, UiDocumentBuilder.bare([host]), locale: rtl ? 'ar' : null);
        expect(tester.takeException(), isNull);
        final hostRect = tester.getRect(_box(99));
        expect(hostRect.width, _near(inline));
        expect(hostRect.height, _near(_num(expected['block'])), reason: 'content box height');
        for (var i = 0; i < rects.length; i++) {
          final rect = tester.getRect(_box(i));
          expect(rect.left - hostRect.left, _near(_num(rects[i]['x'])), reason: 'x of child $i');
          expect(rect.top - hostRect.top, _near(_num(rects[i]['y'])), reason: 'y of child $i');
          expect(rect.width, _near(_num(rects[i]['width'])), reason: 'width of child $i');
          expect(rect.height, _near(_num(rects[i]['height'])), reason: 'height of child $i');
        }
      });
    }
  });

  // ───────────────────────────── screenCases ─────────────────────────────

  group('screenCases: the screen body', () {
    for (final row in _rows('screenCases')) {
      final height = _num(row['height']);
      final padding = _obj(row['padding']);
      final gap = _num(row['gap']);
      final heights = (row['children']! as List<Object?>).map(_num).toList();
      final justify = row['justify']! as String;
      final barHeight = row['appBarHeight'] == null ? null : _num(row['appBarHeight']);
      final bottom = row['bottom'] == null ? null : _obj(row['bottom']);
      final shrink = row['shrink'] == true;
      final expected = _obj(row['expect']);
      final tops = (expected['tops']! as List<Object?>).map(_num).toList();

      test('formula: ${row['name']}', () {
        final body = _obj(expected['body']);
        // Body with an app bar: the top padding is the screen gap; with a pinned block the bottom one is too.
        final top = barHeight == null ? _num(padding['top']) : gap;
        final bot = bottom?['pinnedHeight'] != null ? gap : _num(padding['bottom']);
        final content = top + heights.fold<double>(0, (a, b) => a + b) + (heights.length > 1 ? gap * (heights.length - 1) : 0) + bot;
        expect(screenBodyFreeSpace(bodyHeight: _num(body['height']), contentHeight: content), _near(_num(expected['free'])));
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, 320, height);
        final kids = [for (var i = 0; i < heights.length; i++) _kid(i, height: heights[i])];
        final content = <_Json>[
          if (barHeight != null)
            {
              'id': 'bar',
              'type': 'AppBar',
              'props': {
                'title': {'kind': 'literal', 'value': 'Шапка'},
                'showBack': false,
              },
              'style': {'height': barHeight},
            },
          ...kids,
          if (bottom?['pinnedHeight'] != null)
            {
              'id': 'pin',
              'type': 'Container',
              'props': {'direction': 'column'},
              'style': {'height': bottom!['pinnedHeight'], 'background': {'kind': 'color', 'color': {'value': _hex(98)}}},
              'pin': 'bottom',
            },
          if (bottom?['navBarHeight'] != null)
            {
              'id': 'nav',
              'type': 'NavBar',
              'props': <String, Object?>{},
              'children': [
                for (final id in ['a', 'b', 'c'])
                  {
                    'id': id,
                    'type': 'NavItem',
                    'props': {
                      'icon': 'house',
                      'label': {'kind': 'literal', 'value': id},
                      'action': {'type': 'navigate.section', 'params': {'screenId': id}},
                    },
                  },
              ],
            },
        ];
        _Json screen(String id, List<_Json> children, {String? presentation}) => {
          'screenId': id,
          'name': id,
          'presentation': ?presentation,
          'root': {
            'id': '$id-root',
            'type': 'Screen',
            'props': {'gap': gap, 'justify': justify},
            'style': {'padding': padding},
            'children': children,
          },
        };
        final screens = shrink
            ? [
                screen('page', [
                  {
                    'id': 'open',
                    'type': 'Button',
                    'props': {
                      'label': {'kind': 'literal', 'value': 'Відкрити'},
                      'variant': 'primary',
                      'action': {'type': 'navigate', 'params': {'screenId': 'layer'}},
                    },
                  },
                ]),
                screen('layer', content, presentation: 'modal'),
              ]
            : [screen('s', content)];
        await pumpDocument(
          tester,
          UiDocument.fromJson({
            'schemaVersion': kSupportedSchemaVersion,
            'documentId': 'align',
            'name': 'align',
            'initialScreenId': screens.first['screenId'],
            'screens': screens,
          }),
        );
        if (shrink) {
          await tester.tap(find.text('Відкрити'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        // Coordinates are from the top of the layer / screen: for a bottom layer we take the top of the first child
        // relative to the bottom edge of the window.
        final frame = shrink
            ? tester.getRect(find.byType(SingleChildScrollView).last)
            : Rect.fromLTWH(0, 0, 320, height);
        // A "by content" layer sits above the screen bottom: all coordinates are from the top of the layer.
        final base = shrink ? frame.top : 0.0;
        for (var i = 0; i < tops.length; i++) {
          expect(tester.getRect(_box(i)).top - base, _near(tops[i]), reason: 'top of child $i');
        }
        final scrolls = expected['scrolls'] == true;
        final position = tester
            .state<ScrollableState>(find.descendant(of: find.byType(SingleChildScrollView).last, matching: find.byType(Scrollable)).first)
            .position;
        expect(position.maxScrollExtent > 0.01, scrolls, reason: 'scrolls');
      });
    }
  });

  // ───────────────────────────── non-sources ─────────────────────────────

  group('a column without a height source does not read justify', () {
    testWidgets('in a tab', (tester) async {
      _view(tester, 320, 800);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'tabs',
            'type': 'Tabs',
            'props': <String, Object?>{},
            'children': [
              {
                'id': 'tab',
                'type': 'Tab',
                'props': {'title': {'kind': 'literal', 'value': 'T'}},
                'children': [
                  {
                    'id': 'col',
                    'type': 'Column',
                    'props': {'gap': 0, 'justify': 'end'},
                    'children': [_kid(0, height: 30), _kid(1, height: 30)],
                  },
                ],
              },
            ],
          },
        ]),
      );
      expect(tester.takeException(), isNull);
      final a = tester.getRect(_box(0));
      final b = tester.getRect(_box(1));
      expect(b.top - a.bottom, 0, reason: 'children are flush: the column sees no free space');
    });

    testWidgets('a neighbour taller than the column in a row: the column does not stretch', (tester) async {
      _view(tester, 320, 800);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'row',
            'type': 'Row',
            'props': {'gap': 0, 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': false},
            'children': [
              {
                'id': 'col',
                'type': 'Column',
                'props': {'gap': 0, 'justify': 'end'},
                'children': [_kid(0, height: 30, width: 50)],
              },
              _kid(1, height: 200, width: 50),
            ],
          },
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_box(0)).top, 0, reason: 'the column is as tall as its content, children at the top');
    });
  });

  // ───────────────────────────── ruleCases ─────────────────────────────

  group('ruleCases: the x-style.layout.alignment block', () {
    final block = _obj(_obj(_obj(_schema['x-style'])['layout'])['alignment']);
    Object? at(String path) {
      Object? current = block;
      for (final part in path.split('.')) {
        current = (current! as Map)[part];
      }
      return current;
    }

    for (final row in _rows('ruleCases')) {
      test('${row['rule']} — ${row['name']}', () => expect(at(row['rule']! as String), row['expect']));
    }

    test('the code words and defaults are the ones in the artifact', () {
      expect(JustifyToken.values.map((v) => v.wire).toList(), at('main.values'));
      expect(kJustifyWithoutProp.wire, at('main.withoutProp'));
      expect(kCrossAlignBlockWithoutProp.wire, at('cross.block.withoutProp'));
      expect(kCrossAlignInlineWithoutProp.wire, at('cross.inline.withoutProp'));
      expect(ColumnHeightSource.values.map((v) => v.wire).toSet(), (at('main.column.heightSources')! as List).toSet());
    });

    test('the reader knows every key of the block', () {
      expect(block.keys.toSet(), {'props', 'hosts', 'cross', 'main', 'screen', 'validator'});
    });
  });
}

List<_Json> _rows2(Object? value) => (value! as List<Object?>).cast<_Json>();
