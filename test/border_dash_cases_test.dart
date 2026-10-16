/// A DASHED BORDER (schema 9.22.0, `style.border.style: 'dashed'`).
///
/// The shared table (`assets/contract/fixtures/border-dash/border-dash-cases.json`) runs row by row:
///
///  1. `lineCases` -- the centre line, its radii, the perimeter and the fitted pattern, within 1e-5;
///  2. `pathCases` -- the path of the centre line, character for character;
///  3. `styleCases` -- the word `dashed`; no field or another word is solid;
///  4. `schemaCases` -- the artifact accepts what the table says it accepts, and the reader never throws;
///  5. `ruleCases` -- the rules as data: the artifact and the code mirror.
///
/// Plus real boxes: the painter's dashes on a real node, left to right and right to left, and a dashed
/// border takes the room of a solid one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/border_dash.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/render/dashed_border.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/border-dash/border-dash-cases.json').readAsStringSync()) as _Row;
final _Row _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

double _n(Object? value) => (value! as num).toDouble();

DashRadii _radii(Object? raw) {
  final r = raw! as _Row;
  return (topStart: _n(r['topStart']), topEnd: _n(r['topEnd']), bottomEnd: _n(r['bottomEnd']), bottomStart: _n(r['bottomStart']));
}

DashedBox _boxOf(Object? raw) {
  final box = raw! as _Row;
  return (width: _n(box['width']), height: _n(box['height']), border: _n(box['border']), radii: _radii(box['radii']));
}

