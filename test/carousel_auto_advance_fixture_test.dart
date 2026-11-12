/// The frame of 9.42.0 (`fixtures/carousel-auto-advance-screens.json`): stories that turn by themselves every five
/// seconds with a segmented bar that follows them through the stop path, and a promo banner that goes round.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';

import 'support/fixtures.dart';

void main() {
  const id = 'carousel-auto-advance-screens';
  const path = 'account.cardIndex';

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The frame opened on one of its two screens.
  UiDocument opened(String screenId) {
    final json = (jsonDecode(readFixture(id)) as Map).cast<String, Object?>();
    return UiDocument.fromJson({...json, 'initialScreenId': screenId});
  }

  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)))
      .position;

  /// Lives [ms] of the frame in steps of 20 ms: the timer ticks every 100 ms of its own.
  Future<void> live(WidgetTester tester, int ms) async {
    for (var left = ms; left > 0; left -= 20) {
      await tester.pump(Duration(milliseconds: left < 20 ? left : 20));
    }
  }

  test('the frame is registered and both carousels carry the field', () {
    expect(fixtureIds, contains(id));
    final doc = loadFixture(id);
    expect(doc.schemaVersion, '9.42.0');
    expect(readFixture(id), contains('"autoAdvance": {'));
    expect(readFixture(id), contains('"loop": true'));
    expect(doc.screenById('stories'), isNotNull);
    expect(doc.screenById('promo'), isNotNull);
  });

  testWidgets('the stories turn by themselves: one write per step, the bar and the scroll follow', (tester) async {
    phone(tester);
    final log = <List<Object?>>[];
    await pumpDocument(tester, opened('stories'), theme: fixtureTheme(id), onWrite: (p, value) => log.add([p, value]));
    await tester.pump();
    final position = positionOf(tester);
    expect(position.pixels, 0);

    await live(tester, 4800);
    expect(log, isEmpty, reason: 'five seconds have not passed');
    await live(tester, 600);
    expect(log, [
      [path, 1],
    ]);
    await live(tester, 600);
    expect(position.pixels, greaterThan(0), reason: 'the story turned');
    final second = position.pixels;

    await live(tester, 5600);
    expect(log, [
      [path, 1],
      [path, 2],
    ]);
    await live(tester, 600);
    expect(position.pixels, greaterThan(second));
    final last = position.pixels;

    await live(tester, 12000);
    expect(log, hasLength(2), reason: 'without loop the timer stops on the last story');
    expect(position.pixels, last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the promo goes round: after the last banner back to the first', (tester) async {
    phone(tester);
    await pumpDocument(tester, opened('promo'), theme: fixtureTheme(id));
    await tester.pump();
    final position = positionOf(tester);
    var maxOffset = 0.0;
    var wentBack = false;
    for (var ms = 0; ms < 20000 && !wentBack; ms += 100) {
      await live(tester, 100);
      final now = position.pixels;
      if (now > maxOffset) maxOffset = now;
      wentBack = maxOffset > 0 && now < maxOffset - 1 && now < 1;
    }
    expect(maxOffset, greaterThan(0), reason: 'it moved forward on its own');
    expect(wentBack, isTrue, reason: 'and went round to the first banner');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finger held on the stories stops the clock', (tester) async {
    phone(tester);
    final log = <List<Object?>>[];
    await pumpDocument(tester, opened('stories'), theme: fixtureTheme(id), onWrite: (p, value) => log.add([p, value]));
    await tester.pump();
    final finger = await tester.startGesture(tester.getCenter(find.byType(Carousel)));
    await live(tester, 20000);
    expect(log, isEmpty);
    await finger.up();
    await live(tester, 6000);
    expect(log, isNotEmpty, reason: 'let go, it goes on');
  });
}
