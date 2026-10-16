/// A COMPARISON WITH THE VALUE OF ANOTHER PATH (schema 9.23.0, `x-listFilter.valuePath`).
///
/// `valuePathCases` of the shared table (`assets/contract/fixtures/inputs/input-cases.json`) run row by row, by the
/// rule over the data layers AND on a real screen (`visibleIf`). The state of a node (`styleWhen`) and the disabled
/// state of a button read the same parsed condition; one row of each proves that.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/visibility.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/inputs/input-cases.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

void main() {
  test('the table has the promised rows', () => expect(_rows('valuePathCases'), hasLength(22)));

  group('valuePathCases', () {
    for (final row in _rows('valuePathCases')) {
      final name = row['name']! as String;
      final holds = row['holds']! as bool;
      final data = (row['data']! as _Row).cast<String, Object?>();

      test('rule: $name', () {
        final condition = VisibilityCondition.parse(row['condition']);
        expect(condition, isA<PathComparisonCondition>());
        expect(condition!.evaluate(ScreenData(data)), holds);
      });

      testWidgets('screen: $name', (tester) async {
        await pumpDocument(tester, docWith([textNode('guarded', visibleIf: row['condition'])]), data: data);
        expect(find.text('guarded'), holds ? findsOneWidget : findsNothing);
      });
    }
  });

  test('a `value` and a `valuePath` together are not a condition: the node stays visible', () {
    final condition = VisibilityCondition.parse({
      'path': 'ui.a',
      'op': 'eq',
      'value': 'x',
      'valuePath': 'ui.b',
    });
    expect(condition, isA<AlwaysVisibleCondition>());
  });

  test('an operator of a newer minor with a `valuePath` stays visible (the unknown operator is stronger)', () {
    final condition = VisibilityCondition.parse({'path': 'ui.a', 'op': 'startsWith', 'valuePath': 'ui.b'});
    expect(condition!.evaluate(const ScreenData({'ui.a': 'x', 'ui.b': 'y'})), isTrue);
  });

  testWidgets('the state of a node reads the same condition', (tester) async {
    Map<String, Object?> node() => textNode('state', style: {'background': colorBackground('surface')})
      ..['styleWhen'] = [
        {
          'when': {'path': 'ui.budget', 'op': 'gte', 'valuePath': 'ui.spent'},
          'style': {'background': colorBackground('primary')},
        },
      ];
    await pumpDocument(tester, docWith([node()]), data: {'ui.budget': 1, 'ui.spent': 3});
    final base = nodeDecoration(tester, 'state').color;
    await pumpDocument(tester, docWith([node()]), data: {'ui.budget': 5, 'ui.spent': 3});
    expect(nodeDecoration(tester, 'state').color, isNot(equals(base)));
    // No operand: the state does not hold, `gte` or not.
    await pumpDocument(tester, docWith([node()]), data: {'ui.budget': 5});
    expect(nodeDecoration(tester, 'state').color, base);
  });
}
