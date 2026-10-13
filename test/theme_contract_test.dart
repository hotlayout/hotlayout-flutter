import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/fallback_theme.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import 'support/fixtures.dart';
import 'support/network.dart';

/// Guard for the theme contract.
///
/// Before theme contract 1.0.0 the design-system values were hardcoded in
/// `render_theme.dart` and kept in sync with the web copy only by a comment.
/// Drift went unnoticed. Now the values come from the artifact, and this file
/// guards both the loading mechanism and that the embedded fallback does not
/// silently drift from the current artifact.
/*
 * THEME VERSIONS IN SYNTHETIC THEMES ARE DERIVED FROM THE OWN VERSION, not
 * written as numbers.
 *
 * Literals ('3.0.0' as 'our major', '4.0.0' as 'foreign') broke on a major
 * bump not because a rule broke but because 'ours' became foreign and vice
 * versa. The quieter variant is worse: a 'foreign major is rejected' test with
 * a literal that just became ours would start proving the opposite.
 */
final int _major = int.parse(kSupportedThemeContractVersion.split('.').first);
final String ownMajor = '$_major.0.0';
final String newerMinor = '$_major.9.0';
final String nextMajor = '${_major + 1}.0.0';
final String previousMajor = '${_major - 1}.0.0';

void main() {
  final artifact = jsonDecode(readThemeContract()) as Map<String, Object?>;
  final artifactContract = artifact['contract'] as Map<String, Object?>;
  final artifactPolicy =
      (artifact['x-compatibility'] as Map<String, Object?>)['policy'] as Map<String, Object?>;

  /// List of gradient angles taken straight from the artifact `x-schema`.
  ///
  /// Read from the file instead of hardcoded numbers: this list is what
  /// `gradientAngleSpace: 'axis-aligned-only'` promises, so tests compare against it.
  final artifactAngleEnum =
      ((((((artifact['x-schema'] as Map<String, Object?>)[r'$defs']
                              as Map<String, Object?>)['ThemeGradient']
                          as Map<String, Object?>)['properties']
                      as Map<String, Object?>)['angle']
                  as Map<String, Object?>)['enum']!
              as List<Object?>)
          .cast<num>();

  group('theme artifact is loaded', () {
    test('theme comes from a file, not from hardcoded constants', () {
      final load = ThemeLoad.parse(readThemeContract());

      expect(load.status, ThemeLoadStatus.ok, reason: load.detail);
      expect(load.isFallback, isFalse);
      expect(load.contract.version, artifactContract['themeContractVersion']);
      expect(load.contract.defaultThemeId, artifactContract['defaultThemeId']);
      expect(load.contract.themeIds, contains('light'));
    });

    test('theme metadata arrives intact', () {
      final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;

      expect(theme.id, 'light');
      expect(theme.name, 'Default');
      // The theme source is our own and temporary: there is no dedicated design
      // yet, and the theme says so itself rather than via a code comment.
      expect(theme.source, contains('starter palette'));
      expect(theme.brightness, Brightness.light);
      expect(theme.bodyFont?.primary, 'Inter');
      expect(theme.headingFont?.primary, 'Inter');
    });

    test('`provisional` is data, not a CSS comment', () {
      // Before the theme contract, the fact that a colour was picked by us lived
      // in a comment in `product-theme.css`, unknown to Dart.
      final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;

      expect(theme.provisional, contains('color.warning'));
      expect(theme.provisional, contains('color.danger'));
      // 1.0.0 also marks font families as provisional, the most provisional of
      // all: commercial fonts are not bundled into the app.
      expect(theme.isProvisional('fontFamilies.body'), isTrue);
      expect(theme.isProvisional('fontFamilies.heading'), isTrue);
      expect(theme.isProvisional('elevation.low'), isTrue);
      /*
       * The list must stay a LIST, not 'everything provisional': otherwise the
       * marker stops distinguishing picked values from design-issued ones.
       * Currently every colour and text style in our theme is provisional (no
       * dedicated design yet), while spacing and radius scales are not: they are
       * numbers agreed with the builder, not taste.
       */
      expect(theme.isProvisional('spacing.md'), isFalse);
      expect(theme.isProvisional('radius.lg'), isFalse);
    });

    test('`origins` arrive - names of design-system variables', () {
      /*
       * The mechanism is checked on OUR theme, not the artifact: `origins` is
       * intentionally EMPTY there since no dedicated design system exists to name
       * an origin.
       *
       * The assertion below keeps that boundary explicit: once our design appears,
       * `origins` fills up and this line fails, reminding us to verify provenance
       * rather than just repaint colours.
       */
      final theme = RenderTheme.fromJson({
        ..._theme('with-origins'),
        'origins': {'color.primary': 'brand/strong', 'typography.bodyM': 'text/14/regular'},
      });

      expect(theme.origins['color.primary'], 'brand/strong');
      expect(theme.origins['typography.bodyM'], 'text/14/regular');
      // Not every value has a design-system counterpart: the mapping is partial.
      expect(theme.origins.containsKey('spacing.md'), isFalse);

      expect(
        ThemeLoad.parse(readThemeContract()).contract.defaultTheme.origins,
        isEmpty,
        reason: 'no dedicated design yet: nothing to name as the origin of values',
      );
    });

    test('every token the renderer can draw is covered by the theme', () {
      // Otherwise half the screen would silently fall back to resolver defaults.
      final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;

      for (final token in ColorToken.values) {
        expect(theme.colors.containsKey(token.wire), isTrue, reason: 'color.${token.wire}');
      }
      for (final token in SpacingToken.values) {
        expect(theme.spacing.containsKey(token.wire), isTrue, reason: 'spacing.${token.wire}');
      }
      for (final token in RadiusToken.values) {
        expect(theme.radii.containsKey(token.wire), isTrue, reason: 'radius.${token.wire}');
      }
      for (final token in TypographyToken.values) {
        expect(theme.typography.containsKey(token.wire), isTrue, reason: 'typography.${token.wire}');
      }
      for (final token in ElevationToken.values) {
        expect(theme.elevations.containsKey(token.wire), isTrue, reason: 'elevation.${token.wire}');
      }
      for (final token in GradientToken.values) {
        expect(theme.gradients.containsKey(token.wire), isTrue, reason: 'gradient.${token.wire}');
      }
    });
  });

  group('artifact values = values that used to be hardcoded', () {
    // The most valuable part of the migration: any mismatch here is exactly the
    // bug the epic exists to prevent. The values below are the ones that used to
    // be constants in `render_theme.dart`.
    final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;

    test('colors', () {
      expect(theme.color(ColorToken.primary), const Color(0xFF4F46E5));
      expect(theme.color(ColorToken.onPrimary), const Color(0xFFFFFFFF));
      expect(theme.color(ColorToken.secondary), const Color(0xFFEEF0F6));
      expect(theme.color(ColorToken.accent), const Color(0xFF0369A1));
      expect(theme.color(ColorToken.surface), const Color(0xFFFFFFFF));
      expect(theme.color(ColorToken.onSurface), const Color(0xFF111827));
      expect(theme.color(ColorToken.muted), const Color(0xFF6B7280));
      expect(theme.color(ColorToken.success), const Color(0xFF15803D));
      expect(theme.color(ColorToken.warning), const Color(0xFFB45309));
      expect(theme.color(ColorToken.danger), const Color(0xFFDC2626));
    });

    test('spacing and radii', () {
      expect(theme.space(SpacingToken.none), 0);
      expect(theme.space(SpacingToken.xs), 4);
      expect(theme.space(SpacingToken.sm), 8);
      expect(theme.space(SpacingToken.md), 12);
      expect(theme.space(SpacingToken.lg), 16);
      expect(theme.space(SpacingToken.xl), 24);

      expect(theme.radius(RadiusToken.none), 0);
      expect(theme.radius(RadiusToken.sm), 8);
      expect(theme.radius(RadiusToken.md), 12);
      expect(theme.radius(RadiusToken.lg), 20);
      expect(theme.radius(RadiusToken.pill), 72);
    });

    test('typography: size, weight, line-height multiplier', () {
      expect(theme.text(TypographyToken.displayL).fontSize, 24);
      expect(theme.text(TypographyToken.displayL).fontWeight, FontWeight.w700);
      expect(theme.text(TypographyToken.displayL).height, closeTo(1.1667, 1e-9));

      expect(theme.text(TypographyToken.bodyM).fontSize, 14);
      expect(theme.text(TypographyToken.bodyM).fontWeight, FontWeight.w400);
      expect(theme.text(TypographyToken.bodyM).height, closeTo(1.4286, 1e-9));

      expect(theme.text(TypographyToken.caption).fontSize, 10);
      expect(theme.text(TypographyToken.caption).fontWeight, FontWeight.w500);
      expect(theme.text(TypographyToken.numericL).fontSize, 20);
      expect(theme.text(TypographyToken.numericL).fontWeight, FontWeight.w600);
    });

    test('`role` picks the font family: heading takes the heading family, the rest the text family', () {
      /*
       * THE THEME IS CUSTOM HERE, ON PURPOSE. In our theme both families are Inter,
       * so any role would give the same name and the mistake 'heading takes the
       * text family' would pass silently. So the role is checked on a theme with
       * DIFFERENT families, with `role` taken from the same artifact (`titleS` is
       * body).
       */
      final twoFamilies = RenderTheme.fromJson({
        ..._theme('two-families'),
        'fontFamilies': {
          'body': {'primary': 'Body Face', 'fallback': <String>[]},
          'heading': {'primary': 'Heading Face', 'fallback': <String>[]},
        },
        'typography': {
          'displayL': {'fontSize': 24, 'lineHeight': 1.1667, 'fontWeight': 700, 'role': 'heading'},
          'titleM': {'fontSize': 18, 'lineHeight': 1.3333, 'fontWeight': 600, 'role': 'heading'},
          'titleS': {'fontSize': 16, 'lineHeight': 1.5, 'fontWeight': 500, 'role': 'body'},
          'bodyM': {'fontSize': 14, 'lineHeight': 1.4286, 'fontWeight': 400, 'role': 'body'},
        },
      });

      expect(twoFamilies.text(TypographyToken.displayL).fontFamily, 'Heading Face');
      expect(twoFamilies.text(TypographyToken.titleM).fontFamily, 'Heading Face');
      // `titleS` is a heading by name but body by role in the contract.
      expect(twoFamilies.text(TypographyToken.titleS).fontFamily, 'Body Face');
      expect(twoFamilies.text(TypographyToken.bodyM).fontFamily, 'Body Face');

      // Our theme still reads the role from the artifact; both family names are
      // simply identical in it.
      expect(theme.text(TypographyToken.displayL).fontFamily, 'Inter');
      expect(theme.text(TypographyToken.bodyM).fontFamily, 'Inter');
    });

    test('tabular figures for numericL - platform overlay on top of the contract', () {
      // `role` in the contract only knows body/heading, so the numeric scale
      // cannot be derived from it. The rule stays on the Dart side, explicitly and
      // in one place.
      expect(
        theme.text(TypographyToken.numericL).fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(theme.text(TypographyToken.bodyM).fontFeatures, isNull);
    });

    test('shadows: contract colour + opacity = one alpha channel in Flutter', () {
      expect(theme.elevation(ElevationToken.low), [
        const BoxShadow(color: Color(0x1F111827), blurRadius: 2, offset: Offset(0, 1)),
      ]);
      expect(theme.elevation(ElevationToken.medium), [
        const BoxShadow(color: Color(0x2E111827), blurRadius: 20, offset: Offset(0, 8)),
      ]);
    });

    test('`elevation: []` means "no shadow", not "value missing"', () {
      // The difference matters: the first is a design decision, the second a hole in the theme.
      expect(theme.elevations.containsKey(ElevationToken.none.wire), isTrue);
      expect(theme.elevation(ElevationToken.none), isEmpty);
    });
  });

  group('gradients (3.0.0): theme values, angle translated to the Flutter coordinate system', () {
    final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;

    test('stops and colours arrive one to one', () {
      final gradient = theme.gradient(GradientToken.brandBackdrop)!;

      expect(gradient.colors, [const Color(0xFFEEF2FF), const Color(0xFFF0F9FF)]);
      expect(gradient.stops, [0.0, 1.0]);
    });

    test('contract 90 degrees = left to right in Flutter', () {
      // The contract angle is 'CSS-like': 0 degrees bottom to top, 90 degrees left
      // to right. Flutter has no direction as such, only a pair of `Alignment`s, so
      // this translation is the one place where the convention lives.
      final gradient = theme.gradient(GradientToken.brandBackdrop)!;

      expect(gradient.begin, isA<Alignment>());
      expect((gradient.begin as Alignment).x, closeTo(-1, 1e-9));
      expect((gradient.begin as Alignment).y, closeTo(0, 1e-9));
      expect((gradient.end as Alignment).x, closeTo(1, 1e-9));
      expect((gradient.end as Alignment).y, closeTo(0, 1e-9));
    });

    test('the remaining axis-aligned angles translate like 90 degrees', () {
      ({double x, double y}) beginOf(num angle) {
        final gradient = _gradientTheme(angle).gradient(GradientToken.brandBackdrop)!;
        final begin = gradient.begin as Alignment;
        return (x: begin.x, y: begin.y);
      }

      // 0 degrees: bottom to top, i.e. starts at the bottom.
      expect(beginOf(0).y, closeTo(1, 1e-9));
      // 180 degrees: top to bottom.
      expect(beginOf(180).y, closeTo(-1, 1e-9));
      // 270 degrees: right to left.
      expect(beginOf(270).x, closeTo(1, 1e-9));
    });

    test('gradient fills the box edge to edge', () {
      // Were the direction a unit vector in normalised coordinates, the fill would
      // end before the edge and leave a visible seam. An axis-aligned angle must
      // give exactly +-1.
      for (final angle in [0, 90, 180, 270]) {
        final gradient = _gradientTheme(angle).gradient(GradientToken.brandBackdrop)!;
        final begin = gradient.begin as Alignment;
        final end = gradient.end as Alignment;

        expect(math.max(begin.x.abs(), begin.y.abs()), 1, reason: '$angle°');
        // The end is the exact opposite of the start, otherwise the gradient would be shifted.
        expect(end.x, -begin.x, reason: '$angle°');
        expect(end.y, -begin.y, reason: '$angle°');
      }
    });

    test('token missing from the theme -> no gradient, not a default one', () {
      // `fromJsonRaw`: the question here is what THIS theme says. Through
      // `fromJson` a missing core gradient would be filled from the built-in theme
      // (`partialThemeDefaults`), and 'no gradient' would stop being an answer to
      // parsing.
      // Token missing from the theme means no gradient. A theme without gradients
      // remains usable.
      final without = RenderTheme.fromJsonRaw({'id': 'x', 'roles': _roles()});

      expect(without.gradients, isEmpty);
      expect(without.gradient(GradientToken.brandBackdrop), isNull);
      expect(without.hasRoles, isTrue);

      // ...whereas the reader (`fromJson`) fills a core token the theme did not
      // name from the built-in theme of the same brightness
      // (`partialThemeDefaults`). This does not contradict 'no gradient': the honest
      // 'none' remains for a token absent from the built-in theme too, i.e. a project-own name.
      final filled = RenderTheme.fromJson({'id': 'x', 'roles': _roles()});
      expect(filled.gradient(GradientToken.brandBackdrop), isNotNull);
      expect(filled.resolveGradient(const TokenGradientRef('sunset')), isNull);
    });

    test('a gradient with its OWN name is read on a par with the core (4.0.0)', () {
      // The vocabulary is open: `sunset` was declared by the theme, so a document
      // may reference it.
      final theme = RenderTheme.fromJson({
        'id': 'x',
        'roles': _roles(),
        'gradient': {
          'sunset': {
            'angle': 0,
            'stops': [
              {'color': '#000000', 'position': 0},
              {'color': '#ffffff', 'position': 1},
            ],
          },
          'brandBackdrop': {
            'angle': 90,
            'stops': [
              {'color': '#010203', 'position': 0},
              {'color': '#040506', 'position': 1},
            ],
          },
        },
      });

      expect(theme.gradients.keys, unorderedEquals(['sunset', 'brandBackdrop']));
      expect(theme.gradient(GradientToken.brandBackdrop)!.colors.first, const Color(0xFF010203));
      expect(
        theme.resolveGradient(const TokenGradientRef('sunset'))!.colors,
        [const Color(0xFF000000), const Color(0xFFFFFFFF)],
      );
    });

    test('non-increasing stops give an ABSENT gradient, not a broken one', () {
      // `fromJsonRaw`: this is about parsing ONE entry, not about filling the core.
      // The contract promises increasing stops, but JSON Schema cannot express that,
      // so ajv on the builder side does not stop it. Skia draws unordered stops
      // unpredictably; a silently wrong gradient is worse than an absent one because
      // nobody notices.
      final theme = RenderTheme.fromJsonRaw({
        'id': 'x',
        'roles': _roles(),
        'gradient': {
          'brandBackdrop': {
            'angle': 90,
            'stops': [
              {'color': '#010203', 'position': 0.9},
              {'color': '#040506', 'position': 0.1},
            ],
          },
        },
      });

      expect(theme.gradient(GradientToken.brandBackdrop), isNull);
    });

    test('fewer than two usable stops - also no gradient', () {
      // `fromJsonRaw`: this is about parsing ONE entry, not about filling the core.
      Map<String, Object?> withStops(List<Object?> stops) => {
        'id': 'x',
        'roles': _roles(),
        'gradient': {
          'brandBackdrop': {'angle': 90, 'stops': stops},
        },
      };

      expect(
        RenderTheme.fromJsonRaw(withStops([
          {'color': '#010203', 'position': 0},
        ])).gradients,
        isEmpty,
      );
      // One stop is intact, the second has no colour: one remains.
      expect(
        RenderTheme.fromJsonRaw(withStops([
          {'color': '#010203', 'position': 0},
          {'position': 1},
        ])).gradients,
        isEmpty,
      );
      expect(RenderTheme.fromJsonRaw(withStops(const [])).gradients, isEmpty);
    });

    test('gradient without an angle is not a gradient', () {
      // `fromJsonRaw`: this is about parsing ONE entry, not about filling the core.
      final theme = RenderTheme.fromJsonRaw({
        'id': 'x',
        'roles': _roles(),
        'gradient': {
          'brandBackdrop': {
            'stops': [
              {'color': '#010203', 'position': 0},
              {'color': '#040506', 'position': 1},
            ],
          },
        },
      });

      expect(theme.gradients, isEmpty);
    });
  });

  group('roles: the "semantics -> palette" map comes from the theme', () {
    final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;

    test('roles are read from the artifact, as token names, not hex', () {
      // Were the values colours, we would reintroduce the 'two parallel colour
      // dictionaries' problem one level up: a rebrand would also have to edit the roles.
      final artifactRoles =
          ((artifactContract['themes'] as Map)['light'] as Map)['roles'] as Map<String, Object?>;
      expect((artifactRoles['badgeTone'] as Map).keys, contains('warning'));
      expect(((artifactRoles['badgeTone'] as Map)['warning'] as Map)['background'], 'warning');

      expect(
        theme.badgeToneRoles[BadgeToneToken.warning],
        const ThemeRole(background: 'warning', foreground: 'onPrimary'),
      );
      expect(
        theme.buttonVariantRoles[ButtonVariantToken.secondary],
        const ThemeRole(background: 'surface', foreground: 'primary', border: 'primary'),
      );
    });

    test('every tone and variant the renderer can draw is covered by the theme', () {
      // Otherwise part of the semantics would fall back to the resolver neutral default.
      for (final tone in BadgeToneToken.values) {
        expect(theme.badgeToneRoles.containsKey(tone), isTrue, reason: 'badgeTone.${tone.wire}');
      }
      for (final variant in ButtonVariantToken.values) {
        expect(
          theme.buttonVariantRoles.containsKey(variant),
          isTrue,
          reason: 'buttonVariant.${variant.wire}',
        );
      }
    });

    test('badge tones: theme values = values hardcoded in the `switch` before 2.0.0', () {
      // The most valuable assertion of the move: if the theme map diverged from the
      // one that was in code, badges would silently change colour.
      void expectTone(BadgeToneToken tone, ColorToken background, ColorToken foreground) {
        final role = theme.badgeTone(tone);
        expect(role.background, theme.color(background), reason: tone.wire);
        expect(role.foreground, theme.color(foreground), reason: tone.wire);
        expect(role.border, isNull, reason: tone.wire);
      }

      expectTone(BadgeToneToken.neutral, ColorToken.secondary, ColorToken.onSurface);
      expectTone(BadgeToneToken.success, ColorToken.success, ColorToken.onPrimary);
      expectTone(BadgeToneToken.warning, ColorToken.warning, ColorToken.onPrimary);
      expectTone(BadgeToneToken.danger, ColorToken.danger, ColorToken.onPrimary);
      expectTone(BadgeToneToken.accent, ColorToken.accent, ColorToken.onPrimary);

      // The same values as absolute colours, so the test does not reduce to the
      // tautology 'theme equals theme'.
      expect(theme.badgeTone(BadgeToneToken.warning).background, const Color(0xFFB45309));
      expect(theme.badgeTone(BadgeToneToken.warning).foreground, const Color(0xFFFFFFFF));
      expect(theme.badgeTone(BadgeToneToken.neutral).background, const Color(0xFFEEF0F6));
      expect(theme.badgeTone(BadgeToneToken.neutral).foreground, const Color(0xFF111827));
    });

    test('button variants: the same value check', () {
      final primary = theme.buttonVariant(ButtonVariantToken.primary);
      expect(primary.background, theme.color(ColorToken.primary));
      expect(primary.foreground, theme.color(ColorToken.onPrimary));
      expect(primary.border, isNull, reason: 'primary never had a border');

      final secondary = theme.buttonVariant(ButtonVariantToken.secondary);
      expect(secondary.foreground, theme.color(ColorToken.primary));
      expect(secondary.border, theme.color(ColorToken.primary));
      // A DIVERGENCE found by the move: in the builder CSS `secondary` always had
      // `background: surface`, while `OutlinedButton` here had no fill at all.
      // Invisible on a white screen, visible on a coloured container. Both
      // platforms now take the values from the contract.
      expect(secondary.background, theme.color(ColorToken.surface));

      final ghost = theme.buttonVariant(ButtonVariantToken.ghost);
      expect(ghost.foreground, theme.color(ColorToken.primary));
      expect(ghost.background, isNull);
      expect(ghost.border, isNull);
    });

    testWidgets('optionality reaches the widget: ghost has no fill, secondary has a border', (
      tester,
    ) async {
      // The point is that `null` did not collapse into 'transparent colour'. In CSS
      // the difference is flattened (`background: transparent`), in Flutter it is
      // real: `TextButton` has no background nor a pressed-state background.
      await pumpDocument(
        tester,
        docWith([
          buttonNode('Головна', id: 'b1', variant: 'primary', action: const {'type': 'none'}),
          buttonNode('Друга', id: 'b2', variant: 'secondary', action: const {'type': 'none'}),
          buttonNode('Привид', id: 'b3', variant: 'ghost', action: const {'type': 'none'}),
        ]),
        theme: theme,
      );

      final filled = tester.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(filled.backgroundColor?.resolve(const {}), theme.color(ColorToken.primary));
      expect(filled.side?.resolve(const {}), isNull, reason: 'primary has no border');

      final outlined = tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!;
      expect(outlined.side?.resolve(const {})?.color, theme.color(ColorToken.primary));
      expect(outlined.backgroundColor?.resolve(const {}), theme.color(ColorToken.surface));

      final text = tester.widget<TextButton>(find.byType(TextButton)).style!;
      expect(text.foregroundColor?.resolve(const {}), theme.color(ColorToken.primary));
      // Specifically `isNull`, not 'equals transparent': there is no fill at all.
      expect(text.backgroundColor, isNull);
      expect(text.side, isNull);
    });

    testWidgets('synthetic theme with different roles paints different colours', (tester) async {
      // Proof of the mechanism: the document is unchanged byte for byte, so is the
      // palette, and the hex values in the theme are the same. ONLY the role map changed.
      final synthetic = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'інші-ролі',
          'themes': {
            'інші-ролі': _theme(
              'інші-ролі',
              roles: _roles(
                // success badge turns red with white text...
                badgeSuccess: const {'background': 'danger', 'foreground': 'surface'},
                // ...primary button loses its fill...
                buttonPrimary: const {'foreground': 'onSurface'},
                // ...and ghost, conversely, gets one.
                buttonGhost: const {'background': 'accent', 'foreground': 'onPrimary'},
              ),
            ),
          },
        },
      }).contract.defaultTheme;

      final doc = docWith([
        badgeNode('Готово', tone: 'success'),
        buttonNode('Головна', id: 'b1', variant: 'primary', action: const {'type': 'none'}),
        buttonNode('Привид', id: 'b2', variant: 'ghost', action: const {'type': 'none'}),
      ]);

      // First, the same document on the artifact theme.
      await pumpDocument(tester, doc, theme: theme);
      expect(_badgeBackground(tester, 'Готово'), theme.color(ColorToken.success));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);

      // ...and on the synthetic one.
      await pumpDocument(tester, doc, theme: synthetic);
      expect(_badgeBackground(tester, 'Готово'), const Color(0xFFDC2626));
      expect(_labelColor(tester, 'Готово'), const Color(0xFFFFFFFF));
      // primary now has no background -> `TextButton`; ghost with a background -> `FilledButton`.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).style!.backgroundColor?.resolve(
          const {},
        ),
        const Color(0xFF0369A1),
      );
      expect(tester.widget<TextButton>(find.byType(TextButton)).style!.backgroundColor, isNull);
    });

    testWidgets('a role with a border draws the border on a badge too', (tester) async {
      // Slots are the same for all roles, so a badge with a border is a legal
      // theme. The renderer has no right to silently drop what the theme says.
      final outlinedBadge = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'обведений',
          'themes': {
            'обведений': _theme(
              'обведений',
              roles: _roles(badgeSuccess: const {'foreground': 'success', 'border': 'success'}),
            ),
          },
        },
      }).contract.defaultTheme;

      await pumpDocument(
        tester,
        docWith([badgeNode('Готово', tone: 'success')]),
        theme: outlinedBadge,
      );

      final decoration = _badgeDecoration(tester, 'Готово');
      expect(decoration.color, isNull, reason: 'no background, and that is not a transparent colour');
      // The border is named by the `success` role, so the colour is that exact token.
      expect(decoration.border?.top.color, const Color(0xFF15803D));
    });

    test('theme without `roles` is USABLE: a missing role is drawn neutrally', () {
      // A theme without `roles` used to be unusable (the hand-written default map
      // was removed in 2.0.0) and the reader returned the embedded fallback. But the
      // neutral look is not an invented map: `x-style.roles.neutral` describes it
      // literally (no background or border, text in the root colour), and the
      // builder `roleSurfaceOf` does not fail on such a theme. The schema requires
      // `roles`, but a reader of a newer minor or a hand-made theme is not
      // validated by the schema.
      final noRoles = _theme('без-ролей')..remove('roles');
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'без-ролей',
          'themes': {'без-ролей': noRoles},
        },
      });

      expect(load.status, ThemeLoadStatus.ok);
      final theme = load.contract.defaultTheme;
      expect(theme.id, 'без-ролей');
      expect(theme.hasRoles, isFalse);
      for (final tone in BadgeToneToken.values) {
        final role = theme.badgeTone(tone);
        expect(role.background, isNull, reason: tone.wire);
        expect(role.border, isNull, reason: tone.wire);
        expect(role.foreground, theme.color(ColorToken.onSurface), reason: tone.wire);
      }
      for (final variant in ButtonVariantToken.values) {
        final role = theme.buttonVariant(variant);
        expect(role.background, isNull, reason: variant.wire);
        expect(role.border, isNull, reason: variant.wire);
        expect(role.foreground, theme.color(ColorToken.onSurface), reason: variant.wire);
      }
    });

    test('half the roles: other groups and roles are neutral, theme is usable', () {
      final halfRoles = _theme('половина')
        ..['roles'] = {
          'badgeTone': (_roles()['badgeTone'] as Map<String, Object?>),
        };

      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'половина',
          'themes': {'половина': halfRoles},
        },
      });
      expect(load.status, ThemeLoadStatus.ok);
      final theme = load.contract.defaultTheme;
      // A group that is absent is neutral...
      expect(theme.buttonVariant(ButtonVariantToken.primary).background, isNull);
      // ...while a present one is read.
      expect(theme.badgeTone(BadgeToneToken.success).foreground, isNot(theme.color(ColorToken.onSurface)));
    });

    test('a malformed role (not an object, no foreground) is neutral, not a crash', () {
      final broken = _theme('зіпсована')
        ..['roles'] = {
          'badgeTone': {'success': 'зелений', 'warning': {'background': 'accent'}, 'neutral': 42},
          'buttonVariant': 'primary',
        };
      final theme = RenderTheme.fromJson(broken);
      expect(theme.badgeTone(BadgeToneToken.success).background, isNull);
      expect(theme.badgeTone(BadgeToneToken.warning).background, isNull);
      expect(theme.badgeTone(BadgeToneToken.neutral).foreground, theme.color(ColorToken.onSurface));
      expect(theme.buttonVariant(ButtonVariantToken.primary).background, isNull);
    });

    test('a single missing role -> neutral look, not an invented colour', () {
      // A real case: the widget dictionary and the theme contract are versioned
      // independently, so a new badge tone may arrive with the schema before its
      // role arrives with the theme. With `missingRole: 'render-neutral'` this is a
      // policy row rather than our own decision (its test is in the mirror group).
      final withoutWarning = _roles();
      (withoutWarning['badgeTone'] as Map<String, Object?>).remove('warning');
      final partial = RenderTheme.fromJson({
        'id': 'x',
        'color': {'onSurface': '#010203'},
        'roles': withoutWarning,
      });

      expect(partial.hasRoles, isTrue);
      final role = partial.badgeTone(BadgeToneToken.warning);
      expect(role.background, isNull);
      expect(role.border, isNull);
      expect(role.foreground, const Color(0xFF010203));
    });

    test('role references a colour the theme does not declare -> neutral for THAT slot only', () {
      // `unknownRoleColor: 'render-neutral'` (4.0.0). Since roles may reference any
      // theme colour, a reference can turn out dangling. The slot with the dangling
      // reference goes neutral, not the whole role: background and border read as
      // absent, foreground as the root colour. The two healthy slots are not
      // discarded because of one broken one.
      final theme = RenderTheme.fromJson({
        'id': 'x',
        'color': {
          'onSurface': '#010203',
          'muted': '#0a0b0c',
          'brandCoral': '#ff7a59',
          'border': '#cccccc',
        },
        'roles': {
          'badgeTone': {
            // Dangling BACKGROUND: the slot is empty, the role foreground (`muted`) and border stay.
            'neutral': {'background': 'brandAlt', 'foreground': 'muted', 'border': 'border'},
            // An own name the theme DECLARES is a legal role reference.
            'accent': {'background': 'brandCoral', 'foreground': 'onSurface'},
            // Dangling FOREGROUND: root colour; the role background stays.
            'success': {'background': 'brandCoral', 'foreground': 'brandInk'},
            // Dangling BORDER: no border, the rest stays.
            'danger': {'background': 'brandCoral', 'foreground': 'muted', 'border': 'brandLine'},
          },
          'buttonVariant': {
            'primary': {'background': 'primary'},
          },
        },
      });

      final neutral = theme.badgeTone(BadgeToneToken.neutral);
      expect(neutral.background, isNull);
      expect(neutral.foreground, const Color(0xFF0A0B0C));
      expect(neutral.border, const Color(0xFFCCCCCC));

      expect(theme.badgeTone(BadgeToneToken.accent).background, const Color(0xFFFF7A59));

      final success = theme.badgeTone(BadgeToneToken.success);
      expect(success.background, const Color(0xFFFF7A59));
      expect(success.foreground, const Color(0xFF010203), reason: 'root colour, onSurface');

      final danger = theme.badgeTone(BadgeToneToken.danger);
      expect(danger.border, isNull);
      expect(danger.background, const Color(0xFFFF7A59));
      expect(danger.foreground, const Color(0xFF0A0B0C));

      // A role without `foreground` is unusable: nothing to draw the text with.
      expect(theme.buttonVariantRoles.containsKey(ButtonVariantToken.primary), isFalse);
    });
  });

  group('fallback: a theme that failed to load does not crash the app', () {
    test('embedded snapshot = the artifact `contract` block, one to one', () {
      // This assertion replaced the comment 'source of values: product-theme.css'.
      expect(kFallbackThemeContractJson, equals(artifactContract));
    });

    test('fallback goes through the same parser as the artifact', () {
      final fromArtifact = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;
      final fromFallback = RenderTheme.fallback();

      expect(fromFallback.id, fromArtifact.id);
      expect(fromFallback.colors, fromArtifact.colors);
      expect(fromFallback.spacing, fromArtifact.spacing);
      expect(fromFallback.radii, fromArtifact.radii);
      expect(fromFallback.typography, fromArtifact.typography);
      expect(fromFallback.elevations, fromArtifact.elevations);
      expect(fromFallback.gradients, fromArtifact.gradients);
      expect(fromFallback.provisional, fromArtifact.provisional);
      expect(fromFallback.origins, fromArtifact.origins);
      expect(fromFallback.bodyFont, fromArtifact.bodyFont);
      expect(fromFallback.headingFont, fromArtifact.headingFont);
    });

    test('broken data gives the fallback, not an exception', () {
      for (final broken in ['', '{', 'не json зовсім', '[]', '42', '"рядок"']) {
        final load = ThemeLoad.parse(broken);
        expect(load.isFallback, isTrue, reason: broken);
        expect(load.contract.themes, isNotEmpty, reason: broken);
      }
    });

    test('structurally empty contract is also the fallback', () {
      // No version at all means a broken artifact, not a foreign major.
      expect(ThemeLoad.fromJson({}).status, ThemeLoadStatus.malformed);
      expect(
        ThemeLoad.fromJson({
          'contract': {
            'themes': {'a': _theme('a')},
          },
        }).status,
        ThemeLoadStatus.malformed,
      );
      expect(
        ThemeLoad.fromJson({
          'contract': {'themeContractVersion': ownMajor, 'themes': <String, Object?>{}},
        }).status,
        ThemeLoadStatus.malformed,
      );
      expect(
        ThemeLoad.fromJson({
          'contract': {'themeContractVersion': ownMajor, 'themes': 'не мапа'},
        }).status,
        ThemeLoadStatus.malformed,
      );
    });

    test('fallback is not silent: the reason travels with the theme', () {
      final load = ThemeLoad.parse('{');

      expect(load.status, ThemeLoadStatus.malformed);
      expect(load.detail, isNotNull);
      // The host receives the fact of substitution AS DATA and may decide
      // otherwise than 'draw as is'.
      expect(load.status.isFallback, isTrue);
    });

    test('one broken theme out of two does not take the rest down', () {
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'good',
          'themes': {'good': _theme('good'), 'broken': 'це не тема'},
        },
      });

      expect(load.status, ThemeLoadStatus.ok);
      expect(load.contract.themeIds, ['good']);
    });

    test('a partial theme is healed by the resolver, not by replacing the whole theme', () {
      // One corrupt token is no reason to discard ten correct ones. `roles` is
      // present deliberately: 'partial theme' here is about VALUES, not roles.
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'partial',
          'themes': {
            'partial': {
              'id': 'partial',
              'color': {'primary': '#010203', 'accent': 'не колір'},
              'spacing': {'md': 'дванадцять'},
              'roles': _roles(),
            },
          },
        },
      });

      expect(load.status, ThemeLoadStatus.ok);
      final theme = load.contract.defaultTheme;
      expect(theme.color(ColorToken.primary), const Color(0xFF010203));
      // The corrupt value did not reach the map, and the core was completed from
      // the BUILT-IN theme of the same brightness (`partialThemeDefaults`), not with
      // zero: a theme missing `spacing.md` must not hide the padding entirely.
      final builtIn = ThemeContract.fallback().defaultTheme;
      expect(theme.color(ColorToken.accent), builtIn.color(ColorToken.accent));
      expect(theme.space(SpacingToken.md), builtIn.space(SpacingToken.md));
    });
  });

  group('theme contract version: same rule, different number', () {
    test('renderer declares the same version as the artifact', () {
      expect(artifactContract['themeContractVersion'], kSupportedThemeContractVersion);
      expect(artifact['x-themeContractVersion'], kSupportedThemeContractVersion);
    });

    test('versions of the two contracts are independent', () {
      // A rebrand does not change the widget vocabulary, a new widget does not change the palette.
      expect(kSupportedThemeContractVersion, isNot(kSupportedSchemaVersion));
    });

    test('the rule is reused, not duplicated', () {
      expect(
        checkContractVersion(ownMajor, readerVersion: kSupportedThemeContractVersion),
        VersionVerdict.ok,
      );
      expect(checkContractVersion('1.4.0', readerVersion: '1.0.0'), VersionVerdict.newerMinor);
      expect(checkContractVersion('2.0.0', readerVersion: '1.0.0'), VersionVerdict.newerMajor);
      expect(checkContractVersion(null, readerVersion: '1.0.0'), VersionVerdict.unparsable);
    });

    test('a foreign theme-contract major is not read - the fallback is used', () {
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': nextMajor,
          'defaultThemeId': 'alien',
          'themes': {'alien': _theme('alien', primary: '#ff0000')},
        },
      });

      expect(load.status, ThemeLoadStatus.incompatibleVersion);
      // Key point: the foreign major colours did NOT reach rendering.
      expect(load.contract.defaultTheme.color(ColorToken.primary), const Color(0xFF4F46E5));
    });

    test('theme 2.x is not read after the bump to 3.0.0 - and that is reported', () {
      // A major bump is not whimsical: a field became required (`roles` in 2.0.0,
      // `gradient` in 3.0.0), and `Theme` in `x-schema` is `additionalProperties:
      // false`, so it cannot be added in a minor. A 2.x theme has no gradients at
      // all; 'reading it partially' would mean drawing a screen without a
      // background that the design already drew.
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': previousMajor,
          'defaultThemeId': 'старенька',
          'themes': {'старенька': _theme('старенька', primary: '#ff0000')},
        },
      });

      // Not a silent substitution: the status distinguishes 'app is behind' from
      // 'artifact is broken', and the reason goes to the host as a string.
      expect(load.status, ThemeLoadStatus.incompatibleVersion);
      expect(load.isFallback, isTrue);
      expect(load.detail, contains(previousMajor));
      expect(load.detail, contains(kSupportedThemeContractVersion));
      expect(load.contract.defaultTheme.color(ColorToken.primary), const Color(0xFF4F46E5));
    });

    test('an older minor is read: a minor only adds', () {
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': newerMinor,
          'defaultThemeId': 'next',
          'themes': {'next': _theme('next', primary: '#123456')},
        },
      });

      expect(load.status, ThemeLoadStatus.ok);
      expect(load.contract.defaultTheme.color(ColorToken.primary), const Color(0xFF123456));
    });

    test('a name outside the core is a theme-own token, and it is read', () {
      // Before 4.0.0 this test claimed `brandAlt` and `xxl` were ignored: a name
      // outside the renderer list was a 'token from a newer minor'. Now this is the
      // NORM (`customTokens: 'declared-by-theme'`) and parsing goes by JSON keys no
      // longer for logging but because the keys ARE the vocabulary.
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': newerMinor,
          'defaultThemeId': 'next',
          'themes': {
            'next': {
              'id': 'next',
              'color': {'primary': '#123456', 'brandAlt': '#654321'},
              'spacing': {'xxl': 48, 'xl': 24},
              'roles': _roles(),
            },
          },
        },
      });

      final theme = load.contract.defaultTheme;
      expect(load.status, ThemeLoadStatus.ok);
      expect(theme.color(ColorToken.primary), const Color(0xFF123456));
      expect(theme.space(SpacingToken.xl), 24);
      // An own name sits alongside the core; a missing core is completed from the
      // built-in theme (`partialThemeDefaults`), own names are not.
      expect(theme.colors.keys, containsAll(['primary', 'brandAlt']));
      expect(theme.colors.keys.toSet().difference(ColorToken.values.map((t) => t.wire).toSet()), {'brandAlt'});
      expect(theme.resolveColor(const ColorRef.token('brandAlt')), const Color(0xFF654321));
      expect(theme.resolveSpacing(const ScaleRef.token('xxl')), 48);
    });

    test('missing file is not an exception but a status', () async {
      final load = await ThemeLoad.fromBundle(assetPath: 'assets/contract/немає-такого.json');

      expect(load.status, ThemeLoadStatus.assetMissing);
      expect(load.contract.themes, isNotEmpty);
    });

    /*
     * Theme from the HOST asset: the host names the path, there is no default.
     * While the default was the path of our demo asset, a call without the
     * parameter in a foreign app always gave `assetMissing` and silently drew
     * with the built-in theme.
     */
    test('theme is read from the asset the host named', () async {
      final load = await ThemeLoad.fromBundle(
        assetPath: 'assets/contract/fixtures/themes/rewards-showcase-theme.json',
        bundle: diskAssetBundle(),
      );

      expect(load.status, ThemeLoadStatus.ok, reason: load.detail);
      expect(load.contract.defaultTheme.colors.keys, contains('brandText'));
    });
  });

  group('Dart mirror of x-compatibility.policy', () {
    // The same guard `schema_version_test.dart` keeps for the widget schema.
    // Before 1.0.0 the theme contract had no such block and five of these rows
    // were invented by the renderer; now they are contractual and the mirror
    // cannot drift silently.
    test('artifact policy is the one the renderer mirrors', () {
      expect(kThemeCompatibilityPolicy, artifactPolicy);
    });

    test('version rule: majorMustMatch + minorAdditionsAreOptional', () {
      expect(artifactPolicy['majorMustMatch'], isTrue);
      expect(artifactPolicy['minorAdditionsAreOptional'], isTrue);

      expect(
        checkContractVersion(nextMajor, readerVersion: kSupportedThemeContractVersion),
        VersionVerdict.newerMajor,
      );
      // The major must match in both directions: after the bump to 3.0.0 an old
      // theme artifact is as foreign as a future one.
      expect(
        checkContractVersion(previousMajor, readerVersion: kSupportedThemeContractVersion),
        VersionVerdict.olderMajor,
      );
      expect(
        checkContractVersion(newerMinor, readerVersion: kSupportedThemeContractVersion),
        VersionVerdict.newerMinor,
      );
    });

    test('newerMinor: read-known-fields-only - read by keys, not by schema', () {
      // The contract says that `x-schema` describes exactly this minor, so a newer
      // theme cannot be validated with it. A reader that takes fields by key can read it.
      expect(artifactPolicy['schemaDescribesExactVersion'], isTrue);
      expect(artifactPolicy['newerMinor'], 'read-known-fields-only');

      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': newerMinor,
          'defaultThemeId': 'next',
          'themes': {
            'next': {
              'id': 'next',
              'brightness': 'light',
              'color': {'primary': '#123456', 'brandAlt': '#654321'},
              'roles': _roles(),
            },
          },
        },
      });

      expect(load.status, ThemeLoadStatus.ok);
      expect(load.contract.defaultTheme.color(ColorToken.primary), const Color(0xFF123456));
    });

    test('unreadableTheme: fallback-and-report - both the fallback AND the report', () {
      expect(artifactPolicy['unreadableTheme'], 'fallback-and-report');

      final load = ThemeLoad.parse('{');
      // fallback…
      expect(load.contract.themes, isNotEmpty);
      expect(load.contract.defaultTheme.color(ColorToken.primary), const Color(0xFF4F46E5));
      // ...and report: not a log but data the host can act on.
      expect(load.isFallback, isTrue);
      expect(load.status, ThemeLoadStatus.malformed);
      expect(load.detail, isNotNull);
    });

    test('unknownThemeId: use-default', () {
      expect(artifactPolicy['unknownThemeId'], 'use-default');

      final contract = ThemeLoad.parse(readThemeContract()).contract;
      expect(contract.themeById('партнерська-якої-немає').id, contract.defaultThemeId);
    });

    test('customTokens: declared-by-theme - a name outside the core is read', () {
      // This row replaced `unknownToken: 'ignore'` (4.0.0): a name outside the core
      // is now the norm, not a 'token from the future'.
      expect(artifactPolicy['customTokens'], 'declared-by-theme');
      expect(artifactPolicy.containsKey('unknownToken'), isFalse);

      final theme = RenderTheme.fromJson({
        'id': 'x',
        'color': {'primary': '#123456', 'brandAlt': '#654321'},
        'radius': {'card': 24},
        'elevation': {
          'card': [
            {'offsetX': 0, 'offsetY': 4, 'blur': 12, 'spread': 0, 'color': '#000000', 'opacity': 0.2},
          ],
        },
        'typography': {
          'hero': {'fontSize': 40, 'lineHeight': 1.1, 'fontWeight': 800, 'role': 'heading'},
        },
      });

      expect(theme.color(ColorToken.primary), const Color(0xFF123456));
      expect(theme.resolveColor(const ColorRef.token('brandAlt')), const Color(0xFF654321));
      expect(theme.resolveRadius(const ScaleRef.token('card')), 24);
      expect(theme.resolveShadow(const TokenShadowRef('card')), hasLength(1));
      expect(theme.resolveTypography(const TypographyRef('hero'))!.fontSize, 40);
    });

    test('missingCustomToken: treat-as-unknown-token - absent from THIS theme', () {
      // An own name exists in the light theme and is missing in the dark one. For
      // the document it is the same unknown token: the resolver gives `null`, not a
      // colour from the neighbouring theme nor a 'similar' token.
      expect(artifactPolicy['missingCustomToken'], 'treat-as-unknown-token');

      final light = RenderTheme.fromJson({
        'id': 'light',
        'color': {'onSurface': '#000000', 'border': '#cccccc', 'brandCoral': '#ff7a59'},
        'spacing': {'sm': 8, 'xxl': 48},
      });
      final dark = RenderTheme.fromJson({
        'id': 'dark',
        'color': {'onSurface': '#ffffff', 'border': '#333333'},
        'spacing': {'sm': 8},
      });

      const coral = ColorRef.token('brandCoral');
      expect(light.resolveColor(coral), const Color(0xFFFF7A59));
      expect(dark.resolveColor(coral), isNull);
      // In a `props` field with a default: the FIELD default, not `onSurface`.
      const line = FieldColor(coral, ColorToken.border);
      expect(dark.fieldColor(line), const Color(0xFF333333));
      const gap = FieldSpacing(ScaleRef.token('xxl'), SpacingToken.sm);
      expect(light.fieldSpacing(gap), 48);
      expect(dark.fieldSpacing(gap), 8);
    });

    test('missingLetterSpacing: zero - an entry without the field gives zero, not the platform tracking', () {
      expect(artifactPolicy['missingLetterSpacing'], 'zero');
      final theme = RenderTheme.fromJson({
        'id': 'x',
        'typography': {
          'bodyM': {'fontSize': 16, 'fontWeight': 400, 'lineHeight': 1.5, 'role': 'body'},
          'caption': {'fontSize': 12, 'fontWeight': 400, 'lineHeight': 1.5, 'role': 'body', 'letterSpacing': 0.4},
        },
        'roles': _roles(),
      });
      expect(theme.text(TypographyToken.bodyM).letterSpacing, 0);
      expect(theme.text(TypographyToken.caption).letterSpacing, 0.4);
    });

    test('colorAlpha: rrggbbaa-alpha-last - alpha is last, reordered in Flutter', () {
      // `Color(int)` in Flutter expects `0xAARRGGBB`. The contract eight digits
      // passed as is would give `0xFF7A5980`: a nearly opaque teal instead of a
      // semi-transparent coral - and nothing would fail.
      expect(artifactPolicy['colorAlpha'], 'rrggbbaa-alpha-last');

      final theme = RenderTheme.fromJson({
        'id': 'x',
        'color': {
          'onSurface': '#111827',
          'scrim': '#ff7a5980',
          'clear': '#00000000',
          'solid': '#ff7a59ff',
          'broken': '#ff7a598',
          'upper': '#FF7A59',
        },
        'gradient': {
          'fade': {
            'angle': 180,
            'stops': [
              {'color': '#00000000', 'position': 0},
              {'color': '#000000cc', 'position': 1},
            ],
          },
        },
      });

      final scrim = theme.resolveColor(const ColorRef.token('scrim'))!;
      expect(scrim.toARGB32(), 0x80FF7A59);
      expect(theme.resolveColor(const ColorRef.token('clear'))!.toARGB32(), 0x00000000);
      expect(theme.resolveColor(const ColorRef.token('solid'))!.toARGB32(), 0xFFFF7A59);
      // Seven or nine digits is not a colour; there is simply no such token in the theme.
      expect(theme.resolveColor(const ColorRef.token('broken')), isNull);
      // Alpha reaches gradient stops too.
      final fade = theme.resolveGradient(const TokenGradientRef('fade'))!;
      expect(fade.colors.map((color) => color.toARGB32()), [0x00000000, 0xCC000000]);
      // The SHADOW layer colour stays `#rrggbb`: shadow opacity is a separate field.
      final shadowed = RenderTheme.fromJson({
        'id': 'y',
        'elevation': {
          'bad': [
            {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0, 'color': '#11182780', 'opacity': 0.5},
          ],
        },
      });
      expect(shadowed.resolveShadow(const TokenShadowRef('bad')), isEmpty);
    });

    test('unknownRoleColor: neutral-slot', () {
      // The behaviour is held by the test 'role references a colour the theme does
      // not declare' in the roles group: the slot goes neutral, not the whole role.
      expect(artifactPolicy['unknownRoleColor'], 'neutral-slot');
    });

    test('partialTheme: resolve-missing-to-defaults', () {
      expect(artifactPolicy['partialTheme'], 'resolve-missing-to-defaults');

      final theme = RenderTheme.fromJson({
        'id': 'x',
        'color': {'onSurface': '#010203'},
      });

      // Token missing -> value from the BUILT-IN theme of the same brightness
      // (`partialThemeDefaults: 'built-in-theme-of-same-brightness'`). The resolver
      // used to return `onSurface` for a colour and zero for a spacing: a default
      // nobody could see.
      final builtIn = ThemeContract.fallback().defaultTheme;
      expect(theme.color(ColorToken.onSurface), const Color(0xFF010203), reason: 'own value stays');
      expect(theme.color(ColorToken.accent), builtIn.color(ColorToken.accent));
      expect(theme.space(SpacingToken.xl), builtIn.space(SpacingToken.xl));
      expect(theme.text(TypographyToken.titleM), builtIn.text(TypographyToken.titleM));
      expect(theme.gradient(GradientToken.brandBackdrop), isNotNull);
    });

    test('partialThemeDefaults: built-in-theme-of-same-brightness - dark takes dark', () {
      expect(artifactPolicy['partialThemeDefaults'], 'built-in-theme-of-same-brightness');

      final contract = ThemeContract.fallback();
      final dark = contract.themes.values.firstWhere((t) => t.brightness == Brightness.dark);
      final light = contract.themes.values.firstWhere((t) => t.brightness == Brightness.light);
      expect(dark.color(ColorToken.surface), isNot(light.color(ColorToken.surface)));

      final partialDark = RenderTheme.fromJson({'id': 'x', 'brightness': 'dark', 'roles': _roles()});
      final partialLight = RenderTheme.fromJson({'id': 'y', 'brightness': 'light', 'roles': _roles()});
      expect(partialDark.color(ColorToken.surface), dark.color(ColorToken.surface));
      expect(partialDark.color(ColorToken.onSurface), dark.color(ColorToken.onSurface));
      expect(partialLight.color(ColorToken.surface), light.color(ColorToken.surface));

      // Not completed: own names, the three optional state colours and roles.
      final theme = RenderTheme.fromJson({
        'id': 'z',
        'brightness': 'dark',
        'color': {'muted': '#112233'},
        'roles': _roles(),
      });
      expect(theme.colors.containsKey('brandCoral'), isFalse);
      for (final name in kThemeColorFallbacks.keys) {
        expect(theme.colors.containsKey(name), isFalse, reason: '$name has its own fallback');
      }
      // The optional colour falls back to a theme token, not to a built-in shade.
      expect(theme.colorNamed('locked'), const Color(0xFF112233));
    });

    test('zeroScaleToken: none-is-zero - `none` is zero whatever the theme writes', () {
      expect(artifactPolicy['zeroScaleToken'], 'none-is-zero');
      final theme = RenderTheme.fromJson({
        'id': 'x',
        'spacing': {'none': 16, 'md': 12},
        'radius': {'none': 8},
        'elevation': {
          'none': [
            {'offsetX': 0, 'offsetY': 4, 'blur': 8, 'spread': 0, 'color': '#000000', 'opacity': 0.5},
          ],
        },
        'roles': _roles(),
      });
      expect(theme.space(SpacingToken.none), 0);
      expect(theme.radius(RadiusToken.none), 0);
      expect(theme.elevation(ElevationToken.none), isEmpty);
      expect(theme.space(SpacingToken.md), 12, reason: 'rest of the scale is untouched');

      // The same from the artifact side: `none` in OUR theme really is zero.
      final builtIn = ThemeContract.fallback().defaultTheme;
      expect(builtIn.space(SpacingToken.none), 0);
      final zero = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
              as Map)['x-tokens']['zeroScale'] as Map;
      expect(zero['token'], 'none');
      expect(zero['sets'], ['spacing', 'radius', 'elevation']);
    });

    test('key `__proto__` in the theme is invalid: neither a token nor a theme', () {
      // In the schema this is `propertyNames.pattern` on `themes` plus the token-name
      // pattern; in Dart it would be an ordinary map key and the reader would silently accept it.
      final theme = RenderTheme.fromJson({
        'id': 'x',
        'color': {'__proto__': '#010203', 'primary': '#112233'},
        'spacing': {'__proto__': 99},
        'origins': {'__proto__': 'x', 'color.primary': 'y'},
        'roles': _roles(),
      });
      expect(theme.colors.containsKey('__proto__'), isFalse);
      expect(theme.spacing.containsKey('__proto__'), isFalse);
      expect(theme.origins.keys, ['color.primary']);
      expect(theme.resolveColor(const TokenColorRef('__proto__')), isNull);

      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'good',
          'themes': {'__proto__': _theme('proto'), 'good': _theme('good')},
        },
      });
      expect(load.contract.themeIds, ['good']);
    });

    testWidgets('missingRole: render-neutral - neutral, not an invented colour', (
      tester,
    ) async {
      // The renderer already degraded this way, but it was our own decision, now a
      // policy row. Checked by behaviour, on a painted badge, not just by matching
      // the policy text.
      expect(artifactPolicy['missingRole'], 'render-neutral');

      // A theme whose `warning` tone is not described models 'the widget vocabulary
      // got ahead of the theme': contracts are versioned independently.
      final roles = _roles();
      (roles['badgeTone'] as Map<String, Object?>).remove('warning');
      final theme = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'без-warning',
          'themes': {'без-warning': _theme('без-warning', roles: roles)},
        },
      }).contract.defaultTheme;

      await pumpDocument(
        tester,
        docWith([
          badgeNode('Увага', tone: 'warning', id: 'b1'),
          badgeNode('Готово', tone: 'success', id: 'b2'),
        ]),
        theme: theme,
      );

      // Role missing -> neutral: no fill, no border, `onSurface` text.
      final neutral = _badgeDecoration(tester, 'Увага');
      expect(neutral.color, isNull);
      expect(neutral.border, isNull);
      expect(_labelColor(tester, 'Увага'), theme.color(ColorToken.onSurface));
      // Key point: the badge stayed on screen and is readable; it neither vanished
      // nor took a random colour.
      expect(find.text('Увага'), findsOneWidget);
      // A neighbouring tone the theme describes is unaffected.
      expect(_badgeBackground(tester, 'Готово'), theme.color(ColorToken.success));
    });

    test('gradientAngleSpace: axis-aligned angles as in CSS, diagonal ones corner to corner', () {
      // 3.1.0 narrowed the angle to four axis-aligned ones: CSS measures the angle
      // against the real box geometry while `Alignment` uses a normalised one, so
      // 45 degrees was drawn only approximately and silently. 4.0.0 brought diagonals
      // BACK, but not as degrees: 45 / 135 / 225 / 315 mean 'corner to corner'. So
      // this test asserts WHERE exactly each of the eight angles is drawn.
      expect(artifactPolicy['gradientAngleSpace'], 'axis-as-css-diagonal-css-to-corner');
      expect(artifactPolicy['diagonalGradientGeometry'], 'css-to-corner');

      // The artifact lists exactly the eight angles the renderer can draw.
      final angles = artifactAngleEnum;
      expect(angles.toSet(), {0, 45, 90, 135, 180, 225, 270, 315});
      expect(angles.toSet(), {...kAxisGradientAngles, ...kCornerGradientAngles});

      // The `Alignment` pair for each angle as a table, not a formula: this very
      // table is what `RenderTheme.gradientDirection` mirrors.
      const expected = <int, (Alignment, Alignment)>{
        // Axis-aligned, 'as in CSS': 0 degrees bottom to top, then clockwise.
        0: (Alignment.bottomCenter, Alignment.topCenter),
        90: (Alignment.centerLeft, Alignment.centerRight),
        180: (Alignment.topCenter, Alignment.bottomCenter),
        270: (Alignment.centerRight, Alignment.centerLeft),
        // Diagonal: corner to corner. 135 goes from top-left to bottom-right (as the
        // contract states literally); the rest follow the same clockwise sequence.
        45: (Alignment.bottomLeft, Alignment.topRight),
        135: (Alignment.topLeft, Alignment.bottomRight),
        225: (Alignment.topRight, Alignment.bottomLeft),
        315: (Alignment.bottomRight, Alignment.topLeft),
      };

      for (final value in angles) {
        final gradient = _gradientTheme(value).gradient(GradientToken.brandBackdrop);
        expect(
          gradient,
          isNotNull,
          reason: '$value degrees is listed in the contract but the renderer does not draw it',
        );
        expect((gradient!.begin, gradient.end), expected[value], reason: '$value°');
        // Start and end lie on the box edge, exactly opposite each other; otherwise
        // the gradient would not reach the corner or would be shifted.
        final begin = gradient.begin as Alignment;
        final end = gradient.end as Alignment;
        expect(end, -begin, reason: '$value°');
        expect(math.max(begin.x.abs(), begin.y.abs()), 1, reason: '$value°');
      }

      // A diagonal goes exactly from a corner: both coordinates on the edge.
      for (final value in kCornerGradientAngles) {
        final begin = _gradientTheme(value).gradient(GradientToken.brandBackdrop)!.begin as Alignment;
        expect((begin.x.abs(), begin.y.abs()), (1, 1), reason: '$value°');
      }

      // Angles are PHYSICAL: the type is `Alignment`, not `AlignmentDirectional`, so
      // the gradient is not mirrored in right-to-left writing.
      expect(_gradientTheme(135).gradient(GradientToken.brandBackdrop)!.begin, isA<Alignment>());

      // An angle outside the list is a theme from the future or a corrupt one: no gradient.
      for (final value in [30, 60, 360, -45, 44.9]) {
        expect(
          _gradientTheme(value).gradient(GradientToken.brandBackdrop),
          isNull,
          reason: '$value degrees is outside the contract',
        );
      }
    });

    test('gradientStopOrder: non-descending + unorderedGradient: do-not-draw', () {
      // Increasing positions is a rule about ADJACENT array elements, which JSON
      // Schema cannot express. So the policy makes the promise and the reader
      // catches it: Skia draws unordered stops unpredictably, i.e. 'almost right',
      // and nobody would notice.
      expect(artifactPolicy['gradientStopOrder'], 'non-descending');
      expect(artifactPolicy['unorderedGradient'], 'do-not-draw');

      final unordered = RenderTheme.fromJsonRaw({
        'id': 'x',
        'roles': _roles(),
        'gradient': {
          'brandBackdrop': {
            'angle': 90,
            'stops': [
              {'color': '#000000', 'position': 1},
              {'color': '#ffffff', 'position': 0},
            ],
          },
        },
      });

      // No gradient; the theme does not become unusable because of it.
      expect(unordered.gradient(GradientToken.brandBackdrop), isNull);
      expect(unordered.hasRoles, isTrue);

      // EQUAL positions are ordered: that is a hard colour edge, not a violation.
      // Before 4.0.0 the renderer rejected them too ('strictly increasing'); the contract has clarified this.
      final hardStop = RenderTheme.fromJsonRaw({
        'id': 'y',
        'gradient': {
          'brandBackdrop': {
            'angle': 90,
            'stops': [
              {'color': '#000000', 'position': 0},
              {'color': '#000000', 'position': 0.5},
              {'color': '#ffffff', 'position': 0.5},
              {'color': '#ffffff', 'position': 1},
            ],
          },
        },
      });
      expect(hardStop.gradient(GradientToken.brandBackdrop)!.stops, [0, 0.5, 0.5, 1]);
    });

    test('shadowOrder: first-is-nearest - the list is reversed for Flutter', () {
      // CSS paints the first shadow on top; Flutter paints `boxShadow` in list
      // order, i.e. the last on top. So the first shadow of the contract must become
      // the LAST in Flutter, otherwise two shadows of one level silently swap depth.
      expect(artifactPolicy['shadowOrder'], 'first-is-nearest');

      final theme = RenderTheme.fromJson({
        'id': 'x',
        'elevation': {
          'low': [
            {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0, 'color': '#111111', 'opacity': 1},
            {'offsetX': 0, 'offsetY': 9, 'blur': 9, 'spread': 0, 'color': '#222222', 'opacity': 1},
          ],
        },
      });

      final shadows = theme.elevation(ElevationToken.low);
      expect(shadows, hasLength(2));
      // The one nearest the viewer (first in the contract) is painted last.
      expect(shadows.last.color, const Color(0xFF111111));
      expect(shadows.first.color, const Color(0xFF222222));
    });

    test('a single shadow is not damaged by reversal', () {
      // Our palette has one shadow per level; reversal must not touch what was
      // already drawn correctly.
      final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;
      expect(theme.elevation(ElevationToken.low), [
        const BoxShadow(color: Color(0x1F111827), blurRadius: 2, offset: Offset(0, 1)),
      ]);
    });

    test('lengthUnit: logical-pixels and lineHeightUnit: font-size-multiple', () {
      // Units are no longer guessed: they are in the policy.
      expect(artifactPolicy['lengthUnit'], 'logical-pixels');
      expect(artifactPolicy['lineHeightUnit'], 'font-size-multiple');

      final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;
      expect(theme.space(SpacingToken.xl), 24);
      expect(theme.text(TypographyToken.bodyM).height, closeTo(1.4286, 1e-9));
    });
  });

  group('brightness: the system mode picks the theme, not app code', () {
    ThemeContract lightAndDark() => ThemeLoad.fromJson({
      'contract': {
        'themeContractVersion': ownMajor,
        'defaultThemeId': 'light',
        'themes': {
          'light': _theme('light', surface: '#ffffff'),
          'dark': _theme('dark', brightness: 'dark', surface: '#101114'),
        },
      },
    }).contract;

    test('brightness is read from the contract', () {
      final contract = lightAndDark();

      expect(contract.themeById('light').brightness, Brightness.light);
      expect(contract.themeById('dark').brightness, Brightness.dark);
    });

    test('theme is chosen by brightness, not by a hardcoded name', () {
      final contract = lightAndDark();

      expect(contract.themeForBrightness(Brightness.dark).id, 'dark');
      expect(contract.themeForBrightness(Brightness.light).id, 'light');
    });

    test('no theme of the needed brightness -> the default one, not emptiness', () {
      /*
       * The contract is SYNTHETIC: the real theme artifact now also has a dark
       * theme (see the test below), so the rule has to be checked on a set
       * assembled here, otherwise it would quietly check the opposite.
       */
      final contract = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'light',
          'themes': {'light': _theme('light', surface: '#ffffff')},
        },
      }).contract;

      expect(contract.themeForBrightness(Brightness.dark).id, contract.defaultThemeId);
    });

    /*
     * The multi-theme mechanism stopped being theoretical (3.3.0).
     *
     * All checks above ran on synthetic contracts, i.e. proved only what the code
     * can do. Now a dark theme is in the artifact ITSELF and the renderer learned
     * nothing for it: it still takes the theme by `defaultThemeId`, choosing
     * another is the host business.
     *
     * It has no design-supplied values, and the test holds exactly that, because
     * otherwise picked colours would later read as agreed ones.
     */
    test('the real artifact has a dark theme, and all of it is provisional', () {
      final contract = ThemeLoad.parse(readThemeContract()).contract;
      final dark = contract.themeForBrightness(Brightness.dark);

      expect(dark.brightness, Brightness.dark);
      expect(dark.id, isNot(contract.defaultThemeId));
      expect(dark.provisional, contains('color.surface'));
    });

    test('unknown or missing brightness - light, with a log', () {
      expect(RenderTheme.fromJson({'id': 'x'}).brightness, Brightness.light);
      expect(
        RenderTheme.fromJson({'id': 'x', 'brightness': 'сутінки'}).brightness,
        Brightness.light,
      );
    });

    test('brightness reaches ThemeData, not only the document', () {
      // Otherwise system widgets (AppBar, ripple) would stay light on top of a dark document.
      final material = lightAndDark().themeById('dark').toMaterialTheme();

      expect(material.brightness, Brightness.dark);
      expect(material.colorScheme.brightness, Brightness.dark);
    });

    testWidgets('dark theme reaches the pixels', (tester) async {
      final contract = lightAndDark();
      final doc = docWith([textNode('Привіт')]);

      await pumpDocument(tester, doc, theme: contract.themeForBrightness(Brightness.dark));
      expect(_screenBackground(tester), const Color(0xFF101114));
    });
  });

  group('several themes: a mechanism, not one theme with another name', () {
    ThemeLoad twoThemes() => ThemeLoad.fromJson({
      'contract': {
        'themeContractVersion': ownMajor,
        'defaultThemeId': 'light',
        'themes': {
          'light': _theme('light', primary: '#4f46e5', surface: '#ffffff'),
          'dark': _theme('dark', primary: '#7cf0c0', surface: '#101114'),
        },
      },
    });

    test('selection by id, unknown id falls back to the default', () {
      final contract = twoThemes().contract;

      expect(contract.themeById('dark').id, 'dark');
      expect(contract.themeById('light').id, 'light');
      expect(contract.themeById('партнерська-якої-немає').id, 'light');
      expect(contract.themeById(null).id, 'light');
      expect(contract.hasTheme('dark'), isTrue);
    });

    test('defaultThemeId pointing nowhere - take any, do not crash', () {
      final load = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'немає-такої',
          'themes': {'only': _theme('only')},
        },
      });

      expect(load.contract.defaultTheme.id, 'only');
    });

    testWidgets('same document, another theme - other pixels', (tester) async {
      // The main proof of the epic: the document did not change a byte, only the
      // theme did, and rendering took its values.
      final contract = twoThemes().contract;
      final doc = docWith([textNode('Привіт')]);

      await pumpDocument(tester, doc, theme: contract.themeById('light'));
      expect(_screenBackground(tester), const Color(0xFFFFFFFF));

      await pumpDocument(tester, doc, theme: contract.themeById('dark'));
      expect(_screenBackground(tester), const Color(0xFF101114));
    });
  });

  group('lineHeight is a multiplier, not pixels', () {
    testWidgets('line height = fontSize x lineHeight', (tester) async {
      // Were the multiplier passed to `TextStyle.height` as px, the line would be
      // 1.1667 logical pixels tall. We check what was painted, not the style field.
      final theme = ThemeLoad.parse(readThemeContract()).contract.defaultTheme;
      final doc = docWith([
        textNode('Заголовок', style: const {'typography': 'displayL'}),
      ]);

      await pumpDocument(tester, doc, theme: theme);

      final size = tester.getSize(find.text('Заголовок'));
      expect(size.height, closeTo(24 * 1.1667, 0.5));
    });

    testWidgets('multiplier from the theme really drives the line height', (tester) async {
      final tall = ThemeLoad.fromJson({
        'contract': {
          'themeContractVersion': ownMajor,
          'defaultThemeId': 'tall',
          'themes': {
            'tall': {
              'id': 'tall',
              'color': {'surface': '#ffffff', 'onSurface': '#000000'},
              'typography': {
                'bodyM': {'fontSize': 20, 'lineHeight': 3, 'fontWeight': 400, 'role': 'body'},
              },
              'roles': _roles(),
            },
          },
        },
      }).contract.defaultTheme;

      await pumpDocument(tester, docWith([textNode('Рядок')]), theme: tall);

      expect(tester.getSize(find.text('Рядок')).height, closeTo(60, 0.5));
    });
  });

  /*
   * THEME FROM THE NETWORK. The edited theme is now published to storage and
   * the app reads it on start.
   *
   * The key point is not 'it was read' but WHAT HAPPENS WHEN IT WAS NOT. A theme
   * is presentation, not content, so no failure path may leave the user without
   * a screen: without fresh colours they see a slightly different shade,
   * without a screen they see nothing.
   */
  group('theme from the network', () {
    /// The published theme is a BARE contract, without the `x-schema` envelope:
    /// the envelope exists for the validator, not for delivery.
    String published({String version = kSupportedThemeContractVersion, String primary = '#00ff00'}) => jsonEncode({
      'themeContractVersion': version,
      'defaultThemeId': 'мережева',
      'themes': {
        'мережева': _theme('мережева', primary: primary),
      },
    });

    Uri url() => Uri.parse('https://example.test/theme/published.json');

    test('published theme is read and replaces the built-in one', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.replying(200, published()),
      );

      expect(load.status, ThemeLoadStatus.ok);
      expect(load.contract.defaultTheme.color(ColorToken.primary), const Color(0xFF00FF00));
    });

    /*
     * 404 means 'theme not published yet', the most common state of a new
     * project, not a fault. The app draws with what it was built with.
     */
    test('404 falls back to the built-in theme and does not crash startup', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.replying(404, ''),
      );

      expect(load.status, ThemeLoadStatus.networkUnavailable);
      expect(load.contract.themes, isNotEmpty);
    });

    /*
     * Where it falls back: to the host asset if one is named, to the EMBEDDED
     * theme otherwise. There is no default path: an invented key in a foreign
     * app would find nothing.
     */
    test('with `assetPath` the fallback goes to the host theme, status stays network', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.replying(404, ''),
        assetPath: 'assets/contract/fixtures/themes/rewards-showcase-theme.json',
        bundle: diskAssetBundle(),
      );

      expect(load.status, ThemeLoadStatus.networkUnavailable);
      expect(load.contract.defaultTheme.colors.keys, contains('brandText'));
    });

    test('without `assetPath` the fallback goes to the embedded theme, without reading an asset', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.replying(404, ''),
      );

      expect(load.status, ThemeLoadStatus.networkUnavailable);
      expect(load.detail, contains('404'));
      expect(load.contract.defaultThemeId, ThemeContract.fallback().defaultThemeId);
    });

    test('connection drop also falls back', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.failing(StateError('немає мережі')),
      );

      expect(load.status, ThemeLoadStatus.networkUnavailable);
      expect(load.contract.themes, isNotEmpty);
    });

    test('a silent network does not hold startup beyond the timeout', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.silent(),
        timeout: const Duration(milliseconds: 20),
      );

      expect(load.status, ThemeLoadStatus.networkUnavailable);
    });

    /*
     * 'Server is silent' and 'server returned garbage' are different news and
     * get different statuses: the first passes by itself, the second means someone
     * published a broken theme and the conversation must be with them.
     */
    test('garbage from the network gives `malformed`, not "network did not respond"', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.replying(200, 'зовсім не json'),
      );

      expect(load.status, ThemeLoadStatus.malformed);
      expect(load.contract.themes, isNotEmpty);
    });

    /*
     * A foreign theme major MUST NOT be read: the structure is different and
     * 'reading it partially' means painting with the wrong colour.
     */
    test('foreign major is rejected with its own status', () async {
      final load = await ThemeLoad.fromNetwork(
        url(),
        transport: FakeDocumentTransport.replying(200, published(version: '99.0.0')),
      );

      expect(load.status, ThemeLoadStatus.incompatibleVersion);
      expect(load.contract.themes, isNotEmpty);
    });
  });

  group('fallback colours (3.4.0)', () {
    /// The key point of this minor.
    ///
    /// The policy says `partialTheme: 'resolve-missing-to-defaults'`, but 'resolve
    /// to defaults' without a list of defaults is an instruction to INVENT them.
    /// The contract supplied the list (`x-optionalColors`) and the constant in
    /// code must mirror it, otherwise web and Flutter draw differently and this
    /// is noticeable only with the two screens side by side.
    test('renderer constant equals the artifact map', () {
      final optional = artifact['x-optionalColors']! as Map<String, Object?>;
      final fallbacks = optional['fallbacks']! as Map<String, Object?>;

      expect(kThemeColorFallbacks, equals(fallbacks));
    });

    test('the list of optional ones matches the map keys', () {
      final optional = artifact['x-optionalColors']! as Map<String, Object?>;
      final tokens = (optional['tokens']! as List<Object?>).cast<String>().toList()..sort();
      final keys = kThemeColorFallbacks.keys.toList()..sort();

      expect(tokens, equals(keys));
    });

    /// A 3.3.0 theme must look EXACTLY as it did in this renderer. That is the
    /// point of fallbacks: a reader update does not change other screens.
    test('a theme without the new colours paints them with fallbacks, not onSurface', () {
      final themes = artifactContract['themes']! as Map<String, Object?>;
      final light = Map<String, Object?>.from(themes['light']! as Map);
      final colors = Map<String, Object?>.from(light['color']! as Map);
      for (final token in kThemeColorFallbacks.keys) {
        colors.remove(token);
      }
      light['color'] = colors;

      final theme = RenderTheme.fromJson(light);

      expect(theme.color(ColorToken.locked), equals(theme.color(ColorToken.muted)));
      expect(theme.color(ColorToken.inProgress), equals(theme.color(ColorToken.accent)));
      expect(theme.color(ColorToken.completed), equals(theme.color(ColorToken.success)));
      expect(theme.color(ColorToken.locked), isNot(equals(theme.color(ColorToken.onSurface))));
    });

    test('own value overrides the fallback', () {
      final themes = artifactContract['themes']! as Map<String, Object?>;
      final theme = RenderTheme.fromJson(themes['light']! as Map<String, Object?>);

      expect(theme.color(ColorToken.locked), isNot(equals(theme.color(ColorToken.muted))));
    });
  });

  group('letter spacing (3.4.0)', () {
    /// The unit is logical pixels, so the value goes into `TextStyle` one to one.
    /// The test checks specifically the ABSENCE of multiplication by font size: a
    /// mistake here would give text that spreads proportionally to size on the phone.
    test('value reaches TextStyle without recalculation', () {
      final themes = artifactContract['themes']! as Map<String, Object?>;
      final light = Map<String, Object?>.from(themes['light']! as Map);
      final typography = Map<String, Object?>.from(light['typography']! as Map);
      final titleM = Map<String, Object?>.from(typography['titleM']! as Map);
      titleM['letterSpacing'] = -0.5;
      typography['titleM'] = titleM;
      light['typography'] = typography;

      final theme = RenderTheme.fromJson(light);

      expect(theme.text(TypographyToken.titleM).letterSpacing, equals(-0.5));
    });

    /// A theme without the field means 'normal font tracking', i.e. ZERO, stated
    /// explicitly. `null` in `TextStyle` means 'inherit', and the label would pick
    /// up the default Material tracking (see the next test).
    test('missing field - zero spacing, not inherited', () {
      final themes = artifactContract['themes']! as Map<String, Object?>;
      final theme = RenderTheme.fromJson(themes['light']! as Map<String, Object?>);

      expect(theme.text(TypographyToken.titleM).letterSpacing, 0);
    });

    /// The same on the PAINTED label, after merging with the inherited style.
    /// Material tracking (0.25 dp per character in `bodyMedium`) made every line
    /// wider than on the builder canvas, wrapping it where it fitted there.
    testWidgets('label does not pick up the default Material tracking', (tester) async {
      final theme = RenderTheme.fallback();
      const label = 'двадцять знаків тут!';
      await pumpDocument(tester, docWith([textNode(label)]), theme: theme);

      // The tracking the label was really painted with: after merging with the
      // inherited style, not the one in the theme.
      final painted = tester.widget<RichText>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(painted.text.style!.letterSpacing, 0);
      expect(
        painted.text.style!.fontSize,
        theme.text(TypographyToken.bodyM).fontSize,
        reason: 'we measure the style the node text is painted with',
      );
    });
  });


}

