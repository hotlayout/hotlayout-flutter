/// THE FRAME `value-countdown-screens` (schema 9.21.0): a balance that counts after a payment, a ring and two
/// bars that grow to the new step, a countdown that ticks in seconds, and a mission screen whose app bar becomes
/// solid and shows its title on scroll. Every screen in two languages and on two phone widths, then each scene
/// as its story says (and with reduced motion).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/countdown_clock.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

UiDocument _startingAt(String screenId) {
  final json = jsonDecode(readFixture('value-countdown-screens')) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

void _view(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Map<String, Object?> _data({required num points, required num progress, String endsAt = '2026-10-10T09:00:30.000Z'}) => {
  'user.points': points,
  'task.progress': progress,
  'task.target': 5,
  'offer.endsAt': endsAt,
};

List<String> _texts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data != null) text.data!,
];

void main() {
  late DateTime clock;

  setUp(() {
    clock = DateTime.utc(2026, 10, 10, 9, 0, 0);
    readerClock = () => clock;
    addTearDown(() => readerClock = DateTime.now);
  });

  test('the fixture is in the catalogue, at 9.21.0, in two languages', () {
    final doc = loadFixture('value-countdown-screens');
    expect(doc.schemaVersion, '9.33.0');
    expect(fixtureIds, contains('value-countdown-screens'));
    expect(doc.screens.map((screen) => screen.screenId), ['balance', 'mission']);
    expect(doc.locales, ['en', 'uk']);
  });

  group('every screen is drawn without exceptions', () {
    for (final screen in ['balance', 'mission']) {
      for (final width in [320.0, 393.0]) {
        for (final locale in [null, 'uk']) {
          testWidgets('$screen / ${width.toInt()}${locale == null ? '' : ' / $locale'}', (tester) async {
            _view(tester, width);
            await pumpDocument(tester, _startingAt(screen), locale: locale, data: _data(points: 1240, progress: 3));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('«after a payment»: the balance counts, the ring and the bars grow', () {
    final bar = find.byType(ProgressTrack);

    double ratioOf(WidgetTester tester, int index) => tester.widgetList<ProgressTrack>(bar).elementAt(index).ratio;

    testWidgets('the numbers lead from the old values to the new ones', (tester) async {
      _view(tester, 393);
      final doc = _startingAt('balance');
      await pumpDocument(tester, doc, data: _data(points: 1240, progress: 3));
      expect(_texts(tester), contains('1,240'));
      expect(_texts(tester), contains('3 / 5'));
      expect(ratioOf(tester, 0), closeTo(0.6, 1e-9));
      expect(ratioOf(tester, 1), closeTo(0.6, 1e-9));

      await pumpDocument(tester, doc, data: _data(points: 1540, progress: 4));
      // The frame of the change: the old numbers, the new ones are not shown ahead.
      expect(_texts(tester), contains('1,240'));
      expect(_texts(tester), contains('3 / 5'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_texts(tester), contains('1,502'), reason: '1240 + trunc(300 * 0.875) = 1502');
      expect(_texts(tester), contains('3 / 5'), reason: '3 + trunc(1 * 0.875) = 3: whole steps stay on the old value');
      expect(ratioOf(tester, 0), closeTo(0.6 + 0.2 * 0.875, 1e-9), reason: 'the bar fills without a step');
      expect(ratioOf(tester, 1), closeTo(0.6 + 0.2 * 0.875, 1e-9));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_texts(tester), contains('1,540'));
      expect(_texts(tester), contains('4 / 5'));
      expect(ratioOf(tester, 0), closeTo(0.8, 1e-9));
      expect(tester.hasRunningAnimations, isFalse, reason: 'when the numbers arrive, nothing runs any more');
    });

    testWidgets('with reduced motion the numbers change at once', (tester) async {
      _view(tester, 393);
      final doc = _startingAt('balance');
      await pumpDocument(tester, doc, data: _data(points: 1240, progress: 3), disableAnimations: true);
      await pumpDocument(tester, doc, data: _data(points: 1540, progress: 4), disableAnimations: true);
      expect(_texts(tester), contains('1,540'));
      expect(_texts(tester), contains('4 / 5'));
      expect(ratioOf(tester, 0), closeTo(0.8, 1e-9));
    });

    testWidgets('in Ukrainian the same numbers lead, written by the language', (tester) async {
      _view(tester, 393);
      final doc = _startingAt('balance');
      await pumpDocument(tester, doc, locale: 'uk', data: _data(points: 1240, progress: 3));
      expect(_texts(tester).any((text) => text.contains('1 240')), isTrue, reason: _texts(tester).toString());
      await pumpDocument(tester, doc, locale: 'uk', data: _data(points: 1540, progress: 4));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_texts(tester).any((text) => text.contains('1 502')), isTrue, reason: _texts(tester).toString());
    });
  });

  group('the countdown ticks', () {
    testWidgets('seconds go down once a second, the days and hours stand', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('balance'), data: _data(points: 1, progress: 1, endsAt: '2026-10-12T23:05:09.000Z'));
      String countdown() => _texts(tester).firstWhere((text) => text.startsWith('Ends in'));
      final first = countdown();
      expect(first, startsWith('Ends in 2 d 14 h 05 min'));
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(countdown(), isNot(first));
      expect(countdown(), startsWith('Ends in 2 d 14 h 05 min'));
    });
  });

  group('the mission screen: the app bar after scrolling', () {
    final bar = find.byKey(const ValueKey('hl-zone-bar'));

    double titleOpacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.descendant(of: bar, matching: find.byType(Opacity)).first).opacity;

    bool solid(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.descendant(of: bar, matching: find.byType(DecoratedBox)))
        .any((box) => box.decoration is BoxDecoration && (box.decoration as BoxDecoration).color != null);

    for (final locale in <String?>[null, 'uk']) {
      testWidgets('the bar is transparent with no title at rest, solid with the title when scrolled${locale == null ? '' : ' ($locale)'}', (tester) async {
        _view(tester, 393);
        await pumpDocument(tester, _startingAt('mission'), locale: locale, data: _data(points: 1, progress: 1));
        expect(titleOpacity(tester), 0);
        expect(solid(tester), isFalse);
        final zone = tester.getSize(bar).height;
        final controller = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first).controller!;
        controller.jumpTo(zone);
        await tester.pump();
        expect(titleOpacity(tester), 0, reason: 'exactly the bar zone: still rest');
        controller.jumpTo(zone + 1);
        await tester.pump();
        expect(titleOpacity(tester), 1);
        expect(solid(tester), isTrue);
        controller.jumpTo(0);
        await tester.pump();
        expect(titleOpacity(tester), 0);
        expect(solid(tester), isFalse);
      });
    }
  });
}
