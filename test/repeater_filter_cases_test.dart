/// A FILTERED LIST FROM DATA (schema 9.23.0, `x-listFilter`): `Repeater.where`, a comparison with the value of another
/// path and the emptiness of a filtered list.
///
/// The shared table (`assets/contract/fixtures/repeater-filter/repeater-filter-cases.json`) runs row by row, each
/// row by the rule AND through a real screen:
///
///  1. `filterCases` -- which records pass;
///  2. `limitCases` -- the limit counts the records that passed;
///  3. `gridCases` -- cells of the drawn records only, no holes;
///  4. `carouselCases` -- stops follow the drawn cards;
///  5. `numberCases` -- numbers follow the drawn rows;
///  6. `emptinessCases` -- the empty state of a filtered list;
///  7. `documentCases` -- every document is read and drawn without a crash.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/visibility.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table =
    jsonDecode(File('assets/contract/fixtures/repeater-filter/repeater-filter-cases.json').readAsStringSync()) as _Row;
final _Row _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

List<Object?> _recordsOf(_Row row) => (row['records'] ?? _table['records']) as List<Object?>;

Map<String, Object?> _outerOf(_Row row) => {...(row['outer'] as Map<String, Object?>? ?? const {})};

Map<String, Object?> _list({
  Object? where,
  int? limit,
  int? columns,
  bool carousel = false,
  String template = 'id',
  Map<String, Object?>? templateStyle,
  bool numbered = false,
}) => {
  'id': 'list',
  'type': 'Repeater',
  'props': {
    'source': 'rewards',
    'item': 'reward',
    'direction': carousel ? 'row' : 'column',
    'gap': 'none',
    'columns': ?columns,
    'limit': ?limit,
    'where': ?where,
    'carousel': ?(carousel ? <String, Object?>{} : null),
  },
  'children': [
    {
      'id': 'row',
      'type': 'Text',
      'props': {
        'content': {'kind': 'binding', 'path': 'reward.$template', 'fallback': '?'},
        'align': 'start',
        'overflow': 'clip',
        'marker': ?(numbered ? 'number' : null),
      },
      'style': ?templateStyle,
    },
  ],
};

Map<String, Object?> _dataOf(_Row row, {bool withList = true}) => {
  ..._outerOf(row),
  if (withList) 'rewards': _recordsOf(row),
};

String _idOf(Object? record) {
  final map = record! as _Row;
  return (map['id'] ?? map['reward.id'])! as String;
}

