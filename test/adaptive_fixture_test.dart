/// FIXTURE `adaptive-screens` (9.18.0): the width-adaptivity showcase.
///
/// The contract table covers individual rules (`adaptive_cases_test.dart`); here --
/// the whole showcase: every screen is drawn without exceptions at the class bounds and in
/// three languages (en, uk, ar), and above all what it promises is delivered by a real
/// measurement -- at 393 / 768 / 1280.
library;

import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart' show ScreenPresentationToken;
import 'package:hotlayout_flutter/src/render/app_bar_layout.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart' show kModalLayerKey;
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/demo_data.dart';
import 'support/fixtures.dart';

void _view(WidgetTester tester, double width, [double height = 1000]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

UiDocument _startingAt(String screenId) {
  final json = jsonDecode(readFixture('adaptive-screens')) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

Future<void> _pump(WidgetTester tester, double width, String screen, {String? locale}) async {
  _view(tester, width);
  await pumpDocument(tester, _startingAt(screen), locale: locale, data: sampleScreenData);
  expect(tester.takeException(), isNull);
}

void main() {
  test('fixture: schema version, catalog and three languages', () {
    final doc = loadFixture('adaptive-screens');
    expect(doc.schemaVersion, '9.24.0');
    expect(fixtureIds, contains('adaptive-screens'));
    expect(doc.screens.map((s) => s.screenId), ['home', 'lab', 'rewards', 'bonus']);
    expect(doc.screens.last.presentation, ScreenPresentationToken.modal);
    expect(doc.locales, ['en', 'uk', 'ar']);
  });

  group('every screen is drawn without exceptions at the class bounds', () {
    for (final screen in ['home', 'lab', 'rewards', 'bonus']) {
      for (final width in [320.0, 393.0, 599.0, 600.0, 768.0, 1023.0, 1024.0, 1280.0, 1920.0]) {
        for (final locale in [null, 'uk', 'ar']) {
          testWidgets('$screen / ${width.toInt()}${locale == null ? '' : ' / $locale'}', (tester) async {
            await _pump(tester, width, screen, locale: locale);
          });
        }
      }
    }
  });

  group('lab: grid 2 -> 3 -> 4', () {
    // How many cells stand in the first row -- by layout, not by class name.
    int firstRow(WidgetTester tester) {
      final first = tester.getTopLeft(find.text('1')).dy;
      var count = 0;
      for (var i = 1; i <= 8; i++) {
        if ((tester.getTopLeft(find.text('$i')).dy - first).abs() < 1) count++;
      }
      return count;
    }

    for (final (width, columns) in [(393.0, 2), (599.0, 2), (600.0, 3), (768.0, 3), (1023.0, 3), (1024.0, 4), (1280.0, 4)]) {
      testWidgets('${width.toInt()}: $columns in a row', (tester) async {
        await _pump(tester, width, 'lab');
        expect(firstRow(tester), columns);
      });
    }
  });

  group('lab: "phone only" and "wide only" blocks', () {
    for (final (width, phone, tablet, wide) in [
      (393.0, true, false, false),
      (599.0, true, false, false),
      (600.0, false, true, false),
      (768.0, false, true, false),
      (1023.0, false, true, false),
      (1024.0, false, true, true),
      (1280.0, false, true, true),
    ]) {
      testWidgets('${width.toInt()}', (tester) async {
        await _pump(tester, width, 'lab');
        expect(find.text('Phone only'), phone ? findsOneWidget : findsNothing);
        expect(find.text('Tablet and wider'), tablet ? findsOneWidget : findsNothing);
        expect(find.text('Wide only'), wide ? findsOneWidget : findsNothing);
      });
    }
  });

  group('lab: column -> row 2 : 1', () {
    for (final locale in [null, 'ar']) {
      testWidgets('1280${locale == null ? '' : ' / $locale'}: parts in one row, the wider is the main one', (tester) async {
        await _pump(tester, 1280, 'lab', locale: locale);
        final main = tester.getRect(find.text(locale == null ? 'Main part' : 'الجزء الرئيسي').first);
        final side = tester.getRect(find.text(locale == null ? 'Side part' : 'الجزء الجانبي').first);
        expect((main.top - side.top).abs(), lessThan(1), reason: 'in one row');
        // The writing start is left in LTR and right in RTL: the main one comes first.
        if (locale == null) {
          expect(main.left, lessThan(side.left));
        } else {
          expect(main.left, greaterThan(side.left));
        }
      });
    }

    testWidgets('393: parts one under the other', (tester) async {
      await _pump(tester, 393, 'lab');
      final main = tester.getRect(find.text('Main part'));
      final side = tester.getRect(find.text('Side part'));
      expect(side.top, greaterThan(main.top));
      expect((main.left - side.left).abs(), lessThan(1));
    });
  });

  group('content width', () {
    testWidgets('lab: at 1280 the column is no wider than 960 and is centred; at 768 it is full width', (tester) async {
      await _pump(tester, 1280, 'lab');
      final grid = tester.getRect(find.text('Grid: 2, 3 or 4 in a row'));
      expect(grid.left, greaterThanOrEqualTo((1280 - 960) / 2));
      await _pump(tester, 768, 'lab');
      expect(tester.getRect(find.text('Grid: 2, 3 or 4 in a row')).left, lessThan(40));
    });

    testWidgets('home: base 1120 -- at 1280 the side column is on the right, content within the column', (tester) async {
      await _pump(tester, 1280, 'home');
      final side = tester.getRect(find.text('Leaderboard'));
      expect(side.right, lessThanOrEqualTo(1280 - (1280 - 1120) / 2));
      final main = tester.getRect(find.text('Active quests'));
      expect(main.left, greaterThanOrEqualTo((1280 - 1120) / 2));
      expect(side.left, greaterThan(main.left), reason: 'the side column is alongside, on the right (LTR)');
    });

    testWidgets('home: at 393 the side column is under the main one', (tester) async {
      await _pump(tester, 393, 'home');
      expect(tester.getRect(find.text('Leaderboard')).top, greaterThan(tester.getRect(find.text('Active quests')).top));
    });
  });

  group('navigation bar: at the bottom on a phone, at the top on a wide screen (step 2)', () {
    Finder item(String id) => find.byKey(ValueKey('sdui-nav-item-$id'));

    testWidgets('home: at 393 the bar is at the bottom, the app bar at the top', (tester) async {
      await _pump(tester, 393, 'home');
      expect(find.byType(ScreenZones), findsOneWidget);
      expect(tester.getRect(item('nav-home')).bottom, closeTo(1000, 1));
      expect(tester.getRect(find.text('Home').first).top, lessThan(80));
    });

    for (final width in [600.0, 768.0, 1024.0, 1280.0, 1920.0]) {
      testWidgets('home: at ${width.toInt()} the items are in the app bar, there is no bottom zone', (tester) async {
        await _pump(tester, width, 'home');
        final bar = tester.getRect(find.byType(AppBarLayout));
        for (final id in ['nav-home', 'nav-lab', 'nav-rewards', 'nav-profile']) {
          final rect = tester.getRect(item(id));
          expect(rect.top, greaterThanOrEqualTo(bar.top - 0.01), reason: id);
          expect(rect.bottom, lessThanOrEqualTo(bar.bottom + 0.01), reason: '$id in the app bar');
        }
        // There is no bottom zone: the body runs to the very bottom, and no layout child stands under it.
        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones));
        var count = 0;
        for (var child = zones.firstChild; child != null; child = zones.childAfter(child)) {
          count += 1;
        }
        expect(count, 2, reason: 'app bar and body');
        // The bell is an app bar action: the items stand before it in reading order.
        final layout = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
        final bell = layout.lastChild!;
        expect(tester.getRect(item('nav-profile')).right, lessThanOrEqualTo((bell.localToGlobal(Offset.zero) & bell.size).left + 0.01));
      });
    }

    testWidgets('home, Arabic: the app bar items go right to left, the first is the rightmost', (tester) async {
      await _pump(tester, 1280, 'home', locale: 'ar');
      final first = tester.getRect(item('nav-home'));
      final second = tester.getRect(item('nav-lab'));
      expect(first.left, greaterThan(second.left));
    });

    for (final width in [768.0, 1280.0]) {
      testWidgets('rewards (no app bar): at ${width.toInt()} its own strip at the top, edge to edge', (tester) async {
        await _pump(tester, width, 'rewards');
        final first = tester.getRect(item('nav-home'));
        expect(first.top, 0);
        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones));
        final strip = zones.firstChild!;
        expect(strip.localToGlobal(Offset.zero), Offset.zero);
        expect(strip.size.width, width, reason: 'strip edge to edge');
        // Items start at the row start, in the content column (contentMaxWidth: 1120).
        final content = ((width - 1120) / 2).clamp(0.0, width);
        expect(first.left, closeTo(content, 0.01));
        // The body scrolls under the strip: the strip does not move.
        expect(tester.getRect(find.text('Spend your points on something nice')).top, greaterThanOrEqualTo(strip.size.height));
      });
    }

    testWidgets('rewards: at 393 the bar is at the bottom', (tester) async {
      await _pump(tester, 393, 'rewards');
      expect(tester.getRect(item('nav-home')).bottom, closeTo(1000, 1));
    });

    testWidgets('switching a section with a top item: the stack resets, as with the bottom bar', (tester) async {
      await _pump(tester, 1280, 'home');
      await tester.tap(item('nav-rewards'));
      await tester.pumpAndSettle();
      expect(find.text('Spend your points on something nice'), findsOneWidget);
      expect(find.text('Level 7 · Explorer'), findsNothing);
      // A section without an app bar: now the bar is its own strip, and the item of the active section is marked.
      final selected = tester.getSemantics(find.bySemanticsLabel('Rewards').first);
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    });
  });

  group('at all six widths and in both writing directions', () {
    Finder item(String id) => find.byKey(ValueKey('sdui-nav-item-$id'));

    for (final width in [393.0, 600.0, 768.0, 1024.0, 1280.0, 1920.0]) {
      for (final locale in [null, 'ar']) {
        final rtl = locale == 'ar';
        final suffix = '${width.toInt()}${rtl ? ' / ar' : ''}';

        testWidgets('home, $suffix: item order follows the writing direction, everything within the screen', (tester) async {
          await _pump(tester, width, 'home', locale: locale);
          final first = tester.getRect(item('nav-home'));
          final second = tester.getRect(item('nav-lab'));
          expect(rtl ? first.left > second.left : first.left < second.left, isTrue, reason: 'the first item is at the writing start');
          for (final id in ['nav-home', 'nav-lab', 'nav-rewards', 'nav-profile']) {
            final rect = tester.getRect(item(id));
            expect(rect.left, greaterThanOrEqualTo(-0.01), reason: id);
            expect(rect.right, lessThanOrEqualTo(width + 0.01), reason: id);
          }
          // A narrow phone has the bar at the bottom (items side by side across the full width); a wide one has it in the app bar, in one row.
          final top = tester.getRect(item('nav-home')).top;
          expect(tester.getRect(item('nav-profile')).top, closeTo(top, 0.01), reason: 'items in one row');
          if (width < 600) {
            expect(tester.getRect(item('nav-home')).bottom, closeTo(1000, 1));
          } else {
            expect(top, lessThan(120));
          }
        });

        testWidgets('rewards, $suffix: strip at the top edge to edge, items from the writing start in the column', (tester) async {
          await _pump(tester, width, 'rewards', locale: locale);
          final firstRect = tester.getRect(item('nav-home'));
          if (width < 600) {
            expect(firstRect.bottom, closeTo(1000, 1));
            return;
          }
          final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones));
          expect(zones.firstChild!.size.width, width);
          final content = ((width - 1120) / 2).clamp(0.0, width);
          if (rtl) {
            expect(firstRect.right, closeTo(width - content, 0.01));
          } else {
            expect(firstRect.left, closeTo(content, 0.01));
          }
        });
      }
    }
  });

  group('bonus: sheet on a phone, window on a wide screen', () {
    Future<void> openBonus(WidgetTester tester, double width, {String? locale}) async {
      await _pump(tester, width, 'home', locale: locale);
      final claim = find.text(switch (locale) { 'ar' => 'احصل على +20 نقطة', 'uk' => 'Забрати +20 балів', _ => 'Claim +20 pts' });
      await tester.ensureVisible(claim.first);
      await tester.tap(claim.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('393: full width, pinned to the bottom', (tester) async {
      await openBonus(tester, 393);
      final rect = tester.getRect(find.byKey(kModalLayerKey));
      expect(rect.width, 393);
      expect(rect.bottom, closeTo(1000, 0.01));
    });

    for (final width in [768.0, 1280.0]) {
      testWidgets('${width.toInt()}: a 560 window in the centre, bottom corners rounded', (tester) async {
        await openBonus(tester, width);
        final rect = tester.getRect(find.byKey(kModalLayerKey));
        expect(rect.width, 560);
        expect(rect.center.dx, closeTo(width / 2, 0.01));
        expect(rect.center.dy, closeTo(500, 0.01));
        // The root names only the top corners in the document; in the window the bottom ones take their radius.
        final decorated = find.descendant(
          of: find.byKey(kModalLayerKey),
          matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null),
        );
        final radius = (tester.widget<DecoratedBox>(decorated.first).decoration as BoxDecoration).borderRadius! as BorderRadiusDirectional;
        expect(radius.bottomStart, radius.topStart);
        expect(radius.bottomEnd, radius.topEnd);
        expect(radius.topStart, isNot(Radius.zero));
        // The window content is the phone layout: ListTile across the full window width.
        expect(find.text('Day 5 · today'), findsOneWidget);
      });
    }

    testWidgets('1280, Arabic: window in the centre, bottom corners from the top ones of their own side', (tester) async {
      await openBonus(tester, 1280, locale: 'ar');
      final rect = tester.getRect(find.byKey(kModalLayerKey));
      expect(rect.width, 560);
      final decorated = find.descendant(
        of: find.byKey(kModalLayerKey),
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null),
      );
      final radius = (tester.widget<DecoratedBox>(decorated.first).decoration as BoxDecoration).borderRadius! as BorderRadiusDirectional;
      expect(radius.bottomStart, radius.topStart);
      expect(radius.bottomEnd, radius.topEnd);
    });

    testWidgets('the scrim closes the sheet window, like the sheet', (tester) async {
      await openBonus(tester, 1280);
      await tester.tapAt(const Offset(40, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsNothing);
      expect(find.text('Level 7 · Explorer'), findsOneWidget);
    });
  });
}
