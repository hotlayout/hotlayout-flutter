import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';

import 'support/fixtures.dart';

/// Shared node style (9.0.0): PARSING.
///
/// Before 9.0.0 this file guarded the rule "style beats props": text color
/// lived in two places, and both platforms had to answer the same way as to
/// which one wins. That rule is gone (appearance lives only in `style`), so
/// what needs guarding now is different: that EVERY value form reaches the
/// model, and that parsing never throws. How a style is painted: `style_box_test.dart`.
void main() {
  NodeStyle? style(Object? raw) => NodeStyle.parse(raw);

  group('each reference form', () {
    test('color: token, token tint, own value', () {
      expect(style({'color': 'accent'})!.color, const ColorRef.token('accent'));
      expect(
        style({'color': {'token': 'accent', 'opacity': 0.1}})!.color,
        const TokenColorRef('accent', opacity: 0.1),
      );
      expect(
        style({'color': {'value': '#ff7a59'}})!.color,
        const CustomColorRef(Color(0xFFFF7A59)),
      );
      expect(
        style({'color': {'value': '#ff7a59', 'opacity': 0.5}})!.color,
        const CustomColorRef(Color(0xFFFF7A59), opacity: 0.5),
      );
    });

    test('color: a custom token name is the same kind of reference as a core name', () {
      // Parsing does not check the name against a list: the theme declares `brandCoral`.
      expect(style({'color': 'brandCoral'})!.color, const ColorRef.token('brandCoral'));
    });

    test('padding and radius: token or number', () {
      expect(style({'padding': 'md'})!.padding, const BoxSpacing.all(ScaleRef.token('md')));
      expect(style({'padding': 20})!.padding, const BoxSpacing.all(ScaleRef.value(20)));
      expect(style({'radius': 'pill'})!.radius, const BoxRadius.all(ScaleRef.token('pill')));
      expect(style({'radius': 24})!.radius, const BoxRadius.all(ScaleRef.value(24)));
    });

    test('side paddings: logical, an unnamed side is absent', () {
      final padding = style({
        'padding': {'top': 20, 'end': 'lg', 'start': 'xs'},
      })!.padding!;

      expect(padding.top, const ScaleRef.value(20));
      expect(padding.end, const ScaleRef.token('lg'));
      expect(padding.start, const ScaleRef.token('xs'));
      expect(padding.bottom, isNull, reason: 'an unnamed side is zero, not a default');
      // `margin` has the same form.
      expect(style({'margin': {'bottom': 'sm'}})!.margin!.bottom, const ScaleRef.token('sm'));
    });

    test('corner radii: logical', () {
      final radius = style({
        'radius': {'topStart': 24, 'topEnd': 'lg'},
      })!.radius!;

      expect(radius.topStart, const ScaleRef.value(24));
      expect(radius.topEnd, const ScaleRef.token('lg'));
      expect(radius.bottomEnd, isNull);
      expect(radius.bottomStart, isNull);
    });

    test('font: token or token with adjustments', () {
      expect(style({'typography': 'titleM'})!.typography, const TypographyRef('titleM'));
      expect(
        style({
          'typography': {
            'token': 'titleM',
            'fontSize': 28,
            'fontWeight': 700,
            'lineHeight': 1.2,
            'letterSpacing': -0.5,
          },
        })!.typography,
        const TypographyRef(
          'titleM',
          fontSize: 28,
          fontWeight: 700,
          lineHeight: 1.2,
          letterSpacing: -0.5,
        ),
      );
    });

    test('size: number or binding, on all six fields', () {
      for (final field in ['width', 'height', 'minWidth', 'maxWidth', 'minHeight', 'maxHeight']) {
        BindableNumber? read(NodeStyle s) => switch (field) {
          'width' => s.width,
          'height' => s.height,
          'minWidth' => s.minWidth,
          'maxWidth' => s.maxWidth,
          'minHeight' => s.minHeight,
          _ => s.maxHeight,
        };

        final literal = read(style({field: 120})!);
        expect(literal, isA<LiteralNumber>(), reason: field);
        expect((literal! as LiteralNumber).value, 120, reason: field);

        final bound = read(style({
          field: {'kind': 'binding', 'path': 'task.progress', 'fallback': 60},
        })!);
        expect(bound, isA<BoundNumber>(), reason: field);
        expect((bound! as BoundNumber).path, 'task.progress');
        expect((bound as BoundNumber).fallback, 60);
      }
    });

    test('border: width and color reference', () {
      final border = style({
        'border': {'width': 2, 'color': {'token': 'primary', 'opacity': 0.4}},
      })!.border!;

      expect(border.width, 2);
      expect(border.color, const TokenColorRef('primary', opacity: 0.4));
    });

    test('background: color, gradient (token and own), image', () {
      expect(
        style({'background': {'kind': 'color', 'color': {'value': '#101010'}}})!.background,
        const ColorBackground(CustomColorRef(Color(0xFF101010))),
      );
      expect(
        style({'background': {'kind': 'gradient', 'gradient': 'missionSunset'}})!.background,
        const GradientBackground(TokenGradientRef('missionSunset')),
      );

      final custom = style({
        'background': {
          'kind': 'gradient',
          'gradient': {
            'angle': 135,
            'stops': [
              {'color': 'primary', 'position': 0},
              {'color': {'value': '#c13584'}, 'position': 1},
            ],
          },
        },
      })!.background! as GradientBackground;
      final gradient = custom.gradient as CustomGradientRef;
      expect(gradient.angle, 135);
      expect(gradient.stops.map((stop) => stop.position), [0, 1]);
      expect(gradient.stops.first.color, const ColorRef.token('primary'));
      expect(gradient.isOrdered, isTrue);

      final image = style({
        'background': {
          'kind': 'image',
          'source': {'kind': 'url', 'url': 'https://cdn.example.com/bg.png'},
          'fit': 'contain',
        },
      })!.background! as ImageBackground;
      expect(image.source, isA<UrlImageSource>());
      expect(image.fit, ImageFitToken.contain);
    });

    test('shadow: token or own layers, opacity inside the color reference', () {
      expect(style({'shadow': 'card'})!.shadow, const TokenShadowRef('card'));

      final custom = style({
        'shadow': [
          {
            'offsetX': 0,
            'offsetY': 8,
            'blur': 24,
            'spread': -4,
            'color': {'token': 'onSurface', 'opacity': 0.12},
          },
        ],
      })!.shadow! as CustomShadowRef;
      expect(custom.layers.single.offsetY, 8);
      expect(custom.layers.single.blur, 24);
      expect(custom.layers.single.spread, -4);
      expect(custom.layers.single.color, const TokenColorRef('onSurface', opacity: 0.12));
    });

    test('opacity is a number 0..1, and zero is legal', () {
      expect(style({'opacity': 0.5})!.opacity, 0.5);
      expect(style({'opacity': 0})!.opacity, 0);
      expect(style({'opacity': 1})!.opacity, 1);
    });
  });

  group('parsing never throws: policy `unknownStyleField: ignore-field`', () {
    test('a field from a future minor is skipped, the rest of the style is painted', () {
      final parsed = style({
        'color': 'accent',
        'backdropBlur': 12,
        'transform': {'rotate': 45},
      });

      expect(parsed, isNotNull, reason: 'one unknown field must not cancel the whole look');
      expect(parsed!.color, const ColorRef.token('accent'));
    });

    test('a style made ONLY of unknown fields reads as absent', () {
      expect(style({'backdropBlur': 12}), isNull);
    });

    test('an empty style and garbage instead of a style both mean "no style"', () {
      // The schema rejects an empty object (`minProperties: 1`), but the reader must be
      // more tolerant than the schema: the document comes from the network.
      expect(style(const <String, Object?>{}), isNull);
      expect(style('зовсім не обʼєкт'), isNull);
      expect(style(42), isNull);
      expect(style(null), isNull);
      expect(style(const [1, 2]), isNull);
    });

    test('a known field of the wrong shape is skipped on its own, neighbours stay', () {
      const broken = <String, Object?>{
        'color': {'token': 'accent'}, // no opacity: an extra form, but understandable
        'typography': 42,
        'padding': true,
        'margin': <String, Object?>{}, // `margin: {}` says the same as an absent field
        'width': 'широко',
        'height': {'kind': 'binding', 'path': 'x'}, // nothing to paint with, no fallback
        'radius': <String, Object?>{},
        'border': {'width': 1}, // no color
        'background': 'secondary', // 8.x form: a token string
        'shadow': <Object?>[], // "no shadow" is an absent field
        'opacity': 'напівпрозоро',
      };
      final parsed = style(broken)!;

      expect(parsed.color, const ColorRef.token('accent'));
      expect(parsed.typography, isNull);
      expect(parsed.padding, isNull);
      expect(parsed.margin, isNull);
      // `nonNumericLiteral: 'lower-bound'`: where the schema expects a NUMBER within
      // bounds and a string stands there, the field's lower bound applies, not
      // "the field does not apply". The assertions are INVERTED here (they used to say `isNull`):
      // a word in place of a width is 1 dp, a word in place of opacity is 0.
      expect((parsed.width! as LiteralNumber).value, kStyleSizeMin);
      expect(parsed.height, isNull, reason: 'a binding without fallback is another form, not a number');
      expect(parsed.radius, isNull);
      expect(parsed.border, isNull);
      expect(parsed.background, isNull);
      expect(parsed.shadow, isNull);
      expect(parsed.opacity, 0);
    });

    test('a string that cannot be a token name is not a reference', () {
      // The most common such garbage is a raw hex where the schema expects a token.
      expect(style({'color': '#ff0000'}), isNull);
      expect(style({'padding': '12px'}), isNull);
      expect(style({'shadow': 'box shadow'}), isNull);
    });

    test('a gradient with a broken stop is cancelled AS A WHOLE, it does not just lose the stop', () {
      // A gradient missing one stop is a DIFFERENT gradient and would look as
      // intended. Same for a shadow missing one layer.
      expect(
        style({
          'background': {
            'kind': 'gradient',
            'gradient': {
              'angle': 90,
              'stops': [
                {'color': 'primary', 'position': 0},
                {'color': '#не-колір', 'position': 0.5},
                {'color': 'accent', 'position': 1},
              ],
            },
          },
        }),
        isNull,
      );
      expect(
        style({
          'shadow': [
            {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0, 'color': 'onSurface'},
            {'offsetX': 0, 'offsetY': 1, 'blur': 2, 'spread': 0},
          ],
        }),
        isNull,
      );
    });

    test('a number outside the schema bounds is clamped, it does not reach Flutter as is', () {
      // The builder will not produce this, but the document could come from elsewhere. And in
      // Flutter a negative padding, opacity 1.5 or negative blur is an
      // assert, not an ugly look.
      final parsed = style({
        'padding': -8,
        'margin': 999,
        'radius': 4096,
        'opacity': 1.5,
        'width': 0,
        'height': 50000,
        'border': {'width': 99, 'color': 'border'},
        'typography': {'token': 'bodyM', 'fontSize': 2, 'fontWeight': 1500, 'lineHeight': 0},
        'shadow': [
          {'offsetX': 500, 'offsetY': -500, 'blur': -5, 'spread': 500, 'color': 'onSurface'},
        ],
      })!;

      expect(parsed.padding, const BoxSpacing.all(ScaleRef.value(0)));
      expect(parsed.margin, const BoxSpacing.all(ScaleRef.value(kMaxSpacingPx)));
      expect(parsed.radius, const BoxRadius.all(ScaleRef.value(kMaxRadiusPx)));
      expect(parsed.opacity, 1);
      expect((parsed.width! as LiteralNumber).value, kStyleSizeMin);
      expect((parsed.height! as LiteralNumber).value, kStyleSizeMax);
      expect(parsed.border!.width, kMaxBorderWidthPx);
      expect(parsed.typography!.fontSize, kMinFontSizePx);
      expect(parsed.typography!.fontWeight, 900);
      expect(parsed.typography!.lineHeight, kMinLineHeight);
      final layer = (parsed.shadow! as CustomShadowRef).layers.single;
      expect(layer.offsetX, kMaxShadowOffsetPx);
      expect(layer.offsetY, -kMaxShadowOffsetPx);
      expect(layer.blur, 0);
      expect(layer.spread, kMaxShadowSpreadPx);
    });

    test('NaN is not a number (lower bound), infinity is a number out of bounds (bound)', () {
      // Inverted for `nonNumericLiteral` / `literalOutOfRange`:
      // both used to read as "no field". `NaN` is not a number, so the lower
      // bound applies; +-infinity is a number, only out of bounds, so it is clamped.
      expect(style({'opacity': double.nan})!.opacity, 0);
      expect(style({'padding': double.infinity})!.padding, const BoxSpacing.all(ScaleRef.value(kMaxSpacingPx)));
      expect((style({'width': double.negativeInfinity})!.width! as LiteralNumber).value, kStyleSizeMin);
    });
  });

  group('style on a node', () {
    TextNode parseText({Object? style}) {
      final doc = docWith([
        {
          'id': 'text-1',
          'type': 'Text',
          'props': {
            'content': {'kind': 'literal', 'value': 'Привіт'},
          },
          'style': ?style,
        },
      ]);
      return doc.initialScreen.root.children.first as TextNode;
    }

    test('a node without a style has none', () {
      expect(parseText().style, isNull);
    });

    test('the style sits on the node raw, without overlay on props', () {
      // Before 9.0.0 color and font from here were overlaid on `props` during parsing
      // ("style beats props"). `Text.props` no longer has these fields, so there is
      // nothing to overlay: the node simply carries its style to the renderer.
      final node = parseText(style: const {'color': 'accent', 'typography': 'titleM'});

      expect(node.style!.color, const ColorRef.token('accent'));
      expect(node.style!.typography, const TypographyRef('titleM'));
    });

    test('appearance fields left in props (an 8.x document) do not act on the node', () {
      final node =
          docWith([
                {
                  'id': 'text-1',
                  'type': 'Text',
                  'props': {
                    'content': {'kind': 'literal', 'value': 'Привіт'},
                    'color': 'accent',
                    'typography': 'titleM',
                  },
                },
              ]).initialScreen.root.children.first
              as TextNode;

      expect(node.style, isNull);
    });
  });

  group('state overlay: by TOP-LEVEL fields', () {
    test('what the state names wins, what it does not name stays base', () {
      final merged = style({'color': 'muted'})!.over(style({'color': 'accent', 'typography': 'titleM'}));

      expect(merged.color, const ColorRef.token('muted'));
      expect(merged.typography, const TypographyRef('titleM'));
    });

    test('padding in a state replaces the base AS A WHOLE, not per side', () {
      // A deep merge has no way to say "this state has NO top padding": a side
      // the state did not name would quietly stay at the base value.
      final merged = style({
        'padding': {'top': 'lg'},
      })!.over(style({
        'padding': {'top': 'sm', 'start': 'md', 'end': 'md', 'bottom': 'sm'},
      }));

      expect(merged.padding!.top, const ScaleRef.token('lg'));
      expect(merged.padding!.start, isNull);
      expect(merged.padding!.end, isNull);
      expect(merged.padding!.bottom, isNull);
    });

    test('border, radius and font with adjustments are also replaced as a whole', () {
      final merged = style({
        'border': {'width': 2, 'color': 'danger'},
        'radius': {'topStart': 4},
        'typography': 'caption',
      })!.over(style({
        'border': {'width': 1, 'color': 'border'},
        'radius': 'lg',
        'typography': {'token': 'titleM', 'fontSize': 22},
      }));

      expect(merged.border!.width, 2);
      expect(merged.border!.color, const ColorRef.token('danger'));
      expect(merged.radius!.topStart, const ScaleRef.value(4));
      expect(merged.radius!.topEnd, isNull);
      expect(merged.typography, const TypographyRef('caption'), reason: 'size 22 did not leak through');
    });

    test('each of the fifteen fields is overlaid: none forgotten in `over`', () {
      const fields = <String, Object?>{
        'color': 'primary',
        'typography': 'titleM',
        'padding': 'md',
        'margin': 'sm',
        'width': 100,
        'height': 110,
        'minWidth': 10,
        'maxWidth': 200,
        'minHeight': 11,
        'maxHeight': 210,
        'radius': 'md',
        'border': {'width': 1, 'color': 'border'},
        'background': {'kind': 'color', 'color': 'surface'},
        'shadow': 'low',
        'opacity': 0.5,
      };
      for (final field in fields.keys) {
        final overlay = style({field: fields[field]})!;
        // Over an empty base the field must ARRIVE...
        final onto = overlay.over(style({'opacity': 0.25}));
        expect(onto.isEmpty, isFalse);
        // ...and the base under another state must SURVIVE.
        final other = field == 'opacity' ? {'color': 'muted'} : {'opacity': 0.25};
        final kept = style(other)!.over(overlay);
        expect(_fieldOf(kept, field), _fieldOf(overlay, field), reason: 'base style.$field is gone');
        expect(_fieldOf(onto, field), _fieldOf(overlay, field), reason: 'state style.$field did not arrive');
      }
    });
  });
}

Object? _fieldOf(NodeStyle style, String field) => switch (field) {
  'color' => style.color,
  'typography' => style.typography,
  'padding' => style.padding,
  'margin' => style.margin,
  'width' => (style.width as LiteralNumber?)?.value,
  'height' => (style.height as LiteralNumber?)?.value,
  'minWidth' => (style.minWidth as LiteralNumber?)?.value,
  'maxWidth' => (style.maxWidth as LiteralNumber?)?.value,
  'minHeight' => (style.minHeight as LiteralNumber?)?.value,
  'maxHeight' => (style.maxHeight as LiteralNumber?)?.value,
  'radius' => style.radius,
  'border' => style.border,
  'background' => style.background,
  'shadow' => style.shadow,
  'opacity' => style.opacity,
  _ => throw ArgumentError(field),
};
