import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

/// "Token or value" -> theme value.
///
/// A mirror of the builder `resolve.ts`. There are few rules here, but each is a place
/// where two readers would diverge silently: what to do with a token the theme does not
/// know; how a tint opacity and the alpha of the colour itself combine; where
/// an optional state colour falls back; what a diagonal angle means.
void main() {
  // A theme with the core and its own names - exactly the case the dictionaries were
  // opened for: `brandCoral`, `xxl`, `card`, `hero`, `missionSunset`.
  final theme = RenderTheme.fromJson({
    'id': 'brand',
    'fontFamilies': {
      'body': {'primary': 'Body Face', 'fallback': <String>[]},
      'heading': {'primary': 'Heading Face', 'fallback': <String>[]},
    },
    'color': {
      'primary': '#4f46e5',
      'onSurface': '#111827',
      'muted': '#6b7280',
      'accent': '#0369a1',
      'success': '#15803d',
      'border': '#e5e7eb',
      'brandCoral': '#ff7a59',
      'scrim': '#00000080',
    },
    'spacing': {'none': 0, 'sm': 8, 'md': 12, 'xxl': 48},
    'radius': {'none': 0, 'md': 12, 'card': 24},
    'typography': {
      'bodyM': {'fontSize': 14, 'lineHeight': 1.5, 'fontWeight': 400, 'role': 'body'},
      'titleM': {
        'fontSize': 18,
        'lineHeight': 1.3333,
        'fontWeight': 700,
        'letterSpacing': -0.2,
        'role': 'heading',
      },
      'hero': {'fontSize': 40, 'lineHeight': 1.1, 'fontWeight': 800, 'role': 'heading'},
    },
    'elevation': {
      'none': <Object?>[],
      'card': [
        {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0, 'color': '#111827', 'opacity': 0.1},
        {'offsetX': 0, 'offsetY': 8, 'blur': 24, 'spread': -4, 'color': '#111827', 'opacity': 0.2},
      ],
    },
    'gradient': {
      'missionSunset': {
        'angle': 135,
        'stops': [
          {'color': '#ff7a59', 'position': 0},
          {'color': '#c13584', 'position': 1},
        ],
      },
    },
  });

  group('colour', () {
    test('three forms of reference', () {
      expect(theme.resolveColor(const ColorRef.token('brandCoral')), const Color(0xFFFF7A59));
      expect(
        theme.resolveColor(const TokenColorRef('brandCoral', opacity: 0.2)),
        const Color(0xFFFF7A59).withValues(alpha: 0.2),
      );
      expect(
        theme.resolveColor(const CustomColorRef(Color(0xFF123456))),
        const Color(0xFF123456),
      );
      expect(
        theme.resolveColor(const CustomColorRef(Color(0xFF123456), opacity: 0.5)),
        const Color(0xFF123456).withValues(alpha: 0.5),
      );
    });

    test('opacities MULTIPLY: a tint of a semi-transparent token is a quarter, not a half', () {
      // Otherwise the same tint would mean different things depending on whether the
      // token has its own alpha.
      final half = theme.resolveColor(const ColorRef.token('scrim'))!;
      expect(half.a, closeTo(128 / 255, 1e-6));

      final quarter = theme.resolveColor(const TokenColorRef('scrim', opacity: 0.5))!;
      expect(quarter.a, closeTo(128 / 255 / 2, 1e-6));
    });

    test('opacity 0 and 1 are legal edges', () {
      expect(theme.resolveColor(const TokenColorRef('primary', opacity: 0))!.a, 0);
      expect(theme.resolveColor(const TokenColorRef('primary', opacity: 1)), const Color(0xFF4F46E5));
    });

    test('no token - `null`, not a "similar" colour', () {
      expect(theme.resolveColor(const ColorRef.token('brandTeal')), isNull);
      expect(theme.resolveColor(const TokenColorRef('brandTeal', opacity: 0.5)), isNull);
      // REVERSED by `partialThemeDefaults`. Previously a core name THIS theme did not have
      // was also "absent" for a document reference. Now a missing core name is taken
      // from the built-in theme of the same brightness - so `warning` resolves to its
      // value instead of `null`. "Absent" stayed for
      // custom names that nobody knows.
      expect(
        theme.resolveColor(const ColorRef.token('warning')),
        ThemeContract.fallback().defaultTheme.color(ColorToken.warning),
      );
    });

    test('an optional state colour falls back to the fallback token - with a tint too', () {
      // `x-optionalColors.fallbacks`: `locked → muted`, `completed → success`.
      expect(theme.resolveColor(const ColorRef.token('locked')), const Color(0xFF6B7280));
      expect(
        theme.resolveColor(const TokenColorRef('completed', opacity: 0.5)),
        const Color(0xFF15803D).withValues(alpha: 0.5),
      );
    });
  });

  group('spacing and radius', () {
    test('a token is a theme value, a number is as is', () {
      expect(theme.resolveSpacing(const ScaleRef.token('md')), 12);
      expect(theme.resolveSpacing(const ScaleRef.token('xxl')), 48);
      expect(theme.resolveSpacing(const ScaleRef.value(20)), 20);
      expect(theme.resolveRadius(const ScaleRef.token('card')), 24);
      expect(theme.resolveRadius(const ScaleRef.value(6)), 6);
    });

    test('scales are not mixed: a spacing name is not a radius', () {
      expect(theme.resolveRadius(const ScaleRef.token('xxl')), isNull);
      expect(theme.resolveSpacing(const ScaleRef.token('card')), isNull);
    });

    test('box paddings: sides are logical, an unnamed one is zero', () {
      expect(
        theme.resolveBoxSpacing(const BoxSpacing.all(ScaleRef.token('md'))),
        const EdgeInsetsDirectional.all(12),
      );
      expect(
        theme.resolveBoxSpacing(
          const BoxSpacing.sides(top: ScaleRef.value(20), end: ScaleRef.token('sm')),
        ),
        const EdgeInsetsDirectional.only(top: 20, end: 8),
      );
    });

    test('a side with an unknown token is zero, the rest applies', () {
      expect(
        theme.resolveBoxSpacing(
          const BoxSpacing.sides(top: ScaleRef.token('huge'), start: ScaleRef.token('md')),
        ),
        const EdgeInsetsDirectional.only(start: 12),
      );
      expect(
        theme.resolveBoxRadius(
          const BoxRadius.corners(topStart: ScaleRef.token('blob'), bottomEnd: ScaleRef.token('card')),
        ),
        const BorderRadiusDirectional.only(bottomEnd: Radius.circular(24)),
      );
    });

    test('`unknownBoxToken: omit-field` - ONE value with an unknown token is not applied', () {
      expect(theme.resolveBoxSpacing(const BoxSpacing.all(ScaleRef.token('huge'))), isNull);
      expect(theme.resolveBoxRadius(const BoxRadius.all(ScaleRef.token('blob'))), isNull);
      expect(theme.resolveBoxSpacing(null), isNull);
    });

    test('`unknownSideToken: side-is-zero` - a shape with sides applies ALWAYS', () {
      // Contract 9 changed the renderer decision: previously, when no named side
      // resolved, the property was not applied. Now a shape with sides is
      // zero on every unknown side, even on all of them
      // (for a button this means "remove the built-in padding", not "keep it").
      expect(
        theme.resolveBoxSpacing(const BoxSpacing.sides(top: ScaleRef.token('huge'))),
        EdgeInsetsDirectional.zero,
      );
      expect(
        theme.resolveBoxSpacing(
          const BoxSpacing.sides(top: ScaleRef.token('a'), end: ScaleRef.token('b')),
        ),
        EdgeInsetsDirectional.zero,
      );
      expect(
        theme.resolveBoxRadius(const BoxRadius.corners(topStart: ScaleRef.token('blob'))),
        BorderRadiusDirectional.zero,
      );
      // Parsing: the same two forms from JSON.
      // A broken value SHAPE of a side is the same as an unknown token:
      // the side is zero, the field applies.
      expect(
        theme.resolveBoxSpacing(BoxSpacing.tryParse({'top': 'Bad!', 'start': 'md'})),
        const EdgeInsetsDirectional.only(start: 12),
      );
      expect(
        theme.resolveBoxSpacing(BoxSpacing.tryParse({'top': 'Bad!', 'end': true})),
        EdgeInsetsDirectional.zero,
      );
      expect(
        theme.resolveBoxRadius(BoxRadius.tryParse({'topStart': 'Bad!'})),
        BorderRadiusDirectional.zero,
      );
      expect(BoxSpacing.tryParse({}), isNull);
      expect(BoxSpacing.tryParse('huge')!.isSingleValue, isTrue);
      expect(BoxSpacing.tryParse({'top': 'huge'})!.isSingleValue, isFalse);
      expect(BoxRadius.tryParse({'topStart': 'blob'})!.isSingleValue, isFalse);
    });

    test('per-corner radii mirror in right-to-left writing', () {
      final radius = theme.resolveBoxRadius(
        const BoxRadius.corners(topStart: ScaleRef.value(24), bottomEnd: ScaleRef.value(4)),
      )!;

      final ltr = radius.resolve(TextDirection.ltr);
      expect(ltr.topLeft, const Radius.circular(24));
      expect(ltr.bottomRight, const Radius.circular(4));
      expect(ltr.topRight, Radius.zero);

      final rtl = radius.resolve(TextDirection.rtl);
      expect(rtl.topRight, const Radius.circular(24));
      expect(rtl.bottomLeft, const Radius.circular(4));
      expect(rtl.topLeft, Radius.zero);
    });
  });

  group('font', () {
    test('a token gives the theme style together with the role family', () {
      final style = theme.resolveTypography(const TypographyRef('titleM'))!;

      expect(style.fontSize, 18);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.height, 1.3333);
      expect(style.letterSpacing, -0.2);
      expect(style.fontFamily, 'Heading Face');
    });

    test('an edit replaces exactly its own field, the family stays with the token', () {
      final style = theme.resolveTypography(const TypographyRef('titleM', fontSize: 28))!;

      expect(style.fontSize, 28);
      expect(style.fontWeight, FontWeight.w700, reason: 'the weight was not edited');
      expect(style.letterSpacing, -0.2);
      expect(style.fontFamily, 'Heading Face');
      // `lineHeight` is a multiplier, and it multiplies the already EDITED size: 28 x 1.3333,
      // not the old absolute height. In Flutter this comes out by itself -
      // `TextStyle.height` is also a multiplier.
      expect(style.height, 1.3333);
    });

    test('all four edits together', () {
      final style = theme.resolveTypography(
        const TypographyRef(
          'bodyM',
          fontSize: 22,
          fontWeight: 600,
          lineHeight: 1.2,
          letterSpacing: 0.5,
        ),
      )!;

      expect(style.fontSize, 22);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.height, 1.2);
      expect(style.letterSpacing, 0.5);
      expect(style.fontFamily, 'Body Face');
    });

    test('a custom font token is the same as a core token', () {
      expect(theme.resolveTypography(const TypographyRef('hero'))!.fontSize, 40);
    });

    test('no token - no style, even if edits are named', () {
      // The contract has no own style "from scratch": the family is always given by a token.
      expect(theme.resolveTypography(const TypographyRef('giant', fontSize: 60)), isNull);
    });
  });

  group('gradient', () {
    test('a theme token', () {
      final gradient = theme.resolveGradient(const TokenGradientRef('missionSunset'))!;

      expect(gradient.colors, [const Color(0xFFFF7A59), const Color(0xFFC13584)]);
      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
    });

    test('own gradient: colours are references, the angle is from the same table', () {
      final gradient = theme.resolveGradient(
        const CustomGradientRef(
          angle: 90,
          stops: [
            (color: ColorRef.token('primary'), position: 0),
            (color: TokenColorRef('brandCoral', opacity: 0.5), position: 0.6),
            (color: CustomColorRef(Color(0xFF000000)), position: 1),
          ],
        ),
      )!;

      expect(gradient.begin, Alignment.centerLeft);
      expect(gradient.end, Alignment.centerRight);
      expect(gradient.colors, [
        const Color(0xFF4F46E5),
        const Color(0xFFFF7A59).withValues(alpha: 0.5),
        const Color(0xFF000000),
      ]);
      expect(gradient.stops, [0, 0.6, 1]);
    });

    test('all eight angles of an own gradient - the same Alignment pair as the theme', () {
      const expected = <int, (Alignment, Alignment)>{
        0: (Alignment.bottomCenter, Alignment.topCenter),
        45: (Alignment.bottomLeft, Alignment.topRight),
        90: (Alignment.centerLeft, Alignment.centerRight),
        135: (Alignment.topLeft, Alignment.bottomRight),
        180: (Alignment.topCenter, Alignment.bottomCenter),
        225: (Alignment.topRight, Alignment.bottomLeft),
        270: (Alignment.centerRight, Alignment.centerLeft),
        315: (Alignment.bottomRight, Alignment.topLeft),
      };
      for (final entry in expected.entries) {
        final gradient = theme.resolveGradient(
          CustomGradientRef(
            angle: entry.key.toDouble(),
            stops: const [
              (color: ColorRef.token('primary'), position: 0),
              (color: ColorRef.token('accent'), position: 1),
            ],
          ),
        )!;
        expect((gradient.begin, gradient.end), entry.value, reason: '${entry.key}°');
        // The diagonal - with exact CSS geometry, the axial one - an ordinary gradient.
        expect(
          gradient is CornerGradient,
          kCornerGradientAngles.contains(entry.key),
          reason: '${entry.key}°',
        );
      }
    });

    test('a stop on an unknown token cancels the gradient WHOLE', () {
      expect(
        theme.resolveGradient(
          const CustomGradientRef(
            angle: 90,
            stops: [
              (color: ColorRef.token('primary'), position: 0),
              (color: ColorRef.token('brandTeal'), position: 0.5),
              (color: ColorRef.token('accent'), position: 1),
            ],
          ),
        ),
        isNull,
      );
    });

    test('unorderedGradient: omit-field - backward stops are neither drawn nor sorted', () {
      const unordered = CustomGradientRef(
        angle: 90,
        stops: [
          (color: ColorRef.token('primary'), position: 0.8),
          (color: ColorRef.token('accent'), position: 0.2),
        ],
      );
      expect(unordered.isOrdered, isFalse);
      expect(theme.resolveGradient(unordered), isNull);

      // Equal positions are legal: it is a hard colour edge, not an order violation.
      const hardStop = CustomGradientRef(
        angle: 90,
        stops: [
          (color: ColorRef.token('primary'), position: 0),
          (color: ColorRef.token('primary'), position: 0.5),
          (color: ColorRef.token('accent'), position: 0.5),
          (color: ColorRef.token('accent'), position: 1),
        ],
      );
      expect(hardStop.isOrdered, isTrue);
      expect(theme.resolveGradient(hardStop), isNotNull);
    });

    test('an angle outside the eight allowed - no gradient', () {
      expect(
        theme.resolveGradient(
          const CustomGradientRef(
            angle: 30,
            stops: [
              (color: ColorRef.token('primary'), position: 0),
              (color: ColorRef.token('accent'), position: 1),
            ],
          ),
        ),
        isNull,
      );
    });
  });

  group('diagonal gradient: CSS `to <corner>` geometry', () {
    /*
     * THE MOST IMPORTANT THING ABOUT DIAGONALS. "From corner to corner" says where the start
     * and end are - but on a NON-SQUARE box that is not enough. In CSS `to bottom right` the
     * 50% line passes through the two OTHER corners of the rectangle. A naive
     * `LinearGradient(topLeft -> bottomRight)` draws lines of equal colour
     * perpendicular to the diagonal, and on a 2:1 card the middle of the gradient no
     * longer passes through the other corners - the top right corner gets 80% of the way
     * instead of 50%. Two readers would draw the same card differently.
     */
    const size = Size(200, 100);

    CornerGradient cornerOf(int angle) =>
        theme.resolveGradient(
              CustomGradientRef(
                angle: angle.toDouble(),
                stops: const [
                  (color: CustomColorRef(Color(0xFF000000)), position: 0),
                  (color: CustomColorRef(Color(0xFFFFFFFF)), position: 1),
                ],
              ),
            )!
            as CornerGradient;

    Offset cornerAt(Alignment alignment) => alignment.alongSize(size);

    test('start and end are in the corners, the middle is on the SECOND diagonal (all four)', () {
      for (final angle in kCornerGradientAngles) {
        final gradient = cornerOf(angle);
        final begin = gradient.begin as Alignment;
        final end = gradient.end as Alignment;
        // The two other corners of the rectangle.
        final others = [Alignment(begin.x, end.y), Alignment(end.x, begin.y)];

        expect(gradient.positionAt(cornerAt(begin), size), closeTo(0, 1e-9), reason: '$angle°');
        expect(gradient.positionAt(cornerAt(end), size), closeTo(1, 1e-9), reason: '$angle°');
        for (final other in others) {
          expect(
            gradient.positionAt(cornerAt(other), size),
            closeTo(0.5, 1e-9),
            reason: '$angle°: the 50% isoline must pass through corner $other',
          );
        }
        expect(gradient.positionAt(size.center(Offset.zero), size), closeTo(0.5, 1e-9));
      }
    });

    testWidgets('on a 2:1 card the other two corners are DRAWN with the gradient middle', (tester) async {
      // The shader itself is checked, not a formula next to it: black -> white,
      // and the pixels near the two "other" corners must be exactly mid grey.
      // A naive `Alignment` pair would give 80% and 20% there (204 and 51).
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.fromSize(
              size: size,
              child: DecoratedBox(decoration: BoxDecoration(gradient: cornerOf(135))),
            ),
          ),
        ),
      );

      final bytes = await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!;
      });

      int grayAt(int x, int y) => bytes!.getUint8((y * size.width.toInt() + x) * 4);

      // 135 - from top left (black) to bottom right (white).
      expect(grayAt(1, 1), lessThan(8));
      expect(grayAt(198, 98), greaterThan(247));
      // The two other corners are the middle. Tolerance of one pixel from the corner and for smoothing.
      expect(grayAt(198, 1), inInclusiveRange(118, 138));
      expect(grayAt(1, 98), inInclusiveRange(118, 138));
      // The centre is the middle too, and the whole second diagonal is the same.
      expect(grayAt(100, 50), inInclusiveRange(120, 135));
      expect(grayAt(150, 25), inInclusiveRange(120, 135));
      expect(grayAt(50, 75), inInclusiveRange(120, 135));
    });

    test('formula from `x-gradientGeometry`: the line end is where the artifact says', () {
      // end = (0.5 + sx*h^2/(w^2+h^2), 0.5 + sy*w^2/(w^2+h^2)) in normalised
      // coordinates; the start is symmetric. The shader computes differently (a unit
      // square stretched by a matrix), so agreement with the formula is a check of two
      // independent paths to the same geometry.
      const signs = <int, (int, int)>{45: (1, -1), 135: (1, 1), 225: (-1, 1), 315: (-1, -1)};
      for (final box in const [Size(200, 100), Size(100, 300), Size(120, 120)]) {
        final w2 = box.width * box.width;
        final h2 = box.height * box.height;
        for (final entry in signs.entries) {
          final (sx, sy) = entry.value;
          final gradient = cornerOf(entry.key);
          final dx = sx * h2 / (w2 + h2);
          final dy = sy * w2 / (w2 + h2);
          final end = Offset((0.5 + dx) * box.width, (0.5 + dy) * box.height);
          final start = Offset((0.5 - dx) * box.width, (0.5 - dy) * box.height);
          final reason = '${entry.key}° on $box';

          expect(gradient.positionAt(end, box), closeTo(1, 1e-9), reason: reason);
          expect(gradient.positionAt(start, box), closeTo(0, 1e-9), reason: reason);
          // The gradient line is PERPENDICULAR to the isolines in pixels: a shift along
          // the perpendicular to it does not change the path fraction.
          final line = end - start;
          final across = Offset(-line.dy, line.dx);
          expect(gradient.positionAt(end + across * 0.3, box), closeTo(1, 1e-9), reason: reason);
          expect(gradient.positionAt(start - across * 0.7, box), closeTo(0, 1e-9), reason: reason);
        }
      }
    });

    test('an axial gradient stays ordinary: it needs no stretching', () {
      final axis = theme.resolveGradient(
        const CustomGradientRef(
          angle: 180,
          stops: [
            (color: ColorRef.token('primary'), position: 0),
            (color: ColorRef.token('accent'), position: 1),
          ],
        ),
      )!;
      expect(axis, isNot(isA<CornerGradient>()));
    });

    test('a degenerate box does not crash the shader', () {
      final gradient = cornerOf(45);
      expect(() => gradient.createShader(Rect.zero), returnsNormally);
      expect(() => gradient.createShader(const Rect.fromLTWH(0, 0, 100, 0)), returnsNormally);
    });
  });

  group('shadow', () {
    test('a theme token: the order is reversed for Flutter (the first is the nearest)', () {
      final shadows = theme.resolveShadow(const TokenShadowRef('card'))!;

      expect(shadows, hasLength(2));
      // The first contract layer is the nearest to the element, i.e. drawn
      // LAST: Flutter puts `boxShadow` in list order.
      expect(shadows.last.blurRadius, 2);
      expect(shadows.first.blurRadius, 24);
      expect(shadows.first.spreadRadius, -4);
    });

    test('`none` is an empty list, and that is not the same as "no shadow in the theme"', () {
      expect(theme.resolveShadow(const TokenShadowRef('none')), isEmpty);
      expect(theme.resolveShadow(const TokenShadowRef('glow')), isNull);
    });

    test('own shadow: opacity is in the colour reference, the order is the same', () {
      final shadows = theme.resolveShadow(
        const CustomShadowRef([
          ShadowLayerRef(
            offsetX: 0,
            offsetY: 1,
            blur: 2,
            spread: 0,
            color: TokenColorRef('onSurface', opacity: 0.12),
          ),
          ShadowLayerRef(
            offsetX: 2,
            offsetY: 12,
            blur: 32,
            spread: -6,
            color: CustomColorRef(Color(0xFF000000), opacity: 0.25),
          ),
        ]),
      )!;

      expect(shadows, hasLength(2));
      expect(shadows.last.color, const Color(0xFF111827).withValues(alpha: 0.12));
      expect(shadows.last.offset, const Offset(0, 1));
      expect(shadows.first.color, const Color(0xFF000000).withValues(alpha: 0.25));
      expect(shadows.first.offset, const Offset(2, 12));
      expect(shadows.first.blurRadius, 32);
      expect(shadows.first.spreadRadius, -6);
    });

    test('a layer on an unknown token cancels the shadow WHOLE', () {
      expect(
        theme.resolveShadow(
          const CustomShadowRef([
            ShadowLayerRef(
              offsetX: 0,
              offsetY: 1,
              blur: 2,
              spread: 0,
              color: ColorRef.token('onSurface'),
            ),
            ShadowLayerRef(
              offsetX: 0,
              offsetY: 1,
              blur: 2,
              spread: 0,
              color: ColorRef.token('brandTeal'),
            ),
          ]),
        ),
        isNull,
      );
    });
  });

  group('`props` field with a default', () {
    test('a number and an own token act, an unknown token gives the field default', () {
      expect(theme.fieldSpacing(FieldSpacing.parse(20, fieldDefault: SpacingToken.sm)), 20);
      expect(theme.fieldSpacing(FieldSpacing.parse('xxl', fieldDefault: SpacingToken.sm)), 48);
      expect(theme.fieldSpacing(FieldSpacing.parse('huge', fieldDefault: SpacingToken.sm)), 8);
      expect(
        theme.fieldColor(
          FieldColor.parse(const {'token': 'brandCoral', 'opacity': 0.5}, fieldDefault: ColorToken.border),
        ),
        const Color(0xFFFF7A59).withValues(alpha: 0.5),
      );
      expect(
        theme.fieldColor(FieldColor.parse(const {'value': '#010203'}, fieldDefault: ColorToken.border)),
        const Color(0xFF010203),
      );
      expect(
        theme.fieldColor(FieldColor.parse('brandTeal', fieldDefault: ColorToken.border)),
        const Color(0xFFE5E7EB),
      );
    });
  });
}
