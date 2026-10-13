/// Icon in a button and a badge, button sizes, the icon button and the "icon
/// beside text" rule (schema 9.5.0).
///
/// FIRST HALF - the shared table `fixtures/icon-text/icon-text-cases.json`
/// (39 rows, one for all readers), WHOLE and PAINTED: a document is built from a row,
/// `renderDocument` paints it, and the answer is MEASURED on screen -
/// where the icon box sits relative to the text, what size it is, how many dp
/// tall the button is, what the screen reader hears. The reference mirror functions
/// are deliberately not asked here: a mirror that matches by string and
/// diverges in behaviour is worse than none.
///
/// SECOND HALF - what the table does not say: defaults from `x-style.layout` rather than from the
/// schema; an own style beats the size; the touch target is an area, not a
/// size; a badge is not a control; corrupted values; the fixture in three languages.
///
/// In the tests the font is Ahem: a glyph is a square of the font size, a line is `fontSize x height`,
/// so widths and heights here are exact numbers, not "approximately".
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/demo_data.dart';
import 'support/fixtures.dart';
import 'support/icons.dart';

final RenderTheme _theme = RenderTheme.fallback();

const Map<String, Object?> _literal = {'kind': 'literal', 'value': 'Label'};

Map<String, Object?> _button(
  Map<String, Object?> props, {
  String id = 'btn',
  String variant = 'primary',
  bool fullWidth = false,
  Object? label = _literal,
  Map<String, Object?>? style,
}) => {
  'id': id,
  'type': 'Button',
  'props': {
    'label': label,
    'variant': variant,
    'action': {
      'type': 'press',
      'params': {'which': id},
    },
    'fullWidth': fullWidth,
    ...props,
  },
  'style': ?style,
};

Map<String, Object?> _badge(Map<String, Object?> props, {Object? label = _literal, Map<String, Object?>? style}) => {
  'id': 'bdg',
  'type': 'Badge',
  'props': {'label': label, 'tone': 'neutral', ...props},
  'style': ?style,
};

Map<String, Object?> _tile(Map<String, Object?> trailing, {Map<String, Object?>? style}) => {
  'id': 'tile',
  'type': 'ListTile',
  'props': {
    'leading': {'kind': 'none'},
    'title': {'kind': 'literal', 'value': 'Title'},
    'trailing': {'kind': 'text', 'text': _literal, ...trailing},
  },
  'style': ?style,
};

Map<String, Object?> _iconButton(
  Map<String, Object?> props, {
  String id = 'ib',
  Map<String, Object?>? style,
}) => {
  'id': id,
  'type': 'IconButton',
  'props': {
    'icon': 'arrow-left',
    'label': {'kind': 'literal', 'value': 'Back'},
    'variant': 'primary',
    'size': 'md',
    'action': {
      'type': 'press',
      'params': {'which': id},
    },
    ...props,
  },
  'style': ?style,
};

/// Place node from the table: the `props.icon` of a `ListTile` row is `trailing.icon`.
Map<String, Object?> _placeNode(String widget, Map<String, Object?> props) => switch (widget) {
  'Button' => _button(props),
  'Badge' => _badge(props),
  'ListTile' => _tile(props),
  _ => throw StateError('the table named a place the test does not know: $widget'),
};

/// A document without a screen style - coordinates are counted from zero; root children
/// stand in a column and take their natural width (button, badge) or the full width (row).
UiDocument _doc(List<Map<String, Object?>> children) => UiDocumentBuilder.bare(children, gap: 'md');

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, Object?>> children, {
  String direction = 'ltr',
  SduiActionCallback? onAction,
}) async {
  await pumpDocument(
    tester,
    _doc(children),
    theme: _theme,
    // A document without localization takes the direction from the host word.
    locale: direction == 'rtl' ? 'ar' : 'en',
    onAction: onAction,
  );
  // The Material button changes the label font with an ANIMATION (`AnimatedDefaultTextStyle`):
  // when a test paints a second document in place of the first, the size in the first frame
  // is still the old one. We wait for it to settle - measuring the document, not the transition.
  await tester.pumpAndSettle();
}

final Finder _anyButton = find.bySubtype<ButtonStyleButton>();
final Finder _label = find.text('Label');

/// The icon box beside text. The documents of this file have no other boxes
/// (leading row icon), so there is no need to look for "the right one".
final Finder _iconBox = find.byType(IconBox);

/// Size to a hundredth: the font line is `font size x multiplier` with four
/// digits (14 x 1.4286 = 20.0004), while the table gives integers.
Matcher _size(double width, [double? height]) =>
    within<Size>(distance: 0.01, from: Size(width, height ?? width));

IconGlyphPainter? _painterIn(WidgetTester tester, Finder box) {
  final paints = find.descendant(of: box, matching: find.byType(CustomPaint));
  for (final paint in tester.widgetList<CustomPaint>(paints)) {
    if (paint.painter case final IconGlyphPainter painter) return painter;
  }
  return null;
}

/// Size of the place WIDGET: the button, the badge pill or the list row.
Size _placeSize(WidgetTester tester, String widget) => switch (widget) {
  'Button' => tester.getSize(_anyButton),
  // The badge pill is the nearest decorated box around the label.
  'Badge' => tester.getSize(find.ancestor(of: _label, matching: find.byType(DecoratedBox)).first),
  // The whole list row is the outer one of the rows around the label.
  _ => tester.getSize(find.ancestor(of: _label, matching: find.bySubtype<Row>()).last),
};

