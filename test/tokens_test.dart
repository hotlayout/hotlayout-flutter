import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/icon_set.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

void main() {
  group('token resolution', () {
    /*
     * TWO KINDS OF TOKENS (9.0.0), and the tests below are split between them on purpose.
     *
     * CLOSED — words of the widget schema itself (`align`, `orientation`, `overflow`,
     * badge tone): the list is in the schema, and an unknown word gives the default already during
     * parsing.
     *
     * OPEN — the theme's six dictionaries (colour, spacing, radius, font, shadow,
     * gradient): the THEME declares the names, so "unknown" is resolved only against
     * it. Before 9.0.0 this file checked `ColorToken.parse('neon') → onSurface`;
     * that parse no longer exists, because `neon` may be a project's own colour,
     * and parsing has no right to decide that on the theme's behalf.
     */
    test('closed list: a known name gives its value', () {
      expect(AspectRatioToken.parse('4:3'), AspectRatioToken.classic);
      expect(OrientationToken.parse('vertical'), OrientationToken.vertical);
      expect(TextOverflowToken.parse('clip'), TextOverflowToken.clip);
      expect(ProgressLabelFormatToken.parse('percent'), ProgressLabelFormatToken.percent);
    });

    test('closed list: an unknown name does not throw but gives the default', () {
      // 9.3.0: icons are an EXCEPTION to "gives the default". An unknown name does not
      // become the field default (`star`): `unknownIcon` outranks `unknownToken`, because a star
      // in place of a flame would look correct.
      expect(IconToken.parse('rocket-from-the-future'), IconToken.unknown);
      expect(BadgeToneToken.parse('electric'), BadgeToneToken.neutral);
      expect(AspectRatioToken.parse('21:9'), AspectRatioToken.wide);
      expect(OrientationToken.parse('diagonal'), OrientationToken.horizontal);
      expect(TextOverflowToken.parse('fade'), TextOverflowToken.ellipsis);
      expect(ProgressLabelFormatToken.parse('ratio'), ProgressLabelFormatToken.valueOfMax);
    });

    test('closed list: null and a non-string also give the default', () {
      expect(AlignToken.parse(null), AlignToken.start);
      expect(AlignToken.parse(const {}), AlignToken.start);
      expect(IconSizeToken.parse(42), IconSizeToken.md);
    });

    test('open dictionary: a name matching the pattern stays a REFERENCE, not the default', () {
      // Parsing does not know whether `neon` exists in the theme — and does not pretend to.
      expect(ColorRef.tryParse('neon'), const ColorRef.token('neon'));
      expect(ScaleRef.tryParse('gigantic', max: kMaxSpacingPx), const ScaleRef.token('gigantic'));
      expect(TypographyRef.tryParse('hero'), const TypographyRef('hero'));
      // But a string that cannot be a name is not a reference at all.
      expect(ColorRef.tryParse('#ff0000'), isNull);
      expect(ColorRef.tryParse('Neon'), isNull);
      expect(ColorRef.tryParse(42), isNull);
      expect(ScaleRef.tryParse('дуже-великий', max: kMaxSpacingPx), isNull);
    });

    test('open dictionary: an unknown name in a field with a default gives the FIELD DEFAULT', () {
      final theme = RenderTheme.fallback();

      expect(
        theme.fieldSpacing(FieldSpacing.parse('gigantic', fieldDefault: SpacingToken.sm)),
        theme.space(SpacingToken.sm),
      );
      expect(
        theme.fieldColor(FieldColor.parse('neon', fieldDefault: ColorToken.border)),
        theme.color(ColorToken.border),
      );
      // Not a "type default": the same unknown name in another field gives another one.
      expect(
        theme.fieldColor(FieldColor.parse('neon', fieldDefault: ColorToken.primary)),
        theme.color(ColorToken.primary),
      );
      // A value of the wrong shape — the same field default.
      expect(
        theme.fieldSpacing(FieldSpacing.parse(const {'px': 4}, fieldDefault: SpacingToken.md)),
        theme.space(SpacingToken.md),
      );
    });

    test('open dictionary: an unknown name WITHOUT a field default gives nothing', () {
      // `style` fields have no defaults by construction — `omit-field`.
      final theme = RenderTheme.fallback();

      expect(theme.resolveColor(const ColorRef.token('neon')), isNull);
      expect(theme.resolveSpacing(const ScaleRef.token('gigantic')), isNull);
      expect(theme.resolveRadius(const ScaleRef.token('squircle')), isNull);
      expect(theme.resolveTypography(const TypographyRef('hero')), isNull);
      expect(theme.resolveShadow(const TokenShadowRef('glow')), isNull);
      expect(theme.resolveGradient(const TokenGradientRef('sunset')), isNull);
    });

    test('the theme resolves every core token', () {
      final theme = RenderTheme.fallback();
      for (final token in ColorToken.values) {
        expect(theme.color(token), isA<Color>());
        expect(theme.resolveColor(ColorRef.token(token.wire)), theme.color(token));
      }
      for (final token in SpacingToken.values) {
        expect(theme.space(token), greaterThanOrEqualTo(0));
        expect(theme.resolveSpacing(ScaleRef.token(token.wire)), theme.space(token));
      }
      for (final token in RadiusToken.values) {
        expect(theme.radius(token), greaterThanOrEqualTo(0));
        expect(theme.resolveRadius(ScaleRef.token(token.wire)), theme.radius(token));
      }
      for (final token in TypographyToken.values) {
        expect(theme.text(token).fontSize, isNotNull);
        expect(theme.resolveTypography(TypographyRef(token.wire)), theme.text(token));
      }
      for (final token in ElevationToken.values) {
        expect(theme.resolveShadow(TokenShadowRef(token.wire)), theme.elevation(token));
      }
      for (final token in GradientToken.values) {
        expect(theme.gradient(token), isNotNull);
      }
      // Icons do not belong to the theme: the drawing comes from the contract set. That EVERY name
      // is drawn is covered by `icon_library_test.dart`.
      expect(IconToken.values, hasLength(kIconBodies.length));
    });

    test('an incomplete theme map does not break core resolution', () {
      // `partialTheme: 'resolve-missing-to-defaults'`: the theme was read partially,
      // while the renderer refers to the core itself — and must get something.
      final partial = RenderTheme(
        colors: const {'onSurface': Color(0xFF000000)},
        spacing: const {},
        radii: const {},
        typography: const {},
        elevations: const {},
      );

      expect(partial.color(ColorToken.accent), const Color(0xFF000000));
      expect(partial.space(SpacingToken.xl), 0);
      expect(partial.radius(RadiusToken.pill), 0);
      expect(partial.text(TypographyToken.displayL).fontSize, 14);
      expect(partial.elevation(ElevationToken.medium), isEmpty);
      // But a REFERENCE from the document to the same name stays an honest "missing".
      expect(partial.resolveColor(const ColorRef.token('accent')), isNull);
    });
  });
}
