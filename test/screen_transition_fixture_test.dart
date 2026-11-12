/// The frame of 9.38.0 (`fixtures/screen-transition-screens.json`): an onboarding of three pages, a sheet of terms, a
/// window "All set", a page that dissolves in (`transition: fade`) and a page that appears at once (`none`).
/// The route that is walked is the one the contract names for a visual check: Next, Next, Read the terms, Got it, Finish,
/// Close, Back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart' show kModalScrimOpacity;
import 'package:hotlayout_flutter/src/model/screen_transition.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';
import 'package:hotlayout_flutter/src/render/screen_transitions.dart' show PageMotion;

import 'support/fixtures.dart';

void main() {
  const id = 'screen-transition-screens';

  /// A phone: the layers of the frame are sheets only on a compact area.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<List<String>> open(WidgetTester tester) async {
    phone(tester);
    final shown = <String>[];
    await pumpDocument(
      tester,
      loadFixture(id),
      theme: fixtureTheme(id),
      onScreenShown: (event) => shown.add('${event.cause.name}:${event.screenId}'),
    );
    await tester.pumpAndSettle();
    return shown;
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  /// The pump that gets the layer going (its clock starts one frame after it is built), then [ms] of its motion.
  Future<void> layerAt(WidgetTester tester, int ms) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
  }

  test('the frame is registered and names the field on two of its screens', () {
    expect(fixtureIds, contains(id));
    final doc = loadFixture(id);
    expect(doc.screenById('news')!.transition, ScreenTransitionWord.fade);
    expect(doc.screenById('skip')!.transition, ScreenTransitionWord.none);
    expect(doc.screenById('welcome')!.transition, isNull);
    expect(doc.screenById('terms')!.presentation.wire, 'modal');
    expect(doc.screenById('done')!.modalPlacement!.wire, 'center');
  });

  testWidgets('the route of the contract: pages slide, the terms rise as a sheet, the window fades in', (tester) async {
    final shown = await open(tester);
    expect(find.text('Welcome'), findsOneWidget);

    // Next: the page comes in from the end edge over the first one.
    await press(tester, 'Next');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PageMotion), findsNWidgets(2));
    expect(find.text('Welcome'), findsOneWidget, reason: 'the old page is drawn under the new one while it moves');
    expect(find.text('Pick your rewards'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsNothing);

    await press(tester, 'Next');
    await tester.pumpAndSettle();
    expect(find.text('Stay in the loop'), findsOneWidget);

    // Read the terms: a sheet rises over the page, and the scrim thickens with it.
    await press(tester, 'Read the terms');
    await layerAt(tester, 70);
    expect(find.byType(PageMotion), findsNothing, reason: 'a layer is not a page step');
    final height = tester.getSize(find.byKey(kModalLayerKey)).height;
    final top = tester.getTopLeft(find.byKey(kModalLayerKey)).dy;
    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.byKey(kModalLayerKey)).dy;
    expect(top - rest, closeTo(0.3928 * height, 1));
    expect(find.text('Stay in the loop'), findsOneWidget, reason: 'the page stays under the sheet');

    await press(tester, 'Got it');
    await layerAt(tester, 110);
    expect(tester.getTopLeft(find.byKey(kModalLayerKey)).dy - rest, closeTo(0.3248 * height, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(kModalLayerKey), findsNothing);

    // Finish: the window grows from a slight zoom while it fades in.
    await press(tester, 'Finish');
    await layerAt(tester, 50);
    final scale = tester
        .widget<Transform>(find.ancestor(of: find.byKey(kModalLayerKey), matching: find.byType(Transform)).first)
        .transform
        .storage[0];
    expect(scale, closeTo(0.9843, 1e-3));
    await tester.pumpAndSettle();
    expect(find.text('All set'), findsOneWidget);

    await press(tester, 'Close');
    await tester.pumpAndSettle();
    await press(tester, 'Back');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PageMotion), findsNWidgets(2), reason: 'back slides the page out');
    await tester.pumpAndSettle();
    expect(find.text('Pick your rewards'), findsOneWidget);
    expect(shown, [
      'entry:welcome',
      'forward:interests',
      'forward:alerts',
      'forward:terms',
      'back:alerts',
      'forward:done',
      'back:alerts',
      'back:interests',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the scrim under the sheet is the resting colour once the sheet is in place', (tester) async {
    await open(tester);
    await press(tester, 'Next');
    await tester.pumpAndSettle();
    await press(tester, 'Next');
    await tester.pumpAndSettle();
    await press(tester, 'Read the terms');
    await tester.pumpAndSettle();
    final scrim = tester.widget<ColoredBox>(find.descendant(of: find.byType(GestureDetector), matching: find.byType(ColoredBox)).first);
    expect(scrim.color.a, closeTo(kModalScrimOpacity, 1e-6));
  });

  testWidgets('a page that says fade dissolves in: no slide, the old page fades out over it', (tester) async {
    await open(tester);
    await press(tester, "What's new");
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PageMotion), findsNothing);
    final fading = tester.widget<Opacity>(find.ancestor(of: find.text('Welcome'), matching: find.byType(Opacity)).last);
    expect(fading.opacity, closeTo(0.2244, 1e-3));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsNothing);
    expect(find.text('A calmer look'), findsOneWidget);
    await press(tester, 'Back');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PageMotion), findsNothing, reason: 'it dissolves out too');
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('a page that says none is there at once, and goes at once', (tester) async {
    await open(tester);
    await press(tester, 'Skip');
    expect(find.text('Welcome'), findsNothing);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.byType(PageMotion), findsNothing);
    await press(tester, 'Back');
    expect(find.text('Skipped'), findsNothing);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('"reduce motion": the whole route is at once', (tester) async {
    phone(tester);
    await pumpDocument(tester, loadFixture(id), theme: fixtureTheme(id), disableAnimations: true);
    await press(tester, 'Next');
    expect(find.byType(PageMotion), findsNothing);
    expect(find.text('Welcome'), findsNothing);
    await press(tester, 'Next');
    await press(tester, 'Read the terms');
    await tester.pump();
    expect(find.byKey(kModalLayerKey), findsOneWidget);
    await press(tester, 'Got it');
    expect(find.byKey(kModalLayerKey), findsNothing);
  });
}
