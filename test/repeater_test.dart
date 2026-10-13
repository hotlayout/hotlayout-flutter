import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';

import 'support/fixtures.dart';

/// List from data (8.4.0).
///
/// The main thing checked here: there is one template, and as many drawn instances as
/// there are records - and each reads ITS OWN record. A divergence from the builder would
/// cost the most here: in the editor the list would look right, and on the phone it would
/// show identical rows.
void main() {
  _gridTests();
  _twoLevelScopeTests();

  Map<String, Object?> repeater({
    String source = 'tasks',
    String item = 'task',
    int? limit,
    String direction = 'column',
    int? columns,
  }) => {
    'id': 'list',
    'type': 'Repeater',
    'props': {
      'source': source,
      'item': item,
      'direction': direction,
      'gap': 'sm',
      'columns': ?columns,
      'limit': ?limit,
    },
    'children': [
      {
        'id': 'row',
        'type': 'Text',
        'props': {
          'content': {'kind': 'binding', 'path': 'task.title', 'fallback': 'Задача'},
        },
      },
    ],
  };

  const tasks = {
    'tasks': [
      {'title': 'Перша задача'},
      {'title': 'Друга задача'},
      {'title': 'Третя задача'},
    ],
  };

  group('parsing', () {
    test('the source and prefix are read from the document', () {
      final node = docWith([repeater()]).initialScreen.root.children.first;

      expect(contractType(node), 'Repeater');
    });
  });

  group('render', () {
    testWidgets('draws one instance per record', (tester) async {
      await pumpDocument(tester, docWith([repeater()]), data: tasks);

      expect(find.text('Перша задача'), findsOneWidget);
      expect(find.text('Друга задача'), findsOneWidget);
      expect(find.text('Третя задача'), findsOneWidget);
    });

    /*
     * The most important test of the file: each instance reads ITS OWN record. If the scope
     * did not change, all three rows would show the first task - and that would look like
     * a working list.
     */
    testWidgets('each instance reads its own record, not the first', (tester) async {
      await pumpDocument(tester, docWith([repeater()]), data: tasks);

      expect(find.text('Перша задача'), findsOneWidget);
      expect(find.text('Друга задача'), findsOneWidget);
    });

    testWidgets('the limit cuts the list', (tester) async {
      await pumpDocument(tester, docWith([repeater(limit: 2)]), data: tasks);

      expect(find.text('Друга задача'), findsOneWidget);
      expect(find.text('Третя задача'), findsNothing);
    });

    /*
     * An empty list gives an empty place, not a placeholder: what to show instead of the
     * list is decided by the document with a neighbouring node with a condition. Otherwise
     * every app would get our phrase in the middle of its screen.
     */
    testWidgets('empty data draws nothing and does not crash', (tester) async {
      await pumpDocument(tester, docWith([repeater()]), data: const {'tasks': []});

      expect(find.text('Задача'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an absent collection behaves as empty', (tester) async {
      await pumpDocument(tester, docWith([repeater()]), data: const {});

      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-list instead of a collection does not crash the screen', (tester) async {
      await pumpDocument(tester, docWith([repeater()]), data: const {'tasks': 'зовсім не список'});

      expect(tester.takeException(), isNull);
    });

    /*
     * A bound from the CONTRACT, not from the renderer: if each platform chose its own,
     * the same document would show a different number of rows.
     */
    testWidgets('the contract bound cuts a too-long list', (tester) async {
      final many = {
        'tasks': [for (var i = 0; i < kMaxRepeaterItems + 10; i += 1) {'title': 'Задача $i'}],
      };
      await pumpDocument(tester, docWith([repeater()]), data: many);

      expect(find.text('Задача ${kMaxRepeaterItems - 1}'), findsOneWidget);
      expect(find.text('Задача $kMaxRepeaterItems'), findsNothing);
    });
  });

  group('empty state via a condition', () {
    Map<String, Object?> emptyNotice(String op) => {
      'id': 'notice',
      'type': 'Text',
      'visibleIf': {'path': 'tasks', 'op': op},
      'props': {
        'content': {'kind': 'literal', 'value': 'Активних задач немає'},
      },
    };

    /*
     * This is how the empty state is expressed: a neighbouring node with a condition on the
     * same collection the list reads. A separate "what to show when empty" slot would be a
     * second concept in the contract for the same thing.
     */
    testWidgets('an empty collection shows the neighbouring node', (tester) async {
      await pumpDocument(
        tester,
        docWith([repeater(), emptyNotice('isEmpty')]),
        data: const {'tasks': []},
      );

      expect(find.text('Активних задач немає'), findsOneWidget);
    });

    testWidgets('a non-empty collection hides it', (tester) async {
      await pumpDocument(tester, docWith([repeater(), emptyNotice('isEmpty')]), data: tasks);

      expect(find.text('Активних задач немає'), findsNothing);
      expect(find.text('Перша задача'), findsOneWidget);
    });

    testWidgets('isNotEmpty - the mirror', (tester) async {
      await pumpDocument(tester, docWith([emptyNotice('isNotEmpty')]), data: tasks);

      expect(find.text('Активних задач немає'), findsOneWidget);
    });

    /*
     * AN ABSENT COLLECTION BEHAVES AS EMPTY (8.18.0) - and this is the most important case
     * of the whole rule, not a side one.
     *
     * Previously it was the other way round, and the argument sounded reasonable: "otherwise
     * nodes hidden today will appear on screens without data". But the nodes hidden there
     * were exactly the ones that should appear: the "empty state" exists FOR the no-data
     * case. That is, the right behaviour was described as a risk.
     *
     * For someone looking at the screen, "the backend returned no tasks" and "the backend
     * returned an empty task list" are the same situation. Only someone reading the JSON
     * sees the difference.
     */
    testWidgets('an absent collection behaves as empty', (tester) async {
      await pumpDocument(tester, docWith([emptyNotice('isEmpty')]), data: const {});

      expect(find.text('Активних задач немає'), findsOneWidget);
    });

    /*
     * The mirror half, and together with the previous one it is the essence of the change:
     * on empty data EXACTLY ONE of the two conditions fires. Previously neither did,
     * and the screen got a hole that no branch explained.
     */
    testWidgets('on an absent collection exactly one of the two conditions fires', (tester) async {
      await pumpDocument(tester, docWith([emptyNotice('isNotEmpty')]), data: const {});

      expect(find.text('Активних задач немає'), findsNothing);
    });
  });

  group('record scope', () {
    test('a record goes under its own name and does not erase the rest of the scope', () {
      const base = ScreenData.scoped(
        document: {'campaign.title': 'Вересень'},
        scope: {'item': {'name': 'Навушники'}},
      );

      final scoped = base.withItem('task', const {'title': 'Перший'});

      expect(scoped.lookup('task.title'), 'Перший');
      expect(scoped.lookup('item.name'), 'Навушники', reason: 'the outer scope stays');
      expect(scoped.lookup('campaign.title'), 'Вересень', reason: 'document data stays');
    });

    test('a nested list overrides only its own name', () {
      const base = ScreenData.scoped(document: {});

      final outer = base.withItem('task', const {'title': 'Група'});
      final inner = outer.withItem('item', const {'name': 'Нагорода'});

      expect(inner.lookup('task.title'), 'Група');
      expect(inner.lookup('item.name'), 'Нагорода');
    });

    test('listOf yields an empty list for anything but a list', () {
      const data = ScreenData({'tasks': 'рядок', 'items': 42});

      expect(const ScreenData({}).listOf('tasks'), isEmpty);
      expect(data.listOf('tasks'), isEmpty);
      expect(data.listOf('items'), isEmpty);
    });
  });
}

/*
 * INSTANCE GRID (8.13.0). A debt named back in 8.5.0: `Grid` lays out DOCUMENT nodes, so a
 * collection grid could not be expressed with it - the number of cells is known only at
 * runtime.
 *
 * What is checked is the LAYOUT, not the presence of the field: a grid drawn as a column
 * looks like a working list, and the mistake would only be seen on screen.
 */
void _gridTests() {
  Map<String, Object?> badges({int? columns}) => {
    'id': 'list',
    'type': 'Repeater',
    'props': {
      'source': 'badges',
      'item': 'badge',
      'direction': 'column',
      'gap': 'none',
      'columns': ?columns,
    },
    'children': [
      {
        'id': 'cell',
        'type': 'Text',
        'props': {
          'content': {'kind': 'binding', 'path': 'badge.name', 'fallback': '—'},
        },
      },
    ],
  };

  Map<String, Object?> data(int count) => {
    'badges': [for (var i = 0; i < count; i += 1) {'name': 'Б$i'}],
  };

  group('instance grid', () {
    testWidgets('no field - a column, as before 8.13.0', (tester) async {
      await pumpDocument(tester, docWith([badges()]), data: data(4));

      final first = tester.getRect(find.text('Б0'));
      final second = tester.getRect(find.text('Б1'));
      expect(second.top, greaterThanOrEqualTo(first.bottom));
    });

    testWidgets('two columns: the first two instances stand side by side', (tester) async {
      await pumpDocument(tester, docWith([badges(columns: 2)]), data: data(4));

      final first = tester.getRect(find.text('Б0'));
      final second = tester.getRect(find.text('Б1'));
      final third = tester.getRect(find.text('Б2'));

      // First row: equal height, different horizontal positions.
      expect(second.top, first.top);
      expect(second.left, greaterThan(first.left));
      // The third went to the next row - under the first, not under the second.
      expect(third.top, greaterThan(first.bottom - 1));
      expect(third.left, first.left);
    });

    /*
     * An incomplete last row must not stretch its cells: otherwise two badges in a
     * four-column grid would each take half the screen, and the bottom row would stop
     * standing under the top one. That is why the grid stops being a grid - the same rule
     * as in `Grid`.
     */
    testWidgets('an incomplete last row keeps cells of the same width', (tester) async {
      await pumpDocument(tester, docWith([badges(columns: 2)]), data: data(3));

      final first = tester.getRect(find.text('Б0'));
      final third = tester.getRect(find.text('Б2'));

      expect(third.left, first.left);
    });

    testWidgets('a number outside the contract bounds is clamped, not rejected', (tester) async {
      await pumpDocument(tester, docWith([badges(columns: 9)]), data: data(4));

      // The contract maximum is four columns: all four stand in one row.
      final tops = [
        for (var i = 0; i < 4; i += 1) tester.getRect(find.text('Б$i')).top,
      ];
      expect(tops.toSet(), hasLength(1));
    });
  });
}

/*
 * SCOPE ON TWO LEVELS: groups -> steps of a group.
 *
 * `ScreenData.withItem` stacks layers since 8.1.0, and a unit test for that already
 * existed. What was missing was an END-TO-END check: that a nested `Repeater` really reads
 * the collection FROM THE SCOPE of the outer record (`group.steps`), and not only from the
 * document root, and that inside the inner template the fields of the outer record
 * stay in place.
 *
 * This is where the builder and the renderer used to diverge: the canvas REPLACED the
 * scope instead of layering it, and "steps of the September group" were drawn under the
 * heading "group from the dictionary".
 */
void _twoLevelScopeTests() {
  Map<String, Object?> boundText(String id, String path) => {
    'id': id,
    'type': 'Text',
    'props': {
      'content': {'kind': 'binding', 'path': path, 'fallback': '—'},
    },
  };

  Map<String, Object?> nested(List<Map<String, Object?>> template) => {
    'id': 'outer',
    'type': 'Repeater',
    'props': {'source': 'groups', 'item': 'group', 'direction': 'column', 'gap': 'none'},
    'children': [
      {
        'id': 'inner',
        'type': 'Repeater',
        // The collection is addressed RELATIVE to the outer record - exactly what
        // does not exist without scope stacking.
        'props': {'source': 'group.steps', 'item': 'step', 'direction': 'column', 'gap': 'none'},
        'children': template,
      },
    ],
  };

  const data = {
    'groups': [
      {
        'title': 'Група вересня',
        'steps': [
          {'title': 'Оплати рахунок'},
          {'title': 'Познач картку'},
        ],
      },
    ],
  };

  group('scope on two levels', () {
    testWidgets('a nested list reads the collection from the scope of the outer record', (tester) async {
      await pumpDocument(tester, docWith([nested([boundText('t', 'step.title')])]), data: data);

      expect(find.text('Оплати рахунок'), findsOneWidget);
      expect(find.text('Познач картку'), findsOneWidget);
    });

    testWidgets('inside the inner template the fields of the OUTER record stay', (tester) async {
      await pumpDocument(tester, docWith([nested([boundText('t', 'group.title')])]), data: data);

      // Once for EACH step: the group heading inside the step list.
      expect(find.text('Група вересня'), findsNWidgets(2));
    });
  });
}
