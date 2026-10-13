/// FIXTURE `media-chrome-screens` (schema 9.9.0): a badges screen with an
/// app bar and an action, a "mission complete" window at 320 and 393, a window with long text
/// (scrolling inside), an "About badges" sheet — in English, Ukrainian and
/// Arabic. A test on a real screen checks what the table
/// (`media_chrome_cases_test.dart`) says about individual rules, ALL TOGETHER.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/render/app_bar_layout.dart';
import 'package:hotlayout_flutter/src/render/image_frame.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/fixtures.dart';

void _view(WidgetTester tester, double width, [double height = 793]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

void main() {
  final doc = loadFixture('media-chrome-screens');

  test('fixture: four screens, windows and the sheet are named by screen entry fields', () {
    expect(doc.screens.map((screen) => screen.screenId), ['badges', 'done', 'about', 'rules']);
    expect(doc.screenById('badges')!.statusBarIcons?.wire, 'light');
    expect(doc.screenById('done')!.placement.wire, 'center');
    expect(doc.screenById('rules')!.placement.wire, 'center');
    expect(doc.screenById('about')!.placement.wire, 'bottom');
  });

  // Screen anatomy: the fixture's first screen has a
  // TRANSPARENT app bar over the root gradient. Scrolling moves neither the bar nor the background:
  // the gradient shows through the bar, not the card that scrolls; the card is clipped at the bottom
  // edge of the bar. The first frame at rest is the same as it was.
  for (final locale in ['en', 'uk', 'ar']) {
    testWidgets('badges screen, $locale: bar and gradient stay, only the body scrolls', (tester) async {
      _view(tester, 393, 520);
      await pumpDocument(tester, doc, locale: locale);
      expect(tester.takeException(), isNull);

      final zones = tester.renderObject<RenderBox>(find.byType(ScreenZones).last);
      final bar = (zones as ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>).firstChild!;
      final body = (zones as ContainerRenderObjectMixin<RenderBox, ContainerBoxParentData<RenderBox>>).lastChild!;
      final barBottom = bar.localToGlobal(Offset.zero).dy + bar.size.height;
      expect(body.localToGlobal(Offset.zero).dy, barBottom, reason: 'the body area starts under the bar');
      expect(body.localToGlobal(Offset.zero).dy + body.size.height, 520, reason: '...and runs to the bottom');

      final gradient = find.ancestor(of: find.byType(ScreenZones), matching: find.byType(DecoratedBox)).first;
      final gradientBefore = tester.getRect(gradient);
      final barBefore = bar.localToGlobal(Offset.zero);
      final cardBefore = tester.getTopLeft(find.byType(ImageFrame).first);
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(bar.localToGlobal(Offset.zero), barBefore, reason: 'the bar does not scroll');
      expect(tester.getRect(gradient), gradientBefore, reason: 'the root gradient stays');
      expect(gradientBefore.size, const Size(393, 520));
      final scrolled = tester.state<ScrollableState>(find.descendant(of: find.byType(SingleChildScrollView).first, matching: find.byType(Scrollable)).first).position.pixels;
      expect(scrolled, greaterThan(0), reason: 'content is larger than the 393 × 520 screen');
      expect(tester.getTopLeft(find.byType(ImageFrame).first).dy, closeTo(cardBefore.dy - scrolled, 0.01), reason: 'the body moves exactly by the scroll');
    });
  }

  for (final locale in ['en', 'uk', 'ar']) {
    testWidgets('badges screen, $locale: bar with two actions, circle, 343 : 120 banner', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, doc, locale: locale);
      expect(tester.takeException(), isNull);

      final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
      var count = 0;
      for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
        count += 1;
      }
      expect(count, 4, reason: 'arrow, title and two actions');

      // Avatars 48 / 64 (a circle via `pill`); the banner has a 343 : 120 ratio at the card width.
      final frames = tester.widgetList<ImageFrame>(find.byType(ImageFrame)).length;
      expect(frames, greaterThanOrEqualTo(5), reason: 'without data the badge list is empty; the remaining frames are in place');
      final banner = find.byType(ImageFrame).evaluate().map((e) => (e.renderObject! as RenderBox).size).firstWhere(
        (size) => (size.width / size.height - 343 / 120).abs() < 0.01,
        orElse: () => Size.zero,
      );
      expect(banner, isNot(Size.zero), reason: 'the 343 : 120 banner (own ratio) is found');
      final circle = find.byType(ImageFrame).evaluate().map((e) => (e.renderObject! as RenderBox).size).where(
        (size) => size.width == 64 && size.height == 64,
      );
      expect(circle, isNotEmpty);
    });
  }

  testWidgets('Arabic: arrow on the right, actions on the left, first action closer to the title', (tester) async {
    _view(tester, 393);
    await pumpDocument(tester, doc, locale: 'ar');
    final render = tester.renderObject<RenderAppBarLayout>(find.byType(AppBarLayout));
    final boxes = <Rect>[];
    for (var child = render.firstChild; child != null; child = render.childAfter(child)) {
      final offset = (child.parentData! as ContainerBoxParentData<RenderBox>).offset;
      boxes.add(offset & child.size);
    }
    final back = boxes[0];
    final first = boxes[2];
    final second = boxes[3];
    expect(back.right, closeTo(render.size.width - 0, 0.5), reason: 'the leading zone is on the right');
    expect(second.left, closeTo(0, 0.5), reason: 'the last action is pressed to the left edge');
    expect(first.left, greaterThan(second.left), reason: 'the first action of the document is closer to the title');
  });

  for (final width in [320.0, 393.0]) {
    testWidgets('"mission complete" window at ${width.round()}: width = area − 2 × xl, centred', (tester) async {
      _view(tester, width);
      await pumpDocument(tester, doc);
      await tester.tap(find.text('Complete the mission'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final rect = tester.getRect(find.byKey(kModalLayerKey));
      expect(rect.width, width - 48);
      expect(rect.center.dx, closeTo(width / 2, 0.5));
      expect(rect.center.dy, closeTo(793 / 2, 0.5));
      // The badges screen stays visible under the window (behind the scrim).
      expect(find.text('My badges'), findsOneWidget);
      expect(find.text('Complete the mission'), findsWidgets);

      // The button in the window closes it.
      await tester.tap(find.text('Great'));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsNothing);
    });
  }

  testWidgets('window with long text at 320 × 548: scrolls INSIDE, margins at top and bottom', (tester) async {
    _view(tester, 320, 548);
    await pumpDocument(tester, doc);
    // The button is below the first screen: the page scrolls (the bar moves with it).
    await tester.ensureVisible(find.text('Read the rules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read the rules'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(kModalLayerKey));
    expect(rect.top, 24);
    expect(rect.bottom, 548 - 24);
    final scrollable = find.descendant(of: find.byKey(kModalLayerKey), matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable.first).position.maxScrollExtent, greaterThan(0));
    // The button at the bottom needs scrolling to.
    await tester.dragUntilVisible(find.text('Got it'), scrollable.first, const Offset(0, -80));
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('"About badges" sheet: from the bottom at full width, with a close action in the bar', (tester) async {
    _view(tester, 393);
    await pumpDocument(tester, doc);
    // The bar action "About badges" opens the sheet.
    await tester.tap(find.bySemanticsLabel('About badges').first);
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(kModalLayerKey));
    expect(rect.left, 0);
    expect(rect.right, 393);
    expect(rect.bottom, 793);
    expect(find.text('About badges'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Close').first);
    await tester.pumpAndSettle();
    expect(find.byKey(kModalLayerKey), findsNothing);
  });

  testWidgets('the show event carries the badges request and window placement only when the screen named them', (tester) async {
    _view(tester, 393);
    final shown = <ScreenShown>[];
    await pumpDocument(tester, doc, onScreenShown: shown.add);
    expect(shown.single.statusBarIcons, 'light');
    expect(shown.single.modalPlacement, isNull);
    await tester.tap(find.text('Complete the mission'));
    await tester.pumpAndSettle();
    expect(shown.last.screenId, 'done');
    expect(shown.last.modalPlacement, 'center');
    expect(shown.last.statusBarIcons, isNull);
  });
}
