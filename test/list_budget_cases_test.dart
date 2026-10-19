/// THE LIST BUDGET OF A SCREEN (`x-listBudget`): the shared table
/// `assets/contract/fixtures/repeater-filter/list-budget-cases.json`.
///
/// A row gives the lists abstractly (`records` drawn after `where` and `limit`, `inside` the lists of the template);
/// the test builds REAL `Repeater` nodes and collections from it and checks twice:
///
///  1. the plan of the screen (`ListBudgetPlan`): what each list may draw, the total and what was not drawn;
///  2. a real screen, for the rows of the default budget: how many instances of each list are on it.
///
/// The `validatorCases` belong to the builder (it refuses to publish a screen above the budget); a reader has
/// nothing to do for them, and the test says so by counting them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/render/list_budget.dart';

import 'hardening/support.dart';
import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/repeater-filter/list-budget-cases.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

/// A list node: its template is a text named like the list, or a column with that text and the lists inside.
Map<String, Object?> _list(_Row list) {
  final name = list['name']! as String;
  final inside = (list['inside'] as List<Object?>? ?? const []).cast<_Row>();
  final text = textNode(name, id: '$name-text');
  return {
    'id': name,
    'type': 'Repeater',
    'props': {'source': name, 'item': 'i$name', 'direction': 'column', 'gap': 'none'},
    'children': [
      if (inside.isEmpty)
        text
      else
        {
          'id': '$name-row',
          'type': 'Column',
          'props': {'gap': 'none'},
          'children': [text, for (final child in inside) _list(child)],
        },
    ],
  };
}

Iterable<_Row> _flat(Iterable<_Row> lists) sync* {
  for (final list in lists) {
    yield list;
    yield* _flat((list['inside'] as List<Object?>? ?? const []).cast<_Row>());
  }
}

Map<String, Object?> _dataOf(_Row row) => {
  for (final list in _flat((row['lists']! as List<Object?>).cast<_Row>()))
    list['name']! as String: [
      for (var i = 0; i < (list['records']! as int); i += 1) {'n': i},
    ],
};

List<Map<String, Object?>> _nodesOf(_Row row) => [for (final list in (row['lists']! as List<Object?>).cast<_Row>()) _list(list)];

Map<String, int> _drawnOf(_Row row) => (row['drawn']! as Map<String, Object?>).cast<String, int>();

void main() {
  test('the table has the promised rows', () {
    expect(_rows('budgetCases'), hasLength(14));
    expect(_rows('validatorCases'), hasLength(7), reason: 'those are the builder\'s rows: the reader draws what it is given');
    expect(kListBudgetPerScreen, 2550);
  });

  group('budgetCases -- the plan of a screen', () {
    for (final row in _rows('budgetCases')) {
      test(row['name']! as String, () {
        final doc = docWith(_nodesOf(row));
        final plan = ListBudgetPlan.of(
          rootOf(doc),
          ScreenData(_dataOf(row)),
          budget: (row['budget'] as int?) ?? kListBudgetPerScreen,
        );
        final drawn = _drawnOf(row);
        expect({for (final name in drawn.keys) name: plan.drawnByList[name] ?? 0}, drawn);
        expect(plan.total, row['total']);
        expect(plan.notDrawn, row['notDrawn']);
      });
    }
  });

  group('budgetCases -- a real screen at the default budget', () {
    for (final row in _rows('budgetCases').where((row) => row['budget'] == null)) {
      testWidgets(row['name']! as String, (tester) async {
        final lines = await captureDebugPrint(() async {
          await pumpDocument(tester, docWith(_nodesOf(row)), data: _dataOf(row));
        });
        final drawn = _drawnOf(row);
        for (final entry in drawn.entries) {
          expect(
            find.text(entry.key, skipOffstage: false).evaluate().length,
            entry.value,
            reason: 'instances of "${entry.key}" on the screen',
          );
        }
        // One report per screen: how many instances were not drawn, and not a word of the data.
        final reports = lines.where((line) => line.contains('list budget')).toList();
        if (row['notDrawn'] == 0) {
          expect(reports, isEmpty);
        } else {
          expect(reports, hasLength(1), reason: 'one report for the screen');
          expect(reports.single, contains('${row['notDrawn']}'));
        }
      });
    }
  });
}