/// Roles for mechanism tests: the same map as in the artifact unless told
/// otherwise. Parameters allow assembling a SYNTHETIC theme with different
/// semantics to prove colours really come from the theme, not from code.
Map<String, Object?> _roles({
  Map<String, Object?>? badgeSuccess,
  Map<String, Object?>? buttonPrimary,
  Map<String, Object?>? buttonGhost,
}) => {
  'badgeTone': {
    'neutral': {'background': 'secondary', 'foreground': 'onSurface'},
    'success': badgeSuccess ?? {'background': 'success', 'foreground': 'onPrimary'},
    'warning': {'background': 'warning', 'foreground': 'onPrimary'},
    'danger': {'background': 'danger', 'foreground': 'onPrimary'},
    'accent': {'background': 'accent', 'foreground': 'onPrimary'},
  },
  'buttonVariant': {
    'primary': buttonPrimary ?? {'background': 'primary', 'foreground': 'onPrimary'},
    'secondary': {'background': 'surface', 'foreground': 'primary', 'border': 'primary'},
    'ghost': buttonGhost ?? {'foreground': 'primary'},
  },
};

/// Minimally complete theme for mechanism tests, not for values.
Map<String, Object?> _theme(
  String id, {
  String primary = '#4f46e5',
  String surface = '#ffffff',
  String brightness = 'light',
  Map<String, Object?>? roles,
}) => {
  'id': id,
  'name': 'Тема $id',
  'source': 'тест',
  'brightness': brightness,
  'provisional': <String>[],
  'origins': <String, String>{},
  'fontFamilies': {
    'body': {'primary': 'Body Face', 'fallback': <String>[]},
    'heading': {'primary': 'Heading Face', 'fallback': <String>[]},
  },
  'spacing': {'none': 0, 'xs': 4, 'sm': 8, 'md': 12, 'lg': 16, 'xl': 24},
  'radius': {'none': 0, 'sm': 8, 'md': 12, 'lg': 20, 'pill': 72},
  'color': {
    'primary': primary,
    'onPrimary': '#ffffff',
    'secondary': '#eef0f6',
    'accent': '#0369a1',
    'surface': surface,
    'onSurface': '#111827',
    'muted': '#6b7280',
    'success': '#15803d',
    'warning': '#b45309',
    'danger': '#dc2626',
  },
  'typography': {
    'bodyM': {'fontSize': 14, 'lineHeight': 1.4286, 'fontWeight': 400, 'role': 'body'},
  },
  'elevation': {'none': <Object?>[], 'low': <Object?>[], 'medium': <Object?>[]},
  'roles': roles ?? _roles(),
};

