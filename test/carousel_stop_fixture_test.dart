/// The frame of 9.32.0 (`fixtures/carousel-stop-screens.json`): the cards of an account in a carousel whose active
/// stop is `account.cardIndex`. An own dot writes the number of its card, the carousel goes to it and does not write
/// again, and the details of that card appear in place; a swipe to the last card writes its number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';

import 'support/fixtures.dart';

void main() {
  const path = 'account.cardIndex';
  const details = {
    'details-debit': 'Coffee · −₴85',
    'details-credit': 'Tickets · −₴1 250',
    'details-new': 'Open a card to start',
  };

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  List<String> shown() => [
    for (final entry in details.entries)
      if (find.text(entry.value).evaluate().isNotEmpty) entry.key,
  ];

  final scroller = find.descendant(of: find.byType(Carousel), matching: find.byType(SingleChildScrollView));
  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)))
      .position;

  test('the frame is registered, current and carries the path on its carousel', () {
    expect(fixtureIds, contains('carousel-stop-screens'));
    final doc = loadFixture('carousel-stop-screens');
    expect(doc.schemaVersion, '9.32.0');
    expect(readFixture('carousel-stop-screens'), contains('"stopPath": "$path"'));
  });

  testWidgets('a dot of the second card: one write, the carousel goes to it, the credit details show', (tester) async {
    phone(tester);
    final log = <List<Object?>>[];
    await pumpDocument(tester, loadFixture('carousel-stop-screens'), onWrite: (p, value) => log.add([p, value]));
    await tester.pumpAndSettle();
    expect(shown(), isEmpty, reason: 'no value: no card is named');
    expect(positionOf(tester).pixels, 0);

    await tester.tap(find.byKey(const ValueKey('sdui-press-dot-1@')).first);
    await tester.pumpAndSettle();
    expect(log, [
      [path, 1],
    ]);
    expect(positionOf(tester).pixels, greaterThan(0));
    expect(shown(), ['details-credit']);
  });

  testWidgets('a swipe to the last card writes its number and shows the details of the new card', (tester) async {
    phone(tester);
    final log = <List<Object?>>[];
    await pumpDocument(tester, loadFixture('carousel-stop-screens'), onWrite: (p, value) => log.add([p, value]));
    await tester.pumpAndSettle();
    await tester.fling(scroller.first, const Offset(-2000, 0), 3000);
    await tester.pumpAndSettle();
    expect(log, [
      [path, 2],
    ]);
    expect(shown(), ['details-new']);
  });
}
