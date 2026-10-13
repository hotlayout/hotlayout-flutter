import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/demo_data.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

void main() {
  group('golden documents', () {
    for (final id in fixtureIds) {
      test('$id parses', () {
        final doc = loadFixture(id);
        expect(doc.isSupportedVersion, isTrue);
        expect(doc.documentId, isNotEmpty);
        expect(doc.screens, isNotEmpty);
        for (final screen in doc.screens) {
          expect(screen.screenId, isNotEmpty);
          expect(screen.root, isA<ScreenNode>());
        }
        // `initialScreenId` must point to a real screen of the document -
        // otherwise the renderer opens something other than what the manager intended.
        expect(doc.screenById(doc.initialScreenId), isNotNull);
      });

      testWidgets('$id renders without exceptions', (tester) async {
        await pumpDocument(tester, loadFixture(id), data: sampleScreenData, theme: fixtureTheme(id));
        expect(tester.takeException(), isNull);
      });
    }

    test('full-catalog covers all 22 types and none became unknown', () {
      final nodes = flattenDocument(loadFixture('full-catalog-screen')).toList();
      final types = nodes.map(contractType).toSet();

      expect(nodes.whereType<UnknownNode>(), isEmpty);
      expect(types, {
        'Screen',
        'AppBar',
        'Column',
        'Row',
        'Container',
        'Grid',
        'Stack',
        'Tabs',
        'Tab',
        'Accordion',
        'ChoiceGroup',
    'Repeater',
        'Spacer',
        'Divider',
        'Text',
        'Image',
        'Icon',
        'Button',
        'ListTile',
        'ProgressBar',
        'CircularProgress',
        'Badge',
      });
    });

    testWidgets('all fixtures paint on a phone screen', (tester) async {
      // The showcase will run on a real phone, not on the default 800x600 of
      // the tests: an `overflow` in a row with a thumbnail and a selection circle shows up
      // exactly on a narrow screen.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (final id in fixtureIds) {
        await pumpDocument(tester, loadFixture(id), data: sampleScreenData, theme: fixtureTheme(id));
        expect(tester.takeException(), isNull, reason: id);
      }
    });

    test('tasks-flow - three screens, and every navigation leads to an existing screen', () {
      final doc = loadFixture('tasks-flow-screens');
      final ids = doc.screens.map((screen) => screen.screenId).toSet();

      expect(ids, {'tasks', 'task-details', 'reward-sheet'});
      expect(doc.initialScreen.screenId, 'tasks');

      // The third screen arrived with 8.12.0 and it carries the presentation mode:
      // the golden document must contain the capability, not only its description in the schema.
      final sheet = doc.screens.firstWhere((screen) => screen.screenId == 'reward-sheet');
      expect(sheet.presentation, ScreenPresentationToken.modal);
      // The start screen cannot be modal - this is a builder rule, and
      // the fixture proves it is respected in what arrived here.
      expect(doc.initialScreen.presentation, ScreenPresentationToken.page);

      final targets = flattenDocument(doc)
          .whereType<ButtonNode>()
          .map((button) => button.action.navigationTarget)
          .nonNulls;

      expect(targets, isNotEmpty);
      for (final target in targets) {
        expect(ids, contains(target));
      }
    });

    test('every `navigate` in every fixture leads to an existing screen - from a row too', () {
      // Since 6.1.0 navigation exists on more than buttons, so both
      // entry points must be checked: otherwise a record card could lead nowhere, and
      // it would be noticed for the first time in a demo.
      for (final id in fixtureIds) {
        final doc = loadFixture(id);
        final screens = doc.screens.map((screen) => screen.screenId).toSet();
        final actions = [
          for (final node in flattenDocument(doc))
            ...switch (node) {
              ButtonNode(:final action) => [action],
              ListTileNode(:final action?) => [action],
              _ => const <ButtonAction>[],
            },
        ];

        for (final target in actions.map((action) => action.navigationTarget).nonNulls) {
          expect(screens, contains(target), reason: '$id: navigation to a non-existent screen');
        }
      }
    });

    testWidgets('Accordion expands on tap', (tester) async {
      // The accordion visibility condition in the fixture is `campaign.title eq 'Autumn
      // rewards'`, exactly the dictionary sample of that path. The sample data
      // mirrors the dictionary, so the condition holds by itself; if that ever
      // stops, it means a NEW divergence,
      // and the test must fail rather than "help" with a
      // substitution.
      // (A silent loss of the block would otherwise go unnoticed.)
      await pumpDocument(
        tester,
        loadFixture('full-catalog-screen'),
        data: sampleScreenData,
      );

      // `initiallyExpanded: false` in the fixture - the content is hidden at first.
      expect(find.textContaining('Випадковим чином'), findsNothing);
      await tester.ensureVisible(find.text('Як обирають переможців?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Як обирають переможців?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Випадковим чином'), findsOneWidget);
    });

    testWidgets('Row.justify=between gives spaceBetween', (tester) async {
      await pumpDocument(tester, loadFixture('task-progress-screen'), data: sampleScreenData);
      // A document row paints `RowLayout`, not Flutter `Row`: the widths of children
      // without weight are natural, not equal (see `row_natural_width_test`).
      final row = tester.widget<RowLayout>(
        find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(RowLayout)).first,
      );
      expect(row.justify, JustifyToken.between);
    });

    testWidgets('Button hands the host an action the renderer does not understand', (tester) async {
      final fired = <String>[];
      await pumpDocument(
        tester,
        loadFixture('task-progress-screen'),
        data: sampleScreenData,
        onAction: (action, nodeId) => fired.add('${action.type}@$nodeId'),
      );
      await tester.ensureVisible(find.text('Start task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start task'));
      expect(fired, ['submit@cta']);
    });
  });
}
