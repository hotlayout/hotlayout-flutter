import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// The contract's `AppBar` (6.0.0) is a panel of the DOCUMENT, not an app bar of the application.
///
/// The difference is not cosmetic: a document need not occupy the whole screen, so
/// the renderer has no right to replace the host's `Scaffold`. The bar is simply
/// the first child of a column in the same tree.
///
/// It STAYS in place; only the body scrolls (`appBarScroll: 'fixed-only-the-body-scrolls'`).
/// An earlier 9.9.0 wording ("the bar scrolls with the content") was withdrawn
/// before release: on mobile the bar is at the top. This asserts it the same
/// way as before 9.9.0.
void main() {
  group('AppBar as the screen app bar', () {
    testWidgets('stands above the scroll view, not inside it; only the body scrolls', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          appBarNode('Мої нагороди', subtitle: 'Жовтень'),
          textNode('Вміст екрана'),
          {
            'id': 'tall',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'height': 1200},
            'children': [],
          },
        ]),
      );

      expect(find.text('Мої нагороди'), findsOneWidget);
      expect(find.text('Жовтень'), findsOneWidget);
      final scroll = find.byType(SingleChildScrollView);
      expect(
        find.descendant(of: scroll, matching: find.text('Мої нагороди')),
        findsNothing,
        reason: 'the bar must stay in place while the content scrolls',
      );
      expect(find.descendant(of: scroll, matching: find.text('Вміст екрана')), findsOneWidget);

      final barBefore = tester.getTopLeft(find.text('Мої нагороди'));
      final bodyBefore = tester.getTopLeft(find.text('Вміст екрана'));
      await tester.drag(scroll, const Offset(0, -80));
      await tester.pump();
      expect(tester.getTopLeft(find.text('Мої нагороди')), barBefore, reason: 'the app bar does not move');
      expect(tester.getTopLeft(find.text('Вміст екрана')).dy, lessThan(bodyBefore.dy), reason: 'the body moves');
    });

    testWidgets('title and subtitle are bindings', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'bar',
            'type': 'AppBar',
            'props': {
              'title': {'kind': 'binding', 'path': 'task.title', 'fallback': 'Задача'},
              'subtitle': {'kind': 'binding', 'path': 'campaign.title', 'fallback': '—'},
              'showBack': true,
              'background': {'kind': 'color', 'color': 'surface'},
            },
          },
        ]),
        data: const {'task.title': 'Оплати 5 покупок', 'campaign.title': 'Жовтень'},
      );

      expect(find.text('Оплати 5 покупок'), findsOneWidget);
      expect(find.text('Жовтень'), findsOneWidget);
    });

    testWidgets('without a subtitle the bar leaves no empty line', (tester) async {
      await pumpDocument(tester, docWith([appBarNode('Тільки заголовок')]));

      expect(find.text('Тільки заголовок'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('showBack controls the presence of the arrow', (tester) async {
      await pumpDocument(tester, docWith([appBarNode('З кнопкою')]));
      expect(findAppBarBack, findsOneWidget);

      await pumpDocument(tester, docWith([appBarNode('Без кнопки', showBack: false)]));
      expect(findAppBarBack, findsNothing);
    });
  });

  group('what "back" means', () {
    testWidgets('the arrow takes one step in the document stack', (tester) async {
      // In the contract `showBack` is a flag WITHOUT an action, so the renderer
      // defined the behaviour itself, using the action a button already supports: no new
      // semantics appeared, the degradation is the same.
      await pumpDocument(
        tester,
        docWithScreens([
          screenEntry('first', [
            appBarNode('Перший', showBack: false),
            buttonNode(
              'Далі',
              id: 'go',
              action: {
                'type': 'navigate',
                'params': {'screenId': 'second'},
              },
            ),
          ]),
          screenEntry('second', [
            appBarNode('Другий'),
            textNode('Другий екран'),
          ]),
        ], initialScreenId: 'first'),
      );

      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();
      expect(find.text('Другий екран'), findsOneWidget);

      await tester.tap(findAppBarBack);
      await tester.pumpAndSettle();
      expect(find.text('Далі'), findsOneWidget);
    });

    testWidgets('back from the first screen -- leaves the flow, the host decides', (tester) async {
      final fired = <String>[];
      await pumpDocument(
        tester,
        docWith([appBarNode('Єдиний', id: 'top-bar')]),
        onAction: (action, nodeId) => fired.add('${action.type}@$nodeId'),
      );

      await tester.tap(findAppBarBack);
      await tester.pump();

      expect(fired, ['navigate.back@top-bar']);
    });
  });

  group('a bar not in its place', () {
    testWidgets('a second bar is drawn where it stands, not discarded', (tester) async {
      // The builder will not emit such a document (`app_bar_misplaced`), but
      // a document arrives from the network. The renderer does not decide for the manager what to
      // remove from the document: the content stays, the first bar becomes the screen app bar.
      await pumpDocument(
        tester,
        docWith([
          appBarNode('Справжня шапка', id: 'top'),
          textNode('Між ними'),
          appBarNode('Зайва панель', id: 'stray'),
        ]),
      );

      expect(find.text('Справжня шапка'), findsOneWidget);
      expect(find.text('Зайва панель'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('Зайва панель'),
        ),
        findsOneWidget,
        reason: 'the extra bar stays in the body and does not become the app bar',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar inside a Column is drawn too', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'col',
            'type': 'Column',
            'props': {'gap': 'sm', 'align': 'start'},
            'children': [appBarNode('Панель у колонці', id: 'deep')],
          },
        ]),
      );

      expect(find.text('Панель у колонці'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('model', () {
    test('AppBar without children -- as before 9.9.0; children (9.9.0) are the bar actions', () {
      final plain = flattenDocument(docWith([appBarNode('Без дій')])).whereType<AppBarNode>().single;
      expect(plain.children, isEmpty);

      // Parsing takes all children; what is drawn of them is decided by drawing
      // (`appBarChildren`) -- see `media_chrome_cases_test.dart`.
      final withChildren = flattenDocument(
        docWith([
          {
            ...appBarNode('З дітьми'),
            'children': [textNode('Не малюється')],
          },
        ]),
      ).whereType<AppBarNode>().single;
      expect(withChildren.children, hasLength(1));
    });

    test('progress and catalog fixtures start with a bar', () {
      for (final id in ['task-progress-screen', 'full-catalog-screen']) {
        final root = rootOf(loadFixture(id)) as ScreenNode;
        expect(root.children.first, isA<AppBarNode>(), reason: id);
        expect(
          root.children.whereType<AppBarNode>(),
          hasLength(1),
          reason: '$id: the bar must be the only one',
        );
      }
    });
  });
}