void main() {
  test('the table has the promised rows', () {
    expect(_rows('lineCases'), hasLength(6));
    expect(_rows('pathCases'), hasLength(2));
    expect(_rows('styleCases'), hasLength(3));
    expect(_rows('schemaCases'), hasLength(3));
    expect(_rows('ruleCases'), hasLength(6));
  });

  group('lineCases -- the centre line and the pattern', () {
    for (final row in _rows('lineCases')) {
      test(row['name']! as String, () {
        final expected = row['expect']! as _Row;
        final line = dashedLineOf(_boxOf(row['box']));
        final radii = _radii(expected['radii']);
        expect(line.radii.topStart, closeTo(radii.topStart, 1e-5));
        expect(line.radii.topEnd, closeTo(radii.topEnd, 1e-5));
        expect(line.radii.bottomEnd, closeTo(radii.bottomEnd, 1e-5));
        expect(line.radii.bottomStart, closeTo(radii.bottomStart, 1e-5));
        expect(line.perimeter, closeTo(_n(expected['perimeter']), 1e-5));
        expect(line.count, expected['count']);
        expect(line.dash, closeTo(_n(expected['dash']), 1e-5));
        expect(line.gap, closeTo(_n(expected['gap']), 1e-5));
      });
    }
  });

  group('pathCases -- the path of the centre line', () {
    for (final row in _rows('pathCases')) {
      test(row['name']! as String, () => expect(dashedPathOf(_boxOf(row['box'])), row['expect']));
    }
  });

  group('styleCases -- the word', () {
    for (final row in _rows('styleCases')) {
      test(row['name']! as String, () {
        final style = NodeStyle.parse({'border': row['border']});
        expect(style!.border!.dashed ? 'dashed' : null, row['expect']);
      });
    }
  });

  group('schemaCases -- the artifact says it and the reader does not throw', () {
    final words = (((_schema[r'$defs']! as _Row)['NodeBorder']! as _Row)['properties']! as _Row)['style']! as _Row;
    for (final row in _rows('schemaCases')) {
      test(row['name']! as String, () {
        final style = (row['style']! as _Row)['border']! as _Row;
        expect((words['enum']! as List<Object?>).contains(style['style']), row['valid'], reason: 'the artifact');
        // Whatever the word, the reader reads the border and keeps its width and colour.
        final border = NodeStyle.parse({'border': style})!.border!;
        expect(border.width, _n(style['width']));
        expect(border.dashed, style['style'] == 'dashed');
      });
    }
  });

  group('ruleCases -- the artifact and the code mirror', () {
    final block = ((_schema['x-style']! as _Row)['layout']! as _Row)['borderDash']! as _Row;
    for (final row in _rows('ruleCases')) {
      test(row['name']! as String, () {
        final rule = row['rule']! as String;
        expect(block[rule], row['expect']);
        if (rule == 'dash') expect(kBorderDash, row['expect']);
        if (rule == 'gap') expect(kBorderGap, row['expect']);
      });
    }
    test('the word and the unit', () {
      expect(block['words'], [kDashedBorderWord]);
      expect(block['unit'], 'border-width');
    });
  });

  Map<String, Object?> card({String radius = 'lg', bool dashed = true, double border = 1}) => {
    'id': 'card',
    'type': 'Container',
    'style': {
      'width': 345,
      'height': 82,
      'radius': radius,
      'border': {'width': border, 'color': 'border', if (dashed) 'style': 'dashed'},
    },
    'children': [textNode('inside')],
  };

  DashedBorderPainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: find.byType(DashedBorder), matching: find.byType(CustomPaint)).first,
    );
    return paint.foregroundPainter! as DashedBorderPainter;
  }

  for (final locale in ['en', 'ar']) {
    testWidgets('a dashed node ($locale): the pattern of the table on a real box', (tester) async {
      await pumpDocument(tester, docWith([card()]), locale: locale);
      final painter = painterOf(tester);
      final size = tester.getSize(find.byType(DashedBorder).first);
      expect(size, const Size(345, 82));
      final dashes = painter.dashes(size);
      final line = dashedLineOf((
        width: 345,
        height: 82,
        border: 1,
        radii: (
          topStart: painter.radius.topLeft.x,
          topEnd: painter.radius.topRight.x,
          bottomEnd: painter.radius.bottomRight.x,
          bottomStart: painter.radius.bottomLeft.x,
        ),
      ));
      expect(dashes, hasLength(line.count));
      // The first dash starts at the inline START of the top edge: the left in English, the right in Arabic.
      final first = dashes.first.computeMetrics().first.getTangentForOffset(0)!.position;
      expect(first.dy, closeTo(0.5, 1e-6), reason: 'on the centre line of the top edge');
      if (locale == 'en') {
        expect(first.dx, lessThan(size.width / 2));
      } else {
        expect(first.dx, greaterThan(size.width / 2));
      }
      // Each dash is as long as the contract says.
      final length = dashes.first.computeMetrics().first.length;
      expect(length, closeTo(line.dash, 0.05));
    });
  }

  testWidgets('a dashed border takes the room of a solid one', (tester) async {
    await pumpDocument(tester, docWith([card(dashed: false, border: 4)]));
    final solid = tester.getRect(find.text('inside'));
    await pumpDocument(tester, docWith([card(border: 4)]));
    expect(tester.getRect(find.text('inside')), solid);
    expect(find.byType(DashedBorder), findsOneWidget);
  });

  testWidgets('a solid node has no dashed painter', (tester) async {
    await pumpDocument(tester, docWith([card(dashed: false)]));
    expect(find.byType(DashedBorder), findsNothing);
  });

  testWidgets('a dashed border in a state of the node and on a button surface', (tester) async {
    final node = textNode('state', style: {'border': {'width': 1, 'color': 'border'}})
      ..['styleWhen'] = [
        {
          'when': {'path': 'ui.on', 'op': 'isTrue'},
          'style': {'border': {'width': 1, 'color': 'border', 'style': 'dashed'}},
        },
      ];
    await pumpDocument(tester, docWith([node]), data: {'ui.on': false});
    expect(find.byType(DashedBorder), findsNothing);
    await pumpDocument(tester, docWith([node]), data: {'ui.on': true});
    expect(find.byType(DashedBorder), findsOneWidget);

    final button = buttonNode('Pay', action: {'type': 'none'})
      ..['style'] = {'border': {'width': 2, 'color': 'primary', 'style': 'dashed'}};
    await pumpDocument(tester, docWith([button]));
    expect(find.byType(DashedBorder), findsOneWidget);
  });
}
