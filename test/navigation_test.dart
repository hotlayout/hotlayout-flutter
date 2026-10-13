import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/labels.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'package:hotlayout_flutter/src/model/tokens.dart';

import 'support/demo_data.dart';
import 'support/icons.dart';
import 'support/fixtures.dart';

Map<String, Object?> _navigate(String screenId) => {
  'type': ButtonAction.navigate,
  'params': {ButtonAction.screenIdParam: screenId},
};

UiDocument _twoScreens() => docWithScreens([
  screenEntry('first', [
    textNode('Перший екран', id: 't1'),
    buttonNode('Далі', action: _navigate('second'), id: 'to-second'),
  ]),
  screenEntry('second', [
    textNode('Другий екран', id: 't2'),
    buttonNode('Назад', action: const {'type': ButtonAction.navigateBack}, id: 'back'),
  ]),
], initialScreenId: 'first');

void main() {
  group('navigation between document screens', () {
    testWidgets('the `navigate` button opens the given screen, `navigate.back` returns', (
      tester,
    ) async {
      final host = <String>[];
      await pumpDocument(tester, _twoScreens(), onAction: (a, id) => host.add('${a.type}@$id'));

      expect(find.text('Перший екран'), findsOneWidget);

      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();
      expect(find.text('Другий екран'), findsOneWidget);
      expect(find.text('Перший екран'), findsNothing);

      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();
      expect(find.text('Перший екран'), findsOneWidget);

      // A transition is the renderer's job; it does not bother the host.
      expect(host, isEmpty);
    });

    testWidgets('navigating to a nonexistent screen breaks nothing and goes to the host', (tester) async {
      final host = <ButtonAction>[];
      final doc = docWithScreens([
        screenEntry('only', [
          textNode('Єдиний екран', id: 't'),
          buttonNode('У нікуди', action: _navigate('нема-такого'), id: 'ghost'),
        ]),
      ], initialScreenId: 'only');

      await pumpDocument(tester, doc, onAction: (action, _) => host.add(action));
      await tester.tap(find.text('У нікуди'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Єдиний екран'), findsOneWidget);
      // The host may know more than the document, so the action does not vanish silently.
      expect(host.single.navigationTarget, 'нема-такого');
    });

    testWidgets('`navigate` without screenId degrades just as gently', (tester) async {
      final host = <ButtonAction>[];
      final doc = docWithScreens([
        screenEntry('only', [
          buttonNode('Без цілі', action: const {'type': ButtonAction.navigate}, id: 'no-target'),
        ]),
      ], initialScreenId: 'only');

      await pumpDocument(tester, doc, onAction: (action, _) => host.add(action));
      await tester.tap(find.text('Без цілі'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(host.single.type, ButtonAction.navigate);
    });

    testWidgets('`navigate.back` from the first screen exits the flow, the host decides', (
      tester,
    ) async {
      final host = <String>[];
      final doc = docWithScreens([
        screenEntry('only', [
          buttonNode('Назад', action: const {'type': ButtonAction.navigateBack}, id: 'back'),
        ]),
      ], initialScreenId: 'only');

      await pumpDocument(tester, doc, onAction: (a, id) => host.add('${a.type}@$id'));
      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();

      expect(host, ['navigate.back@back']);
    });

    testWidgets('a stack deeper than two screens unwinds step by step', (tester) async {
      final doc = docWithScreens([
        screenEntry('a', [
          textNode('A', id: 'ta'),
          buttonNode('до B', action: _navigate('b'), id: 'ab'),
        ]),
        screenEntry('b', [
          textNode('B', id: 'tb'),
          buttonNode('до C', action: _navigate('c'), id: 'bc'),
          buttonNode('назад', action: const {'type': ButtonAction.navigateBack}, id: 'bb'),
        ]),
        screenEntry('c', [
          textNode('C', id: 'tc'),
          buttonNode('назад', action: const {'type': ButtonAction.navigateBack}, id: 'cb'),
        ]),
      ], initialScreenId: 'a');

      await pumpDocument(tester, doc);
      await tester.tap(find.text('до B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('до C'));
      await tester.pumpAndSettle();
      expect(find.text('C'), findsOneWidget);

      await tester.tap(find.text('назад'));
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);

      await tester.tap(find.text('назад'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('the start screen is the one in initialScreenId, not the first in the list', (
      tester,
    ) async {
      final doc = docWithScreens([
        screenEntry('first', [textNode('Перший', id: 't1')]),
        screenEntry('second', [textNode('Другий', id: 't2')]),
      ], initialScreenId: 'second');

      await pumpDocument(tester, doc);
      expect(find.text('Другий'), findsOneWidget);
    });

    test('initialScreenId pointing nowhere — take the first screen, do not crash', () {
      final doc = docWithScreens([
        screenEntry('first', [textNode('Перший', id: 't1')]),
        screenEntry('second', [textNode('Другий', id: 't2')]),
      ], initialScreenId: 'нема-такого');

      expect(doc.initialScreen.screenId, 'first');
    });

    testWidgets('flow fixture: there and back', (tester) async {
      // List rows come from the `tasks` collection, and the details read `task.*`.
      // Since 9.2.0 the details show the record of the ROW that was tapped (`navigateFromListItem`),
      // not the document sample: before that the transition in the fixture carried nothing, and
      // the details showed different text ("Make 5 card payments") than the row.
      await pumpDocument(tester, loadFixture('tasks-flow-screens'), data: sampleScreenData);

      expect(find.text('Spend 500 with your card'), findsOneWidget);

      await tester.ensureVisible(find.text('Spend 500 with your card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spend 500 with your card'));
      await tester.pumpAndSettle();
      // Details screen: the title comes from the row record, not from the document sample.
      expect(find.text('Spend 500 with your card'), findsOneWidget);
      expect(find.text('Make 5 card payments'), findsNothing);
      // `visibleIf: task.completed isTrue` — on sample data the task is still in
      // progress (the row record has `completed: false`), so there is no "done" mark;
      // it appears only once the task is completed.
      expect(find.text('Completed'), findsNothing);

      await tester.ensureVisible(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Spend 500 with your card'), findsOneWidget);
    });

    testWidgets('the renderer tells the host which screen is shown — at start too', (tester) async {
      // The stack is the renderer's internal business, but the host needs the fact
      // "this screen is current": it draws the system bars, and their styling comes
      // from the CURRENT screen. Since 7.0.0 this became visible: a start screen with
      // a solid colour would leave a white bar above the next screen's gradient.
      final seen = <String>[];
      await pumpDocument(tester, _twoScreens(), onScreenChanged: (s) => seen.add(s.screenId));
      // The first message arrives after the frame, not during build: the host
      // calls `setState` on it.
      await tester.pumpAndSettle();
      expect(seen, ['first']);

      await tester.tap(find.text('Далі'));
      await tester.pumpAndSettle();
      expect(seen, ['first', 'second']);

      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();
      expect(seen, ['first', 'second', 'first']);
    });

    testWidgets('a transition to nowhere is not reported to the host as a screen change', (tester) async {
      // The action goes to the host (it may know more than the document), but the screen did
      // not change — so there is nothing to redraw the bars for.
      final seen = <String>[];
      await pumpDocument(
        tester,
        docWith([buttonNode('У нікуди', action: _navigate('немає-такого'))]),
        onScreenChanged: (s) => seen.add(s.screenId),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('У нікуди'));
      await tester.pumpAndSettle();

      expect(seen, ['inline']);
    });

    testWidgets('a document that cannot be read declares no screen', (tester) async {
      final seen = <String>[];
      await pumpDocument(
        tester,
        // The foreign major is COMPUTED from our own (see `foreignMajorVersion`):
        // a literal stopped being foreign twice on the day the renderer moved.
        docWith([textNode('Не побачите')], schemaVersion: foreignMajorVersion),
        onScreenChanged: (s) => seen.add(s.screenId),
      );
      await tester.pumpAndSettle();

      expect(seen, isEmpty, reason: 'no flow — nothing to declare');
    });

    testWidgets('a document with a foreign major shows an explanation, not emptiness', (tester) async {
      await pumpDocument(
        tester,
        docWith([textNode('Не побачите')], schemaVersion: foreignMajorVersion),
      );

      expect(find.text('Не побачите'), findsNothing);
      expect(find.text(const RendererLabels().updateRequired), findsOneWidget);
    });
  });

  /*
   * INCOMPATIBLE-VERSION BANNER: two sides — two texts.
   *
   * Previously it said "update the app" for both sides, and for an 8.x document in
   * a 9.x reader that was advice which, once followed, would show the same
   * banner: a newer reader does not read the old major either. Such a document is
   * fixed by republishing from the builder — i.e. not by the user.
   */
  group('incompatible-version banner', () {
    const labels = RendererLabels();

    Future<List<String>> pumpAndCollectLog(WidgetTester tester, UiDocument doc, {RendererLabels? own}) async {
      final log = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => log.add(message ?? '');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: renderDocument(
                doc,
                theme: RenderTheme.fallback(),
                data: const {},
                labels: own ?? labels,
              ),
            ),
          ),
        );
      } finally {
        debugPrint = original;
      }
      return log;
    }

    test('default words: "update" and the neutral one differ', () {
      expect(labels.updateRequired, 'Update the app to see this screen.');
      expect(labels.screenUnavailable, 'This screen is not available right now.');
      // The neutral text does not advise what will not help.
      expect(labels.screenUnavailable.toLowerCase(), isNot(contains('update')));
    });

    testWidgets('document of a NEWER major: "update the app"', (tester) async {
      final log = await pumpAndCollectLog(
        tester,
        docWith([textNode('Не побачите')], schemaVersion: foreignMajorVersion),
      );

      expect(find.text(labels.updateRequired), findsOneWidget);
      expect(find.text(labels.screenUnavailable), findsNothing);
      expect(findIcon(IconToken.parse('download')), findsOneWidget);
      expect(log.single, allOf(contains('[hotlayout]'), contains(foreignMajorVersion), contains('newer major')));
    });

    testWidgets('document of an OLDER major: neutral text, cause in the log', (tester) async {
      final log = await pumpAndCollectLog(
        tester,
        docWith([textNode('Не побачите')], schemaVersion: previousMajorVersion),
      );

      expect(find.text('Не побачите'), findsNothing);
      expect(find.text(labels.screenUnavailable), findsOneWidget);
      expect(find.text(labels.updateRequired), findsNothing, reason: 'updating would not help here');
      // And the icon is not the one that prompts to update.
      expect(findIcon(IconToken.parse('download')), findsNothing);
      // The developer gets both versions and the action that actually fixes it.
      expect(
        log.single,
        allOf(
          contains('[hotlayout]'),
          contains(previousMajorVersion),
          contains(UiDocument.supportedSchemaVersion),
          contains('older major'),
          contains('republished from the builder'),
        ),
      );
    });

    testWidgets('an unreadable version: neutral text too', (tester) async {
      final log = await pumpAndCollectLog(
        tester,
        docWith([textNode('Не побачите')], schemaVersion: 'дев’ять'),
      );

      expect(find.text(labels.screenUnavailable), findsOneWidget);
      expect(find.text(labels.updateRequired), findsNothing);
      expect(log.single, contains('is not a version'));
    });

    testWidgets('the host supplies its own words — each side takes its own', (tester) async {
      const own = RendererLabels(updateRequired: 'Оновіть застосунок', screenUnavailable: 'Екран недоступний');

      await pumpAndCollectLog(
        tester,
        docWith([textNode('x')], schemaVersion: foreignMajorVersion),
        own: own,
      );
      expect(find.text('Оновіть застосунок'), findsOneWidget);
      expect(find.text('Екран недоступний'), findsNothing);

      await pumpAndCollectLog(
        tester,
        docWith([textNode('x')], schemaVersion: previousMajorVersion),
        own: own,
      );
      expect(find.text('Екран недоступний'), findsOneWidget);
      expect(find.text('Оновіть застосунок'), findsNothing);
      // The replaced word leaves no English behind.
      expect(find.text(labels.screenUnavailable), findsNothing);
    });
  });
}
