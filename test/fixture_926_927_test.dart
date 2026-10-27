/// THE FRAMES `longpress-groups-sheet-screens` (schema 9.26.0) and `live-record-screens` (9.27.0): every screen in three
/// languages on two phone widths, then each story as its screen says.
///
///  * History: a day over its records («Today», «Yesterday», «Wed, Oct 14»); a hold on the card opens the window
///    «Mission options», a tap opens the page «Mission»; «Quick redeem» is a sheet that is dragged down, «Confirm» one
///    that is closed by its button alone;
///  * Tasks: the task opened from the list shows 3 / 5, and when the data moves it to the completed list the page,
///    and the sheet «Details» over it, show 5 / 5 and «completed» in place.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show ScreenFlowController, ScreenShownCause;
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';

import 'support/fixtures.dart';

const _history = 'longpress-groups-sheet-screens';
const _tasks = 'live-record-screens';

UiDocument _startingAt(String id, String screenId) {
  final json = jsonDecode(readFixture(id)) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

void _view(WidgetTester tester, double width, [double height = 800]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _activities = [
  {'title': 'Coffee row', 'points': 120, 'day': 'Today'},
  {'title': 'Movie row', 'points': -300, 'day': 'Today'},
  {'title': 'Strong row', 'points': 80, 'day': 'Yesterday'},
  {'title': 'Check-in row', 'points': 5, 'day': 'Yesterday'},
  {'title': 'Trip row', 'points': 250, 'day': 'Wed, Oct 14'},
];

Map<String, Object?> _task(String id, String title, int progress, String status) => {
  'id': id,
  'title': title,
  'progress': progress,
  'target': 5,
  'status': status,
};

void main() {
  test('the fixtures are in the catalogue, at 9.27.0, in two languages', () {
    for (final id in [_history, _tasks]) {
      final doc = loadFixture(id);
      expect(doc.schemaVersion, '9.31.0', reason: id);
      expect(fixtureIds, contains(id));
      expect(doc.locales, ['en', 'uk'], reason: id);
    }
  });

  group('every screen is drawn without exceptions', () {
    for (final entry in {
      _history: ['history', 'mission', 'peek', 'redeem', 'confirm'],
      _tasks: ['tasks', 'task', 'peek'],
    }.entries) {
      for (final screen in entry.value) {
        for (final width in [320.0, 393.0]) {
          for (final locale in [null, 'uk', 'ar']) {
            testWidgets('${entry.key}/$screen at $width (${locale ?? 'en'})', (tester) async {
              _view(tester, width);
              await pumpDocument(
                tester,
                _startingAt(entry.key, screen),
                locale: locale,
                data: {
                  'activities': _activities,
                  'tasks': [_task('spend', 'Spend 500 with your card', 3, 'inProgress')],
                  'task.title': 'Spend 500 with your card',
                  'task.progress': 3,
                },
                safeTop: 47,
                safeBottom: 34,
              );
              expect(tester.takeException(), isNull);
              await tester.pumpAndSettle();
            });
          }
        }
      }
    }
  });

  group('History', () {
    testWidgets('a day stands over its records: «Today» over two, «Yesterday» over two, «Wed, Oct 14» over one', (tester) async {
      _view(tester, 393, 1000);
      await pumpDocument(tester, loadFixture(_history), data: const {'activities': _activities}, safeTop: 47, safeBottom: 34);
      final order = ['Today', 'Coffee row', 'Movie row', 'Yesterday', 'Strong row', 'Check-in row', 'Wed, Oct 14', 'Trip row'];
      var previous = -1.0;
      for (final line in order) {
        expect(find.text(line), findsOneWidget, reason: line);
        final top = tester.getTopLeft(find.text(line)).dy;
        expect(top, greaterThan(previous), reason: '$line is below the line before it');
        previous = top;
      }
    });

    testWidgets('a hold on the card opens «Mission options» and asks for the haptic response; a tap opens «Mission»', (tester) async {
      _view(tester, 393, 1000);
      final haptics = <String>[];
      final shown = <String>[];
      await pumpDocument(
        tester,
        loadFixture(_history),
        data: const {'activities': _activities},
        onHaptic: (word, nodeId, record) => haptics.add('${word.wire}@$nodeId'),
        onScreenShown: (event) => shown.add('${event.cause.name}:${event.screenId}'),
        safeTop: 47,
        safeBottom: 34,
      );
      await tester.pump();
      shown.clear();

      final gesture = await tester.startGesture(tester.getCenter(find.text('Hold for options')));
      await tester.pump(const Duration(milliseconds: 460));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Mission options'), findsOneWidget);
      expect(shown, ['forward:peek']);
      expect(haptics, ['medium@mission-card'], reason: 'the hold asks; the tap\'s «light» did not');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Mission options'), findsNothing);

      shown.clear();
      haptics.clear();
      await tester.tap(find.text('Hold for options'));
      await tester.pumpAndSettle();
      expect(shown, ['forward:mission']);
      expect(haptics, ['light@mission-card']);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('«Quick redeem» is dragged down to close, «Confirm» is closed by its button alone', (tester) async {
      _view(tester, 393, 1000);
      final shown = <ScreenShownCause>[];
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await pumpDocument(
        tester,
        loadFixture(_history),
        data: const {'activities': _activities},
        controller: controller,
        onScreenShown: (event) => shown.add(event.cause),
        safeTop: 47,
        safeBottom: 34,
      );
      await tester.tap(find.text('Quick redeem'));
      await tester.pumpAndSettle();
      expect(controller.currentScreenId, 'redeem');
      final height = tester.getSize(find.byKey(kModalLayerKey)).height;
      final start = tester.getCenter(find.text('Drag down to close'));
      final drag = await tester.startGesture(start);
      for (var step = 1; step <= 10; step += 1) {
        await drag.moveTo(start + Offset(0, height * 0.4 * step / 10), timeStamp: Duration(milliseconds: 150 * step));
        await tester.pump(const Duration(milliseconds: 150));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.currentScreenId, 'history');
      expect(shown.last, ScreenShownCause.back);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(controller.currentScreenId, 'confirm');
      final confirmStart = tester.getCenter(find.text('This sheet waits for a button'));
      final stubborn = await tester.startGesture(confirmStart);
      await stubborn.moveTo(confirmStart + const Offset(0, 300), timeStamp: const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await stubborn.up();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 30));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.currentScreenId, 'confirm', reason: 'no drag, no scrim, no Esc');
      await tester.tap(find.text('Confirm').last);
      await tester.pumpAndSettle();
      expect(controller.currentScreenId, 'history');
    });
  });

  group('Tasks', () {
    testWidgets('the page opened from «Spend 500 with your card» shows 5 / 5 and «completed» when the data moves the task, and the sheet over it too',
        (tester) async {
      _view(tester, 393, 1000);
      final doc = loadFixture(_tasks);
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      final shown = <String>[];
      Future<void> pump(Map<String, Object?> data) => pumpDocument(
        tester,
        doc,
        data: data,
        controller: controller,
        onScreenShown: (event) => shown.add('${event.cause.name}:${event.screenId}'),
        safeTop: 47,
        safeBottom: 34,
      );

      await pump({
        'tasks': [_task('spend', 'Spend 500 with your card', 3, 'inProgress'), _task('invite', 'Invite a friend', 0, 'locked')],
        'doneTasks': <Object?>[],
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spend 500 with your card'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 5'), findsOneWidget);
      // The status of the page, and the same task's row in «More tasks» (the list is the data, not the record).
      expect(find.text('inProgress'), findsNWidgets(2));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(controller.currentScreenId, 'peek');
      expect(find.text('3 / 5'), findsNWidgets(2), reason: 'the page and the sheet over it');
      shown.clear();

      await pump({
        'tasks': [_task('invite', 'Invite a friend', 0, 'locked')],
        'doneTasks': [_task('spend', 'Spend 500 with your card', 5, 'completed')],
      });
      await tester.pumpAndSettle();
      expect(find.text('5 / 5'), findsNWidgets(2));
      expect(find.text('completed'), findsOneWidget);
      expect(controller.currentScreenId, 'peek', reason: 'the stack stays');
      expect(shown, isEmpty, reason: 'new data is not a show');

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);
    });
  });
}
