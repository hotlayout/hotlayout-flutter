/// THE FRAMES `float-nav-swipe-screens` (schema 9.22.0) and `filter-gradient-compact-screens` (9.23.0), each screen in
/// two languages and on two phone widths, then each scene as its story says.
///
///  * float: the last row of "Home" scrolls clear of the pill and the glass shows the cards under it, "Missions" has a
///    dot, its pinned block stands above the pill, "Redeem" is a swipe that returns when short and goes to "Done"
///    when it reaches the end, "Done" has a code in a dashed border;
///  * filter: "All" shows three cards, "Coffee" one without a hole in the grid, "Books" the empty state, "All" again
///    three; the title is a gradient on the letters; "1.3K ✦ this year" in English, "1,3 тис. ✦ за рік" in Ukrainian.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/dashed_border.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';
import 'package:hotlayout_flutter/src/render/widgets/nav_bar.dart';

import 'support/fixtures.dart';

UiDocument _startingAt(String id, String screenId) {
  final json = jsonDecode(readFixture(id)) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

void _view(WidgetTester tester, double width, [double height = 800]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _data = <String, Object?>{'task.progress': 2, 'user.points': 1250, 'offer.code': 'HL-2026'};

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

void main() {
  test('the fixtures are in the catalogue, at 9.24.0, in two languages', () {
    for (final id in ['float-nav-swipe-screens', 'filter-gradient-compact-screens']) {
      final doc = loadFixture(id);
      expect(doc.schemaVersion, '9.24.0');
      expect(fixtureIds, contains(id));
      expect(doc.locales, ['en', 'uk']);
    }
  });

  group('every screen is drawn without exceptions', () {
    const screens = {
      'float-nav-swipe-screens': ['home', 'missions', 'redeem', 'done'],
      'filter-gradient-compact-screens': ['catalog'],
    };
    for (final MapEntry(key: id, value: ids) in screens.entries) {
      for (final screen in ids) {
        for (final width in [320.0, 393.0]) {
          for (final locale in [null, 'uk', 'ar']) {
            testWidgets('$id / $screen at $width (${locale ?? 'en'})', (tester) async {
              _view(tester, width);
              await pumpDocument(tester, _startingAt(id, screen), data: {..._data, 'items': const <Object?>[]}, locale: locale, safeBottom: 34);
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }
  });

  group('float-nav-swipe-screens', () {
    testWidgets('Home: the last row scrolls clear of the pill; the dot is on Missions', (tester) async {
      _view(tester, 393, 700);
      await pumpDocument(tester, _startingAt('float-nav-swipe-screens', 'home'), data: _data, safeBottom: 34);
      expect(find.byType(NavBadgeMark), findsOneWidget);
      expect(find.byType(ZoneTailPadding), findsOneWidget);
      final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
      final scroll = find.byType(SingleChildScrollView).last;
      final pillBefore = tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byWidgetPredicate((w) => w is Container && w.child is Material)).first).top;
      expect(tester.getRect(find.text('Seven days in a row.')).top, greaterThan(pillBefore), reason: 'before the scroll the last row is under the pill, whose glass shows it');
      await tester.drag(scroll, const Offset(0, -3000));
      await tester.pumpAndSettle();
      final pillTop = tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byWidgetPredicate((w) => w is Container && w.child is Material)).first).top;
      // The last row of the last card ends above the top of the pill (and, before the scroll, was under it).
      final lastLine = tester.getRect(find.text('Seven days in a row.'));
      expect(lastLine.bottom, lessThanOrEqualTo(pillTop + 0.5));
      expect(zones.size.height, 700);
    });

    testWidgets('Missions: the pinned block stands above the pill', (tester) async {
      _view(tester, 393, 700);
      await pumpDocument(tester, _startingAt('float-nav-swipe-screens', 'missions'), data: _data, safeBottom: 34);
      final swipe = _rect(tester, find.byType(SwipeConfirmTrack));
      final pill = tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byWidgetPredicate((w) => w is Container && w.child is Material)).first);
      expect(swipe.bottom, lessThanOrEqualTo(pill.top));
      expect(pill.bottom, lessThan(700), reason: 'the pill hangs above the home indicator');
    });

    testWidgets('Redeem: a short drag returns; a full one goes to Done, where the code stands in a dashed border', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('float-nav-swipe-screens', 'redeem'), data: _data, safeBottom: 34);
      final track = _rect(tester, find.byType(SwipeConfirmTrack));
      final thumb = find.descendant(
        of: find.byType(SwipeConfirmTrack),
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle),
      );
      final start = _rect(tester, thumb);

      var gesture = await tester.startGesture(start.center);
      for (var i = 0; i < 10; i += 1) {
        await gesture.moveBy(Offset((track.width - 60) * 0.5 / 10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_rect(tester, thumb), start, reason: 'a short drag returns');
      expect(find.byType(DashedBorder), findsNothing);

      await tester.tap(find.byType(SwipeConfirmTrack));
      await tester.pumpAndSettle();
      expect(find.byType(DashedBorder), findsNothing, reason: 'a tap is not a confirmation');

      gesture = await tester.startGesture(start.center);
      for (var i = 0; i < 20; i += 1) {
        await gesture.moveBy(Offset(track.width / 20, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(DashedBorder), findsOneWidget, reason: 'the code stands in a dashed border');
      expect(find.text('HL-2026'), findsOneWidget);
    });
  });

  group('filter-gradient-compact-screens', () {
    const items = [
      {'selectedId': 'backpack', 'name': 'Alpine backpack'},
      {'selectedId': 'coffee-set', 'name': 'Coffee set'},
      {'selectedId': 'backpack', 'name': 'City backpack'},
    ];
    final data = {..._data, 'items': items};

    testWidgets('All three, Coffee one without a hole, Books the empty state, All again three', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('filter-gradient-compact-screens', 'catalog'), data: data);
      for (final name in ['Alpine backpack', 'Coffee set', 'City backpack']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Nothing in this category yet'), findsNothing);

      await tester.tap(find.text('Coffee'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee set'), findsOneWidget);
      expect(find.text('Alpine backpack'), findsNothing);
      // One card in a grid of two columns: it stands at the first cell, with no hole before it.
      final card = tester.getRect(find.text('Coffee set'));
      expect(card.left, lessThan(393 / 2));

      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee set'), findsNothing);
      expect(find.text('Nothing in this category yet'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      for (final name in ['Alpine backpack', 'Coffee set', 'City backpack']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Nothing in this category yet'), findsNothing);
    });

    testWidgets('the title is a gradient on the letters', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('filter-gradient-compact-screens', 'catalog'), data: data);
      expect(find.ancestor(of: find.text('Rewards'), matching: find.byType(ShaderMask)), findsOneWidget);
    });

    testWidgets('1.3K in English, 1,3 тис. in Ukrainian', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('filter-gradient-compact-screens', 'catalog'), data: data);
      expect(find.text('1.3K ✦ this year'), findsOneWidget);
      await pumpDocument(tester, _startingAt('filter-gradient-compact-screens', 'catalog'), data: data, locale: 'uk');
      expect(find.text('1,3 тис. ✦ за рік'), findsOneWidget);
    });
  });
}
