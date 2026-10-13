import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';

import 'support/fixtures.dart';

/// Tabs (8.8.0) are the first contract container whose children are not equal:
/// exactly one panel is visible.
///
/// The second thing these tests hold is STATE. Tabs, like a choice group, have
/// their own switch, and the key point is: a tap does not change the document,
/// and rebuilding with the same document does not bring the tab back.
void main() {
  Map<String, Object?> tab(String id, String title, String body) => {
    'id': id,
    'type': 'Tab',
    'props': {
      'title': {'kind': 'literal', 'value': title},
    },
    'children': [textNode(body, id: '$id-body')],
  };

  Map<String, Object?> tabs(
    List<Map<String, Object?>> children, {
    Object initialTab = 0,
  }) => {
    'id': 'tabs',
    'type': 'Tabs',
    'props': {'initialTab': initialTab},
    'children': children,
  };

  final twoTabs = [tab('a', 'Завдання', 'Три завдання'), tab('b', 'Колекція', 'Сім бейджів')];

  group('model', () {
    TabsNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([node])).whereType<TabsNode>().single;

    test('the title lives on the CHILD, not in a parent array of titles', () {
      final node = parse(tabs(twoTabs));
      final titles = node.children.whereType<TabNode>().map((t) => t.title.resolve(const ScreenData({})));

      expect(titles, ['Завдання', 'Колекція']);
    });

    test('a negative or non-integer index is "out of range" (-1), not zero', () {
      // Broken data used to read as zero, i.e. "the first tab" - even when it is
      // hidden. Now reading only says "there is no such tab"; what to open is
      // decided by `openTabIndex` (`initialTabOutOfRange`).
      expect(parse(tabs(twoTabs, initialTab: -3)).initialTab, -1);
      expect(parse(tabs(twoTabs, initialTab: 1.5)).initialTab, -1);
      expect(parse(tabs(twoTabs, initialTab: 'друга')).initialTab, -1);
      expect(parse(tabs(twoTabs, initialTab: 1.0)).initialTab, 1);
    });
  });

  group('layout', () {
    testWidgets('exactly one panel is visible - the one the document named', (tester) async {
      await pumpDocument(tester, docWith([tabs(twoTabs, initialTab: 1)]));

      // Both headers are in the strip...
      expect(find.text('Завдання'), findsOneWidget);
      expect(find.text('Колекція'), findsOneWidget);
      // ...and the content is of the open tab only.
      expect(find.text('Сім бейджів'), findsOneWidget);
      expect(find.text('Три завдання'), findsNothing);
    });

    testWidgets('an index out of range gives the first visible tab, not an empty panel', (tester) async {
      // `initialTabOutOfRange: 'first-visible'`: an empty panel under the strip looks
      // like a broken screen, so the contract gives ONE answer for both a hidden
      // tab and an out-of-range index (`openTabIndex`).
      for (final index in <Object>[7, -1, 1.5, 'друга']) {
        await pumpDocument(tester, docWith([tabs(twoTabs, initialTab: index)]));

        expect(tester.takeException(), isNull, reason: '$index');
        expect(find.text('Три завдання'), findsOneWidget, reason: '$index');
        expect(find.text('Сім бейджів'), findsNothing, reason: '$index');
      }
    });

    /*
     * `hiddenInitialTab: 'first-visible'` (9.0.0). `initialTab` counts ALL
     * tabs in document order, including those hidden by `visibleIf` - otherwise
     * the index would shift along with the data.
     */
    testWidgets('the index counts hidden tabs too: no shift from data', (tester) async {
      final three = [
        tab('a', 'Завдання', 'Три завдання'),
        {...tab('b', 'Колекція', 'Сім бейджів'), 'visibleIf': {'path': 'user.vip', 'op': 'isTrue'}},
        tab('c', 'Історія', 'Два записи'),
      ];

      // The second tab is hidden; the document names the THIRD (index 2).
      await pumpDocument(tester, docWith([tabs(three, initialTab: 2)]), data: const {'user.vip': false});
      expect(find.text('Два записи'), findsOneWidget);
      expect(find.text('Колекція'), findsNothing);
    });

    testWidgets('the named tab is hidden - the first visible one opens', (tester) async {
      final three = [
        tab('a', 'Завдання', 'Три завдання'),
        {...tab('b', 'Колекція', 'Сім бейджів'), 'visibleIf': {'path': 'user.vip', 'op': 'isTrue'}},
        tab('c', 'Історія', 'Два записи'),
      ];

      await pumpDocument(tester, docWith([tabs(three, initialTab: 1)]), data: const {'user.vip': false});
      expect(tester.takeException(), isNull);
      expect(find.text('Три завдання'), findsOneWidget);
      expect(find.text('Два записи'), findsNothing);
    });

    testWidgets('tapping a header switches the panel', (tester) async {
      await pumpDocument(tester, docWith([tabs(twoTabs)]));
      expect(find.text('Три завдання'), findsOneWidget);

      await tester.tap(find.text('Колекція'));
      // `pumpAndSettle`, not `pump`: panels replace each other with a cross-fade,
      // and in the intermediate frame the old one is still in the tree, fading out.
      // The requirement is the same ("the old panel is gone"); only the moment it holds differs.
      await tester.pumpAndSettle();

      expect(find.text('Сім бейджів'), findsOneWidget);
      expect(find.text('Три завдання'), findsNothing);
    });

    testWidgets('rebuilding with the same document does not bring the tab back', (tester) async {
      // State belongs to the node, not to the tree build: a network update of the
      // document with the same content must not undo what the finger did.
      final document = docWith([tabs(twoTabs)]);
      await pumpDocument(tester, document);
      await tester.tap(find.text('Колекція'));
      await tester.pumpAndSettle();

      await pumpDocument(tester, document);

      expect(find.text('Сім бейджів'), findsOneWidget);
    });

    testWidgets('header height does not depend on whether it is open', (tester) async {
      // The underline strip is always there, just transparent in closed tabs:
      // otherwise the strip would jump on tap and its height would diverge from the preview model.
      await pumpDocument(tester, docWith([tabs(twoTabs)]));

      final open = tester.getRect(find.text('Завдання'));
      final closed = tester.getRect(find.text('Колекція'));

      expect(closed.top, closeTo(open.top, 0.01));
      expect(closed.height, closeTo(open.height, 0.01));
    });

    testWidgets('a tab removed by a condition disappears from the STRIP, leaving no gap', (tester) async {
      final hidden = {
        ...tab('a', 'Завдання', 'Три завдання'),
        'visibleIf': {'path': 'task.completed', 'op': 'isTrue'},
      };
      await pumpDocument(
        tester,
        docWith([
          tabs([hidden, tab('b', 'Колекція', 'Сім бейджів')]),
        ]),
        data: const {'task.completed': false},
      );

      expect(find.text('Завдання'), findsNothing);
      // Numbering counts among the visible, so the next panel became index zero.
      expect(find.text('Сім бейджів'), findsOneWidget);
    });

    testWidgets('empty tabs draw nothing and do not crash the screen', (tester) async {
      await pumpDocument(tester, docWith([tabs(const [])]));

      expect(tester.takeException(), isNull);
    });
  });
}
