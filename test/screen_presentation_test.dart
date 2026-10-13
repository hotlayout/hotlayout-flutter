import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

/// Screen presentation mode (8.12.0): as a page or as a layer over the previous one.
///
/// A modal here is neither a new widget nor a `Navigator` dialog, but the very same
/// document screen laid over the previous frame. So exactly that is checked: the
/// screen it was opened from stays UNDER it, and it takes the height of its content
/// rather than all that is available.
void main() {
  Map<String, Object?> goTo(String screenId, {String id = 'btn', String label = 'Відкрити'}) =>
      buttonNode(label, id: id, action: {
        'type': 'navigate',
        'params': {'screenId': screenId},
      });

  UiDocument flow({String? presentation = 'modal'}) => docWithScreens(
    [
      screenEntry('home', [textNode('Головний екран', id: 'home-text'), goTo('gift')]),
      screenEntry(
        'gift',
        [textNode('Ваш подарунок', id: 'gift-text')],
        presentation: presentation,
      ),
    ],
    initialScreenId: 'home',
  );

  group('модель', () {
    test('no field - an ordinary screen, as before 8.12.0', () {
      final doc = flow(presentation: null);
      expect(doc.screens[1].presentation, ScreenPresentationToken.page);
    });

    test('an unknown mode degrades to a page instead of failing the document', () {
      final doc = flow(presentation: 'sheet');
      expect(doc.screens[1].presentation, ScreenPresentationToken.page);
    });

    test('modal is read as modal', () {
      expect(flow().presentation('gift'), ScreenPresentationToken.modal);
    });
  });

  group('показ', () {
    testWidgets('the screen it was opened from stays under the modal', (tester) async {
      await pumpDocument(tester, flow());
      expect(find.text('Ваш подарунок'), findsNothing);

      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();

      // Both screens are on the glass at once - that is the whole point of the mode.
      expect(find.text('Ваш подарунок'), findsOneWidget);
      expect(find.text('Головний екран'), findsOneWidget);
    });

    testWidgets('an ordinary screen REPLACES the previous one', (tester) async {
      await pumpDocument(tester, flow(presentation: null));

      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();

      expect(find.text('Ваш подарунок'), findsOneWidget);
      expect(find.text('Головний екран'), findsNothing);
    });

    /*
     * The sheet takes the height of its CONTENT. This is the half of the mode that is easy
     * to lose unnoticed: a screen stretched over the whole glass is also "shown on top",
     * but it is then indistinguishable from a page, and the point of a modal is gone.
     */
    testWidgets('the sheet is shorter than the glass when there is little content', (tester) async {
      // A bottom sheet is the phone form: on a wide place (800 in tests by default) the sheet
      // becomes a window in the middle (9.18.0, step 2; `wide_chrome_cases_test.dart`).
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 800);
      addTearDown(tester.view.reset);
      await pumpDocument(tester, flow());
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();

      final glass = tester.getSize(find.byType(MaterialApp)).height;
      final sheet = tester.getRect(find.text('Ваш подарунок'));

      expect(sheet.height, lessThan(glass / 2));
      // And pressed to the bottom: the sheet bottom is closer to the glass bottom than its top.
      expect(glass - sheet.bottom, lessThan(sheet.top));
    });

    testWidgets('a tap on the scrim closes the modal', (tester) async {
      await pumpDocument(tester, flow());
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();

      // The top point of the glass is the scrim: the sheet is at the bottom and does not reach it.
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      expect(find.text('Ваш подарунок'), findsNothing);
      expect(find.text('Головний екран'), findsOneWidget);
    });
  });
}

extension on UiDocument {
  ScreenPresentationToken presentation(String screenId) =>
      screens.firstWhere((screen) => screen.screenId == screenId).presentation;
}