/// Badge decoration from the mounted tree: what is really painted, not what
/// we put in the theme.
BoxDecoration _badgeDecoration(WidgetTester tester, String label) => badgeDecoration(tester, label);

Color? _badgeBackground(WidgetTester tester, String label) =>
    _badgeDecoration(tester, label).color;

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

/// Colour of the root `Screen` background: the cheapest way to see which
/// theme values reached the pixels.
///
/// Since 7.0.0 the screen background is a union, so a shared helper
/// ([screenDecoration]) finds the decoration; only 'what colour is it' remains here.
Color _screenBackground(WidgetTester tester) => screenDecoration(tester).color!;

/// Theme with a single gradient at a given angle, to test the angle
/// translation, not the artifact values.
/// `fromJsonRaw`: this checks what the theme ITSELF says about the angle. Through
/// `fromJson` a corrupt core gradient would be filled from the built-in one
/// (`partialThemeDefaults`) and the answer 'no gradient' would vanish.
RenderTheme _gradientTheme(num angle) => RenderTheme.fromJsonRaw({
  'id': 'кут',
  'roles': _roles(),
  'gradient': {
    'brandBackdrop': {
      'angle': angle,
      'stops': [
        {'color': '#000000', 'position': 0},
        {'color': '#ffffff', 'position': 1},
      ],
    },
  },
});