void main() {
  test('the table has the promised rows', () {
    expect(_rows('filterCases'), hasLength(21));
    expect(_rows('limitCases'), hasLength(4));
    expect(_rows('gridCases'), hasLength(5));
    expect(_rows('carouselCases'), hasLength(4));
    expect(_rows('numberCases'), hasLength(2));
    expect(_rows('emptinessCases'), hasLength(8));
    expect(_rows('documentCases'), hasLength(13));
  });

  List<int> passedByRule(_Row row) {
    final where = row['where'] == null ? null : VisibilityCondition.parse(row['where']);
    final records = _recordsOf(row);
    final data = ScreenData(_dataOf(row));
    return [
      for (var i = 0; i < records.length; i += 1)
        if (where == null || where.passes(data.withItem('reward', records[i]))) i,
    ];
  }

  group('filterCases -- which records pass', () {
    for (final row in _rows('filterCases')) {
      final name = row['name']! as String;
      final passed = (row['passed']! as List<Object?>).cast<int>();
      test('rule: $name', () => expect(passedByRule(row), passed));
      testWidgets('screen: $name', (tester) async {
        final records = _recordsOf(row);
        await pumpDocument(tester, docWith([_list(where: row['where'])]), data: _dataOf(row));
        for (var i = 0; i < records.length; i += 1) {
          expect(
            find.text(_idOf(records[i])),
            passed.contains(i) ? findsOneWidget : findsNothing,
            reason: 'record $i (${_idOf(records[i])})',
          );
        }
      });
    }
  });

  group('limitCases -- the limit counts what passed', () {
    for (final row in _rows('limitCases')) {
      final name = row['name']! as String;
      final drawn = (row['drawn']! as List<Object?>).cast<int>();
      testWidgets(name, (tester) async {
        final records = _recordsOf(row);
        await pumpDocument(
          tester,
          docWith([_list(where: row['where'], limit: row['limit'] as int?)]),
          data: _dataOf(row),
        );
        for (var i = 0; i < records.length; i += 1) {
          expect(
            find.text(_idOf(records[i])),
            drawn.contains(i) ? findsOneWidget : findsNothing,
            reason: 'record $i',
          );
        }
      });
    }
  });

  group('gridCases -- the cells of the drawn records, no holes', () {
    for (final row in _rows('gridCases')) {
      final name = row['name']! as String;
      final cells = [
        for (final cell in row['cells']! as List<Object?>) (cell! as List<Object?>).cast<int>(),
      ];
      testWidgets(name, (tester) async {
        final records = _recordsOf(row);
        final passed = passedByRule(row);
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([_list(where: row['where'], columns: row['columns'] as int?)]),
          data: _dataOf(row),
        );
        final rects = [for (final i in passed) tester.getRect(find.text(_idOf(records[i])))];
        expect(rects, hasLength(cells.length));
        // The row is the order of the tops, the column the order of the lefts within the row.
        final tops = {for (final r in rects) r.top.round()}.toList()..sort();
        final lefts = {for (final r in rects) r.left.round()}.toList()..sort();
        for (var i = 0; i < rects.length; i += 1) {
          expect(tops.indexOf(rects[i].top.round()), cells[i][0], reason: 'row of drawn record $i');
          expect(lefts.indexOf(rects[i].left.round()), cells[i][1], reason: 'column of drawn record $i');
        }
      });
    }
  });

  group('carouselCases -- stops follow the drawn cards', () {
    for (final row in _rows('carouselCases')) {
      final name = row['name']! as String;
      final viewport = (row['viewport']! as num).toDouble();
      final card = (row['card']! as num).toDouble();
      final gap = (row['gap']! as num).toDouble();
      test('rule: $name', () {
        final drawn = passedByRule(row).length;
        final result = carouselStops(
          viewport: viewport,
          paddingStart: 0,
          paddingEnd: 0,
          gap: gap,
          cards: List.filled(drawn, card),
        );
        expect(result.stops, hasLength(row['stops']! as int));
      });
      testWidgets('screen: $name', (tester) async {
        tester.view.physicalSize = Size(viewport, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final records = _recordsOf(row);
        final passed = passedByRule(row);
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([
            _list(where: row['where'], carousel: true, templateStyle: {'width': card}),
          ]),
          data: _dataOf(row),
        );
        // A card is drawn per record that passed (the ones past the viewport are built too: a carousel is a row).
        final built = [
          for (var i = 0; i < records.length; i += 1)
            if (find.text(_idOf(records[i]), skipOffstage: false).evaluate().isNotEmpty) i,
        ];
        expect(built, passed);
      });
    }
  });

  group('numberCases -- numbers follow the drawn rows', () {
    for (final row in _rows('numberCases')) {
      final name = row['name']! as String;
      final numbers = (row['numbers']! as List<Object?>).cast<int>();
      testWidgets(name, (tester) async {
        await pumpDocument(
          tester,
          docWith([_list(where: row['where'], numbered: true)]),
          data: _dataOf(row),
        );
        for (final number in numbers) {
          expect(find.textContaining('$number.'), findsOneWidget, reason: 'number $number');
        }
        expect(find.textContaining('${numbers.length + 1}.'), findsNothing);
      });
    }
  });

  group('emptinessCases -- the empty state of a filtered list', () {
    for (final row in _rows('emptinessCases')) {
      final name = row['name']! as String;
      final holds = row['holds']! as bool;
      final data = _dataOf(row, withList: row['noList'] != true);
      if (row['emptyList'] == true) data['rewards'] = const <Object?>[];

      test('rule: $name', () {
        final condition = VisibilityCondition.parse(row['condition'])!;
        expect(condition, isA<FilteredEmptinessCondition>());
        expect(condition.evaluate(ScreenData(data)), holds);
      });
      testWidgets('screen: $name', (tester) async {
        await pumpDocument(
          tester,
          docWith([
            textNode('empty-state', visibleIf: row['condition']),
          ]),
          data: data,
        );
        expect(find.text('empty-state'), holds ? findsOneWidget : findsNothing);
      });
    }
  });

  group('documentCases -- every document is read and drawn without a crash', () {
    for (final row in _rows('documentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final where = row['where'];
        final visibleIf = row['visibleIf'];
        await pumpDocument(
          tester,
          docWith([
            if (where != null) _list(where: where),
            if (visibleIf != null) textNode('guarded', visibleIf: visibleIf),
          ]),
          data: {
            'ui.category': 'fun',
            'ui.budget': 1800,
            'rewards': _table['records'],
          },
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('x-listFilter: the block of the artifact says what this reader does', () {
    final block = _schema['x-listFilter']! as _Row;
    final valuePath = block['valuePath']! as _Row;
    expect(valuePath['ops'], ['eq', 'neq', 'gt', 'gte', 'lt', 'lte']);
    final missing = valuePath['operandMissing']! as _Row;
    expect(missing['is'], ['absent', 'null', 'the-empty-string']);
    expect(missing['inWhere'], 'the-condition-holds-for-every-record');
    expect(missing['elsewhere'], 'the-condition-does-not-hold-eq-and-neq-alike');
    expect((block['where']! as _Row)['limit'], 'the-first-limit-records-that-passed');
    expect((block['emptiness']! as _Row)['limit'], 'not-applied');
  });
}
