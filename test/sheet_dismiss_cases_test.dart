/// A sheet that closes by a drag down, and `dismissible: false` (schema 9.26.0, `x-sheetDismiss`): the shared table
/// `fixtures/sheet-dismiss/sheet-dismiss-cases.json` run through the rule, through the parsed entry and through a real
/// finger, and then what the table cannot say: the sheet follows the finger and never goes above its place, the scrim
/// fades with it, the stack goes back only after the sheet has left, a scrolled body scrolls first, and a layer that
/// waits for an action is not closed by anything but an action.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show ScreenFlowController, ScreenShownCause;
import 'package:hotlayout_flutter/src/model/compatibility.dart' show kSupportedSchemaVersion;
import 'package:hotlayout_flutter/src/model/sheet_dismiss.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/sheet-dismiss/sheet-dismiss-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  final block = schema['x-sheetDismiss']! as _Row;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final startCases = rowsOf('startCases');
  final releaseCases = rowsOf('releaseCases');
  final entryCases = rowsOf('entryCases');
  final documentCases = rowsOf('documentCases');
  final ruleCases = rowsOf('ruleCases');

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A page with a button that opens the sheet; the sheet holds [lines] lines of text and a button that goes back.
  UiDocument sheetDocument({Object? dismissible, Object? placement, int lines = 3, List<_Row> extra = const []}) => UiDocument.fromJson({
    'schemaVersion': kSupportedSchemaVersion,
    'documentId': 'sheet-flow',
    'name': 'sheet',
    'initialScreenId': 'home',
    'screens': [
      screenEntry('home', [
        buttonNode('Open', action: {'type': 'navigate', 'params': {'screenId': 'sheet'}}, id: 'open'),
      ]),
      {
        ...screenEntry(
          'sheet',
          [
            for (var i = 0; i < lines; i += 1)
              {
                'id': 'line$i',
                'type': 'Text',
                'props': {'content': {'kind': 'literal', 'value': 'Line $i'}},
                'style': {'height': 100},
              },
            ...extra,
            buttonNode('Done', action: {'type': 'navigate.back'}, id: 'done'),
          ],
          presentation: 'modal',
          modalPlacement: placement,
        ),
        'dismissible': ?dismissible,
      },
    ],
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Offset sheetTop(WidgetTester tester) => tester.getTopLeft(find.byKey(kModalLayerKey));

  /// A drag of [dy] down from the middle of the sheet over [ms], ending with the finger still down.
  Future<TestGesture> dragDown(WidgetTester tester, double dy, {int ms = 1000, Finder? from}) async {
    final start = tester.getCenter(from ?? find.text('Line 0'));
    final gesture = await tester.startGesture(start);
    const steps = 10;
    for (var step = 1; step <= steps; step += 1) {
      // The events carry their own time: the velocity of the release is read from it.
      await gesture.moveTo(start + Offset(0, dy * step / steps), timeStamp: Duration(milliseconds: ms * step ~/ steps));
      await tester.pump(Duration(milliseconds: ms ~/ steps));
    }
    return gesture;
  }

  test('the table is read in full', () {
    expect(startCases, hasLength(8));
    expect(releaseCases, hasLength(9));
    expect(entryCases, hasLength(2));
    expect(documentCases, hasLength(3));
    expect(ruleCases, hasLength(6));
  });

  group('startCases: drag or scroll', () {
    for (final row in startCases) {
      test(row['name']! as String, () {
        expect(
          sheetDragStarts(
            sheet: row['sheet']! as bool,
            dismissible: row['dismissible']! as bool,
            scrolled: (row['scrolled']! as num).toDouble(),
            dy: (row['dy']! as num).toDouble(),
            dx: (row['dx']! as num).toDouble(),
            onHandle: row['onHandle']! as bool,
          ),
          row['expect'],
        );
      });
    }
  });

  group('releaseCases: what a released sheet comes to', () {
    for (final row in releaseCases) {
      test(row['name']! as String, () {
        final outcome = sheetDragOutcome(
          sheetHeight: (row['sheetHeight']! as num).toDouble(),
          dragged: (row['dragged']! as num).toDouble(),
          velocity: (row['velocity']! as num).toDouble(),
        );
        expect(outcome == SheetDragOutcome.dismiss ? 'dismiss' : 'return', row['expect']);
      });
    }
  });

  group('entryCases and documentCases: the field of the entry', () {
    for (final row in entryCases) {
      test(row['name']! as String, () {
        final entry = row['entry']! as _Row;
        final doc = UiDocument.fromJson({
          'schemaVersion': kSupportedSchemaVersion,
          'documentId': 'entry',
          'name': 'entry',
          'initialScreenId': 'home',
          'screens': [screenEntry('home', const []), {...screenEntry('redeem', const []), ...entry}],
        });
        expect(doc.screenById('redeem')!.dismissible, row['expect']);
      });
    }

    for (final row in documentCases) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        final entry = row['entry']! as _Row;
        final doc = UiDocument.fromJson({
          'schemaVersion': kSupportedSchemaVersion,
          'documentId': 'entry',
          'name': 'entry',
          'initialScreenId': 'home',
          'screens': [
            screenEntry('home', [buttonNode('Open', action: {'type': 'navigate', 'params': {'screenId': 'redeem'}}, id: 'open')]),
            {...screenEntry('redeem', [buttonNode('Done', action: {'type': 'navigate.back'}, id: 'done')]), ...entry},
          ],
        });
        await pumpDocument(tester, doc);
        await openSheet(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Done'), findsOneWidget);
      });
    }

    test('only the word false is read, and a page keeps it too without a layer to close', () {
      for (final raw in [true, 'false', 0, null, <String, Object?>{}]) {
        final doc = UiDocument.fromJson({
          'schemaVersion': kSupportedSchemaVersion,
          'documentId': 'entry',
          'name': 'entry',
          'initialScreenId': 'home',
          'screens': [{...screenEntry('home', const []), 'dismissible': raw}],
        });
        expect(doc.screens.single.dismissible, isTrue, reason: '$raw');
      }
    });
  });

  group('ruleCases and the mirror of the artifact', () {
    for (final row in ruleCases) {
      test('rule: ${row['name']}', () {
        final expected = row['expect'];
        switch (row['rule']) {
          case 'release.dismissShare':
            expect(kSheetDismissShare, expected);
          case 'release.flingVelocity':
            expect(kSheetFlingVelocity, expected);
          case 'release.velocityWindowMs':
            expect(kSheetVelocityWindowMs, expected);
          case 'returns':
            expect({'durationMs': kSheetReturn.durationMs, 'curve': kSheetReturn.curve}, expected);
          case 'exits':
            expect({'durationMs': kSheetExit.durationMs, 'curve': kSheetExit.curve}, expected);
          case 'dismissible.field':
            expect(kDismissibleKey, expected);
          default:
            fail('unknown rule ${row['rule']}');
        }
      });
    }

    test('the scalar rows of the block are the ones in code', () {
      for (final entry in kSheetDismissRules.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
    });
  });

  group('the finger', () {
    testWidgets('the sheet follows the finger down and the scrim fades with it', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument());
      await openSheet(tester);
      final rest = sheetTop(tester);
      final scrim = find.descendant(of: find.byType(ModalLayer), matching: find.byType(ColoredBox)).first;
      final restAlpha = tester.widget<ColoredBox>(scrim).color.a;
      final gesture = await dragDown(tester, 60);
      expect(sheetTop(tester).dy, closeTo(rest.dy + 60, 1), reason: 'it follows the finger from the touch');
      expect(tester.widget<ColoredBox>(scrim).color.a, lessThan(restAlpha));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(sheetTop(tester), rest, reason: 'a short drag returns it');
      expect(tester.widget<ColoredBox>(scrim).color.a, restAlpha);
    });

    testWidgets('it never goes above its place', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument());
      await openSheet(tester);
      final rest = sheetTop(tester);
      final start = tester.getCenter(find.text('Line 0'));
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(start + const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheetTop(tester).dy, closeTo(rest.dy, 0.5));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('dragged past 0.3 of the height and released slowly: it leaves, and only then does the stack go back', (tester) async {
      phone(tester);
      final shown = <ScreenShownCause>[];
      await pumpDocument(tester, sheetDocument(), onScreenShown: (event) => shown.add(event.cause));
      await tester.pump();
      await openSheet(tester);
      expect(shown.last, ScreenShownCause.forward);
      final height = tester.getSize(find.byKey(kModalLayerKey)).height;
      final gesture = await dragDown(tester, height * 0.35, ms: 2000);
      shown.clear();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(shown, isEmpty, reason: 'the sheet is still on its way out');
      expect(find.text('Line 0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(shown, [ScreenShownCause.back]);
      expect(find.text('Line 0'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('a short drag thrown down fast leaves; a long one thrown back up returns', (tester) async {
      phone(tester);
      final shown = <ScreenShownCause>[];
      await pumpDocument(tester, sheetDocument(), onScreenShown: (event) => shown.add(event.cause));
      await openSheet(tester);
      final rest = sheetTop(tester);
      // 40 px in 40 ms is 1000 px/s.
      var gesture = await dragDown(tester, 100, ms: 100);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shown.last, ScreenShownCause.back, reason: 'a fling down closes at any distance');

      await openSheet(tester);
      final start = tester.getCenter(find.text('Line 0'));
      gesture = await dragDown(tester, 300, ms: 2000);
      // Back up fast: the last 100 ms go up at 1250 px/s.
      await gesture.moveTo(start + const Offset(0, 250), timeStamp: const Duration(milliseconds: 2050));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(start + const Offset(0, 175), timeStamp: const Duration(milliseconds: 2100));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsOneWidget, reason: 'a fling up returns it whatever the distance');
      expect(sheetTop(tester), rest);
    });

    testWidgets('a body scrolled away from its top scrolls first; the sheet moves only when it is at the top', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument(lines: 12));
      await openSheet(tester);
      final rest = sheetTop(tester);
      final body = find.byType(SingleChildScrollView).last;
      final scroll = tester.state<ScrollableState>(find.descendant(of: body, matching: find.byType(Scrollable)).first);
      // Scroll the body up by dragging up.
      await tester.drag(find.text('Line 3'), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(100));
      final scrolled = scroll.position.pixels;
      expect(sheetTop(tester), rest);

      // A drag down scrolls the body back; the sheet stays.
      final gesture = await tester.startGesture(tester.getCenter(find.text('Line 8')));
      for (var step = 0; step < 4; step += 1) {
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(scroll.position.pixels, lessThan(scrolled));
      expect(sheetTop(tester), rest, reason: 'the body is not at its top yet');
      await gesture.up();
      await tester.pumpAndSettle();

      // At the top, a drag down moves the sheet.
      scroll.position.jumpTo(0);
      await tester.pump();
      final drag = await dragDown(tester, 60, from: find.text('Line 1'));
      expect(sheetTop(tester).dy, greaterThan(rest.dy + 40));
      await drag.up();
      await tester.pumpAndSettle();
      expect(sheetTop(tester), rest);
    });

    testWidgets('a sideways drag does not move the sheet', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument());
      await openSheet(tester);
      final rest = sheetTop(tester);
      final start = tester.getCenter(find.text('Line 0'));
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(80, 30));
      await tester.pump(const Duration(milliseconds: 50));
      expect(sheetTop(tester), rest);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the finger that drags the sheet presses nothing under it when it lifts', (tester) async {
      phone(tester);
      final calls = <String>[];
      await pumpDocument(
        tester,
        sheetDocument(extra: [buttonNode('Pay', action: {'type': 'pay'}, id: 'pay')]),
        onAction: (action, nodeId) => calls.add(action.type),
      );
      await openSheet(tester);
      final gesture = await dragDown(tester, 14, ms: 100, from: find.text('Pay'));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'a drag that started on a button is not a press of it');
    });

    testWidgets('a centred window has no drag', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument(placement: 'center'));
      await openSheet(tester);
      final rest = sheetTop(tester);
      final gesture = await dragDown(tester, 200, ms: 300);
      expect(sheetTop(tester), rest);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsOneWidget);
    });

    testWidgets('«reduce motion»: the sheet follows the finger, the exit is instant', (tester) async {
      phone(tester);
      final shown = <ScreenShownCause>[];
      await pumpDocument(tester, sheetDocument(), disableAnimations: true, onScreenShown: (event) => shown.add(event.cause));
      await openSheet(tester);
      final rest = sheetTop(tester);
      final gesture = await dragDown(tester, 40, ms: 100);
      expect(sheetTop(tester).dy, closeTo(rest.dy + 40, 1));
      await gesture.up();
      await tester.pump();
      expect(sheetTop(tester), rest, reason: 'the return is instant');

      final drag = await dragDown(tester, 300, ms: 2000);
      shown.clear();
      await drag.up();
      await tester.pump();
      await tester.pump();
      expect(shown, [ScreenShownCause.back], reason: 'the exit is instant too');
    });

    testWidgets('the flow\'s controller sees one step back, and the page below is where it was', (tester) async {
      phone(tester);
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await pumpDocument(tester, sheetDocument(), controller: controller);
      await openSheet(tester);
      expect(controller.canGoBack, isTrue);
      final gesture = await dragDown(tester, 300, ms: 2000);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.canGoBack, isFalse);
      expect(controller.currentScreenId, 'home');
    });
  });

  group('«dismissible: false»: only an action inside closes the layer', () {
    testWidgets('no drag moves it, and it stays', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument(dismissible: false));
      await openSheet(tester);
      final rest = sheetTop(tester);
      final gesture = await dragDown(tester, 300, ms: 300);
      expect(sheetTop(tester), rest);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsOneWidget);
    });

    testWidgets('a tap on the scrim and Esc do nothing', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument(dismissible: false));
      await openSheet(tester);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsOneWidget, reason: 'the scrim takes the touch and does nothing');
      expect(find.text('Open'), findsOneWidget, reason: 'the page below took no touch');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsOneWidget);
    });

    testWidgets('the system back is the host\'s: the controller still goes back, and navigate.back inside closes', (tester) async {
      phone(tester);
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await pumpDocument(tester, sheetDocument(dismissible: false), controller: controller);
      await openSheet(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(controller.canGoBack, isFalse);
    });

    testWidgets('with no field a tap on the scrim and Esc close it, as they did', (tester) async {
      phone(tester);
      await pumpDocument(tester, sheetDocument());
      await openSheet(tester);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsNothing);
      await openSheet(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Line 0'), findsNothing);
    });
  });
}
