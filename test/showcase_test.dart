import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/demo_data.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// CONTRACT 9 SHOWCASE - the renderer's first check on a FULL document with its own
/// theme.
///
/// Before the showcase the renderer saw only small documents built by hand in tests:
/// each checked one property. The showcase is four screens (three pages and a
/// modal) that together carry: the theme's own tokens (`brandText`, `gold`, `ink`,
/// shades with opacity), diagonal gradients, per-corner radius, states on the
/// screen root and a button's own style over a role. The very first run found
/// a crash none of 800 tests had seen (a nested row inside a row with a
/// weight, see `_flexibleRow`).
void main() {
  const id = 'rewards-showcase-screens';
  final doc = loadFixture(id);
  const locales = ['en', 'uk', 'de'];
  const themes = ['light', 'dark'];

  /// A screen drawn directly - including the modal, which nobody sees outside the
  /// flow.
  Future<void> pumpScreen(
    WidgetTester tester,
    ScreenEntry screen, {
    required RenderTheme theme,
    required Map<String, Object?> data,
    String? locale,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: renderScreen(
              screen,
              theme: theme,
              data: data,
              strings: doc.stringsFor(locale),
              locale: doc.shownLocale(locale),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('document', () {
    test('four screens: three pages and one modal', () {
      expect(doc.screens.map((s) => s.screenId), ['home', 'mission', 'redeem', 'mission-done']);
      expect(doc.screens.map((s) => s.presentation), [
        ScreenPresentationToken.page,
        ScreenPresentationToken.page,
        ScreenPresentationToken.page,
        ScreenPresentationToken.modal,
      ]);
      expect(doc.localization!.locales, ['en', 'uk', 'de']);
      expect(doc.isSupportedVersion, isTrue);
    });

    test('its theme is its own: the tokens the core lacks are declared by it', () {
      final contract = fixtureThemeContract(id);
      expect(contract.themeIds, containsAll(themes));
      for (final themeId in themes) {
        final theme = contract.themeById(themeId);
        for (final name in ['brandText', 'gold', 'ink', 'canvas', 'onBrand']) {
          expect(theme.colors.containsKey(name), isTrue, reason: '$themeId.$name');
        }
        for (final name in ['heroAurora', 'missionSunset', 'ctaGlow', 'catalogNight']) {
          expect(theme.gradients.containsKey(name), isTrue, reason: '$themeId.$name');
        }
      }
      // The core stays what it is - the "built-in" theme does not act here.
      expect(contract.themeById('light').brightness, Brightness.light);
      expect(contract.themeById('dark').brightness, Brightness.dark);
    });

    test('every reference to a custom token in the showcase resolves with its theme', () {
      // A token the theme does not declare does not crash - it is "not applied", so the
      // showcase would quietly lose its look. We collect ALL colour and gradient
      // names from the styles and check them against each of the two themes.
      final colors = <String>{};
      final gradients = <String>{};
      void colorOf(Object? ref) {
        if (ref is String) colors.add(ref);
        if (ref is Map && ref['token'] is String) colors.add(ref['token'] as String);
      }

      void style(Object? raw) {
        if (raw is! Map) return;
        colorOf(raw['color']);
        colorOf(raw['border'] is Map ? (raw['border'] as Map)['color'] : null);
        final background = raw['background'];
        if (background is Map && background['kind'] == 'color') colorOf(background['color']);
        if (background is Map && background['kind'] == 'gradient') {
          final gradient = background['gradient'];
          if (gradient is String) gradients.add(gradient);
        }
      }

      // Raw JSON is the only way to see the names: parsed references have already
      // lost whether they were a token.
      void walkRaw(Object? raw) {
        if (raw is Map) {
          if (raw.containsKey('style')) style(raw['style']);
          if (raw.containsKey('styleWhen') && raw['styleWhen'] is List) {
            for (final entry in raw['styleWhen'] as List) {
              if (entry is Map) style(entry['style']);
            }
          }
          raw.values.forEach(walkRaw);
        } else if (raw is List) {
          raw.forEach(walkRaw);
        }
      }

      walkRaw(jsonFixture(id));

      expect(colors, isNotEmpty);
      expect(gradients, isNotEmpty);
      for (final themeId in themes) {
        final theme = fixtureTheme(id, themeId: themeId);
        for (final name in colors) {
          expect(theme.resolveColor(ColorRef.token(name)), isNotNull, reason: '$themeId: colour «$name»');
        }
        for (final name in gradients) {
          expect(theme.resolveGradient(TokenGradientRef(name)), isNotNull, reason: '$themeId: gradient «$name»');
        }
      }
    });
  });

  group('all screens draw without exceptions', () {
    for (final themeId in themes) {
      for (final locale in locales) {
        for (final withData in [true, false]) {
          testWidgets(
            'theme $themeId, locale $locale, ${withData ? 'with sample data' : 'no data'}, LTR',
            (tester) async {
              final theme = fixtureTheme(id, themeId: themeId);
              for (final screen in doc.screens) {
                await pumpScreen(
                  tester,
                  screen,
                  theme: theme,
                  data: withData ? sampleScreenData : const {},
                  locale: locale,
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '${screen.screenId} / $themeId / $locale / ${withData ? 'data' : 'no data'}',
                );
                // The screen is not empty: at least one caption is drawn.
                expect(find.byType(Text), findsWidgets, reason: screen.screenId);
              }
            },
          );
        }
      }
    }

    testWidgets('and right to left too (the showcase has no Arabic, but the direction does not break the layout)', (
      tester,
    ) async {
      final theme = fixtureTheme(id);
      for (final screen in doc.screens) {
        await pumpScreen(
          tester,
          screen,
          theme: theme,
          data: sampleScreenData,
          direction: TextDirection.rtl,
        );
        expect(tester.takeException(), isNull, reason: screen.screenId);
      }
    });

    testWidgets('on a narrow 320 screen too, without overflow', (tester) async {
      final theme = fixtureTheme(id);
      for (final screen in doc.screens) {
        await pumpScreen(tester, screen, theme: theme, data: sampleScreenData, locale: 'de');
        tester.view.physicalSize = const Size(320 * 3, 640 * 3);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: screen.screenId);
      }
    });
  });

  group('what exactly the showcase checks', () {
    testWidgets('the root gradient comes from ITS theme, and the root state changes it', (tester) async {
      final theme = fixtureTheme(id);
      final mission = doc.screenById('mission')!;

      Future<Gradient?> rootGradient(Map<String, Object?> data) async {
        await pumpScreen(tester, mission, theme: theme, data: data);
        expect(tester.takeException(), isNull);
        return screenDecoration(tester).gradient;
      }

      final base = await rootGradient(const {});
      expect(base, theme.resolveGradient(const TokenGradientRef('heroAurora')));
      expect(base, isNotNull);

      expect(
        await rootGradient(const {'task.status': 'completed'}),
        theme.resolveGradient(const TokenGradientRef('missionForest')),
      );
      expect(
        await rootGradient(const {'task.status': 'locked'}),
        theme.resolveGradient(const TokenGradientRef('missionDusk')),
      );
    });

    testWidgets('a locked mission: the button loses gradient and shadow, the background is a theme token', (tester) async {
      final theme = fixtureTheme(id);
      final mission = doc.screenById('mission')!;

      await pumpScreen(tester, mission, theme: theme, data: const {}, locale: 'en');
      final open = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Claim reward'));
      // The button own background is a gradient: the fill is off, `backgroundBuilder` draws.
      expect(open.style!.backgroundBuilder, isNotNull);

      await pumpScreen(tester, mission, theme: theme, data: const {'task.status': 'locked'}, locale: 'en');
      final locked = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Claim reward'));
      expect(locked.style!.backgroundBuilder, isNull, reason: 'the "locked" state turned the gradient off');
      expect(locked.style!.backgroundColor!.resolve({}), theme.color(ColorToken.secondary));
      expect(locked.style!.foregroundColor!.resolve({}), theme.color(ColorToken.muted));
    });

    testWidgets('modal screen: radius on the top corners only', (tester) async {
      final theme = fixtureTheme(id);
      await pumpScreen(tester, doc.screenById('mission-done')!, theme: theme, data: sampleScreenData);

      final clip = tester.widgetList<ClipRRect>(find.byType(ClipRRect)).firstWhere(
        (c) => c.borderRadius is BorderRadiusDirectional,
      );
      final radius = clip.borderRadius as BorderRadiusDirectional;
      expect(radius.topStart, isNot(Radius.zero));
      expect(radius.topEnd, isNot(Radius.zero));
      expect(radius.bottomStart, Radius.zero);
      expect(radius.bottomEnd, Radius.zero);
      // ...and the value comes from the theme (`sheet` is the showcase own radius name).
      expect(radius.topStart, Radius.circular(theme.resolveRadius(const ScaleRef.token('sheet'))!));
    });

    testWidgets('languages really differ: the home screen title is translated', (tester) async {
      final theme = fixtureTheme(id);
      final home = doc.screenById('home')!;
      final shown = <String>{};
      for (final locale in locales) {
        await pumpScreen(tester, home, theme: theme, data: const {}, locale: locale);
        shown.add(
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join('|'),
        );
      }
      expect(shown, hasLength(3), reason: 'en / uk / de draw different texts');
    });
  });

  group('flow: the modal screen opens over the previous one', () {
    for (final locale in locales) {
      testWidgets('locale $locale', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final theme = fixtureTheme(id);
        final screens = <String>[];
        await pumpDocument(
          tester,
          doc,
          theme: theme,
          data: sampleScreenData,
          entry: 'mission',
          locale: locale,
          onScreenChanged: (screen) => screens.add(screen.screenId),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(screens, ['mission']);

        // The button leading to the modal is found by action, not by caption (three languages).
        final claim = flattenDocument(doc)
            .whereType<ButtonNode>()
            .singleWhere((button) => button.action.navigationTarget == 'mission-done');
        final strings = doc.stringsFor(locale);
        final label = claim.label.resolve(ScreenData.scoped(document: sampleScreenData), strings, doc.shownLocale(locale));
        final missionTexts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

        await tester.tap(find.widgetWithText(FilledButton, label));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(screens, ['mission', 'mission-done']);
        // The previous screen STAYED under the modal - that is the meaning of the `modal` mode.
        final nowTexts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
        expect(nowTexts, containsAll(missionTexts.where((t) => t != null && t.isNotEmpty)));
        expect(nowTexts.length, greaterThan(missionTexts.length));
      });
    }
  });
}
