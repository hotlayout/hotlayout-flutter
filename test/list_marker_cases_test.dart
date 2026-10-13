/// LIST ITEM (schema 9.17.0): the `Text.marker` field.
///
/// The test reads the SHARED table
/// `assets/contract/fixtures/list-marker/list-marker-cases.json` (69 rows) and
/// runs it through the formula (`list_marker.dart`) and a REAL widget:
///
///  1. `geometryCases` (18) - column, gap and hanging indent: fractions of the font size;
///  2. `textCases` (10) - what the marker says: "•", digits in the format language, and a full stop;
///  3. `numberCases` (17) - group and number: by formula over the neighbours and by a real
///     screen (an item hidden by a condition takes no number but widens the column);
///  4. `instanceCases` (5) - a list template from data counts its instances;
///  5. `layoutCases` (16) - rectangles of the marker column and the text in both directions,
///     hanging indent, `maxLines` cuts only the text, the mark on the first baseline;
///  6. `naturalCases` (3) - natural width of an item in a row.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/list_marker.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = (json.decode(File('assets/contract/fixtures/list-marker/list-marker-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final _Row _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map).cast<String, Object?>();

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);

DrawnTextMarker _drawn(String wire) => wire == 'bullet' ? DrawnTextMarker.bullet : DrawnTextMarker.number;

void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// Item node: text with the word `marker`, `id` = `t<i>`, content = `t<i>` (or explicit).
_Row _item(int i, {Object? marker, Object? visibleIf, String? content, Map<String, Object?>? style, Object? align, int? maxLines}) => {
  'id': 't$i',
  'type': 'Text',
  'props': {
    'content': {'kind': 'literal', 'value': content ?? 't$i'},
    'align': align ?? 'start',
    'overflow': 'clip',
    'maxLines': ?maxLines,
    'marker': ?marker,
  },
  'style': ?style,
  'visibleIf': ?visibleIf,
};

const _Row _hidden = {'path': 'x.shown', 'op': 'isTrue'};

