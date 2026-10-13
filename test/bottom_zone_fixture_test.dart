/// FIXTURE `bottom-zone-screens` (schema 9.12.0): three sections with the same
/// navigation bar, a pinned button above the bar, a long page with a pinned
/// button and a sheet with two pinned buttons -- in English, Ukrainian and
/// Arabic, at 320 and 393. The table (`bottom_zone_cases_test.dart`) covers
/// individual rules; this covers them together, with a real gesture.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/fixtures.dart';

void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

Finder get _items =>
    find.byWidgetPredicate((w) => w is InkWell && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('sdui-nav-item-'));

void main() {
  final doc = loadFixture('bottom-zone-screens');

  test('fixture: five screens, schema 9.12.0, three languages', () {
    expect(doc.schemaVersion, '9.12.0');
    expect(doc.screens.map((s) => s.screenId), ['home', 'rewards', 'profile', 'terms', 'confirm']);
    expect(doc.initialScreenId, 'home');
  });

  for (final locale in ['en', 'uk', 'ar']) {
    for (final size in [const Size(320, 568), const Size(393, 852)]) {
      final tag = '$locale, ${size.width.round()}';

      testWidgets('$tag: three sections -- the bar is in place, the active item leads to the shown screen', (tester) async {
        _view(tester, size.width, size.height);
        final shown = <ScreenShown>[];
        await pumpDocument(tester, doc, locale: locale, onScreenShown: shown.add, safeBottom: 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_items, findsNWidgets(3));

        // The bar sits at the bottom of the screen and keeps its 61.
        final bar = tester.getRect(_items.first);
        expect(bar.bottom, closeTo(size.height, 0.01));
        expect(bar.height, closeTo(61, 0.01));
        // Three equal shares across the full width.
        for (var i = 0; i < 3; i += 1) {
          expect(tester.getSize(_items.at(i)).width, closeTo(size.width / 3, 0.01));
        }
        // In Arabic the first item is on the right.
        final first = tester.getCenter(_items.at(0)).dx;
        final last = tester.getCenter(_items.at(2)).dx;
        expect(first > last, locale == 'ar');

        // Tap on the second item -- section "rewards", reason switch, depth 1.
        shown.clear();
        await tester.tap(_items.at(1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(shown.single.screenId, 'rewards');
        expect(shown.single.cause, ScreenShownCause.switchSection);
        expect(shown.single.depth, 1);
        expect(_items, findsNWidgets(3));
        // The pinned button sits ABOVE the bar, not under it.
        final redeem = tester.getRect(find.bySubtype<ButtonStyleButton>().last);
        expect(redeem.bottom, lessThanOrEqualTo(tester.getRect(_items.first).top));

        // A repeated tap on the active one does nothing.
        shown.clear();
        await tester.tap(_items.at(1));
        await tester.pumpAndSettle();
        expect(shown, isEmpty);

        // The third section has no pinned block.
        await tester.tap(_items.at(2));
        await tester.pumpAndSettle();
        expect(shown.single.screenId, 'profile');
        expect(find.bySubtype<ButtonStyleButton>(), findsNothing);
      });

      testWidgets('$tag: rewards scrolled to the end -- the last row is above the pinned button, the bar did not move', (tester) async {
        _view(tester, size.width, size.height);
        await pumpDocument(tester, doc, locale: locale);
        await tester.tap(_items.at(1));
        await tester.pumpAndSettle();
        final barBefore = tester.getRect(_items.first);
        final button = tester.getRect(find.bySubtype<ButtonStyleButton>().last);
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -5000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(_items.first), barBefore);
        expect(tester.getRect(find.bySubtype<ButtonStyleButton>().last), button);

        // The bottom of the body content is above the top of the pinned button (its margin + screen gap).
        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
        // Since 9.13.0 the bottom zone is two layout children (the pinned block and the "bottom").
        final bottomZone = _rectOf(zones.childAfter(zones.childAfter(zones.firstChild!)!)!).expandToInclude(_rectOf(zones.lastChild!));
        final scrollPosition = tester.state<ScrollableState>(find.descendant(of: find.byType(SingleChildScrollView).last, matching: find.byType(Scrollable)).first).position;
        expect(scrollPosition.pixels, closeTo(scrollPosition.maxScrollExtent, 0.01));
        final body = _rectOf(zones.childAfter(zones.firstChild!)!);
        expect(body.bottom, closeTo(bottomZone.top, 0.01), reason: 'the body ends at the top edge of the zone');
        expect(button.top, greaterThan(bottomZone.top - 0.01));
      });

      testWidgets('$tag: "terms" -- a long page, the pinned button switches the section', (tester) async {
        _view(tester, size.width, size.height);
        final shown = <ScreenShown>[];
        await pumpDocument(tester, doc, locale: locale, onScreenShown: shown.add);
        await tester.pumpAndSettle();
        // From home -- a plain `navigate`: the stack grows, back returns.
        final open = find.bySubtype<ButtonStyleButton>().first;
        await tester.dragUntilVisible(open, find.byType(SingleChildScrollView).last, const Offset(0, -120));
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.bySubtype<ButtonStyleButton>().last;
        expect(button, findsOneWidget);
        expect(shown.last.screenId, 'terms');
        expect(shown.last.cause, ScreenShownCause.forward);
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -5000));
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(shown.last.screenId, 'rewards');
        expect(shown.last.cause, ScreenShownCause.switchSection);
        expect(shown.last.depth, 1);
      });

      testWidgets('$tag: sheet "confirm" -- two pinned buttons at the bottom of the layer, no bar', (tester) async {
        _view(tester, size.width, size.height);
        await pumpDocument(tester, doc, locale: locale);
        await tester.tap(_items.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.bySubtype<ButtonStyleButton>().last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The layer draws no bar: the items remain only on the screen beneath it.
        final layerZones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
        final layer = _rectOf(layerZones);
        final buttons = find.descendant(of: find.byType(ScreenZones).last, matching: find.bySubtype<ButtonStyleButton>());
        expect(buttons, findsNWidgets(2));
        expect(layer.bottom, closeTo(size.height, 0.01), reason: 'the sheet is at the bottom');
        final lowest = tester.getRect(buttons.last);
        expect(lowest.bottom, lessThanOrEqualTo(layer.bottom));
        expect(layer.bottom - lowest.bottom, lessThan(40), reason: 'the last button is at the bottom of the layer, only the root margin is below it');
      });
    }
  }
}
