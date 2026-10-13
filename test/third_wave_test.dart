import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Contract 9: policy keys for the row share with margins, and natural
/// width in a tight slot. Each test names a policy KEY. The only behavior
/// change is `naturalWidthInTightSlot`; the rest are keys and guard tests for
/// what the renderer already did.
void main() {
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
          as Map<String, Object?>;
  final policy = (schema['x-compatibility']! as Map<String, Object?>)['policy']! as Map<String, Object?>;
  final style = schema['x-style']! as Map<String, Object?>;
  final theme = RenderTheme.fallback();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Map<String, Object?> badge(String id, String label) => {
    'id': id,
    'type': 'Badge',
    'props': {'label': {'kind': 'literal', 'value': label}, 'tone': 'accent'},
  };

  Map<String, Object?> button(String id, String label, {required bool fullWidth}) => {
    'id': id,
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': label},
      'variant': 'primary',
      'action': {'type': 'noop'},
      'fullWidth': fullWidth,
    },
  };

  Map<String, Object?> grid(List<Map<String, Object?>> children, {int columns = 3}) => {
    'id': 'grid',
    'type': 'Grid',
    'props': {'columns': columns, 'gap': 'none'},
    'children': children,
  };

  Future<void> pump(WidgetTester tester, List<Map<String, Object?>> nodes) =>
      pumpDocument(tester, UiDocumentBuilder.bare(nodes), theme: theme);

  Rect badgeRect(WidgetTester tester, String label) =>
      tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first);

  Rect buttonRect(WidgetTester tester, String label) =>
      tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(FilledButton)).first);

  group('row share and tight-slot policy keys', () {
    test('AT, AU, AV and natural width in a tight slot', () {
      expect(policy['invalidWeight'], 'no-weight');
      expect(policy['justifyInNaturalRow'], 'nothing-to-distribute');
      expect(policy['naturalWidthInTightSlot'], 'natural-start-top');
      expect(style['weightShareIncludes'], kWeightShareIncludes);
      final layout = style['layout']! as Map<String, Object?>;
      expect(layout['tightSlotNaturalWidth'], kTightSlotNaturalWidth);
      expect(kTightSlotNaturalWidth, 'column.naturalWidth');
    });
  });

  // ───────────────────────── naturalWidthInTightSlot: natural-start-top

  group('naturalWidthInTightSlot: natural-start-top', () {
    testWidgets('Grid{3} at 360 dp: Badge as in Column{start}, at the start of the cell', (tester) async {
      phone(tester);
      await pump(tester, [
        {
          'id': 'col',
          'type': 'Column',
          'props': {'gap': 'none', 'align': 'start'},
          'children': [badge('b0', 'Нове')],
        },
        grid([badge('b1', 'Нове'), textNode('Текст', id: 't'), button('f', 'Повна', fullWidth: true)]),
        grid([button('n', 'Своя', fullWidth: false), textNode('Ще', id: 't2'), textNode('Ще2', id: 't3')]),
      ]);
      expect(tester.takeException(), isNull);

      Rect nth(Finder f) => tester.getRect(find.ancestor(of: f, matching: find.byType(DecoratedBox)).first);
      final reference = nth(find.text('Нове').first);
      final inCell = nth(find.text('Нове').last);
      expect(inCell.width, reference.width, reason: 'natural width, not 120');
      expect(inCell.left, 0, reason: 'start of the cell');
      expect(inCell.width, lessThan(120));

      expect(tester.getRect(find.text('Текст')).width, lessThanOrEqualTo(120));
      expect(buttonRect(tester, 'Повна').width, 120, reason: 'fullWidth - the whole cell');
      final natural = buttonRect(tester, 'Своя');
      expect(natural.width, lessThan(120), reason: 'fullWidth: false - natural');
      expect(natural.left, 0);
    });

    testWidgets('own style.width wins: the node stays as it is', (tester) async {
      phone(tester);
      await pump(tester, [
        grid([
          {
            ...badge('b1', 'Нове'),
            'style': {'width': 100},
          },
          textNode('Текст', id: 't'),
          textNode('Ще', id: 't2'),
        ]),
      ]);
      expect(tester.takeException(), isNull);
      expect(badgeRect(tester, 'Нове').width, 100);
    });

    testWidgets('Repeater with columns - the same; without columns the instance is stretched', (tester) async {
      phone(tester);
      Map<String, Object?> repeater({int? columns}) => {
        'id': 'rep-${columns ?? 0}',
        'type': 'Repeater',
        'props': {'source': 'items', 'item': 'it', 'gap': 'none', 'columns': ?columns},
        'children': [badge('tpl', 'Знач')],
      };
      const data = {
        'items': [
          {'x': 1},
          {'x': 2},
          {'x': 3},
        ],
      };
      await pumpDocument(tester, UiDocumentBuilder.bare([repeater(columns: 3)]), theme: theme, data: data);
      expect(tester.takeException(), isNull);
      final cell = tester.getRect(find.ancestor(of: find.text('Знач').first, matching: find.byType(DecoratedBox)).first);
      expect(cell.width, lessThan(120));
      expect(cell.left, 0);

      await pumpDocument(tester, UiDocumentBuilder.bare([repeater()]), theme: theme, data: data);
      final stretched =
          tester.getRect(find.ancestor(of: find.text('Знач').first, matching: find.byType(DecoratedBox)).first);
      expect(stretched.width, 360, reason: 'a column is not a tight slot, the instance is stretched');
    });
  });

  // ───────────────────────────── weightShareIncludes: [margin]

  testWidgets('weightShareIncludes: margin lies inside the share', (tester) async {
    phone(tester);
    final margin = theme.space(SpacingToken.sm);
    Map<String, Object?> card(String id, String label, int weight) => {
      'id': id,
      'type': 'Container',
      'props': {'gap': 'none'},
      'style': {
        'background': {'kind': 'color', 'color': 'surface'},
        'margin': 'sm',
      },
      'children': [textNode(label, id: '$id-t')],
      'weight': weight,
    };
    await pump(tester, [
      {
        'id': 'row',
        'type': 'Row',
        'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': false},
        'children': [card('a', 'Три', 3), card('b', 'Один', 1)],
      },
    ]);
    Size box(String label) =>
        tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first);
    expect(margin, 8);
    // Slots are 270 and 90; the box is the slot minus margins on both sides.
    expect(box('Три').width, 270 - 2 * margin);
    expect(box('Один').width, 90 - 2 * margin);
  });

  // ───────────── rowInUnboundedWidth: a nested row without weight is natural

  /// A chip row inside a row with `justify: between` used to stretch over all
  /// the free space, leaving nothing to distribute. An overflow test cannot see
  /// this - nothing overflows.
  testWidgets('a child row without weight takes natural width, the parent justify works', (tester) async {
    phone(tester);
    Map<String, Object?> chip(String id, String label) => {
      'id': id,
      'type': 'Container',
      'props': {'direction': 'row', 'gap': 'none'},
      'children': [textNode(label, id: '$id-t')],
    };
    await pump(tester, [
      {
        'id': 'row',
        'type': 'Row',
        'props': {'gap': 'none', 'align': 'start', 'justify': 'between', 'wrap': false, 'scrollable': false},
        'children': [chip('a', 'Ліва'), chip('b', 'Права')],
      },
    ]);
    expect(tester.takeException(), isNull);
    final left = tester.getRect(find.text('Ліва'));
    final right = tester.getRect(find.text('Права'));
    expect(left.left, 0);
    expect(right.right, 360, reason: 'between pushes the second chip to the end of the row');
  });

  // ─────────────────────────────── invalidWeight: non-integer weight

  test('invalidWeight: a non-integer weight and infinity mean no weight', () {
    int? weightOf(Object? raw) => rootOf(
      docWith([
        {
          'id': 'c',
          'type': 'Container',
          'props': {'gap': 'none'},
          'children': [textNode('А', id: 'c-t')],
          'weight': raw,
        },
      ]),
    ).children.single.weight;

    for (final broken in <Object?>[1.5, 2.5, double.infinity, double.negativeInfinity]) {
      expect(weightOf(broken), isNull, reason: '$broken');
    }
    expect(weightOf(7), 4);
  });

  // ──────────────────── justifyInNaturalRow: nothing-to-distribute

  testWidgets('justifyInNaturalRow: a layer row without fill - justify is powerless', (tester) async {
    phone(tester);
    Map<String, Object?> layer(String justify) => {
      'id': 'st-$justify',
      'type': 'Stack',
      'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
      'children': [
        {
          'id': 'r-$justify',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': justify, 'wrap': false, 'scrollable': false},
          'children': [textNode('П$justify', id: 'x-$justify')],
        },
      ],
    };
    await pump(tester, [layer('start'), layer('end')]);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Пstart')).left, 0);
    expect(tester.getRect(find.text('Пend')).left, 0, reason: 'justify: end moves nothing');
  });
}
