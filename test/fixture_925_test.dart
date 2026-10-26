/// THE FRAME `glow-press-screens` (schema 9.25.0): each screen in three languages on two phone widths, then each scene
/// as its story says.
///
///  * Progress: the steps grow from zero and fill smoothly, the current step glows in `accent`; the solid bar has a
///    soft glow, the ring a strong one; nothing the glow draws takes room;
///  * Cards: three cards shine each in the colour of its own background, the fourth in the colour of the middle stop
///    of its gradient, "Still" does not sink; "Done" sinks to 0.96, "Share" fades, and "Done" asks for a haptic response.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show HotlayoutTransitions;
import 'package:hotlayout_flutter/src/model/press_feedback.dart';
import 'package:hotlayout_flutter/src/model/progress_glow.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/press_feedback.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

const _id = 'glow-press-screens';

UiDocument _startingAt(String screenId) {
  final json = jsonDecode(readFixture(_id)) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

void _view(WidgetTester tester, double width, [double height = 800]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _tracks() => find.byType(ProgressTrack);

void main() {
  final theme = RenderTheme.fallback();

  test('the fixture is in the catalogue, at 9.27.0, in two languages', () {
    final doc = loadFixture(_id);
    expect(doc.schemaVersion, '9.30.0');
    expect(fixtureIds, contains(_id));
    expect(doc.locales, ['en', 'uk']);
  });

  group('every screen is drawn without exceptions', () {
    for (final screen in ['progress', 'cards']) {
      for (final width in [320.0, 393.0]) {
        for (final locale in [null, 'uk', 'ar']) {
          testWidgets('$screen at $width (${locale ?? 'en'})', (tester) async {
            _view(tester, width);
            await pumpDocument(tester, _startingAt(screen), locale: locale, safeTop: 47, safeBottom: 34);
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
            await tester.pumpAndSettle();
          });
        }
      }
    }
  });

  group('Progress', () {
    testWidgets('the steps and the numbers start empty and fill smoothly: one step has a fraction on the way', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('progress'), safeTop: 47, safeBottom: 34);
      final steps = _tracks().first;
      expect(tester.widget<ProgressTrack>(steps).segmentUnits, 0, reason: 'the first frame is empty');
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<ProgressTrack>(steps).segmentUnits, closeTo(3.5, 1e-6), reason: '4 of 6 at e = 0.875');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<ProgressTrack>(steps).segmentUnits, isNull, reason: 'whole steps at rest');
      await tester.pumpAndSettle();
    });

    testWidgets('the strength of every glow, and the current step shines in `accent`', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('progress'), safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      expect([for (final e in _tracks().evaluate()) (e.widget as ProgressTrack).glow], [ProgressGlow.strong, ProgressGlow.soft]);
      final ring = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is RingPainter);
      expect((tester.widget<CustomPaint>(ring).painter! as RingPainter).glow, ProgressGlow.strong);
      // Six steps and one blurred copy of the current one (the fifth, the first not full), in `accent` at 0.9.
      final accent = theme.color(ColorToken.accent);
      expect(tester.renderObject<RenderBox>(_tracks().first), paintsExactlyCountTimes(#drawRRect, 7));
      expect(
        tester.renderObject<RenderBox>(_tracks().first),
        paints..rrect(color: accent.withValues(alpha: accent.a * 0.9), hasMaskFilter: true),
      );
    });

    testWidgets('the glow takes no room: boxes of the scales are the same without the field', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('progress'), safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      final glowing = [for (final e in _tracks().evaluate()) tester.getRect(find.byWidget(e.widget))];
      final json = jsonDecode(readFixture(_id).replaceAll('"glow": "soft"', '"x": 1').replaceAll('"glow": "strong"', '"x": 1')) as Map<String, Object?>;
      await pumpDocument(tester, UiDocument.fromJson(json), safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      final plain = [for (final e in _tracks().evaluate()) tester.getRect(find.byWidget(e.widget))];
      expect(plain, glowing);
    });
  });

  group('Cards', () {
    testWidgets('every card shines in the colour of its own background', (tester) async {
      _view(tester, 393, 1000);
      await pumpDocument(tester, _startingAt('cards'), safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 1));
      // The shadows of the five cards, in the order of the document.
      final shadows = shadowLayersUnder(tester, find.byType(Scaffold))
          .where((layers) => layers.first.blurRadius == 24)
          .map((layers) => layers.single)
          .toList();
      expect(shadows, hasLength(5));
      Color hue(BoxShadow shadow) => shadow.color.withValues(alpha: 1);
      expect(hue(shadows[0]), theme.color(ColorToken.primary));
      expect(hue(shadows[1]), theme.color(ColorToken.accent));
      expect(hue(shadows[2]), theme.color(ColorToken.success));
      expect(hue(shadows[3]), theme.color(ColorToken.accent), reason: 'the stop nearest to the middle of the gradient');
      expect(hue(shadows[4]), theme.color(ColorToken.primary), reason: 'the opacity of the background does not count');
      for (final shadow in shadows) {
        expect(shadow.color.a, closeTo(0.55, 0.005), reason: 'every layer keeps the opacity of its own');
      }
    });

    testWidgets('«Still» does not sink, «Done» sinks to 0.96, «Share» fades, and «Done» asks for a haptic response', (tester) async {
      _view(tester, 393, 1000);
      final haptics = <String>[];
      await pumpDocument(
        tester,
        _startingAt('cards'),
        safeTop: 47,
        safeBottom: 34,
        transitions: HotlayoutTransitions.none,
        onHaptic: (word, nodeId, record) => haptics.add('${word.wire}:$nodeId'),
      );
      await tester.pump(const Duration(seconds: 1));

      double scaleOf(Finder inner) => tester
          .widget<Transform>(find.descendant(of: find.ancestor(of: inner, matching: find.byType(PressFeedback)).first, matching: find.byType(Transform)).first)
          .transform
          .storage[0];

      Future<TestGesture> hold(Finder target) async {
        final gesture = await tester.startGesture(tester.getCenter(target));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        return gesture;
      }

      final still = find.text('Still').first;
      var gesture = await hold(still);
      expect(scaleOf(still), 1);
      await gesture.cancel();
      await tester.pumpAndSettle();

      // The first control that fades is «Share» (the navigation items come after the body).
      final share = find.byWidgetPredicate((w) => w is PressFeedback && w.kind == PressFeedbackKind.fade).first;
      gesture = await hold(share);
      final fade = tester.widget<FadeTransition>(
        find.descendant(of: share, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, closeTo(0.7, 1e-6));
      await gesture.cancel();
      await tester.pumpAndSettle();

      final done = find.text('Done').first;
      gesture = await hold(done);
      expect(scaleOf(done), closeTo(0.96, 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(haptics, ['success:cards-done']);
    });
  });
}
