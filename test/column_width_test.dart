import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';
import 'support/icons.dart';

/// Child width in a column (`columnChildWidth:
/// 'stretch-unless-natural'`, `x-style.layout.column`) and the built-in
/// badge padding (`x-style.layout.badgePadding`).
///
/// Before 9.0.0 the contract was silent here: the builder stretched every
/// column child, while Flutter gave it free width and placed it by `align`. A
/// card with a background in a column was full width on the canvas but hugged
/// its content on the phone. The tests below mirror the artifact lists and
/// check the painted layout (the test window screen is 800 dp).
/// Widget types that can be placed as a child of a column.
const Set<String> kWidgetCatalogTypes = {
  'Button', 'Divider', 'Spacer', 'ProgressBar', 'Grid', 'Text', 'Image', 'Icon', 'Badge', 'ListTile',
  'CircularProgress', 'Column', 'Row', 'Container', 'Stack', 'Repeater', 'Accordion', 'Tabs',
  'IconButton',
};

void main() {
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
          as Map<String, Object?>;
  final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;
  final column = layout['column']! as Map<String, Object?>;
  final theme = RenderTheme.fallback();

  const surface = {'kind': 'color', 'color': 'surface'};
  const screenWidth = 800.0;

  ChildNode parse(Map<String, Object?> json) => rootOf(docWith([json])).children.single;

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, Object?>> children, {
    Map<String, Object?> data = const {},
    String? locale,
  }) => pumpDocument(tester, UiDocumentBuilder.bare(children), theme: theme, data: data, locale: locale);

  /// Card with a background: a column container with a single label. Its box is the nearest
  /// `DecoratedBox` above the label.
  Map<String, Object?> card(
    String label, {
    Map<String, Object?> style = const {},
    String id = 'card',
  }) => {
    'id': id,
    'type': 'Container',
    'props': {'gap': 'none', 'direction': 'column'},
    'style': {'background': surface, ...style},
    'children': [textNode(label, id: '$id-text')],
  };

  Rect cardRect(WidgetTester tester, String label) =>
      tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first);

  Map<String, Object?> column_({
    required List<Map<String, Object?>> children,
    String align = 'start',
    String id = 'col',
  }) => {
    'id': id,
    'type': 'Column',
    'props': {'gap': 'none', 'align': align},
    'children': children,
  };

  Map<String, Object?> badge({String id = 'badge', String label = 'Нове'}) => {
    'id': id,
    'type': 'Badge',
    'props': {'label': {'kind': 'literal', 'value': label}, 'tone': 'accent'},
  };

  Map<String, Object?> button({bool fullWidth = true, String id = 'btn'}) => {
    'id': id,
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': 'Кнопка'},
      'variant': 'primary',
      'action': {'type': 'noop'},
      'fullWidth': fullWidth,
    },
  };

  Map<String, Object?> nodeOf(String type, Map<String, Object?> props) => {
    'id': 'n-${type.toLowerCase()}',
    'type': type,
    'props': {
      ...switch (type) {
        'Button' => {'label': {'kind': 'literal', 'value': 'К'}, 'variant': 'primary', 'action': {'type': 'noop'}},
        'Badge' => {'label': {'kind': 'literal', 'value': 'Б'}, 'tone': 'accent'},
        'Icon' => {'name': 'trophy', 'size': 'md', 'alt': 'і'},
        'CircularProgress' => {'value': {'kind': 'literal', 'value': 1}, 'max': {'kind': 'literal', 'value': 2}},
        'Repeater' => {'source': 'x', 'item': 'y'},
        'Text' => {'content': {'kind': 'literal', 'value': 'Т'}},
        'Tab' => {'title': {'kind': 'literal', 'value': 'Т'}},
        'Accordion' => {'title': {'kind': 'literal', 'value': 'А'}},
        _ => const <String, Object?>{},
      },
      ...props,
    },
    if (const {'Grid', 'Repeater', 'Column', 'Row', 'Container', 'Stack', 'Tab', 'Accordion', 'ChoiceGroup', 'Tabs'}
        .contains(type))
      'children': [textNode('в', id: 'child-${type.toLowerCase()}')],
  };

  // ─────────────────────────────────────────────────── mirror against the artifact

  group('x-style.layout.column — mirror against the artifact', () {
    test('scalar strings', () {
      expect(column['childWidth'], kColumnLayout['childWidth']);
      expect(column['ownWidth'], kColumnLayout['ownWidth']);
      expect(
        column['childWidthWithoutDefiniteParent'],
        kColumnLayout['childWidthWithoutDefiniteParent'],
      );
      expect(column['naturalMaxWidth'], kColumnLayout['naturalMaxWidth']);
      expect(column['naturalWidthAlign'], kColumnLayout['naturalWidthAlign']);
      expect(column['constrainedStretch'], kColumnLayout['constrainedStretch']);
      expect(
        (schema['x-compatibility']! as Map<String, Object?>)['policy'],
        containsPair('columnChildWidth', 'stretch-unless-natural'),
      );
      // Guard: a `column` key this test does not know about is a contract decision.
      expect(column.keys.toSet(), {
        'childWidth', 'childWidthWithoutDefiniteParent', 'parents', 'naturalWidth', 'ownWidth',
        'naturalMaxWidth', 'naturalWidthAlign', 'constrainedStretch',
      });
    });

    test('parents: exactly six column parents and no extras', () {
      final rules = (column['parents']! as List<Object?>).cast<Map<String, Object?>>();
      expect(rules, hasLength(6), reason: 'the contract list grew; the renderer must learn it');

      final accepted = <String>{};
      for (final rule in rules) {
        final type = rule['type']! as String;
        final when = rule['when'] as Map<String, Object?>?;
        if (type == 'Screen') {
          expect(isColumnParent(rootOf(docWith(const []))), isTrue);
        } else {
          final yes = parse(nodeOf(type, {if (when != null) when['prop']! as String: when['equals']}));
          expect(isColumnParent(yes), isTrue, reason: '$type ${when ?? ''}');
          if (when != null) {
            final no = parse(nodeOf(type, {when['prop']! as String: 'row'}));
            expect(isColumnParent(no), isFalse, reason: '$type vs ${when['prop']}=row');
          }
        }
        accepted.add(type);
      }
      // `Container` without `direction` is a column (the field default).
      expect(isColumnParent(parse(nodeOf('Container', const {}))), isTrue);
      // `Repeater` is deliberately NOT a column parent.
      for (final type in ['Row', 'Grid', 'Stack', 'Repeater', 'Tabs']) {
        expect(isColumnParent(parse(nodeOf(type, const {}))), isFalse, reason: type);
      }
    });

    test('naturalWidth: exactly seven conditions (9.5.0 added IconButton), every other type is stretched', () {
      final rules = (column['naturalWidth']! as List<Object?>).cast<Map<String, Object?>>();
      expect(rules, hasLength(7), reason: 'the contract list grew; the renderer must learn it');

      final accepted = <String>{};
      for (final rule in rules) {
        final type = rule['type']! as String;
        final when = rule['when'] as Map<String, Object?>?;
        final yes = parse(nodeOf(type, {if (when != null) when['prop']! as String: when['equals']}));
        expect(hasNaturalColumnWidth(yes), isTrue, reason: '$type ${when ?? ''}');
        if (when != null) {
          final other = when['equals'] is bool ? !(when['equals']! as bool) : 'horizontal';
          final no = parse(nodeOf(type, {when['prop']! as String: other}));
          expect(hasNaturalColumnWidth(no), isFalse, reason: '$type vs ${when['prop']}=$other');
        }
        accepted.add(type);
      }
      // The condition reads the prop AFTER the schema default: `Button` without `fullWidth` is
      // full width (default `true`), `Divider` without `orientation` is horizontal.
      expect(hasNaturalColumnWidth(parse(nodeOf('Button', const {}))), isFalse);
      expect(hasNaturalColumnWidth(parse(nodeOf('Divider', const {}))), isFalse);
      expect(hasNaturalColumnWidth(parse(nodeOf('Spacer', const {}))), isFalse);

      for (final type in kWidgetCatalogTypes.difference(accepted)) {
        expect(hasNaturalColumnWidth(parse(nodeOf(type, const {}))), isFalse, reason: type);
      }
    });

    test('badgePadding: xs vertically, sm horizontally', () {
      final padding = layout['badgePadding']! as Map<String, Object?>;
      expect(padding, {'block': kBadgePaddingBlock.wire, 'inline': kBadgePaddingInline.wire});
    });

    test('button: sm / md padding, titleS label, size = label + padding + border', () {
      // The behaviour is held by `widget_geometry_test.dart` (size as painted).
      expect(layout['buttonPadding'], {
        'block': kButtonPaddingBlock.wire,
        'inline': kButtonPaddingInline.wire,
      });
      expect(layout['buttonTypography'], kButtonTypography.wire);
      expect(layout['buttonSize'], 'label-plus-padding-plus-border');
    });
  });

  // ─────────────────────────────────────────────────────────────── stretched

  group('stretched column child: parent content width minus its own margin', () {
    testWidgets('card with a background in a Column spans the full width', (tester) async {
      await pump(tester, [column_(children: [card('Картка')], align: 'center')]);
      expect(cardRect(tester, 'Картка').width, screenWidth);
    });

    testWidgets('...in Screen, Container, Tab, Accordion, ChoiceGroup too', (tester) async {
      final panels = <String, Map<String, Object?>>{
        'Screen': card('Картка'),
        'Container': {
          'id': 'wrap',
          'type': 'Container',
          'props': {'gap': 'none', 'direction': 'column'},
          'children': [card('Картка')],
        },
        'Tab': {
          'id': 'tabs',
          'type': 'Tabs',
          'props': {'initialTab': 0},
          'children': [
            {
              'id': 'tab',
              'type': 'Tab',
              'props': {'title': {'kind': 'literal', 'value': 'Вкладка'}},
              'children': [card('Картка')],
            },
          ],
        },
        'Accordion': {
          'id': 'acc',
          'type': 'Accordion',
          'props': {'title': {'kind': 'literal', 'value': 'Правила'}, 'initiallyExpanded': true},
          'children': [card('Картка')],
        },
        'ChoiceGroup': choiceGroupNode([card('Картка')]),
      };
      for (final entry in panels.entries) {
        await pump(tester, [entry.value]);
        expect(tester.takeException(), isNull, reason: entry.key);
        expect(cardRect(tester, 'Картка').width, screenWidth, reason: entry.key);
      }
    });

    testWidgets('margin goes inside the tight width: width minus the margins', (tester) async {
      await pump(tester, [
        card('Картка', style: {'margin': 'md'}),
      ]);
      final margin = theme.space(SpacingToken.md);
      final rect = cardRect(tester, 'Картка');
      expect(rect.width, screenWidth - 2 * margin);
      expect(rect.left, margin);
    });

    testWidgets('Text{align: start} in Column{align: center} sits at the START', (tester) async {
      await pump(tester, [
        column_(align: 'center', children: [
          textNode('Зліва', id: 'a'),
          textNode('Посередині', id: 'b', extra: {'align': 'center'}),
        ]),
      ]);
      expect(tester.getTopLeft(find.text('Зліва')).dx, 0);
      final middle = tester.getRect(find.text('Посередині'));
      expect(middle.center.dx, closeTo(screenWidth / 2, 0.5));
    });

    testWidgets('minWidth of a stretched child below the available space fills the space', (tester) async {
      await pump(tester, [card('Картка', style: {'minWidth': 150})]);
      expect(cardRect(tester, 'Картка').width, screenWidth);
    });

    testWidgets('maxWidth caps the stretched width and places it by the parent align', (tester) async {
      for (final (align, left) in [('start', 0.0), ('center', 300.0), ('end', 600.0)]) {
        await pump(tester, [
          column_(align: align, children: [card('Картка', style: {'maxWidth': 200})]),
        ]);
        final rect = cardRect(tester, 'Картка');
        expect(rect.width, 200, reason: align);
        expect(rect.left, left, reason: align);
      }
    });

    testWidgets('maxWidth in a parent without an align prop sits at the start', (tester) async {
      await pump(tester, [card('Картка', style: {'maxWidth': 200})]);
      final rect = cardRect(tester, 'Картка');
      expect(rect.width, 200);
      expect(rect.left, 0);
    });

    testWidgets('in right-to-left writing the start is the right edge', (tester) async {
      await pump(
        tester,
        [column_(align: 'start', children: [card('Картка', style: {'maxWidth': 200})])],
        locale: 'ar',
      );
      final rect = cardRect(tester, 'Картка');
      expect(rect.width, 200);
      expect(rect.right, screenWidth);
    });
  });

  // ───────────────────────────────────────────────────────────────── natural

  group('natural width: own style.width and the naturalWidth list', () {
    testWidgets('card width: 120 in Column{end} sits at the end; in Column{center} it is centred', (tester) async {
      await pump(tester, [column_(align: 'end', children: [card('Картка', style: {'width': 120})])]);
      var rect = cardRect(tester, 'Картка');
      expect(rect.width, 120);
      expect(rect.right, screenWidth);

      await pump(tester, [column_(align: 'center', children: [card('Картка', style: {'width': 120})])]);
      rect = cardRect(tester, 'Картка');
      expect(rect.left, (screenWidth - 120) / 2);
    });

    testWidgets('own width no wider than the parent (naturalMaxWidth)', (tester) async {
      await pump(tester, [card('Картка', style: {'width': 5000})]);
      // The schema limit is 1200 and the parent is 800: the node does not overflow the parent content.
      expect(cardRect(tester, 'Картка').width, screenWidth);
    });

    testWidgets('Badge, Icon, CircularProgress, Button{fullWidth: false} in Column{center} are centred', (
      tester,
    ) async {
      Rect rectOf(Finder finder) => tester.getRect(finder.first);
      await pump(tester, [
        column_(align: 'center', children: [
          badge(),
          nodeOf('Icon', const {}),
          nodeOf('CircularProgress', const {}),
          button(fullWidth: false),
        ]),
      ]);
      expect(tester.takeException(), isNull);
      final badgeBox = tester.getRect(find.ancestor(of: find.text('Нове'), matching: find.byType(DecoratedBox)).first);
      for (final rect in [
        badgeBox,
        rectOf(find.byType(IconGlyph)),
        rectOf(find.byType(RingPlacement)),
        rectOf(find.byType(FilledButton)),
      ]) {
        expect(rect.width, lessThan(screenWidth / 2));
        expect(rect.center.dx, closeTo(screenWidth / 2, 0.5));
      }
    });

    testWidgets('...but in Container they sit at the start (it has no align prop)', (tester) async {
      await pump(tester, [
        {
          'id': 'wrap',
          'type': 'Container',
          'props': {'gap': 'none', 'direction': 'column'},
          'children': [badge(), button(fullWidth: false)],
        },
      ]);
      final badgeBox = tester.getRect(find.ancestor(of: find.text('Нове'), matching: find.byType(DecoratedBox)).first);
      expect(badgeBox.left, 0);
      expect(tester.getRect(find.byType(FilledButton)).left, 0);
    });

    testWidgets('Button{fullWidth: true} in Column{center} spans the full width', (tester) async {
      await pump(tester, [column_(align: 'center', children: [button()])]);
      expect(tester.getRect(find.byType(FilledButton)).width, screenWidth);
    });

    testWidgets('the same button in a Repeater spans the full width, no exceptions', (tester) async {
      await pump(
        tester,
        [
          {
            'id': 'list',
            'type': 'Repeater',
            'props': {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'},
            'children': [button(fullWidth: false)],
          },
        ],
        data: const {
          'items': [
            {'name': 'а'},
          ],
        },
      );
      expect(tester.getRect(find.byType(FilledButton)).width, screenWidth);
    });
  });

  // ──────────────────────────────────────────────────── width NOT tight

  group('a column without tight width neither crashes nor balloons', () {
    testWidgets('column in a row: width of the widest child, children align to it', (tester) async {
      await pump(tester, [
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
          'children': [
            {
              'id': 'wrap',
              'type': 'Container',
              'props': {'gap': 'none', 'direction': 'column'},
              'children': [card('Коротка', id: 'a'), card('Значно довший підпис', id: 'b')],
            },
          ],
        },
      ]);
      expect(tester.takeException(), isNull);
      final short = cardRect(tester, 'Коротка');
      final long = cardRect(tester, 'Значно довший підпис');
      expect(short.width, long.width, reason: 'stretched to the widest natural width');
      expect(long.width, lessThan(screenWidth / 2), reason: 'not to the whole window');
    });

    testWidgets('column in a row whose sibling has a weight: infinite width without an assert', (tester) async {
      await pump(tester, [
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
          'children': [
            {...card('З вагою', id: 'w'), 'weight': 1},
            // No weight while the sibling has one: inflexible, axis without bounds.
            column_(children: [textNode('Без ваги', id: 'a'), card('Картка', id: 'c')]),
          ],
        },
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('Без ваги'), findsOneWidget);
    });

    testWidgets('column in a scrolling row: children are finite and do not crash', (tester) async {
      await pump(tester, [
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': true},
          'children': [
            column_(children: [textNode('Один', id: 'a'), card('Картка', id: 'c')]),
            column_(id: 'col2', children: [textNode('Два', id: 'b'), button()]),
          ],
        },
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('Один'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────── badge

  group('built-in badge padding: sm horizontally, xs vertically', () {
    testWidgets('badge box = label + 2·sm + 2·xs', (tester) async {
      await pump(tester, [column_(children: [badge()])]);
      final box = tester.getRect(find.ancestor(of: find.text('Нове'), matching: find.byType(DecoratedBox)).first);
      final text = tester.getRect(find.text('Нове'));
      expect(box.width - text.width, 2 * theme.space(kBadgePaddingInline));
      expect(box.height - text.height, 2 * theme.space(kBadgePaddingBlock));
      expect(kBadgePaddingInline, SpacingToken.sm);
    });
  });
}
