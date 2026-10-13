/// FIXTURE `carousel-steps-screens` (schema 9.11.0): a carousel of challenges
/// from data, a row of badges and milestone steps on a real screen -- in English,
/// Ukrainian and Arabic, at 320 and 393. The tables (`carousel_cases_test.dart`,
/// `progress_cases_test.dart`) cover individual rules; this covers them together.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/demo_data.dart';
import 'support/fixtures.dart';

void _view(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
}

void main() {
  final doc = loadFixture('carousel-steps-screens');
  final tasks = (sampleScreenData['tasks']! as List<Object?>).length;

  test('fixture: one screen, schema 9.11.0', () {
    expect(doc.schemaVersion, '9.11.0');
    expect(doc.screens.map((s) => s.screenId), ['streak']);
  });

  for (final locale in ['en', 'uk', 'ar']) {
    for (final width in [320.0, 393.0]) {
      testWidgets('$locale, ${width.round()}: two carousels, three step bars, no exceptions', (tester) async {
        _view(tester, width);
        await pumpDocument(tester, doc, data: sampleScreenData, locale: locale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final carousels = tester.widgetList<Carousel>(find.byType(Carousel)).toList();
        expect(carousels, hasLength(2));

        // Challenges: one card in view, peek xl (24), inset lg (16), gap md (12).
        final card = width - 16 - 12 - 24;
        expect(carousels[0].cardWidths, everyElement(closeTo(card, 1e-6)));
        expect(carousels[0].cardWidths, hasLength(tasks));
        // Badges: three in view, gap sm (8), no dots.
        final badge = (width - 16 - 3 * 8 - 24) / 3;
        expect(carousels[1].cardWidths, hasLength(6));
        expect(carousels[1].cardWidths, everyElement(closeTo(badge, 1e-6)));
        expect(carousels[1].dots, isFalse);

        // As many dots as stops: for challenges, one per card.
        final dots = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('carousel-dot'));
        expect(dots, findsNWidgets(tasks));

        // Six badges, three at a time: four stops.
        final second = tester.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView)).where((s) => s.physics is CarouselPhysics).toList();
        expect((second[1].physics! as CarouselPhysics).stops(), hasLength(4));

        // Three bars with six steps.
        final bars = tester.widgetList<ProgressTrack>(find.byType(ProgressTrack)).where((t) => t.segments == 6).toList();
        expect(bars, hasLength(3));
      });
    }
  }

  testWidgets('Arabic: the first challenge card sits to the right of the start inset, badges too', (tester) async {
    _view(tester, 320);
    await pumpDocument(tester, doc, data: sampleScreenData, locale: 'ar');
    await tester.pumpAndSettle();
    final first = tester.getTopRight(find.byType(Carousel).first.hitTestable().first);
    expect(first.dx, closeTo(320, 1e-6));
    final scroll = find.descendant(of: find.byType(Carousel).first, matching: find.byType(SingleChildScrollView));
    await tester.drag(scroll, const Offset(200, 0));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(find.descendant(of: find.byType(Carousel).first, matching: find.byType(Scrollable))).position;
    expect(position.pixels, closeTo(280, 1e-6), reason: 'at 320 the stops are 0, 280, 540');
  });

  testWidgets('en, 320: labels W1...W6 sit under the steps (row share equals the step width)', (tester) async {
    _view(tester, 320);
    await pumpDocument(tester, doc, data: sampleScreenData);
    await tester.pumpAndSettle();
    final track = tester.getRect(find.byType(ProgressTrack).at(tasks + 1));
    final step = (track.width - 5 * 4) / 6;
    for (var i = 0; i < 6; i += 1) {
      final label = tester.getCenter(find.text('W${i + 1}').at(1)).dx;
      expect(label, closeTo(track.left + i * (step + 4) + step / 2, 1.5), reason: 'W${i + 1}');
    }
  });
}
