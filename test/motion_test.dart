import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/motion.dart';

import 'support/fixtures.dart';

/// Renderer MOTION.
///
/// The contract does not cover it: the document does not say HOW a screen appears, and
/// a web reader of the same document is free not to animate anything. What is tested
/// here is not an agreement between platforms but two quality claims:
///  • motion carries MEANING — a modal slides in from the bottom, so it is visible that it was put
///    ON TOP rather than the screen being redrawn;
///  • motion is DISABLED when the system asks for it.
///
/// The second matters more. The "reduce motion" switch is set by people for whom
/// animation is physically bothersome, and an app that ignores it is not
/// "pretty" for them but unusable.
void main() {
  Map<String, Object?> goTo(String screenId) => buttonNode('Відкрити', action: {
    'type': 'navigate',
    'params': {'screenId': screenId},
  });

  UiDocument flow() => docWithScreens(
    [
      screenEntry('home', [textNode('Головний екран', id: 'home-text'), goTo('gift')]),
      screenEntry('gift', [textNode('Подарунок', id: 'gift-text')], presentation: 'modal'),
    ],
    initialScreenId: 'home',
  );

  /// Where the bottom of the sheet is now — measured by the label inside it.
  ///
  /// The sheet moves BOTTOM TO TOP, so while it is on its way this coordinate is larger than
  /// the final one: part of the sheet is still below the bottom edge of the glass. The absolute
  /// value says nothing here (the sheet has screen insets); only COMPARING two moments
  /// means anything — so every claim below is about "more/less", not about
  /// a specific number.
  double sheetBottom(WidgetTester tester) =>
      tester.getRect(find.text('Подарунок')).bottom;

  group('a modal slides in from the bottom', () {
    testWidgets('halfway through, the sheet is lower than at the end', (tester) async {
      // A bottom sheet is a phone shape: on a wide place the sheet becomes a window that fades in
      // (9.18.0, step 2).
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 800);
      addTearDown(tester.view.reset);
      await pumpDocument(tester, flow());
      await tester.tap(find.text('Відкрити'));

      // First frame after the tap: the animation has just started.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midway = sheetBottom(tester);

      await tester.pumpAndSettle();
      final settled = sheetBottom(tester);

      expect(midway, greaterThan(settled), reason: 'the sheet must be approaching its place, not standing still');

      // And it must stop: one more frame moves nothing.
      await tester.pump(const Duration(milliseconds: 100));
      expect(sheetBottom(tester), settled);
    });

    /*
     * The scrim thickens TOGETHER with the sheet. Otherwise the screen under it would darken
     * before it is clear why — and that would read as a painting glitch.
     */
    testWidgets('the scrim gains density gradually', (tester) async {
      await pumpDocument(tester, flow());
      await tester.tap(find.text('Відкрити'));
      await tester.pump();

      double scrimAlpha() {
        final box = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).firstWhere(
          (candidate) => candidate.color.a > 0 && candidate.color.a < 1,
          orElse: () => const ColoredBox(color: Color(0x00000000)),
        );
        return box.color.a;
      }

      await tester.pump(const Duration(milliseconds: 40));
      final early = scrimAlpha();

      await tester.pumpAndSettle();
      final full = scrimAlpha();

      expect(early, lessThan(full));
      expect(full, closeTo(0.45, 0.01));
    });
  });

  group('the system asks for no motion', () {
    testWidgets('the modal is in place from the very first frame', (tester) async {
      await pumpDocument(tester, flow(), disableAnimations: true);
      await tester.tap(find.text('Відкрити'));
      await tester.pump();
      // One extra frame — exactly what the controller needs to
      // read the zero duration and jump to the end.
      await tester.pump();
      final immediate = sheetBottom(tester);

      await tester.pumpAndSettle();

      // Nowhere left to move: the sheet is in place from the first shown frame.
      expect(sheetBottom(tester), immediate);
    });

    test('zero duration is not "do not animate"', () {
      // The animation widgets stay in place and work as usual: no render
      // branch forks, exactly one number changes.
      expect(Motion.quick, isNot(Duration.zero));
      expect(Motion.sheet, greaterThan(Motion.quick));
    });
  });

  group('collapsible block', () {
    testWidgets('content expands rather than appearing', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'acc',
            'type': 'Accordion',
            'props': {
              'title': {'kind': 'literal', 'value': 'Правила'},
              'initiallyExpanded': false,
            },
            'children': [textNode('Довгий текст правил', id: 'body')],
          },
        ]),
      );

      // The block's BOX is measured, not the text: the text height is constant, while the expansion
      // drives the box height — from zero to the content's own height.
      double bodyHeight() => tester.getSize(find.byType(AnimatedSize)).height;

      await tester.tap(find.text('Правила'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final midway = bodyHeight();

      await tester.pumpAndSettle();
      final settled = bodyHeight();

      // Previously the arrow rotated smoothly while everything under it jumped: half of the gesture
      // was animated, half was not, and together they read as a glitch.
      expect(midway, lessThan(settled));
    });
  });
}