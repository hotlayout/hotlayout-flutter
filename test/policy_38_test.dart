import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/fallback_theme.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// Contract 9 style and layout policy rows.
///
/// Every policy row and every concept from `x-style` / `x-style.layout` gets
/// TWO checks here: the mirror against the artifact (the row has not drifted)
/// and the BEHAVIOR as rendered (a mirror whose text matches while behavior
/// diverges is worse than no mirror).
void main() {
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
          as Map<String, Object?>;
  final policy = (schema['x-compatibility']! as Map<String, Object?>)['policy']! as Map<String, Object?>;
  final style = schema['x-style']! as Map<String, Object?>;
  final layout = style['layout']! as Map<String, Object?>;
  final theme = RenderTheme.fallback();

  const surface = {'kind': 'color', 'color': 'surface'};

  Map<String, Object?> box(String label, {Map<String, Object?>? style, String id = 'box'}) =>
      textNode(label, id: id, style: style);

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, Object?>> children, {
    RenderTheme? withTheme,
    Map<String, Object?> data = const {},
  }) => pumpDocument(
    tester,
    UiDocumentBuilder.bare(children),
    theme: withTheme ?? theme,
    data: data,
  );

  Rect boxRect(WidgetTester tester, String label) =>
      tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first);

  ChildNode parseNode(Map<String, Object?> json) => rootOf(docWith([json])).children.single;

  // ─────────────────────────────────────────────────── mirror against the artifact

  group('x-style mirror against the artifact', () {
    test('x-style rows added by the style decisions', () {
      expect(style['unknownTokenInCase'], 'keep-base-field');
      expect(style['tabTitleColorContext'], 'tab');
      expect(style['sizeIncludes'], kSizeIncludes);
      expect(style['boxTokenFields'], kBoxTokenFields);
      expect(style['weightShareIncludes'], kWeightShareIncludes);
      expect(layout['tightSlotNaturalWidth'], kTightSlotNaturalWidth);
      expect(style['fillScope'], 'direct-children-of-stack');

      final roles = style['roles']! as Map<String, Object?>;
      expect(roles['roleBorderAppliesTo'], 'role-with-border-slot');
      expect(roles['withoutBorderSlot'], 'no-border-no-space');
      expect(roles['neutral'], {'background': 'none', 'border': 'none', 'foreground': 'root-color'});
      // The neutral role's foreground is the ROOT color from `x-style.root`.
      expect((style['root']! as Map<String, Object?>)['color'], kRootTextColor);
    });

    test('list guard: an unknown x-style key is a decision the renderer does not know', () {
      expect(style.keys.toSet(), {
        'caseSelection', 'caseMerge', 'inherited', 'inheritance', 'root', 'colorParts',
        'secondaryOpacity', 'unknownInheritedToken', 'unknownTokenInCase',
        'tabTitleColorContext', 'readers', 'sides', 'unnamedSide', 'hiddenDefaults',
        'radiusClips', 'opacityAppliesTo', 'weightOverridesWidth', 'fillOverridesSize',
        'screenExcluded', 'sizeIncludes', 'boxTokenFields', 'fillScope', 'layout', 'roles',
        'weightShareIncludes',
      });
      expect(layout.keys.toSet(), {
        'iconGlyphTypography', 'iconGlyphMeasure', 'defaultIconSize', 'listTileIconSizes',
        'scrollableRow', 'tightSlots', 'tightSlotNaturalWidth', 'sizedBoxKeys', 'column', 'badgePadding',
        'buttonPadding', 'buttonTypography', 'buttonSize', 'row', 'iconGlyphBox',
        // 9.5.0: button sizes, icon button, the "icon beside text" rule and
        // the color of a row's trailing text. Values are checked by
        // `icon_text_test.dart`.
        'buttonSizes', 'defaultButtonSize', 'iconButton', 'iconBesideText', 'listTileTrailingColor',
        // 9.5.0 clarification: button label centered; mirror is `kButtonLabelAlign`.
        'buttonLabelAlign',
        // 9.6.0: line and paragraph rules of composed text; mirror is
        // `kRichTextLayout`, values are checked by `rich_text_cases_test.dart`.
        'richText',
        // 9.7.0: geometry and paint of the bar and ring; mirror is
        // `progress_rules.dart`, values are checked by `progress_cases_test.dart`.
        'progress',
        // 9.9.0: image box, app bar layout, modal layer. Mirror is
        // `media_chrome_rules.dart`; values are checked by `media_chrome_cases_test.dart`.
        'image', 'appBar', 'modalLayer',
        // 9.9.0 clarification: screen anatomy. Values are checked by
        // `screen_anatomy_test.dart` (`screenRuleCases`).
        'screen',
        // 9.10.0: layer placement in a stack and pulling in the flow. Mirror is
        // `offset_rules.dart`; values are checked by `offset_cases_test.dart`.
        'layer', 'pull',
        // 9.11.0: carousel and bar steps. Mirror is `carousel_rules.dart` and
        // `progress_rules.dart`; values are checked by `carousel_cases_test.dart` and
        // `progress_cases_test.dart`.
        'carousel', 'progressSegments',
        // 9.12.0: bottom zone (pinned block, safe inset, keyboard) and the
        // navigation bar. Mirror is `bottom_zone_rules.dart`; values are checked by
        // `bottom_zone_cases_test.dart` (`ruleCases`).
        'bottomZone', 'navBar',
        // 9.13.0: input fields (value, write, disabled state, focus, keyboard);
        // text field, switch, checkbox. Mirror is `input_rules.dart`;
        // values are checked by `input_cases_test.dart` (`ruleCases`).
        'inputs',
        // 9.14.0: survey form (required, disabled button, numeric field, choice
        // write). Mirror is `form_rules.dart` and the numeric section of
        // `input_rules.dart`; values are checked by `form_cases_test.dart` (`ruleCases`).
        'form',
        // 9.15.0: child alignment on both axes in column, container and screen.
        // Mirror is `layout_rules.dart`; values are checked by `align_cases_test.dart`.
        'alignment',
        // 9.16.0: app bar from the layout: a node in the leading zone, title from the
        // start, own glyph size. Mirror is `media_chrome_rules.dart` and `layout_rules.dart`;
        // values are checked by `app_bar_916_cases_test.dart`.
        'appBarLeading', 'appBarTitle', 'ownGlyphSize',
        // 9.17.0: text emphasis, list marker, own style of the ring label.
        // Mirror is `text_emphasis.dart`, `list_marker.dart` and `progress_rules.dart`;
        // values are checked by `text_emphasis_cases_test.dart` and `list_marker_cases_test.dart`.
        'textEmphasis', 'listMarker', 'progressLabel',
        // 9.18.0: width adaptivity, step 1: width class, `showOn`, `styleOn`,
        // `propsOn`, `contentMaxWidth`. Mirror is `width_class.dart`; values are checked by
        // `adaptive_cases_test.dart` (`ruleCases`).
        'widthClass',
        // 9.18.0, step 2: wide space: navigation bar on top and sheet as a window. Mirror is
        // `wide_chrome_rules.dart` (`kWideNavLayout`, `kWideModalRules`); values are checked by
        // `wide_chrome_cases_test.dart` (`wideRuleCases`).
        'wideNav', 'wideModal',
        // 9.18.0 clarification: whitespace in shown text. Mirror is `shown_text.dart`
        // (`kShownTextRules`); values are checked by `shown_text_test.dart`, rows by `template_cases_test.dart`.
        'shownText',
        // 9.19.0: free composition (pressable container; mirror is `composition_rules.dart`, values are
        // checked by `composition_cases_test.dart`), the top of the screen (`screen_top_rules.dart`,
        // `screen_top_cases_test.dart`), `widthUnset` (`width_class.dart`, `width_unset_cases_test.dart`),
        // `partStyle` and `listTileParts` (`part_style.dart`, `list_tile_parts.dart`, `list_tile_cases_test.dart`),
        // `inputParts` (`input_parts.dart`, `input_parts_cases_test.dart`).
        'composition', 'bodyTop', 'safeTop', 'widthUnset', 'partStyle', 'listTileParts', 'inputParts',
        // 9.21.0: round ends of the scale and the app bar after scrolling. Mirrors are
        // `progress_cap.dart` and `scrolled_bar.dart`; values are checked by `progress_cases_test.dart`
        // (`capCases`) and `media_chrome_cases_test.dart` (`scrolled…`).
        'progressCap', 'appBarScrolled',
      });
    });

    test('x-style.layout.row and the schema policy: a row child without weight', () {
      expect(layout['row'], kRowLayout);
      expect(policy['unweightedRowChild'], kUnweightedRowChild);
      expect(policy['unweightedStretchInRow'], kUnweightedStretchInRow);
      // `rigid` and `stretch` point at the lists the renderer uses.
      final row = layout['row']! as Map<String, Object?>;
      expect(row['rigid'], 'column.naturalWidth');
      expect(row['stretch'], 'scrollableRow.stretchToViewport');
      expect(row['stretchShare'], kRowStretchShare);
    });

    test('x-style.layout: icon glyph size is a FONT token, not a number', () {
      expect(layout['iconGlyphTypography'], {
        for (final entry in kIconGlyphTypography.entries) entry.key.wire: entry.value.wire,
      });
      expect(layout['iconGlyphMeasure'], 'typography-font-size');
      expect(layout['defaultIconSize'], kDefaultIconSize.wire);
      expect(layout['listTileIconSizes'], {
        'leadingIcon': kListTileLeadingIconSize.wire,
        'trailingIcon': kListTileTrailingIconSize.wire,
      });
      // All three sizes are listed, and the tokens come from the theme core.
      expect(kIconGlyphTypography.keys.toSet(), IconSizeToken.values.toSet());
      for (final token in kIconGlyphTypography.values) {
        expect(TypographyToken.values, contains(token));
      }
    });

    // 9.1.0: the icon box rule also became data.
    test('x-style.layout.iconGlyphBox: font size wide, token line tall', () {
      expect(layout['iconGlyphBox'], kIconGlyphBox);
      expect(kIconGlyphBox['inline'], layout['iconGlyphMeasure']);
      // Behavior under this key: width = fontSize, height = fontSize x lineHeight.
      for (final size in IconSizeToken.values) {
        final style = theme.text(kIconGlyphTypography[size]!);
        final box = theme.iconBox(size);
        expect(box.width, style.fontSize);
        expect(box.height, closeTo(style.fontSize! * style.height!, 1e-9));
      }
    });

    test('x-style.layout.buttonLabelAlign', () {
      expect(layout['buttonLabelAlign'], kButtonLabelAlign);
    });

    test('x-style.layout.sizedBoxKeys', () {
      expect(layout['sizedBoxKeys'], kSizedBoxKeys);
    });

    test('scrollableRow: the list of stretchable content is exactly those five conditions', () {
      final row = layout['scrollableRow']! as Map<String, Object?>;
      expect(row['childMaxWidth'], 'max(row-viewport, own-width)');
      expect(row['overflow'], 'scroll-instead-of-clip');
      final rules = (row['stretchToViewport']! as List<Object?>).cast<Map<String, Object?>>();
      expect(rules, hasLength(5), reason: 'the contract list grew, the renderer must learn it');

      // For EVERY row of the list we build a matching node and a non-matching
      // one (condition violated); the renderer function must say yes and no
      // respectively.
      final accepted = <String>{};
      for (final rule in rules) {
        final type = rule['type']! as String;
        final when = rule['when'] as Map<String, Object?>?;
        final yes = parseNode(_nodeOf(type, {if (when != null) when['prop']! as String: when['equals']}));
        expect(stretchesToRowViewport(yes), isTrue, reason: '$type ${when ?? ''}');
        if (when != null) {
          final other = when['equals'] is bool ? !(when['equals']! as bool) : 'vertical';
          final no = parseNode(_nodeOf(type, {when['prop']! as String: other}));
          expect(stretchesToRowViewport(no), isFalse, reason: '$type against ${when['prop']}=$other');
        }
        accepted.add(type);
      }

      // The remaining types have natural width; NONE stretches silently.
      for (final type in kWidgetCatalogTypes.difference(accepted)) {
        final node = rootOf(docWith([_nodeOf(type, const {})])).children;
        if (node.isEmpty) continue;
        expect(stretchesToRowViewport(node.single), isFalse, reason: type);
      }
    });

    test('tightSlots: Grid and Repeater with columns set, and only they', () {
      final slots = (layout['tightSlots']! as List<Object?>).cast<Map<String, Object?>>();
      expect(slots, [
        {'type': 'Grid'},
        {
          'type': 'Repeater',
          'when': {'prop': 'columns', 'defined': true},
        },
      ]);
      expect(isTightSlotParent(parseNode(_nodeOf('Grid', const {}))), isTrue);
      expect(isTightSlotParent(parseNode(_nodeOf('Repeater', {'columns': 2}))), isTrue);
      expect(isTightSlotParent(parseNode(_nodeOf('Repeater', const {}))), isFalse);
      expect(isTightSlotParent(parseNode(_nodeOf('Column', const {}))), isFalse);
      expect(isTightSlotParent(parseNode(_nodeOf('Stack', const {}))), isFalse);
      expect(isTightSlotParent(null), isFalse);
    });

    test('openTabIndex mirrors the builder reference', () {
      expect(openTabIndex(1, [true, true, true]), 1);
      expect(openTabIndex(1, [false, false, true]), 2);
      expect(openTabIndex(0, [false, true, true]), 1);
      // A hidden tab does not shift numbering: `2` is the third in the document.
      expect(openTabIndex(2, [false, true, true]), 2);
      // Out of range (larger, negative or non-integer) means the first visible.
      expect(openTabIndex(9, [false, true]), 1);
      expect(openTabIndex(-1, [false, true]), 1);
      expect(openTabIndex(-1, [true, true]), 0);
      expect(openTabIndex(0, [false, false]), isNull);
      expect(openTabIndex(0, const []), isNull);
    });
  });

  // ─────────────────────────────────────────────────────── icon glyph size

  group('icon glyph size is the fontSize of the CURRENT theme font token', () {
    Map<String, Object?> icon(String size) => {
      'id': 'ic-$size',
      'type': 'Icon',
      'props': {'name': 'trophy', 'size': size, 'alt': size},
    };

    Future<void> pumpScaled(WidgetTester tester, UiDocument doc, RenderTheme t, double scale) =>
        tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: renderDocument(doc, theme: t, data: const {})),
            ),
          ),
        );

    testWidgets('sm / md / lg map to bodyS / titleM / displayL of our theme', (tester) async {
      await pump(tester, [icon('sm'), icon('md'), icon('lg')]);
      final sizes = tester.widgetList<IconGlyph>(find.byType(IconGlyph)).map((i) => i.size).toList();
      expect(sizes, [
        theme.text(TypographyToken.bodyS).fontSize,
        theme.text(TypographyToken.titleM).fontSize,
        theme.text(TypographyToken.displayL).fontSize,
      ]);
      // These are NOT the former constants 16/24/32; the fallback theme has other font sizes.
      expect(sizes, isNot([16, 24, 32]));
    });

    testWidgets('another theme, another size: font rebranding moves icons too', (tester) async {
      final raw = jsonDecode(jsonEncode(kFallbackThemeContractJson['themes']))['light'] as Map<String, Object?>;
      (raw['typography']! as Map<String, Object?>)['titleM'] = {
        ...((raw['typography']! as Map<String, Object?>)['titleM']! as Map<String, Object?>),
        'fontSize': 40,
      };
      final big = RenderTheme.fromJson(raw);

      await pump(tester, [icon('md')], withTheme: big);
      expect(tester.widget<IconGlyph>(find.byType(IconGlyph)).size, 40);
    });

    testWidgets('unknown size falls back to md', (tester) async {
      await pump(tester, [icon('xxl')]);
      expect(tester.widget<IconGlyph>(find.byType(IconGlyph)).size, theme.text(TypographyToken.titleM).fontSize);
    });

    testWidgets('grows with the system font scale, like text', (tester) async {
      final doc = UiDocumentBuilder.bare([icon('md')]);
      await pumpScaled(tester, doc, theme, 1);
      final base = tester.getSize(find.byType(IconGlyph)).width;
      await pumpScaled(tester, doc, theme, 2);
      expect(tester.getSize(find.byType(IconGlyph)).width, closeTo(base * 2, 0.01));
    });

    testWidgets('list row: leading icon is md, trailing is sm', (tester) async {
      await pump(tester, [
        listTileNode(
          'Приз',
          leading: {'kind': 'icon', 'icon': 'trophy'},
          trailing: {'kind': 'text', 'text': {'kind': 'literal', 'value': '+100'}, 'icon': 'star'},
        ),
      ]);
      final sizes = tester
          .widgetList<IconGlyph>(find.byType(IconGlyph))
          .map((i) => i.size)
          .toList();
      expect(sizes, [
        theme.iconSize(IconSizeToken.md),
        theme.iconSize(IconSizeToken.sm),
      ]);
      expect(theme.iconSize(IconSizeToken.md), theme.text(TypographyToken.titleM).fontSize);
    });
  });

  // ─────────────────────────────────────────────────────────────── size

  group('sizeOutsideRange: clamp-to-range + invertedSizeRange: min-wins', () {
    testWidgets('width outside its own bounds is clamped by them', (tester) async {
      Future<Size> sized(Map<String, Object?> st) async {
        await pump(tester, [box('Вміст', style: {...st, 'background': surface})]);
        expect(tester.takeException(), isNull, reason: '$st');
        return boxRect(tester, 'Вміст').size;
      }

      expect((await sized({'width': 500, 'maxWidth': 100})).width, 100);
      expect((await sized({'width': 50, 'minWidth': 80})).width, 80);
      expect((await sized({'width': 90, 'minWidth': 80, 'maxWidth': 100})).width, 90);
      expect((await sized({'height': 500, 'maxHeight': 100})).height, 100);
      expect((await sized({'height': 20, 'minHeight': 60})).height, 60);
      // Inverted bounds PLUS a size outside them: the smallest wins.
      expect(await sized({'width': 500, 'minWidth': 200, 'maxWidth': 100, 'height': 5, 'minHeight': 90, 'maxHeight': 40}),
          const Size(200, 90));
    });

    testWidgets('no set of bounds, valid or not, triggers an assert in BoxConstraints', (tester) async {
      final values = <Object?>[null, 1, 80, 1200, 0, -5, 99999, 'x', double.nan, double.infinity, true, <String, Object?>{},
        {'kind': 'binding', 'path': 'p', 'fallback': 70},
        {'kind': 'binding', 'path': 'p', 'fallback': 'x'},
        {'kind': 'binding', 'path': 'p'}];
      var count = 0;
      for (final w in values) {
        for (final lo in values) {
          for (final hi in values) {
            final st = <String, Object?>{
              'width': ?w,
              'minWidth': ?lo,
              'maxWidth': ?hi,
              'height': ?w,
              'minHeight': ?lo,
              'maxHeight': ?hi,
              'background': surface,
            };
            await pump(tester, [box('Вміст', style: st)], data: const {'p': double.nan});
            expect(tester.takeException(), isNull, reason: '$st');
            count += 1;
          }
        }
      }
      expect(count, values.length * values.length * values.length);
    });
  });

  group('sizeIncludes: [border, padding]: the size is the whole box', () {
    testWidgets('width: 40 with padding 12 and border 2 is 40 wide, content inset 12', (tester) async {
      await pump(tester, [
        {
          'id': 'card',
          'type': 'Container',
          'props': {'gap': 'none'},
          'style': {
            'width': 40,
            'padding': 12,
            'border': {'width': 2, 'color': 'border'},
            'background': surface,
          },
          'children': [box('Вміст')],
        },
      ]);
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(DecoratedBox).first);
      expect(card.width, 40);
      // Content starts after the border and padding: 2 + 12.
      expect(tester.getTopLeft(find.text('Вміст')).dx, card.left + 14);
    });

    testWidgets('margin lies outside and is not part of the size', (tester) async {
      await pump(tester, [box('Вміст', style: {'width': 100, 'margin': 10, 'background': surface})]);
      final rect = boxRect(tester, 'Вміст');
      expect(rect.width, 100);
      expect(rect.left, 10);
    });
  });

  // ────────────────────────────────────────────────────────── sides and numbers

  group('malformedSideValue: side-is-zero', () {
    test('a malformed side value is zero, the rest apply, the form is applied', () {
      for (final bad in <Object?>['Bad!', null, <String, Object?>{}, true, <Object?>[1]]) {
        final padding = NodeStyle.parse({
          'padding': {'top': bad, 'start': 8},
        })!.padding!;
        final resolved = theme.resolveBoxSpacing(padding)!;
        expect(resolved.top, 0, reason: '$bad');
        expect(resolved.start, 8, reason: '$bad');
        expect(padding.isSingleValue, isFalse);

        final radius = NodeStyle.parse({
          'radius': {'topStart': bad, 'topEnd': 12},
        })!.radius!;
        final corners = theme.resolveBoxRadius(radius)!;
        expect(corners.topStart, Radius.zero, reason: '$bad');
        expect(corners.topEnd, const Radius.circular(12), reason: '$bad');
      }
    });

    test('a form with one malformed side is NOT empty: it is always applied', () {
      // `{top: null}` is not "no field": the per-side form already said
      // "there is padding here", and all its sides are zero (`unknownBoxToken`
      // against `unknownSideToken`).
      final padding = NodeStyle.parse({'padding': {'top': null}})!.padding;
      expect(padding, isNotNull);
      expect(theme.resolveBoxSpacing(padding), EdgeInsetsDirectional.zero);
    });

    testWidgets('on a button, zero padding from the document replaces the built-in one', (tester) async {
      Future<Size> buttonSize(Map<String, Object?>? st) async {
        await pump(tester, [
          {
            'id': 'b',
            'type': 'Button',
            'props': {
              'label': {'kind': 'literal', 'value': 'Кнопка'},
              'variant': 'primary',
              'action': {'type': 'noop'},
              'fullWidth': false,
            },
            'style': ?st,
          },
        ]);
        expect(tester.takeException(), isNull);
        return tester.getSize(find.byType(FilledButton));
      }

      final builtIn = await buttonSize(null);
      final zero = await buttonSize({'padding': {'top': 'Bad!'}});
      expect(zero.width, lessThan(builtIn.width), reason: 'the built-in button padding is replaced by zeros');
    });
  });

  group('nonNumericLiteral: lower-bound', () {
    test('every numeric style field: not a number gives the lower bound, out of range gives the bound', () {
      // `null` is deliberately absent here: since 9.0.0 in an optional field it
      // means "no field" (`nullNumericField: 'absent'`), and in required ones the
      // lower bound; both cases are in the test below.
      for (final bad in <Object?>['oops', true, <Object?>[], <String, Object?>{}, double.nan]) {
        final parsed = NodeStyle.parse({
          'opacity': bad,
          'width': bad,
          'border': {'width': bad, 'color': 'border'},
          'typography': {'token': 'bodyM', 'fontSize': bad, 'fontWeight': bad, 'lineHeight': bad, 'letterSpacing': bad},
          'shadow': [
            {'offsetX': bad, 'offsetY': bad, 'blur': bad, 'spread': bad, 'color': 'onSurface'},
          ],
          'color': {'token': 'primary', 'opacity': bad},
          'background': {
            'kind': 'gradient',
            'gradient': {
              'angle': 90,
              'stops': [
                {'color': 'primary', 'position': bad},
                {'color': 'accent', 'position': 1},
              ],
            },
          },
        })!;
        final reason = '$bad';
        expect(parsed.opacity, 0, reason: reason);
        // An object instead of a width is another form (a binding without path), not a number.
        if (bad is! Map) {
          expect((parsed.width! as LiteralNumber).value, kStyleSizeMin, reason: reason);
        }
        expect(parsed.border!.width, kMinBorderWidthPx, reason: reason);
        final font = parsed.typography!;
        expect(font.fontSize, kMinFontSizePx, reason: reason);
        expect(font.fontWeight, 100, reason: reason);
        expect(font.lineHeight, kMinLineHeight, reason: reason);
        expect(font.letterSpacing, kMinLetterSpacingPx, reason: reason);
        final layer = (parsed.shadow! as CustomShadowRef).layers.single;
        expect(layer.offsetX, -kMaxShadowOffsetPx, reason: reason);
        expect(layer.offsetY, -kMaxShadowOffsetPx, reason: reason);
        expect(layer.blur, 0, reason: reason);
        expect(layer.spread, -kMaxShadowSpreadPx, reason: reason);
        expect((parsed.color! as TokenColorRef).opacity, 0, reason: reason);
        final gradient = (parsed.background! as GradientBackground).gradient as CustomGradientRef;
        expect(gradient.stops.first.position, 0, reason: reason);
      }
    });

    test('nullNumericField: absent: explicit null in an optional numeric field means no field', () {
      expect(policy['nullNumericField'], 'absent');
      final parsed = NodeStyle.parse({
        'opacity': null,
        'width': null,
        'height': null,
        'minWidth': null,
        'maxWidth': null,
        'minHeight': null,
        'maxHeight': null,
        'typography': {'token': 'bodyM', 'fontSize': null, 'fontWeight': null, 'lineHeight': null, 'letterSpacing': null},
        'color': {'value': '#112233', 'opacity': null},
        'shadow': [
          {'offsetX': null, 'offsetY': null, 'blur': null, 'spread': null, 'color': 'onSurface'},
        ],
        'background': {'kind': 'color', 'color': 'surface'},
      })!;
      // Worst consequence of the old reading: `"opacity": null` made the node
      // invisible (zero).
      expect(parsed.opacity, isNull);
      for (final size in [parsed.width, parsed.height, parsed.minWidth, parsed.maxWidth, parsed.minHeight, parsed.maxHeight]) {
        expect(size, isNull);
      }
      final font = parsed.typography!;
      expect([font.fontSize, font.fontWeight, font.lineHeight, font.letterSpacing], everyElement(isNull));
      expect((parsed.color! as CustomColorRef).opacity, 1);
      final layer = (parsed.shadow! as CustomShadowRef).layers.single;
      expect([layer.offsetX, layer.offsetY, layer.blur, layer.spread], everyElement(0));

      // Required fields: `null` stays not-a-number and gives the lower bound.
      final required = NodeStyle.parse({
        'color': {'token': 'primary', 'opacity': null},
        'border': {'width': null, 'color': 'border'},
        'background': {
          'kind': 'gradient',
          'gradient': {
            'angle': 90,
            'stops': [
              {'color': 'primary', 'position': null},
              {'color': 'accent', 'position': 1},
            ],
          },
        },
      })!;
      expect((required.color! as TokenColorRef).opacity, 0);
      expect(required.border!.width, kMinBorderWidthPx);
      final gradient = (required.background! as GradientBackground).gradient as CustomGradientRef;
      expect(gradient.stops.first.position, 0);
    });

    test('nullNumericField: absent — Text.maxLines, Repeater.limit, Repeater.columns', () {
      Object? prop(String type, String key) {
        final node = rootOf(
          docWith([
            {
              'id': 'n',
              'type': type,
              'props': {
                key: null,
                if (type == 'Text') 'content': {'kind': 'literal', 'value': 'А'},
                if (type == 'Repeater') ...{'source': 'quests', 'item': 'quest'},
              },
              if (type == 'Repeater') 'children': [textNode('Б', id: 't')],
            },
          ]),
        ).children.single;
        return switch (node) {
          TextNode(:final maxLines) => maxLines,
          RepeaterNode(:final limit, :final columns) => key == 'limit' ? limit : columns,
          _ => 'unexpected',
        };
      }

      expect(prop('Text', 'maxLines'), isNull);
      expect(prop('Repeater', 'limit'), isNull);
      expect(prop('Repeater', 'columns'), isNull);
    });

    test('a field that does not exist at all is not covered by the rule; the field default decides', () {
      final parsed = NodeStyle.parse({'color': 'primary'})!;
      expect(parsed.opacity, isNull);
      expect(parsed.width, isNull);
      // A shadow layer without `blur` is zero, without `offsetX` is zero (not the lower bound).
      final shadow = NodeStyle.parse({
        'shadow': [
          {'color': 'onSurface'},
        ],
      })!.shadow! as CustomShadowRef;
      expect(shadow.layers.single.offsetX, 0);
      expect(shadow.layers.single.blur, 0);
    });

    test('size fallback: not a number gives 1, out of range gives the bound', () {
      BindableNumber? width(Object? fallback) =>
          NodeStyle.parse({
            'width': {'kind': 'binding', 'path': 'p', 'fallback': fallback},
          })?.width;
      expect((width('x')! as BoundNumber).fallback, kStyleSizeMin);
      expect((width(99999)! as BoundNumber).fallback, kStyleSizeMax);
      expect((width(-4)! as BoundNumber).fallback, kStyleSizeMin);
      // A binding WITHOUT a fallback is a different story: nothing to paint with.
      expect(NodeStyle.parse({'width': {'kind': 'binding', 'path': 'p'}}), isNull);
    });

    test('out of range: infinity is the bound, not "not a number"', () {
      expect(NodeStyle.parse({'opacity': double.infinity})!.opacity, 1);
      expect(NodeStyle.parse({'opacity': double.negativeInfinity})!.opacity, 0);
      final spacing = NodeStyle.parse({'padding': double.infinity})!.padding!;
      expect(theme.resolveBoxSpacing(spacing)!.top, kMaxSpacingPx);
    });

    testWidgets('rendered: opacity "oops" makes the node transparent but it still takes space', (tester) async {
      await pump(tester, [box('Вміст', style: {'opacity': 'oops'})]);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0);
      expect(find.text('Вміст'), findsOneWidget);
    });

    test('properties with schema bounds: limit, maxLines, columns', () {
      final repeater = parseNode({
        'id': 'r',
        'type': 'Repeater',
        'props': {'source': 'x', 'item': 'y', 'limit': 'багато', 'columns': 'x'},
        'children': const <Object?>[],
      }) as RepeaterNode;
      expect(repeater.limit, 1);
      expect(repeater.columns, kGridMinColumns);

      final big = parseNode({
        'id': 'r',
        'type': 'Repeater',
        'props': {'source': 'x', 'item': 'y', 'limit': 5000},
        'children': const <Object?>[],
      }) as RepeaterNode;
      expect(big.limit, kMaxRepeaterItemsForTest);
      expect(big.columns, isNull);

      final grid = parseNode(_nodeOf('Grid', {'columns': double.nan})) as GridNode;
      expect(grid.columns, kGridMinColumns);
    });
  });

  // ──────────────────────────────────────────────────────────── tabs, fill

  group('initialTabOutOfRange: first-visible', () {
    Map<String, Object?> tabs(Object initial, {bool firstHidden = false}) => {
      'id': 'tabs',
      'type': 'Tabs',
      'props': {'initialTab': initial},
      'children': [
        {
          'id': 'a',
          'type': 'Tab',
          'props': {'title': {'kind': 'literal', 'value': 'Перша'}},
          'visibleIf': ?(firstHidden ? {'path': 'u.vip', 'op': 'isTrue'} : null),
          'children': [textNode('Вміст першої', id: 'ta')],
        },
        {
          'id': 'b',
          'type': 'Tab',
          'props': {'title': {'kind': 'literal', 'value': 'Друга'}},
          'children': [textNode('Вміст другої', id: 'tb')],
        },
        {
          'id': 'c',
          'type': 'Tab',
          'props': {'title': {'kind': 'literal', 'value': 'Третя'}},
          'children': [textNode('Вміст третьої', id: 'tc')],
        },
      ],
    };

    testWidgets('out of range, non-integer and negative give the first VISIBLE tab, not emptiness', (tester) async {
      for (final initial in <Object>[3, 99, -1, 0.5, 'друга']) {
        await pump(tester, [tabs(initial, firstHidden: true)], data: const {'u': {'vip': false}});
        expect(tester.takeException(), isNull, reason: '$initial');
        expect(find.text('Вміст першої'), findsNothing, reason: '$initial (hidden)');
        expect(find.text('Вміст другої'), findsOneWidget, reason: '$initial → first visible');
      }
    });

    testWidgets('the index counts ALL tabs: a named visible one stays itself', (tester) async {
      await pump(tester, [tabs(2, firstHidden: true)], data: const {'u': {'vip': false}});
      expect(find.text('Вміст третьої'), findsOneWidget);
    });

    testWidgets('all look-alikes of "first" in the visible row', (tester) async {
      await pump(tester, [tabs(50)]);
      expect(find.text('Вміст першої'), findsOneWidget);
    });
  });

  group('fillOutsideStack: ignore + fillScope: direct-children-of-stack', () {
    Map<String, Object?> band(String label, {bool fill = true, int width = 120}) => {
      'id': 'band-$label',
      'type': 'Container',
      'props': {'gap': 'none'},
      'style': {'width': width, 'background': surface},
      if (fill) 'fill': true,
      'children': [textNode(label, id: 'txt-$label')],
    };

    testWidgets('fill in a column has no effect: style.width stays', (tester) async {
      await pump(tester, [
        {
          'id': 'col',
          'type': 'Column',
          'props': {'gap': 'none', 'align': 'start'},
          'children': [band('Колонка')],
        },
      ]);
      expect(tester.takeException(), isNull);
      expect(boxRect(tester, 'Колонка').width, 120);
    });

    testWidgets('fill in a row, a container and on the screen root is also ignored', (tester) async {
      await pump(tester, [
        band('Корінь'),
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': false},
          'children': [band('Рядок')],
        },
        {
          'id': 'box',
          'type': 'Container',
          'props': {'gap': 'none'},
          'children': [band('Глибше')],
        },
      ]);
      expect(tester.takeException(), isNull);
      for (final label in ['Корінь', 'Рядок', 'Глибше']) {
        expect(boxRect(tester, label).width, 120, reason: label);
      }
    });

    testWidgets('a direct stack layer: it applies and takes the stack size', (tester) async {
      await pump(tester, [
        {
          'id': 'stack',
          'type': 'Stack',
          'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
          'children': [
            textNode('Опора довга довга', id: 'base'),
            band('Шар'),
          ],
        },
      ]);
      expect(tester.takeException(), isNull);
      // `fill` beats `style.width: 120`: the layer is stretched over the whole stack.
      expect(boxRect(tester, 'Шар').width, isNot(120));
    });

    testWidgets('fill on a layer nested deeper than the stack has no effect', (tester) async {
      await pump(tester, [
        {
          'id': 'stack',
          'type': 'Stack',
          'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
          'children': [
            textNode('Опора довга довга', id: 'base'),
            {
              'id': 'wrap',
              'type': 'Container',
              'props': {'gap': 'none'},
              'children': [band('Вкладений')],
            },
          ],
        },
      ]);
      expect(tester.takeException(), isNull);
      expect(boxRect(tester, 'Вкладений').width, 120);
    });
  });

  // ─────────────────────────────── state with an unknown token, tab, roles

  group('unknownTokenInCase: keep-base-field', () {
    Map<String, Object?> state(Map<String, Object?> caseStyle, Map<String, Object?> base) => {
      ...textNode('Вміст', id: 'node', style: base),
      'styleWhen': [
        {
          'when': {'path': 'on', 'op': 'isTrue'},
          'style': caseStyle,
        },
      ],
    };

    testWidgets('a state with an unknown color keeps the node BASE color', (tester) async {
      await pump(
        tester,
        [state({'color': 'tokenFromTheFuture'}, {'color': 'danger'})],
        data: const {'on': true},
      );
      final text = tester.widget<Text>(find.text('Вміст'));
      expect(text.style!.color, theme.color(ColorToken.danger), reason: 'neither inherited nor root');
    });

    testWidgets('a known token in a state overrides as usual', (tester) async {
      await pump(tester, [state({'color': 'success'}, {'color': 'danger'})], data: const {'on': true});
      expect(tester.widget<Text>(find.text('Вміст')).style!.color, theme.color(ColorToken.success));
    });

    testWidgets('an unknown background in a state keeps the base one; known fields of the same state apply', (tester) async {
      await pump(
        tester,
        [
          state(
            {
              'background': {'kind': 'color', 'color': 'tokenFromTheFuture'},
              'border': {'width': 2, 'color': 'tokenFromTheFuture'},
              'padding': 'tokenFromTheFuture',
              'opacity': 0.5,
            },
            {'background': surface, 'padding': 10},
          ),
        ],
        data: const {'on': true},
      );
      expect(tester.takeException(), isNull);
      final decoration = tester.widget<DecoratedBox>(find.ancestor(of: find.text('Вміст'), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(decoration.color, theme.color(ColorToken.surface), reason: 'base background preserved');
      expect(decoration.border, isNull, reason: 'a border with an unknown color was not applied');
      expect(tester.getTopLeft(find.text('Вміст')).dx, 10, reason: 'base padding preserved');
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.5, reason: 'a known state field applies');
    });

    testWidgets('the per-side form is always applied, even with an unknown side', (tester) async {
      await pump(
        tester,
        [
          state(
            {'padding': {'start': 'tokenFromTheFuture', 'top': 4}},
            {'padding': 30},
          ),
        ],
        data: const {'on': true},
      );
      expect(tester.getTopLeft(find.text('Вміст')), const Offset(0, 4));
    });

    testWidgets('button: a state with an unknown background removes neither the role background nor the base one', (tester) async {
      await pump(tester, [
        {
          'id': 'b',
          'type': 'Button',
          'props': {
            'label': {'kind': 'literal', 'value': 'Кнопка'},
            'variant': 'primary',
            'action': {'type': 'noop'},
            'fullWidth': false,
          },
          'style': {
            'background': {'kind': 'color', 'color': 'success'},
          },
          'styleWhen': [
            {
              'when': {'path': 'on', 'op': 'isTrue'},
              'style': {
                'background': {'kind': 'color', 'color': 'tokenFromTheFuture'},
              },
            },
          ],
        },
      ], data: const {'on': true});
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style!.backgroundColor!.resolve({}), theme.color(ColorToken.success));
    });
  });

  group('tabTitleColorContext: tab', () {
    testWidgets('the title reads the color of ITS OWN tab, not a neighbor', (tester) async {
      Map<String, Object?> tab(String id, String title, {String? color}) => {
        'id': id,
        'type': 'Tab',
        'props': {'title': {'kind': 'literal', 'value': title}},
        'style': ?(color == null ? null : {'color': color}),
        'children': [textNode('Вміст $id', id: 't$id')],
      };

      await pump(tester, [
        {
          'id': 'tabs',
          'type': 'Tabs',
          'props': {'initialTab': 0},
          'style': {'color': 'success'},
          'children': [tab('a', 'Перша'), tab('b', 'Друга', color: 'danger')],
        },
      ]);
      expect(tester.takeException(), isNull);
      // An open tab without its own color takes the ancestor (Tabs) color…
      expect(tester.widget<Text>(find.text('Перша')).style!.color, theme.color(ColorToken.success));
      // …and a closed one has ITS OWN color (danger) at secondary opacity.
      final inactive = tester.widget<Text>(find.text('Друга')).style!.color!;
      expect(inactive.withValues(alpha: 1), theme.color(ColorToken.danger));
      expect(inactive.a, closeTo(kSecondaryPartOpacity, 0.01));
    });
  });

  group('neutral role: missingRole + roles.neutral', () {
    Map<String, Object?> lightJson() =>
        jsonDecode(jsonEncode((kFallbackThemeContractJson['themes']! as Map)['light']))
            as Map<String, Object?>;

    Map<String, Object?> badge(String tone, {Map<String, Object?>? st}) => {
      'id': 'bdg',
      'type': 'Badge',
      'props': {'label': {'kind': 'literal', 'value': 'Знач'}, 'tone': tone},
      'style': ?st,
    };

    Map<String, Object?> button(String variant, {Map<String, Object?>? st}) => {
      'id': 'btn',
      'type': 'Button',
      'props': {
        'label': {'kind': 'literal', 'value': 'Кнопка'},
        'variant': variant,
        'action': {'type': 'noop'},
        'fullWidth': false,
      },
      'style': ?st,
    };

    final variants = <String, void Function(Map<String, Object?> json)>{
      'no roles': (json) => json.remove('roles'),
      'no group': (json) => (json['roles']! as Map<String, Object?>).remove('badgeTone'),
      'no role': (json) => ((json['roles']! as Map<String, Object?>)['badgeTone']! as Map<String, Object?>).remove('success'),
      'role of the wrong shape': (json) => ((json['roles']! as Map<String, Object?>)['badgeTone']! as Map<String, Object?>)['success'] = 'зелений',
      'roles = null': (json) => json['roles'] = null,
    };

    for (final entry in variants.entries) {
      testWidgets('badge, ${entry.key}: no background or border, label in the root color', (tester) async {
        final json = lightJson();
        entry.value(json);
        final bare = RenderTheme.fromJson(json);

        await pump(tester, [badge('success')], withTheme: bare);
        expect(tester.takeException(), isNull);

        final decoration = badgeDecoration(tester, 'Знач');
        expect(decoration.color, isNull);
        expect(decoration.border, isNull);
        expect(tester.widget<Text>(find.text('Знач')).style!.color, bare.color(ColorToken.onSurface));
      });
    }

    testWidgets('button on a theme without roles: no background or border; label is onSurface', (tester) async {
      final json = lightJson()..remove('roles');
      final bare = RenderTheme.fromJson(json);

      await pump(tester, [button('primary')], withTheme: bare);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextButton), findsOneWidget, reason: 'no background or border gives TextButton');
      expect(tester.widget<Text>(find.text('Кнопка')).style?.color ?? bare.color(ColorToken.onSurface),
          bare.color(ColorToken.onSurface));
    });

    testWidgets('own style also applies on the neutral role', (tester) async {
      final bare = RenderTheme.fromJson(lightJson()..remove('roles'));
      await pump(
        tester,
        [badge('success', st: {'background': {'kind': 'color', 'color': 'accent'}, 'color': 'onPrimary'})],
        withTheme: bare,
      );
      expect(badgeDecoration(tester, 'Знач').color, bare.color(ColorToken.accent));
      expect(tester.widget<Text>(find.text('Знач')).style!.color, bare.color(ColorToken.onPrimary));
    });

    testWidgets('a background of an UNKNOWN kind on a button does not override the role', (tester) async {
      await pump(tester, [
        button('primary', st: {'background': {'kind': 'hologram', 'color': 'accent'}}),
      ]);
      expect(tester.takeException(), isNull);
      final role = theme.buttonVariant(ButtonVariantToken.primary);
      final filled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filled.style!.backgroundColor!.resolve({}), role.background);
    });

    testWidgets('roleBorderAppliesTo / withoutBorderSlot: a border (and room for it) only in a role with a slot', (tester) async {
      Future<Size> badgeSize(RenderTheme t) async {
        await pump(tester, [badge('success')], withTheme: t);
        return tester.getSize(find.ancestor(of: find.text('Знач'), matching: find.byType(DecoratedBox)).first);
      }

      Map<String, Object?> withRole(Map<String, Object?> role) {
        final json = lightJson();
        ((json['roles']! as Map<String, Object?>)['badgeTone']! as Map<String, Object?>)['success'] = role;
        return json;
      }

      final noBorder = await badgeSize(RenderTheme.fromJson(withRole({'background': 'secondary', 'foreground': 'onSurface'})));
      final withBorder = await badgeSize(RenderTheme.fromJson(withRole({
        'background': 'secondary',
        'foreground': 'onSurface',
        'border': 'primary',
      })));
      // A border `roleBorderWidth` thick on each side, and only in a role with a slot.
      expect(withBorder.width - noBorder.width, 2 * kRoleBorderWidth);
      expect(withBorder.height - noBorder.height, 2 * kRoleBorderWidth);

      // The slot exists but the color is unknown to the theme: no border and no room for it.
      final brokenBorder = await badgeSize(RenderTheme.fromJson(withRole({
        'background': 'secondary',
        'foreground': 'onSurface',
        'border': 'tokenFromTheFuture',
      })));
      expect(brokenBorder, noBorder);
    });
  });

  // ───────────────────────────────────────── scrolling row, tight slots

  group('scrollableRow: childMaxWidth, stretchToViewport, overflow', () {
    Map<String, Object?> scrollRow(List<Map<String, Object?>> children, {double width = 300}) => {
      'id': 'row',
      'type': 'Row',
      'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': true},
      'style': {'width': width},
      'children': children,
    };

    /// Width of the row content (its only child).
    double contentWidth(WidgetTester tester) {
      final scroll = find.byWidgetPredicate(
        (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
      );
      return tester
          .getSize(find.descendant(of: scroll, matching: find.byWidgetPredicate((w) => w is Row)).first)
          .width;
    }

    Map<String, Object?> button({bool fullWidth = true, Map<String, Object?>? st}) => {
      'id': 'btn',
      'type': 'Button',
      'props': {
        'label': {'kind': 'literal', 'value': 'Кнопка'},
        'variant': 'primary',
        'action': {'type': 'noop'},
        'fullWidth': fullWidth,
      },
      'style': ?st,
    };

    final stretching = <String, Map<String, Object?>>{
      'Button{fullWidth}': button(),
      'Divider{horizontal}': {
        'id': 'd',
        'type': 'Divider',
        'props': {'orientation': 'horizontal', 'spacing': 'none', 'color': 'border'},
      },
      'Spacer{horizontal}': {
        'id': 's',
        'type': 'Spacer',
        'props': {'orientation': 'horizontal', 'size': 'md'},
      },
      'ProgressBar': {
        'id': 'p',
        'type': 'ProgressBar',
        'props': {
          'value': {'kind': 'literal', 'value': 30},
          'max': {'kind': 'literal', 'value': 100},
          'labelFormat': 'none',
          'color': 'primary',
        },
      },
      'Grid': {
        'id': 'g',
        'type': 'Grid',
        'props': {'columns': 2, 'gap': 'none'},
        'children': [textNode('А', id: 'ga'), textNode('Б', id: 'gb')],
      },
    };

    for (final entry in stretching.entries) {
      testWidgets('${entry.key} takes the whole visible-area width', (tester) async {
        await pump(tester, [scrollRow([entry.value])]);
        expect(tester.takeException(), isNull);
        expect(contentWidth(tester), 300);
      });
    }

    testWidgets('the remaining children have natural width (none stretches)', (tester) async {
      final natural = <String, Map<String, Object?>>{
        'Text': textNode('Привіт', id: 't'),
        'Button{fullWidth: false}': button(fullWidth: false),
        'Divider{vertical}': {
          'id': 'dv',
          'type': 'Divider',
          'props': {'orientation': 'vertical', 'spacing': 'none', 'color': 'border'},
        },
        'Spacer{vertical}': {
          'id': 'sv',
          'type': 'Spacer',
          'props': {'orientation': 'vertical', 'size': 'md'},
        },
        'CircularProgress': {
          'id': 'cp',
          'type': 'CircularProgress',
          'props': {
            'value': {'kind': 'literal', 'value': 30},
            'max': {'kind': 'literal', 'value': 100},
            'size': 'sm',
            'color': 'primary',
            'labelFormat': 'none',
          },
        },
        'Badge': {
          'id': 'b',
          'type': 'Badge',
          'props': {'label': {'kind': 'literal', 'value': 'Нове'}, 'tone': 'neutral'},
        },
      };
      for (final entry in natural.entries) {
        await pump(tester, [scrollRow([entry.value])]);
        expect(tester.takeException(), isNull, reason: entry.key);
        expect(contentWidth(tester), lessThan(300), reason: '${entry.key} was stretched');
      }
    });

    testWidgets('own width larger than the area: max(row-viewport, own-width)', (tester) async {
      await pump(tester, [scrollRow([box('Широкий', style: {'width': 520})])]);
      expect(tester.takeException(), isNull);
      expect(contentWidth(tester), 520);
    });

    testWidgets('a node with its own style.width is not in the list: its width is already named', (tester) async {
      await pump(tester, [scrollRow([button(st: {'width': 100})])]);
      expect(tester.takeException(), isNull);
      expect(contentWidth(tester), 100);
    });

    testWidgets('overflow: scroll-instead-of-clip: the excess scrolls instead of being clipped', (tester) async {
      await pump(tester, [
        scrollRow([
          box('Один', style: {'width': 280}, id: 'a'),
          box('Два', style: {'width': 280}, id: 'b'),
          box('Три', style: {'width': 280}, id: 'c'),
        ]),
      ]);
      expect(tester.takeException(), isNull);
      // All three children exist and together are wider than the area.
      expect(contentWidth(tester), 840);
      await tester.drag(find.text('Один'), const Offset(-400, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Один')).dx, lessThan(0), reason: 'the content moved: this is scrolling');
    });
  });

  group('tightSlots: a child with its own size sits at the start and top', () {
    testWidgets('grid cell', (tester) async {
      await pump(tester, [
        {
          'id': 'g',
          'type': 'Grid',
          'props': {'columns': 2, 'gap': 'none'},
          'children': [
            box('Мала', style: {'width': 40, 'height': 20, 'background': surface}, id: 'a'),
            textNode('Висока довга довга довга довга довга довга', id: 'b'),
          ],
        },
      ]);
      expect(tester.takeException(), isNull);
      final rect = boxRect(tester, 'Мала');
      expect(rect.topLeft, Offset.zero);
      expect(rect.size, const Size(40, 20));
    });

    testWidgets('instance of a repeater laid out in columns', (tester) async {
      await pump(
        tester,
        [
          {
            'id': 'r',
            'type': 'Repeater',
            'props': {'source': 'items', 'item': 'item', 'columns': 2, 'gap': 'none'},
            'children': [
              box('Примірник', style: {'width': 40, 'height': 20, 'background': surface}, id: 't'),
            ],
          },
        ],
        data: const {
          'items': [
            <String, Object?>{'a': 1},
            <String, Object?>{'a': 2},
          ],
        },
      );
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.ancestor(of: find.text('Примірник').first, matching: find.byType(DecoratedBox)).first);
      expect(rect.topLeft, Offset.zero);
      expect(rect.size, const Size(40, 20));
    });
  });

  // ────────────────────────────────────────────────────────────── __proto__

  group('the `__proto__` key in a document is invalid: the entry is rejected', () {
    test('Button.action.params', () {
      final action = ButtonAction.parse({
        'type': 'open',
        'params': {'__proto__': 'x', 'screenId': 'next'},
      });
      expect(action.params.keys, ['screenId']);
    });

    test('entryPoints', () {
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'd',
        'name': 'n',
        'initialScreenId': 'a',
        'entryPoints': {'__proto__': 'a', 'promo': 'a'},
        'screens': [screenEntry('a', const [])],
      });
      expect(doc.entryPoints.keys, ['promo']);
    });

    test('translation table: language and place key', () {
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'd',
        'name': 'n',
        'initialScreenId': 'a',
        'localization': {
          'defaultLocale': 'en',
          'locales': ['en', 'uk'],
          'strings': {
            '__proto__': {'a/b/c': 'x'},
            'uk': {'__proto__': 'x', 'a/b/c': 'Привіт'},
          },
        },
        'screens': [screenEntry('a', const [])],
      });
      final localization = doc.localization!;
      expect(localization.strings.containsKey('__proto__'), isFalse);
      expect(localization.strings['uk']!.keys, ['a/b/c']);
    });
  });
}

/// Minimal node of the given type for checking how contract lists are read.
Map<String, Object?> _nodeOf(String type, Map<String, Object?> props) => {
  'id': 'n-${type.toLowerCase()}',
  'type': type,
  'props': {
    ...switch (type) {
      'Button' => {'label': {'kind': 'literal', 'value': 'К'}, 'variant': 'primary', 'action': {'type': 'noop'}},
      'Repeater' => {'source': 'x', 'item': 'y'},
      'Text' => {'content': {'kind': 'literal', 'value': 'Т'}},
      _ => const <String, Object?>{},
    },
    ...props,
  },
  if (const {'Grid', 'Repeater', 'Column', 'Row', 'Container', 'Stack'}.contains(type))
    'children': [textNode('в', id: 'child-${type.toLowerCase()}')],
};

/// Widget types that can be placed as a child of an ordinary container.
const Set<String> kWidgetCatalogTypes = {
  'Button', 'Divider', 'Spacer', 'ProgressBar', 'Grid', 'Text', 'Image', 'Icon', 'Badge', 'ListTile',
  'CircularProgress', 'Column', 'Row', 'Container', 'Stack', 'Repeater', 'Accordion', 'IconButton',
};

const int kMaxRepeaterItemsForTest = 50;