void main() {
  test('table: six groups, 69 rows', () {
    const counts = {
      'geometryCases': 18,
      'textCases': 10,
      'numberCases': 17,
      'instanceCases': 5,
      'layoutCases': 16,
      'naturalCases': 3,
    };
    for (final entry in counts.entries) {
      expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
      final names = _rows(entry.key).map((row) => row['name']).toList();
      expect(names.toSet(), hasLength(names.length), reason: '${entry.key}: names are unique');
    }
    expect(counts.values.reduce((a, b) => a + b), 69);
  });

  group('geometryCases: fractions of the font size', () {
    for (final row in _rows('geometryCases')) {
      test(row['name']! as String, () {
        final geometry = listMarkerGeometry(_drawn(row['marker']! as String), _num(row['fontSize']), groupSize: (row['groupSize']! as num).toInt());
        final expected = row['expect']! as _Row;
        expect(geometry.column, _near(_num(expected['column'])));
        expect(geometry.gap, _near(_num(expected['gap'])));
        expect(geometry.indent, _near(_num(expected['indent'])));
      });
    }
  });

  group('textCases: what the marker says', () {
    for (final row in _rows('textCases')) {
      test(row['name']! as String, () {
        expect(
          listMarkerText(_drawn(row['marker']! as String), (row['number']! as num).toInt(), row['formattingLocale'] as String?),
          row['expect'],
        );
      });
    }
  });

  group('numberCases: group and number', () {
    List<DrawnTextMarker?> markersOf(_Row row) => [
      for (final sibling in (row['siblings']! as List<Object?>).cast<_Row>())
        sibling['type'] == 'Text' ? drawnMarkerOf(readTextMarker(sibling['marker'])) : null,
    ];
    List<bool> visibleOf(_Row row) => [
      for (final sibling in (row['siblings']! as List<Object?>).cast<_Row>()) sibling['visible'] != false,
    ];

    for (final row in _rows('numberCases')) {
      final expected = row['expect']! as _Row;
      final numbers = (expected['numbers']! as List<Object?>).cast<int?>();
      final sizes = (expected['groupSizes']! as List<Object?>).cast<int?>();

      test('formula: ${row['name']}', () {
        final markers = markersOf(row);
        final visible = visibleOf(row);
        expect([for (var i = 0; i < markers.length; i++) listNumberOf(markers, i, visible)], numbers);
        expect([for (var i = 0; i < markers.length; i++) listMarkerGroupSize(markers, i)], sizes);
      });

      testWidgets('real screen: ${row['name']}', (tester) async {
        _view(tester, 393, 3000);
        final siblings = (row['siblings']! as List<Object?>).cast<_Row>();
        final nodes = <_Row>[
          for (var i = 0; i < siblings.length; i++)
            switch (siblings[i]['type']) {
              'Text' => _item(
                i,
                marker: siblings[i]['marker'],
                visibleIf: siblings[i]['visible'] == false ? _hidden : null,
              ),
              'Divider' => {'id': 't$i', 'type': 'Divider', 'props': <String, Object?>{}, 'visibleIf': siblings[i]['visible'] == false ? _hidden : null}
                ..removeWhere((k, v) => v == null),
              _ => {'id': 't$i', 'type': 'Spacer', 'props': <String, Object?>{'size': 'sm'}, 'visibleIf': siblings[i]['visible'] == false ? _hidden : null}
                ..removeWhere((k, v) => v == null),
            },
        ];
        await pumpDocument(tester, UiDocumentBuilder.bare(nodes), data: const {});
        expect(tester.takeException(), isNull);

        final visible = visibleOf(row);
        for (var i = 0; i < siblings.length; i++) {
          if (siblings[i]['type'] != 'Text') continue;
          final shown = visible[i];
          if (!shown) {
            expect(find.text('t$i'), findsNothing, reason: 'hidden by a condition is not painted');
            continue;
          }
          final marker = readTextMarker(siblings[i]['marker']);
          final body = find.text('t$i');
          expect(body, findsOneWidget);
          if (drawnMarkerOf(marker) == null) {
            expect(find.ancestor(of: body, matching: find.byType(Row)), findsNothing, reason: 'an item without a marker is plain text');
            continue;
          }
          // A real marker: text in the column, the mark in the same row.
          final row0 = find.ancestor(of: body, matching: find.byType(Row)).first;
          final label = tester.widget<Text>(
            find.descendant(of: find.descendant(of: row0, matching: find.byType(MarkerColumnEnd)), matching: find.byType(Text)),
          );
          expect(label.data, listMarkerText(_drawn(marker.wire), numbers[i] ?? 1, null), reason: 'item mark $i');
          final column = tester.getSize(find.descendant(of: row0, matching: find.byType(SizedBox)).first).width;
          final geometry = listMarkerGeometry(_drawn(marker.wire), 14.0 * 1.0, groupSize: sizes[i] ?? 1);
          expect(column, _near(geometry.column), reason: 'column by the group per the document');
        }
      });
    }

    test('reader: a word outside the list and a non-string - no marker', () {
      expect(readTextMarker('roman'), TextMarker.none);
      expect(readTextMarker(true), TextMarker.none);
      expect(readTextMarker(null), TextMarker.none);
      expect(readTextMarker('number'), TextMarker.number);
    });
  });

  group('instanceCases: list template from data', () {
    for (final row in _rows('instanceCases')) {
      final visible = (row['templateVisible']! as List<Object?>).cast<bool>();
      final expected = row['expect']! as _Row;
      final numbers = (expected['numbers']! as List<Object?>).cast<int?>();

      test('formula: ${row['name']}', () {
        expect(listInstanceNumbers(visible), numbers);
      });

      testWidgets('real screen: ${row['name']}', (tester) async {
        _view(tester, 393, 3000);
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([
            {
              'id': 'list',
              'type': 'Repeater',
              'props': {'source': 'tasks', 'item': 'task', 'direction': 'column', 'gap': 'none'},
              'children': [
                {
                  'id': 'row',
                  'type': 'Text',
                  'props': {
                    'content': {'kind': 'binding', 'path': 'task.title', 'fallback': '?'},
                    'marker': 'number',
                  },
                  'visibleIf': {'path': 'task.show', 'op': 'isTrue'},
                },
              ],
            },
          ]),
          data: {
            'tasks': [
              for (var i = 0; i < visible.length; i++) {'title': 'r$i', 'show': visible[i]},
            ],
          },
        );
        expect(tester.takeException(), isNull);
        final width = listMarkerGeometry(DrawnTextMarker.number, 14, groupSize: (expected['groupSize']! as num).toInt()).column;
        for (var i = 0; i < visible.length; i++) {
          if (numbers[i] == null) {
            expect(find.text('r$i'), findsNothing);
            continue;
          }
          final row0 = find.ancestor(of: find.text('r$i'), matching: find.byType(Row)).first;
          final label = tester.widget<Text>(
            find.descendant(of: find.descendant(of: row0, matching: find.byType(MarkerColumnEnd)), matching: find.byType(Text)),
          );
          expect(label.data, '${numbers[i]}.', reason: 'instance number $i');
          expect(tester.getSize(find.descendant(of: row0, matching: find.byType(SizedBox)).first).width, _near(width));
        }
      });
    }
  });

  group('layoutCases: rectangles of the marker column and the text', () {
    for (final row in _rows('layoutCases')) {
      final expected = row['expect']! as _Row;
      final marker = _drawn(row['marker']! as String);
      final rtl = row['direction'] == 'rtl';
      final fontSize = _num(row['fontSize']);
      final groupSize = (row['groupSize']! as num).toInt();
      final inline = _num(row['placeInline']);

      test('formula: ${row['name']}', () {
        final geometry = listMarkerGeometry(marker, fontSize, groupSize: groupSize);
        final box = expected['markerBox']! as _Row;
        final textBox = expected['textBox']! as _Row;
        final markerWidth = _num(box['to']) - _num(box['from']);
        expect(geometry.column, _near(markerWidth));
        expect(inline - geometry.indent, _near(_num(expected['textInline'])));
        expect(_num(textBox['to']) - _num(textBox['from']), _near(_num(expected['textInline'])));
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, inline, 1600);
        final lines = (row['lines'] as num?)?.toInt() ?? 1;
        final lineBlock = row['lineBlock'] == null ? null : _num(row['lineBlock']);
        // Lines come from the text column WIDTH, not from a break in the text (`\n` in shown text is a space):
        // each word takes almost the whole column (the Ahem test font is squares as wide as
        // the font size), so two words do not fit in a line, and a word does not break in the middle.
        final wordLength = math.max(7, (_num(expected['textInline']) / fontSize).floor());
        final content = List.generate(lines, (i) => 'рядок$i'.padRight(wordLength, 'W')).join(' ');
        // An item of a group with groupSize is the first among its numbered neighbours.
        final items = <_Row>[
          _item(
            0,
            marker: marker.name,
            content: content,
            maxLines: (row['maxLines'] as num?)?.toInt(),
            align: row['align'],
            style: {
              'typography': {
                'token': 'bodyM',
                'fontSize': fontSize,
                'lineHeight': lineBlock == null ? 20 / fontSize : lineBlock / fontSize,
              },
            },
          ),
          for (var i = 1; i < groupSize; i++) _item(i, marker: 'number'),
        ];
        await pumpDocument(tester, UiDocumentBuilder.bare(items), locale: rtl ? 'ar' : null);
        expect(tester.takeException(), isNull);

        final firstLine = find.textContaining('рядок0');
        final bodyRect = tester.getRect(firstLine);
        final column = find.descendant(
          of: find.ancestor(of: firstLine, matching: find.byType(Row)).first,
          matching: find.byType(SizedBox),
        ).first;
        final markerRect = tester.getRect(column);
        final box = expected['markerBox']! as _Row;
        final textBox = expected['textBox']! as _Row;
        expect(markerRect.left, _near(_num(box['from'])), reason: 'marker column: start');
        expect(markerRect.right, _near(_num(box['to'])), reason: 'marker column: end');
        expect(bodyRect.left, _near(_num(textBox['from'])), reason: 'text column: start');
        expect(bodyRect.right, _near(_num(textBox['to'])), reason: 'text column: end');
        expect(bodyRect.width, _near(_num(expected['textInline'])));
        expect(rtl ? markerRect.right : markerRect.left, _near(rtl ? inline : 0), reason: 'marker at the logical start');
        expect(expected['markerEdge'], rtl ? 'right' : 'left');

        // The mark is pressed to the END of the column (left to right: to the right edge of the column).
        final label = find.descendant(of: column, matching: find.byType(Text));
        final labelRect = tester.getRect(label);
        if (rtl) {
          expect(labelRect.left, _near(markerRect.left), reason: 'column end in RTL - the left edge');
        } else {
          expect(labelRect.right, _near(markerRect.right), reason: 'column end - the right edge');
        }
        // The marker font is the TEXT font (the node font size), without italic or line.
        final labelWidget = tester.widget<Text>(label);
        expect(labelWidget.style!.fontSize, _near(fontSize), reason: 'markerFontSize');
        expect(labelWidget.style!.fontStyle ?? FontStyle.normal, FontStyle.normal);
        expect(labelWidget.style!.decoration ?? TextDecoration.none, TextDecoration.none);

        // Height: line step x visible lines; `maxLines` cuts the text, not the marker.
        final shown = (row['maxLines'] as num?)?.toInt();
        final drawnLines = shown == null || shown > lines ? lines : shown;
        final block = expected['block'];
        final itemRect = tester.getRect(find.ancestor(of: firstLine, matching: find.byType(Row)).first);
        if (block != null) expect(itemRect.height, _near(_num(block)), reason: 'item height');
        expect(drawnLines, greaterThan(0));
        if (expected['markerDrawn'] == true) expect(label, findsOneWidget);

        // The mark on the FIRST baseline of the text.
        double baselineOf(Finder finder) {
          final box0 = tester.renderObject<RenderBox>(finder);
          return tester.getTopLeft(finder).dy + box0.getDryBaseline(box0.constraints, TextBaseline.alphabetic)!;
        }

        expect(baselineOf(label), _near(baselineOf(firstLine)), reason: 'baseline of the first line');

        // `align` acts on the text in ITS column, the marker stays at the line start.
        if (expected['textAlignWithin'] == 'textBox') {
          expect(tester.widget<Text>(firstLine).textAlign, row['align'] == 'center' ? TextAlign.center : TextAlign.end);
        }
      });
    }
  });

  group('naturalCases: natural width of an item in a row', () {
    for (final row in _rows('naturalCases')) {
      final marker = _drawn(row['marker']! as String);
      final fontSize = _num(row['fontSize']);
      final groupSize = (row['groupSize']! as num).toInt();

      test('formula: ${row['name']}', () {
        final geometry = listMarkerGeometry(marker, fontSize, groupSize: groupSize);
        expect(geometry.indent + _num(row['textNaturalInline']), _near(_num((row['expect']! as _Row)['naturalInline'])));
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        // A group of several items stands in one row: the window is such that they fit.
        _view(tester, 6000, 600);
        Future<double> widthOf(Object? markerWord) async {
          await pumpDocument(
            tester,
            UiDocumentBuilder.bare([
              {
                'id': 'r',
                'type': 'Row',
                'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': false},
                'children': [
                  _item(0, marker: markerWord, content: 'Текст для виміру', style: {
                    'typography': {'token': 'bodyM', 'fontSize': fontSize},
                  }),
                  for (var i = 1; i < groupSize; i++) _item(i, marker: markerWord),
                ],
              },
            ]),
          );
          return tester.getSize(find.ancestor(of: find.text('Текст для виміру'), matching: find.byType(Row)).first).width;
        }

        final withMarker = await widthOf(marker.name);
        expect(tester.takeException(), isNull);
        final plainOne = tester.getSize(find.text('Текст для виміру')).width;
        final geometry = listMarkerGeometry(marker, fontSize, groupSize: groupSize);
        expect(withMarker, _near(plainOne + geometry.indent), reason: 'column + gap + natural text width');
      });
    }
  });

  group('9.17.0 mirrors against the artifact', () {
    final layout = (_schema['x-style']! as _Row)['layout']! as _Row;
    final block = layout['listMarker']! as _Row;

    test('x-style.layout.listMarker - the rules the renderer computes with', () {
      for (final entry in kListMarkerLayout.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
      expect(block['glyph'], {'bullet': kListBulletGlyph});
      expect(block['column'], {'bullet': 1, 'digit': kListMarkerDigit, 'suffix': kListMarkerSuffix, 'min': kListMarkerMinColumn});
      expect(block['gap'], kListMarkerGap);
      expect(_table['layout'], {
        'unit': 'font size of the text',
        'column': {'bullet': 1, 'digit': 0.6, 'suffix': 0.4, 'min': 1},
        'gap': 0.5,
        'bullet': kListBulletGlyph,
        'suffix': kListNumberSuffix,
      });
      expect(block.keys.toSet(), {...kListMarkerLayout.keys, 'glyph', 'number', 'column', 'gap', 'heard', 'widget', 'cases'});
    });

    test('capabilities: listMarker since 9.17.0', () {
      final features = ((_schema['x-compatibility']! as Map)['features']! as Map).cast<String, Object?>();
      expect(features['listMarker'], '9.17.0');
      expect(kFeatureCatalog['listMarker'], '9.17.0');
      expect(supportsFeature('listMarker', readerVersion: '9.16.0'), isFalse);
    });

    test('the Repeater template is the only parent with special counting', () {
      expect(numbersByInstance('Repeater'), isTrue);
      for (final type in ['Column', 'Row', 'Stack', 'Container', 'Screen']) {
        expect(numbersByInstance(type), isFalse, reason: type);
      }
    });
  });

  group('item in a stack and carousel cards: neighbours in a row form a group (per the reference)', () {
    testWidgets('numbered stack layers count as neighbours, like `listNumberOf` over children', (tester) async {
      _view(tester, 393, 800);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 's',
            'type': 'Stack',
            'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
            'children': [_item(0, marker: 'number'), _item(1, marker: 'number')],
          },
        ]),
      );
      String labelOf(String body) {
        final row0 = find.ancestor(of: find.text(body), matching: find.byType(Row)).first;
        return tester.widget<Text>(
          find.descendant(of: find.descendant(of: row0, matching: find.byType(MarkerColumnEnd)), matching: find.byType(Text)),
        ).data!;
      }

      expect(labelOf('t0'), '1.');
      expect(labelOf('t1'), '2.');
    });
  });
}
