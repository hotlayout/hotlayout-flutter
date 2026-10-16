/// Grouping of a list from data (schema 9.26.0, `Repeater.groupBy`, `x-repeaterGroup`): the shared table
/// `fixtures/repeater-group/repeater-group-cases.json` run through the rule and through a real list, and then what the
/// table cannot say: the scope of a header, a press inside it, the gap, the numbering, and the lists that are not a
/// column.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/repeater_group.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/repeater-group/repeater-group-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  final block = schema['x-repeaterGroup']! as _Row;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final sameCases = rowsOf('sameCases');
  final groupCases = rowsOf('groupCases');
  final listCases = rowsOf('listCases');
  final documentCases = rowsOf('documentCases');
  final ruleCases = rowsOf('ruleCases');

  void view(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Map<String, Object?> text(String id, String path) => {
    'id': id,
    'type': 'Text',
    'props': {'content': {'kind': 'binding', 'path': path, 'fallback': ''}},
  };

  /// The list of the table: the record is the title, the header is the day.
  Map<String, Object?> list({Map<String, Object?> props = const {}, Map<String, Object?>? propsOn, List<Map<String, Object?>>? children}) => {
    'id': 'list',
    'type': 'Repeater',
    'props': {'source': 'activities', 'item': 'activity', 'direction': 'column', 'gap': 'none', ...props},
    'propsOn': ?propsOn,
    'children': children ?? [text('record', 'activity.title'), text('header', 'activity.day')],
  };

  /// What the list draws, top to bottom: the texts of the day (headers) and of the title (records).
  List<String> drawn(WidgetTester tester, Iterable<String> titles, Iterable<String> days) {
    final found = <({double top, String text})>[];
    for (final element in find.byType(Text).evaluate()) {
      final value = (element.widget as Text).data ?? '';
      if (value.isEmpty) continue;
      found.add((top: tester.getTopLeft(find.byElementPredicate((e) => identical(e, element))).dy, text: value));
    }
    found.sort((a, b) => a.top.compareTo(b.top));
    return [
      for (final item in found)
        if (days.contains(item.text) && !titles.contains(item.text))
          'header:${item.text}'
        else if (titles.contains(item.text))
          'record:${item.text}',
    ];
  }

  test('the table is read in full', () {
    expect(sameCases, hasLength(11));
    expect(groupCases, hasLength(7));
    expect(listCases, hasLength(6));
    expect(documentCases, hasLength(8));
    expect(ruleCases, hasLength(3));
  });

  group('sameCases: one group or two', () {
    for (final row in sameCases) {
      test(row['name']! as String, () {
        expect(sameGroupValue(row['left'], row['right']), row['expect']);
        expect(sameGroupValue(row['right'], row['left']), row['expect'], reason: 'the other way round');
      });
    }
  });

  group('groupCases: the groups of the drawn records', () {
    for (final row in groupCases) {
      test(row['name']! as String, () {
        final expected = (row['expect']! as List<Object?>).cast<_Row>();
        final groups = recordGroupsOf((row['values']! as List<Object?>).toList());
        expect([for (final group in groups) {'start': group.start, 'size': group.size}], expected);
        expect(groupStartsOf((row['values']! as List<Object?>).toList()), {for (final group in expected) group['start']});
      });
    }
  });

  group('listCases: a real list, filter and limit first', () {
    for (final row in listCases) {
      testWidgets(row['name']! as String, (tester) async {
        view(tester, 393);
        final records = (row['records']! as List<Object?>).cast<_Row>();
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([
            list(props: {'groupBy': 'activity.day', 'where': ?row['where'], 'limit': ?row['limit']}),
          ]),
          data: {'activities': records},
        );
        expect(tester.takeException(), isNull);
        final titles = {for (final record in records) record['title']! as String};
        final days = {for (final record in records) record['day']! as String};
        expect(drawn(tester, titles, days), row['expect']);
      });
    }
  });

  group('documentCases: what the reader draws of the documents the table names', () {
    final records = [
      {'title': 'Coffee week', 'day': 'Today'},
      {'title': 'Movie night', 'day': 'Today'},
      {'title': 'Strong week', 'day': 'Yesterday'},
    ];
    for (final row in documentCases) {
      for (final width in [393.0, 1280.0]) {
        testWidgets('${row['name']} (width $width)', (tester) async {
          view(tester, width);
          final props = (row['props']! as _Row).cast<String, Object?>();
          final children = [
            for (final child in (row['children']! as List<Object?>).cast<String>())
              child == 'record' ? text('record', 'activity.title') : text('header', 'activity.day'),
          ];
          await pumpDocument(
            tester,
            UiDocumentBuilder.bare([list(props: props, propsOn: row['propsOn'] as _Row?, children: children)]),
            data: {'activities': records},
          );
          expect(tester.takeException(), isNull);
          // The headers are drawn only for a list in a column that names its path and holds a header; a grid or a row
          // (also from the width class) is drawn as without the field.
          final expanded = ((row['propsOn'] as _Row?)?['expanded'] as _Row?) ?? const {};
          final inColumn = props['columns'] == null &&
              props['direction'] != 'row' &&
              !(width >= 1024 && expanded['columns'] != null);
          final headers = props['groupBy'] != null && children.length == 2 && inColumn;
          final shown = drawn(tester, ['Coffee week', 'Movie night', 'Strong week'], ['Today', 'Yesterday']);
          // A path the record does not have is "absent" in every record: one group, one header.
          final groups = props['groupBy'] == 'activity.day' ? 2 : 1;
          expect(shown.where((item) => item.startsWith('header')).length, headers ? groups : 0);
          expect(shown.where((item) => item.startsWith('record')).length, 3, reason: 'the records are always drawn');
        });
      }
    }
  });

  group('the header', () {
    final records = [
      {'id': 'a', 'title': 'Coffee week', 'day': 'Today'},
      {'id': 'b', 'title': 'Movie night', 'day': 'Today'},
      {'id': 'c', 'title': 'Strong week', 'day': 'Yesterday'},
    ];

    testWidgets('it stands in the scope of the FIRST record of its group, and a press in it carries that record', (tester) async {
      view(tester, 393);
      final seen = <Map<String, Object?>?>[];
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          list(
            props: {'groupBy': 'activity.day'},
            children: [
              text('record', 'activity.title'),
              {
                'id': 'header',
                'type': 'Button',
                'props': {
                  'label': {'kind': 'binding', 'path': 'activity.title', 'fallback': ''},
                  'variant': 'primary',
                  'action': {'type': 'open'},
                },
              },
            ],
          ),
        ]),
        data: {'activities': records},
        onRecordAction: (action, nodeId, record) => seen.add(record),
      );
      // The first record of each group names its header: «Coffee week» and «Strong week».
      expect(find.bySubtype<ButtonStyleButton>(), findsNWidgets(2));
      await tester.tap(find.bySubtype<ButtonStyleButton>().last);
      await tester.pump();
      expect(seen.single, {'activity.id': 'c', 'activity.title': 'Strong week', 'activity.day': 'Yesterday'});
      await tester.tap(find.bySubtype<ButtonStyleButton>().first);
      await tester.pump();
      expect(seen.last?['activity.id'], 'a', reason: 'the first record of the group, not the last');
    });

    testWidgets('a header that its condition hides takes no place and leaves no gap', (tester) async {
      view(tester, 393);
      Map<String, Object?> hidden() => {...text('header', 'activity.day'), 'visibleIf': {'path': 'activity.day', 'op': 'eq', 'value': 'Yesterday'}};
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          list(props: {'groupBy': 'activity.day', 'gap': 'md'}, children: [text('record', 'activity.title'), hidden()]),
        ]),
        data: {'activities': records},
      );
      final shown = drawn(tester, ['Coffee week', 'Movie night', 'Strong week'], ['Today', 'Yesterday']);
      expect(shown, ['record:Coffee week', 'record:Movie night', 'header:Yesterday', 'record:Strong week']);
      final top = tester.getTopLeft(find.text('Coffee week')).dy;
      final second = tester.getTopLeft(find.text('Movie night')).dy;
      expect(second - top, tester.getSize(find.text('Coffee week')).height + 12, reason: 'one gap between two records, none for the hidden header');
    });

    testWidgets('one gap between every two drawn nodes, headers and records alike', (tester) async {
      view(tester, 393);
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([list(props: {'groupBy': 'activity.day', 'gap': 'md'})]),
        data: {'activities': records},
      );
      final lines = ['Today', 'Coffee week', 'Movie night', 'Yesterday', 'Strong week'];
      final height = tester.getSize(find.text('Coffee week')).height;
      for (var i = 1; i < lines.length; i += 1) {
        final step = tester.getTopLeft(find.text(lines[i])).dy - tester.getTopLeft(find.text(lines[i - 1])).dy;
        expect(step, closeTo(height + 12, 0.5), reason: '${lines[i - 1]} to ${lines[i]}');
      }
    });

    testWidgets('a numbered item counts records only: the header is not one of them', (tester) async {
      view(tester, 393);
      Map<String, Object?> numbered(String id, String path) => {
        ...text(id, path),
        'props': {...(text(id, path)['props']! as _Row), 'marker': 'number'},
      };
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          list(props: {'groupBy': 'activity.day'}, children: [numbered('record', 'activity.title'), text('header', 'activity.day')]),
        ]),
        data: {'activities': records},
      );
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsNothing, reason: 'two headers did not take numbers');
    });

    testWidgets('an empty list has no headers, and a list without data has none either', (tester) async {
      view(tester, 393);
      await pumpDocument(tester, UiDocumentBuilder.bare([list(props: {'groupBy': 'activity.day'})]), data: {'activities': <Object?>[]});
      expect(find.byType(Text), findsNothing);
    });
  });

  group('parsed', () {
    test('the header is the second child, only when the list groups', () {
      final grouped = UiDocumentBuilder.bare([list(props: {'groupBy': 'activity.day'})]).screens.first.root.children.single as RepeaterNode;
      expect(grouped.groupBy, 'activity.day');
      expect(grouped.groupHeader?.id, 'header');
      final plain = UiDocumentBuilder.bare([list()]).screens.first.root.children.single as RepeaterNode;
      expect(plain.groupBy, isNull);
      expect(plain.groupHeader, isNull);
    });

    test('a path that is not a non-empty string is no field', () {
      for (final raw in [null, '', 3, true, <String, Object?>{}]) {
        final node = UiDocumentBuilder.bare([list(props: {'groupBy': raw})]).screens.first.root.children.single as RepeaterNode;
        expect(node.groupBy, isNull, reason: '$raw');
      }
    });
  });

  group('ruleCases and the mirror of the artifact', () {
    for (final row in ruleCases) {
      test('rule: ${row['name']}', () {
        final expected = row['expect'];
        switch (row['rule']) {
          case 'header.child':
            expect(kGroupHeaderIndex, expected);
          case 'after':
            expect(block['after'], expected);
          case 'prop':
            expect(kGroupByKey, expected);
          default:
            fail('unknown rule ${row['rule']}');
        }
      });
    }

    test('the scalar rows of the block are the ones in code', () {
      for (final entry in kRepeaterGroupRules.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
    });
  });
}