void main() {
  final table =
      jsonDecode(File('assets/contract/fixtures/icon-text/icon-text-cases.json').readAsStringSync())
          as Map<String, Object?>;
  List<Map<String, Object?>> rows(String group) => (table[group]! as List<Object?>).cast<Map<String, Object?>>();

  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
  final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;

  test('the table is read whole: six groups, 39 rows, and its theme numbers are the numbers of the built-in theme', () {
    const groups = ['orderCases', 'glyphCases', 'buttonSizeCases', 'iconButtonCases', 'nameCases', 'colorCases'];
    expect(
      table.keys.toSet(),
      {
        'description', 'theme', 'gap', ...groups,
        // Schema 9.19.0, an icon from data: the groups are run by `icon_path_cases_test.dart`.
        'iconPathNote', 'iconPathCases', 'iconPathDocumentCases', //
      },
      reason: 'a new table group is a rule this test does not run',
    );
    expect([for (final group in groups) rows(group).length], [17, 5, 6, 5, 4, 2]);

    // The rows rely on these numbers; if the built-in theme moves, the table must
    // fail here, not through twenty unclear pixels below.
    final theme = table['theme']! as Map<String, Object?>;
    for (final entry in (theme['spacing']! as Map<String, Object?>).entries) {
      expect(_theme.space(SpacingToken.values.byName(entry.key)), entry.value, reason: 'spacing.${entry.key}');
    }
    for (final entry in (theme['typography']! as Map<String, Object?>).entries) {
      final declared = entry.value! as Map<String, Object?>;
      final style = _theme.text(TypographyToken.values.byName(entry.key));
      expect(style.fontSize, declared['fontSize'], reason: entry.key);
      expect(style.height, closeTo((declared['lineHeight']! as num).toDouble(), 0.0001), reason: entry.key);
    }
    expect(table['gap'], kIconBesideTextGap.wire);
  });

  group('table - orderCases: where the icon sits, whether it is drawn, whether it is flipped', () {
    for (final row in rows('orderCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final widget = row['widget']! as String;
        final direction = row['direction']! as String;
        final expected = row['expect']! as Map<String, Object?>;
        await _pump(tester, [_placeNode(widget, row['props']! as Map<String, Object?>)], direction: direction);
        expect(tester.takeException(), isNull);

        final box = _iconBox;
        final logical = (expected['logical']! as List<Object?>).cast<String>();
        final visual = (expected['visual']! as List<Object?>).cast<String>();

        if (!logical.contains('icon')) {
          expect(box, findsNothing, reason: 'no icon - no box either');
          expect(expected['drawn'], isFalse);
          return;
        }
        expect(box, findsOneWidget);

        // VISUAL - left to right on screen, as a person sees it.
        final textRect = tester.getRect(_label);
        final boxRect = tester.getRect(box);
        final shown = boxRect.center.dx < textRect.center.dx ? ['icon', 'text'] : ['text', 'icon'];
        expect(shown, visual, reason: 'visual');
        // LOGICAL - in writing direction: in RTL the same order reads from the right.
        expect(direction == 'rtl' ? shown.reversed.toList() : shown, logical, reason: 'logical');
        expect(Directionality.of(tester.element(box)), direction == 'rtl' ? TextDirection.rtl : TextDirection.ltr);

        // The parts do not overlap, and between them there is exactly the rule gap.
        final gap = boxRect.center.dx < textRect.center.dx
            ? textRect.left - boxRect.right
            : boxRect.left - textRect.right;
        expect(gap, _theme.space(kIconBesideTextGap), reason: 'the gap stays even with an empty box');

        // DRAWN - whether there is a drawing; an empty box of the same size is not.
        final painter = _painterIn(tester, box);
        expect(painter != null, expected['drawn'], reason: 'drawn');
        // MIRRORED - mirroring of the DRAWING, separate from the order and exactly once.
        expect(painter?.mirrored ?? false, expected['mirrored'], reason: 'mirrored');
      });
    }
  });

  group('table - glyphCases: glyph size, box, gap and how much the widget grows', () {
    for (final row in rows('glyphCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final widget = row['widget']! as String;
        final expected = row['expect']! as Map<String, Object?>;
        final size = row['size'] as String?;
        Map<String, Object?> node({required bool icon}) =>
            _placeNode(widget, {'icon': ?(icon ? 'gift' : null), 'size': ?(widget == 'Button' ? size : null)});

        await _pump(tester, [node(icon: false)]);
        final bare = _placeSize(tester, widget);
        final bareTextRight = tester.getRect(_label).right;

        await _pump(tester, [node(icon: true)]);
        final withIcon = _placeSize(tester, widget);
        final box = _iconBox;
        final boxSize = tester.getSize(box);

        // The font the label is actually set in is the one the table row names.
        final typography = _theme.text(TypographyToken.values.byName(row['typography']! as String));
        expect(tester.getSize(find.descendant(of: box, matching: find.byType(IconGlyph))),
            _size((expected['glyph']! as num).toDouble()), reason: 'glyph');
        expect(expected['glyph'], typography.fontSize, reason: 'the glyph is at the font size of the named font');
        expect(boxSize.width, expected['boxInline'], reason: 'boxInline');
        expect(boxSize.height, closeTo((expected['boxBlock']! as num).toDouble(), 0.01), reason: 'boxBlock');

        final textRect = tester.getRect(_label);
        final boxRect = tester.getRect(box);
        final gap = boxRect.left > textRect.left ? boxRect.left - textRect.right : textRect.left - boxRect.right;
        expect(gap, expected['gap'], reason: 'gap');
        // The box centre is on the centre of the text LINE, not on the baseline.
        expect(boxRect.center.dy, closeTo(textRect.center.dy, 0.01), reason: 'crossAlign: center');

        if (widget == 'ListTile') {
          // The row takes the whole width, so "how much wider" is measured on the slot:
          // from the right edge of the text without an icon to the left edge of the text with it.
          expect(bareTextRight - textRect.right, expected['addsInline'], reason: 'addsInline');
        } else {
          expect(withIcon.width - bare.width, expected['addsInline'], reason: 'addsInline');
        }
        expect(withIcon.height - bare.height, closeTo((expected['addsBlock']! as num).toDouble(), 0.01),
            reason: 'addsBlock: the icon does not change the height');
      });
    }
  });

  group('table - buttonSizeCases: padding, font and button height', () {
    for (final row in rows('buttonSizeCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final expected = row['expect']! as Map<String, Object?>;
        final border = (row['border']! as num).toDouble();
        // The border comes from the ROLE: `secondary` of the built-in theme has a `border` slot.
        final variant = border == 0 ? 'primary' : 'secondary';
        expect(_theme.buttonVariant(ButtonVariantToken.parse(variant)).border != null, border != 0,
            reason: 'precondition: role border');
        expect(border == 0 ? 0 : kRoleBorderWidth, border);

        await _pump(tester, [_button({'size': ?row['size']}, variant: variant)]);
        final button = tester.getRect(_anyButton);
        final text = tester.getRect(_label);
        final style = DefaultTextStyle.of(tester.element(_label)).style;
        final typography = _theme.text(TypographyToken.values.byName(expected['typography']! as String));

        expect(button.height, expected['block'], reason: 'block');
        expect(text.top - button.top - border, expected['paddingBlock'], reason: 'paddingBlock');
        expect(button.bottom - text.bottom - border, expected['paddingBlock'], reason: 'paddingBlock (bottom)');
        expect(text.left - button.left - border, expected['paddingInline'], reason: 'paddingInline');
        expect(button.right - text.right - border, expected['paddingInline'], reason: 'paddingInline (end)');
        expect(style.fontSize, typography.fontSize, reason: 'typography');
        expect(style.fontWeight, typography.fontWeight, reason: 'typography: weight');
        expect(style.height, typography.height, reason: 'typography: line');
      });
    }
  });

  group('table - iconButtonCases: side, drawing and padding of the icon button', () {
    for (final row in rows('iconButtonCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final expected = row['expect']! as Map<String, Object?>;
        final border = (row['border']! as num).toDouble();
        await _pump(tester, [
          _iconButton({'size': row['size'], 'variant': border == 0 ? 'primary' : 'secondary'}),
        ]);
        final button = tester.getRect(_anyButton);
        final box = tester.getRect(find.byType(IconBox));
        final glyph = tester.getRect(find.byType(IconGlyph));

        expect(button.size, _size((expected['side']! as num).toDouble()), reason: 'side: square');
        expect(glyph.size, _size((expected['glyph']! as num).toDouble()), reason: 'glyph');
        expect(glyph.center, within<Offset>(distance: 0.01, from: box.center), reason: 'drawing centred in the box');
        expect(box.center, within<Offset>(distance: 0.01, from: button.center), reason: 'box centred in the button');
        expect(box.width, closeTo(box.height, 0.01), reason: 'the content box is a square');
        // The padding is the same on ALL four sides.
        for (final side in [
          box.left - button.left,
          button.right - box.right,
          box.top - button.top,
          button.bottom - box.bottom,
        ]) {
          expect(side - border, closeTo((expected['padding']! as num).toDouble(), 0.01), reason: 'padding');
        }
      });
    }
  });

  group('table - nameCases: accessible name of the icon button', () {
    for (final row in rows('nameCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, [
          _iconButton({
            'icon': row['icon'],
            'label': {'kind': 'literal', 'value': row['label']},
          }),
        ]);
        expect(tester.takeException(), isNull);
        // The button EXISTS even with an empty name: button role, tap action.
        expect(
          tester.getSemantics(_anyButton),
          isSemantics(label: row['expect']! as String, isButton: true, hasTapAction: true),
        );
        // The name is not painted on screen.
        expect(find.byType(Text), findsNothing);
        handle.dispose();
      });
    }
  });

  group('table - colorCases: colour of the row trailing text and the icon beside it', () {
    for (final row in rows('colorCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final expected = row['expect']! as Map<String, Object?>;
        final named = row['named'] as String?;
        await _pump(tester, [
          _tile({'icon': 'coins'}, style: named == null ? null : {'color': named}),
        ]);
        expect(
          tester.widget<Text>(_label).style!.color,
          _theme.color(ColorToken.values.byName(expected['text']! as String)),
          reason: 'text',
        );
        expect(
          tester.widget<IconBox>(_iconBox).color,
          _theme.color(ColorToken.values.byName(expected['icon']! as String)),
          reason: 'icon',
        );
      });
    }
  });

  group('9.5.0 mirrors against the artifact', () {
    final compatibility = schema['x-compatibility']! as Map<String, Object?>;

    test('version, widget, capabilities, three policy rows', () {
      // The reader version moved on (9.6.0), and this test asks what 9.5.0 can do.
      expect(schema['x-schemaVersion'], kSupportedSchemaVersion);
      expect(
        SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 5, 0)),
        greaterThanOrEqualTo(0),
      );
      expect((compatibility['widgets']! as Map)['IconButton'], '9.5.0');
      expect(kWidgetCatalog['IconButton'], '9.5.0');
      expect(widgetOriginOf('IconButton'), WidgetOrigin.contractual);
      expect(widgetOriginOf('IconButton', readerVersion: '9.4.0'), isNot(WidgetOrigin.contractual));
      final features = compatibility['features']! as Map<String, Object?>;
      for (final feature in ['iconBesideLabel', 'iconBesideTextRule']) {
        expect(features[feature], '9.5.0');
        expect(kFeatureCatalog[feature], '9.5.0');
        expect(supportsFeature(feature, readerVersion: '9.4.0'), isFalse);
      }
      final policy = compatibility['policy']! as Map<String, Object?>;
      expect(kIconTextPolicy, hasLength(3));
      for (final entry in kIconTextPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // Next come five 9.5.0 clarification rows about the template (guarded by `template_cases_test.dart`) and seven 9.6.0 rows.
      expect(policy.keys.toList().sublist(policy.length - 15 - kActionPolicy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - 12 - kActionPolicy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length)), kIconTextPolicy.keys.toList());
    });

    test('buttonSizes and defaultButtonSize - the tokens the renderer computes with', () {
      final sizes = layout['buttonSizes']! as Map<String, Object?>;
      expect(sizes.keys.toList(), [for (final size in ButtonSizeToken.values) size.name]);
      for (final size in ButtonSizeToken.values) {
        final geometry = buttonGeometryOf(size);
        expect(sizes[size.name], {
          'padding': {'block': geometry.block.wire, 'inline': geometry.inline.wire},
          'typography': geometry.typography.wire,
        }, reason: size.name);
      }
      expect(layout['defaultButtonSize'], kDefaultButtonSize.name);
      // `md` is exactly the pre-9.5.0 button: the old keys remain and equal it.
      expect(sizes['md'], {'padding': layout['buttonPadding'], 'typography': layout['buttonTypography']});
    });

    test('iconButton, iconBesideText and listTileTrailingColor', () {
      expect(layout['iconButton'], kIconButtonLayout);
      final rule = Map<String, Object?>.of(layout['iconBesideText']! as Map<String, Object?>);
      final places = rule.remove('places')! as Map<String, Object?>;
      expect(rule, kIconBesideText);
      expect(rule['gap'], kIconBesideTextGap.wire);
      expect(rule['defaultPosition'], kDefaultIconPosition.name);
      // The three places are exactly those where the renderer calls the shared rule; the row slot
      // takes the icon scale step and a fixed position.
      expect(places.keys.toSet(), {'Button', 'Badge', 'ListTile'});
      expect(places['ListTile'], {
        'text': 'trailing.text',
        'icon': 'trailing.icon',
        'position': 'end',
        'glyph': 'listTileIconSizes.trailingIcon',
      });
      expect((layout['listTileIconSizes']! as Map)['trailingIcon'], kListTileTrailingIconSize.wire);
      for (final place in ['Button', 'Badge']) {
        expect(places[place], {'text': 'label', 'icon': 'icon', 'position': 'iconPosition', 'glyph': 'text'});
      }
      expect(layout['listTileTrailingColor'], kListTileTrailingColor.wire);
    });

    test('roles and schema: IconButton reads the button group; three button fields without a schema default', () {
      final roles = ((schema['x-style']! as Map)['roles']! as Map)['widgets']! as Map<String, Object?>;
      expect(roles.keys.toSet(), kRoleWidgets.keys.toSet());
      expect(roles['IconButton'], {'prop': 'variant', 'group': 'buttonVariant'});
      expect(kRoleWidgets['IconButton'], (prop: 'variant', group: 'buttonVariant'));

      final defs = schema[r'$defs']! as Map<String, Object?>;
      Map<String, Object?> props(String def) => (defs[def]! as Map)['properties']! as Map<String, Object?>;
      for (final (def, prop) in [
        ('ButtonProps', 'icon'),
        ('ButtonProps', 'iconPosition'),
        ('ButtonProps', 'size'),
        ('BadgeProps', 'icon'),
        ('BadgeProps', 'iconPosition'),
      ]) {
        // The default of these fields lives in `x-style.layout`. If the schema ever
        // adds one, there will be two defaults, and they will diverge silently.
        expect((props(def)[prop]! as Map).containsKey('default'), isFalse, reason: '$def.$prop');
        expect(((defs[def]! as Map)['required']! as List).contains(prop), isFalse, reason: '$def.$prop');
      }
      expect((defs['ButtonSize']! as Map)['enum'], [for (final size in ButtonSizeToken.values) size.name]);
      expect((defs['IconPosition']! as Map)['enum'], [for (final position in IconPositionToken.values) position.name]);
    });
  });

  group('parsing: no field, unknown word, value not a string', () {
    ButtonNode button(Map<String, Object?> props) =>
        flattenDocument(_doc([_button(props)])).whereType<ButtonNode>().single;
    BadgeNode badge(Map<String, Object?> props) =>
        flattenDocument(_doc([_badge(props)])).whereType<BadgeNode>().single;

    test('no fields - button and badge as before 9.5.0: no icon, md, start', () {
      expect(button(const {}).icon, isNull);
      expect(button(const {}).size, ButtonSizeToken.md);
      expect(button(const {}).iconPosition, IconPositionToken.start);
      expect(badge(const {}).icon, isNull);
      // `null` is also "no field" (unlike the row slot, where a key with
      // `null` gives an empty box since 9.3.0 - that rule was not touched).
      expect(button(const {'icon': null}).icon, isNull);
      expect(badge(const {'icon': null}).icon, isNull);
    });

    test('size and position outside the list or not a string - the default from data, no exception', () {
      for (final broken in <Object?>['xl', 'MD', '', 7, true, <String>['sm'], <String, Object?>{'size': 'sm'}]) {
        expect(button({'size': broken}).size, kDefaultButtonSize, reason: '$broken');
        expect(button({'icon': 'gift', 'iconPosition': broken}).iconPosition, kDefaultIconPosition, reason: '$broken');
        expect(badge({'icon': 'gift', 'iconPosition': broken}).iconPosition, kDefaultIconPosition, reason: '$broken');
      }
    });

    test('icon named but not from the set or not a string - IconToken.unknown, not "no icon"', () {
      for (final broken in <Object?>['icon-from-the-future', '', 7, false, <String>[], <String, Object?>{'kind': 'media'}]) {
        expect(button({'icon': broken}).icon, same(IconToken.unknown), reason: '$broken');
        expect(badge({'icon': broken}).icon, same(IconToken.unknown), reason: '$broken');
      }
      expect(button(const {'icon': 'toString'}).icon, same(IconToken.unknown));
    });

    test('IconButton: schema FIELD defaults (info, secondary, md), and a corrupted icon is an empty box', () {
      IconButtonNode node(Map<String, Object?> props) => flattenDocument(
        _doc([
          {'id': 'ib', 'type': 'IconButton', 'props': props},
        ]),
      ).whereType<IconButtonNode>().single;

      final bare = node(const {});
      expect(bare.icon.wire, 'info');
      expect(bare.iconName, 'info');
      expect(bare.variant, ButtonVariantToken.secondary);
      expect(bare.size, ButtonSizeToken.md);
      expect(bare.action.type, isNot('navigate'));

      expect(node(const {'variant': 'outline'}).variant, ButtonVariantToken.secondary);
      expect(node(const {'variant': 7}).variant, ButtonVariantToken.secondary);
      expect(node(const {'size': 'huge'}).size, ButtonSizeToken.md);

      final unknown = node(const {'icon': 'icon-from-the-future'});
      expect(unknown.icon, same(IconToken.unknown));
      expect(unknown.iconName, 'icon-from-the-future', reason: 'the name for the screen reader remains');
      expect(node(const {'icon': 7}).iconName, isNull);
      expect(node(const {'icon': null}).iconName, isNull);
    });

    testWidgets('a screen with corrupted fields in every place paints without an exception', (tester) async {
      for (final broken in <Object?>[7, true, <Object?>[], <String, Object?>{}, 'nope', '']) {
        await _pump(tester, [
          _button({'icon': broken, 'iconPosition': broken, 'size': broken, 'variant': broken}),
          _badge({'icon': broken, 'iconPosition': broken, 'tone': broken}),
          _tile({'icon': broken}),
          {
            'id': 'ib',
            'type': 'IconButton',
            'props': {'icon': broken, 'label': broken, 'variant': broken, 'size': broken, 'action': broken},
          },
        ]);
        expect(tester.takeException(), isNull, reason: '$broken');
        // All four places on screen: three boxes beside text and an icon button.
        expect(find.byType(IconBox), findsNWidgets(4), reason: '$broken');
        expect(_anyButton, findsNWidgets(2), reason: '$broken');
      }
    });
  });

  group('button: sizes, icon and own style', () {
    testWidgets('three sizes - 28 / 40 / 48, and the radius does not depend on the size', (tester) async {
      await _pump(tester, [
        for (final size in ['sm', 'md', 'lg']) _button({'size': size}, id: size),
      ]);
      final heights = [for (final element in _anyButton.evaluate()) element.size!.height];
      expect(heights, [28, 40, 48]);
      final shapes = [
        for (final button in tester.widgetList<ButtonStyleButton>(_anyButton))
          button.style!.shape!.resolve(const {}),
      ];
      expect(shapes.toSet(), hasLength(1));
      expect(
        (shapes.first! as RoundedRectangleBorder).borderRadius,
        _theme.borderRadius(RadiusToken.md),
      );
    });

    testWidgets('a button without the new fields is exactly the pre-9.5.0 one: 40 tall, padding 12, titleS', (tester) async {
      await _pump(tester, [_button(const {})]);
      final button = tester.getRect(_anyButton);
      final text = tester.getRect(_label);
      expect(button.height, 40);
      // Ahem: five characters x font size 16.
      expect(button.width, 5 * 16 + 2 * 12);
      expect(text.left - button.left, 12);
      expect(find.byType(IconBox), findsNothing);
    });

    testWidgets('own style beats the size, EACH FIELD SEPARATELY', (tester) async {
      // Padding only: the font stays at size `lg` (titleM).
      await _pump(tester, [
        _button({'size': 'lg'}, style: {'padding': 'xs'}),
      ]);
      var button = tester.getRect(_anyButton);
      var text = tester.getRect(_label);
      expect(text.left - button.left, 4);
      expect(text.top - button.top, 4);
      expect(DefaultTextStyle.of(tester.element(_label)).style.fontSize, 18);

      // Font only: the padding stays at size `sm` (4 / 12).
      await _pump(tester, [
        _button({'size': 'sm', 'icon': 'gift'}, style: {'typography': 'titleM'}),
      ]);
      button = tester.getRect(_anyButton);
      text = tester.getRect(_label);
      expect(DefaultTextStyle.of(tester.element(_label)).style.fontSize, 18);
      expect(text.top - button.top, 4);
      // The icon follows the font the label is ACTUALLY set in: 18 x 24, not 14 x 20.
      expect(tester.getSize(_iconBox), _size(18, 24));
      expect(tester.getRect(_iconBox).left - button.left, 12);
    });

    testWidgets('"full width": the "icon + label" pair is centred TOGETHER', (tester) async {
      await _pump(tester, [_button({'icon': 'gift'}, fullWidth: true)]);
      final button = tester.getRect(_anyButton);
      final text = tester.getRect(_label);
      final box = tester.getRect(_iconBox);
      expect(button.width, 800, reason: 'precondition: the button spans the test window width');
      expect(text.left - box.right, 4, reason: 'the pair is not pushed to the edges');
      expect((box.left + text.right) / 2, button.center.dx);
    });

    testWidgets('icon colour is the label colour: role slot or style.color', (tester) async {
      await _pump(tester, [_button({'icon': 'gift'}, variant: 'secondary')]);
      expect(
        tester.widget<IconBox>(_iconBox).color,
        _theme.buttonVariant(ButtonVariantToken.secondary).foreground,
      );
      await _pump(tester, [
        _button({'icon': 'gift'}, style: {'color': 'danger'}),
      ]);
      expect(tester.widget<IconBox>(_iconBox).color, _theme.color(ColorToken.danger));
    });

    testWidgets('an icon that cannot be drawn - the empty box of the SAME size and the gap remain', (tester) async {
      await _pump(tester, [_button(const {'icon': 'gift'})]);
      final known = tester.getSize(_anyButton);
      for (final broken in <Object?>['icon-from-the-future', 7, <String, Object?>{'kind': 'media'}]) {
        await _pump(tester, [_button({'icon': broken})]);
        expect(tester.getSize(_anyButton), known, reason: '$broken');
        expect(_painterIn(tester, _iconBox), isNull, reason: 'no drawing');
      }
    });

    testWidgets('an empty label beside an icon: icon and gap as they are', (tester) async {
      await _pump(tester, [
        _button({'icon': 'gift'}, label: {'kind': 'literal', 'value': ''}),
      ]);
      final button = tester.getRect(_anyButton);
      final box = tester.getRect(find.byType(IconBox));
      // Padding 12, box 16, gap 4, empty text 0, padding 12.
      expect(button.width, 12 + 16 + 4 + 0 + 12);
      expect(box.left - button.left, 12);
      expect(button.height, 40);
    });

    testWidgets('the icon grows with the system font scale together with the label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: renderDocument(_doc([_button(const {'icon': 'gift'})]), theme: _theme, data: const {}),
            ),
          ),
        ),
      );
      expect(tester.getSize(_iconBox), _size(32, 48));
      expect(tester.getSize(_label).height, 48);
    });
  });

  group('icon button', () {
    testWidgets('three sizes beside buttons of the same sizes - level', (tester) async {
      for (final (size, side) in [('sm', 28.0), ('md', 40.0), ('lg', 48.0)]) {
        await _pump(tester, [
          {
            'id': 'row',
            'type': 'Row',
            'props': {'gap': 'sm', 'align': 'center', 'justify': 'start', 'wrap': false, 'scrollable': false},
            'children': [
              _iconButton({'size': size}),
              _button({'size': size}),
            ],
          },
        ]);
        final rects = [for (final element in _anyButton.evaluate()) tester.getRect(find.byWidget(element.widget))];
        expect(rects[0].size, _size(side), reason: size);
        expect(rects[1].height, side, reason: 'a button of the same size');
        expect(rects[0].top, closeTo(rects[1].top, 0.01));
        expect(rects[1].left - rects[0].right, closeTo(8, 0.01), reason: 'in a row it has its natural width, the gap comes from the document');
      }
    });

    testWidgets('radius is pill: a circle; the border of a tonal one is hairline and adds to the side', (tester) async {
      await _pump(tester, [_iconButton(const {'variant': 'secondary'})]);
      final button = tester.widget<ButtonStyleButton>(_anyButton);
      expect(button, isA<OutlinedButton>());
      expect(
        (button.style!.shape!.resolve(const {})! as RoundedRectangleBorder).borderRadius,
        _theme.borderRadius(RadiusToken.pill),
      );
      expect(button.style!.side!.resolve(const {})!.width, kRoleBorderWidth);
      expect(tester.getSize(_anyButton), _size(42));
    });

    testWidgets('three variants - three role shapes; the drawing colour is the foreground slot', (tester) async {
      for (final (variant, type) in [('primary', FilledButton), ('secondary', OutlinedButton), ('ghost', TextButton)]) {
        await _pump(tester, [_iconButton({'variant': variant})]);
        expect(tester.widget(_anyButton).runtimeType, type, reason: variant);
        expect(
          tester.widget<IconBox>(find.byType(IconBox)).color,
          _theme.buttonVariant(ButtonVariantToken.parse(variant)).foreground,
          reason: variant,
        );
        // And without a background the circle stays a circle at the moment of pressing.
        expect(
          (tester.widget<ButtonStyleButton>(_anyButton).style!.shape!.resolve(const {})! as RoundedRectangleBorder)
              .borderRadius,
          _theme.borderRadius(RadiusToken.pill),
          reason: variant,
        );
      }
    });

    testWidgets('own style: padding is the padding, typography - both the drawing and the square, radius - the rounding, color - the drawing', (tester) async {
      await _pump(tester, [
        _iconButton(const {}, style: {'padding': 'xs', 'typography': 'titleM', 'radius': 'md', 'color': 'danger'}),
      ]);
      // The titleM line is 24, drawing 18, padding 4.
      expect(tester.getSize(_anyButton), _size(24 + 2 * 4));
      expect(tester.getSize(find.byType(IconGlyph)), _size(18));
      // The style lands on the button surface ITSELF (`roles.appliesTo: 'widget-surface'`),
      // not on a box around it: otherwise the padding would act twice and the button would shift.
      expect(tester.getTopLeft(_anyButton), Offset.zero);
      expect(tester.widget<IconBox>(find.byType(IconBox)).color, _theme.color(ColorToken.danger));
      expect(
        (tester.widget<ButtonStyleButton>(_anyButton).style!.shape!.resolve(const {})! as RoundedRectangleBorder)
            .borderRadius
            .resolve(TextDirection.ltr),
        _theme.borderRadius(RadiusToken.md),
      );
    });

    testWidgets('an ancestor-inherited colour does not override the role', (tester) async {
      await _pump(tester, [
        {
          'id': 'col',
          'type': 'Column',
          'props': {'gap': 'sm', 'align': 'start'},
          'style': {'color': 'danger'},
          'children': [_iconButton(const {'variant': 'ghost'})],
        },
      ]);
      expect(
        tester.widget<IconBox>(find.byType(IconBox)).color,
        _theme.buttonVariant(ButtonVariantToken.ghost).foreground,
      );
    });

    testWidgets('in a column it has its natural width, not full', (tester) async {
      await _pump(tester, [_iconButton(const {})]);
      expect(tester.getSize(_anyButton), _size(40));
      expect(tester.getTopLeft(_anyButton).dx, 0, reason: 'at the logical start');
    });

    testWidgets('the action is the same as the button one: goes to the host with the node id', (tester) async {
      final actions = <String>[];
      await _pump(tester, [_iconButton(const {})], onAction: (action, id) => actions.add('${action.type}:$id'));
      await tester.tap(_anyButton);
      expect(actions, ['press:ib']);
    });

    testWidgets('navigate of the icon button goes through the document stack, and the row record travels with the action', (tester) async {
      final records = <Map<String, Object?>?>[];
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'flow',
        'name': 'flow',
        'initialScreenId': 'list',
        'screens': [
          screenEntry('list', [
            {
              'id': 'rep',
              'type': 'Repeater',
              'props': {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'sm'},
              'children': [
                _iconButton(const {
                  'label': {'kind': 'binding', 'path': 'item.name', 'fallback': 'Open'},
                  'action': {'type': 'share'},
                }),
              ],
            },
          ]),
        ],
      });
      final handle = tester.ensureSemantics();
      await pumpDocument(
        tester,
        doc,
        theme: _theme,
        data: const {
          'items': [
            {'name': 'Bottle'},
            {'name': 'Backpack'},
          ],
        },
        onRecordAction: (action, id, record) => records.add(record),
      );
      // The name is the label AFTER data substitution, each instance has its own.
      expect(find.bySemanticsLabel('Bottle'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Backpack'));
      expect(records.single, {'item.name': 'Backpack'});
      handle.dispose();
    });
  });

  group('badge with an icon', () {
    testWidgets('icon colour is the label colour: tone role slot or style.color', (tester) async {
      await _pump(tester, [_badge(const {'icon': 'clock'})]);
      final role = _theme.badgeTone(BadgeToneToken.neutral).foreground;
      expect(tester.widget<Text>(_label).style!.color, role);
      expect(tester.widget<IconBox>(_iconBox).color, role);

      await _pump(tester, [
        _badge(const {'icon': 'clock'}, style: {'color': 'danger'}),
      ]);
      expect(tester.widget<Text>(_label).style!.color, _theme.color(ColorToken.danger));
      expect(tester.widget<IconBox>(_iconBox).color, _theme.color(ColorToken.danger));
    });

    testWidgets('the icon follows the font the label is set in: caption 10 x 12, and with style.typography - that one', (tester) async {
      await _pump(tester, [_badge(const {'icon': 'clock'})]);
      expect(tester.getSize(_iconBox), _size(10, 12));
      await _pump(tester, [
        _badge(const {'icon': 'clock', 'iconPosition': 'end'}, style: {'typography': 'bodyS'}),
      ]);
      expect(tester.getSize(_iconBox), _size(12, 16));
      expect(tester.getRect(_iconBox).left - tester.getRect(_label).right, 4);
    });
  });

  group('accessibility', () {
    testWidgets('button with an icon: button role, name is the label; the icon is not part of the name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [_button(const {'icon': 'gift'})]);
      expect(tester.getSemantics(_anyButton), isSemantics(label: 'Label', isButton: true, hasTapAction: true));
      handle.dispose();
    });

    testWidgets('icon button: name from label AFTER translation, not on screen', (tester) async {
      final handle = tester.ensureSemantics();
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'names',
        'name': 'names',
        'initialScreenId': 's',
        'screens': [
          screenEntry('s', [_iconButton(const {}, id: 'back')]),
        ],
        'localization': {
          'defaultLocale': 'en',
          'locales': ['en', 'uk'],
          'strings': {
            'uk': {'s/back/label': 'Назад'},
          },
        },
      });
      await pumpDocument(tester, doc, theme: _theme, locale: 'uk');
      expect(tester.getSemantics(_anyButton), isSemantics(label: 'Назад', isButton: true, hasTapAction: true));
      expect(find.text('Назад'), findsNothing);
      expect(find.text('Back'), findsNothing);
      await pumpDocument(tester, doc, theme: _theme, locale: 'en');
      expect(tester.getSemantics(_anyButton), isSemantics(label: 'Back', isButton: true));
      handle.dispose();
    });

    testWidgets('badge with an icon is text, NOT a control: no button role, no action, no touch', (tester) async {
      final handle = tester.ensureSemantics();
      final actions = <ButtonAction>[];
      await _pump(tester, [_badge(const {'icon': 'clock'})], onAction: (action, _) => actions.add(action));
      final semantics = tester.getSemantics(_label);
      expect(semantics, isSemantics(label: 'Label'));
      expect(semantics.flagsCollection.isButton, isFalse);
      expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(_label);
      expect(actions, isEmpty);
      expect(_anyButton, findsNothing);
      handle.dispose();
    });
  });

  group('touch target - an area, not a size', () {
    testWidgets('small button 28 and small icon button 28: visible size not inflated, the touch is caught in a strip up to 48', (tester) async {
      final actions = <String>[];
      await _pump(
        tester,
        [
          textNode('Над'),
          _button(const {'size': 'sm'}, id: 'small'),
          textNode('Між', id: 'mid'),
          _iconButton(const {'size': 'sm'}, id: 'round'),
          textNode('Під', id: 'under'),
        ],
        onAction: (action, id) => actions.add(id),
      );
      final buttons = [for (final element in _anyButton.evaluate()) tester.getRect(find.byWidget(element.widget))];
      expect(buttons[0].height, 28);
      expect(buttons[1].size, _size(28));
      // Neighbours are spaced by the document gap (md = 12), not by 48 dp.
      expect(buttons[0].top - tester.getRect(find.text('Над')).bottom, 12);
      expect(tester.getRect(find.text('Між')).top - buttons[0].bottom, 12);

      // (48 - 28) / 2 = 10 dp of strip on each side.
      await tester.tapAt(Offset(buttons[0].center.dx, buttons[0].top - 8));
      await tester.tapAt(Offset(buttons[1].center.dx, buttons[1].bottom + 8));
      // And at the side of the circle: the width is also completed to 48.
      await tester.tapAt(Offset(buttons[1].right + 8, buttons[1].center.dy));
      expect(actions, ['small', 'round', 'round']);

      // Beyond 48 dp the button touch does not take over.
      await tester.tapAt(Offset(buttons[1].right + 14, buttons[1].center.dy));
      expect(actions, hasLength(3));
    });
  });

  group('list row slot: what 9.5.0 changed and what it did not', () {
    testWidgets('trailing text is onSurface and WITHOUT an icon; subtitle and chevron are muted', (tester) async {
      await _pump(tester, [
        {
          'id': 'tile',
          'type': 'ListTile',
          'props': {
            'leading': {'kind': 'none'},
            'title': {'kind': 'literal', 'value': 'Title'},
            'subtitle': {'kind': 'literal', 'value': 'Sub'},
            'trailing': {'kind': 'text', 'text': _literal},
          },
        },
        {
          'id': 'chev',
          'type': 'ListTile',
          'props': {
            'leading': {'kind': 'none'},
            'title': {'kind': 'literal', 'value': 'Other'},
            'trailing': {'kind': 'chevron'},
          },
        },
      ]);
      expect(tester.widget<Text>(_label).style!.color, _theme.color(ColorToken.onSurface));
      expect(tester.widget<Text>(_label).style!.color, tester.widget<Text>(find.text('Title')).style!.color,
          reason: 'colour of the row title');
      expect(tester.widget<Text>(find.text('Sub')).style!.color, _theme.color(ColorToken.muted));
      expect(iconColorOf(tester, findIcon(IconToken.chevron)), _theme.color(ColorToken.muted));
    });

    testWidgets('with a named colour the slot text and icon are PRIMARY parts (without x 0.6), the chevron is secondary', (tester) async {
      await _pump(tester, [
        _tile({'icon': 'coins'}, style: {'color': 'danger'}),
      ]);
      final named = _theme.color(ColorToken.danger);
      expect(tester.widget<Text>(_label).style!.color, named);
      expect(tester.widget<IconBox>(_iconBox).color, named);
    });

    testWidgets('slot icon size did NOT change: step sm - drawing 12, box 12 x 16, not the text font size 14', (tester) async {
      await _pump(tester, [_tile(const {'icon': 'coins'})]);
      expect(tester.getSize(_iconBox), _size(12, 16));
      expect(tester.widget<Text>(_label).style!.fontSize, 14);
    });
  });

  group('buttons-chips-screens fixture', () {
    final doc = loadFixture('buttons-chips-screens');
    final now = DateTime.parse(kSampleNow);

    Future<void> pump(WidgetTester tester, String locale) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpDocument(tester, doc, data: sampleScreenData, locale: locale, now: now);
    }

    Rect buttonWith(WidgetTester tester, String label) =>
        tester.getRect(find.ancestor(of: find.text(label), matching: _anyButton));

    testWidgets('the 9.5.0 document reads whole: no unknown node, 9 icon buttons', (tester) async {
      expect(doc.schemaVersion, '9.5.0');
      final nodes = flattenDocument(doc).toList();
      expect(nodes.whereType<UnknownNode>(), isEmpty);
      expect(nodes.whereType<IconButtonNode>(), hasLength(9));
      expect(nodes.whereType<IconButtonNode>().every((node) => node.icon.isKnown), isTrue);
      await pump(tester, 'en');
      expect(tester.takeException(), isNull);
    });

    testWidgets('in English: the table numbers - icon buttons 30 / 42 / 50, buttons 28 / 40 / 48, chip and slot', (tester) async {
      await pump(tester, 'en');
      final handle = tester.ensureSemantics();

      // Tonal icon buttons of three sizes: the side plus the role hairline border.
      final back = find.bySemanticsLabel('Back');
      expect([for (final element in back.evaluate()) element.size], [_size(30), _size(42), _size(50)]);
      // ghost and primary have no border: 40.
      expect(tester.getSize(find.bySemanticsLabel('About this reward')), _size(40));
      expect(tester.getSize(find.bySemanticsLabel('Close')), _size(40));

      expect(buttonWith(tester, 'See all').height, closeTo(28, 0.01));
      expect(buttonWith(tester, 'Redeem').height, closeTo(40, 0.01));
      expect(buttonWith(tester, 'Continue').height, closeTo(48, 0.01));
      expect(buttonWith(tester, 'Claim reward').width, 390 - 2 * 16, reason: 'full width of the screen content');

      // "See all >": icon after the text; "Redeem" with a gift at the start.
      expect(tester.getRect(findIcon(IconToken.parse('chevron-right'))).left,
          greaterThan(tester.getRect(find.text('See all')).right));
      expect(tester.getRect(findIcon(IconToken.parse('gift')).first).right,
          lessThan(tester.getRect(find.text('Redeem')).left));

      // Chip "52 days left" with a clock, "Medium o" with a circle at the end.
      expect(tester.getRect(findIcon(IconToken.parse('clock'))).right,
          lessThan(tester.getRect(find.text('52 days left')).left));
      expect(tester.getRect(findIcon(IconToken.parse('circle'))).left,
          greaterThan(tester.getRect(find.text('Medium')).right));

      // Row "Coffee voucher" with "120 ◎": text and icon in the title colour.
      final title = tester.widget<Text>(find.text('Coffee voucher')).style!.color;
      expect(tester.widget<Text>(find.text('120')).style!.color, title);
      expect(iconColorOf(tester, findIcon(IconToken.parse('coins'))), title);
      handle.dispose();
    });

    testWidgets('in Arabic: arrows from the other side AND flipped, the gift only from the other side', (tester) async {
      await pump(tester, 'ar');
      expect(tester.takeException(), isNull);
      final continueLabel = find.descendant(
        of: find.ancestor(of: findIcon(IconToken.parse('arrow-right')).first, matching: _anyButton),
        matching: find.byType(Text),
      );
      final arrow = findIcon(IconToken.parse('arrow-right')).first;
      expect(Directionality.of(tester.element(arrow)), TextDirection.rtl);
      // `end` in RTL is to the LEFT of the label.
      expect(tester.getRect(arrow).right, lessThan(tester.getRect(continueLabel).left));
      expect(_painterIn(tester, find.ancestor(of: arrow, matching: find.byType(IconBox)))!.mirrored, isTrue);

      // The gift of the "Redeem" button: `start` in RTL is to the RIGHT, the drawing is not flipped.
      final gift = find.descendant(of: _anyButton, matching: findIcon(IconToken.parse('gift')));
      final giftLabel = find.descendant(
        of: find.ancestor(of: gift, matching: _anyButton),
        matching: find.byType(Text),
      );
      expect(tester.getRect(gift).left, greaterThan(tester.getRect(giftLabel).right));
      expect(_painterIn(tester, find.ancestor(of: gift, matching: find.byType(IconBox)))!.mirrored, isFalse);

      // Row slot: the icon to the LEFT of the text.
      final coins = findIcon(IconToken.parse('coins'));
      expect(tester.getRect(coins).right, lessThan(tester.getRect(find.text('120')).left));
    });

    testWidgets('icon button "About this reward" opens the details screen, "Back" returns', (tester) async {
      await pump(tester, 'en');
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('About this reward'));
      await tester.pumpAndSettle();
      expect(find.text('Any drink, any size. Show the code at the counter.'), findsOneWidget);
      expect(buttonWith(tester, 'Redeem').height, 48);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Buttons and chips'), findsOneWidget);
      handle.dispose();
    });
  });

  group('9.5.0 showcase: five nodes got an icon', () {
    test('icons are named on the series badge and four buttons, and all are from the set', () {
      final doc = loadFixture('rewards-showcase-screens');
      final byId = {for (final node in flattenDocument(doc).whereType<ChildNode>()) node.id: node};
      expect((byId['home-streak-badge']! as BadgeNode).icon?.isKnown, isTrue);
      for (final id in ['mission-claim', 'mission-back', 'redeem-submit', 'done-close']) {
        expect((byId[id]! as ButtonNode).icon?.isKnown, isTrue, reason: id);
      }
    });
  });

  group('a 9.5 document at a reader that knows only 9.4', () {
    test('IconButton is a widget from the future for it, not "outside the contract"', () {
      expect(widgetOriginOf('IconButton', readerVersion: '9.4.0'), WidgetOrigin.fromFuture);
      expect(checkSchemaVersion('9.5.0', readerVersion: '9.4.0'), VersionVerdict.newerMinor);
    });
  });
}
