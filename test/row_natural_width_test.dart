import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

/// THE WIDTH OF A ROW CHILD WITHOUT A WEIGHT IS NATURAL, not "equal shares".
///
/// Previously every child without a weight sat in `Flexible(loose)`: two children got at
/// most half a row each, however much either needed. A chip with a date next to a short
/// counter wrapped the date onto two lines despite plenty of room; a long heading next to a
/// small badge wrapped at the half. On the builder canvas (CSS flex) a child without a
/// weight takes its natural width and shrinks only when the row really does not fit.
///
/// This was found by the contract-9 showcase drawn NEXT TO the builder canvas: an overflow test
/// cannot see it - nothing overflows.
///
/// The tests measure layout, not the widget tree: the test font is Ahem, where a glyph
/// width equals the font size, so the natural width of a label is
/// `glyphs x (size + letter spacing)`.
void main() {
  final theme = RenderTheme.fallback();
  final body = theme.text(TypographyToken.bodyM);
  // A glyph together with the theme letter spacing: exactly that much room it takes in a row.
  final glyph = body.fontSize! + (body.letterSpacing ?? 0);
  final line = body.fontSize! * body.height!;

  /// Row width: a screen without margins over the whole test surface.
  const rowWidth = 800.0;

  Map<String, Object?> row(
    List<Map<String, Object?>> children, {
    String justify = 'start',
    String gap = 'none',
    bool wrap = false,
  }) => {
    'id': 'row',
    'type': 'Row',
    'props': {'gap': gap, 'align': 'center', 'justify': justify, 'wrap': wrap},
    'children': children,
  };

  Map<String, Object?> chip(String label, {String id = 'chip'}) => {
    'id': id,
    'type': 'Container',
    'props': {'direction': 'row', 'gap': 'none'},
    'style': {'background': colorBackground()},
    'children': [textNode(label, id: '$id-text')],
  };

  Map<String, Object?> bar() => {
    'id': 'bar',
    'type': 'ProgressBar',
    'props': {
      'value': {'kind': 'literal', 'value': 1},
      'max': {'kind': 'literal', 'value': 2},
      'color': 'primary',
      'labelFormat': 'none',
    },
  };

  Future<void> pump(WidgetTester tester, List<Map<String, Object?>> children, {TextDirection? direction}) async {
    final doc = UiDocumentBuilder.bare(children);
    if (direction == null) return pumpDocument(tester, doc, theme: theme);
    // Arabic is right-to-left: the renderer takes the direction from the language.
    return pumpDocument(tester, doc, theme: theme, locale: 'ar');
  }

  String chars(int count, [String char = 'а']) => char * count;

  group('plenty of room', () {
    testWidgets('a child wider than half a row stays on ONE line', (tester) async {
      // 45 glyphs - 630 of 800: more than half, but together with the neighbour (28)
      // it fits. `Flexible(loose)` gave it 400 and wrapped it onto two lines.
      await pump(tester, [
        row([textNode(chars(45), id: 'wide'), textNode('бб', id: 'small')]),
      ]);

      final wide = tester.getSize(find.text(chars(45)));
      expect(wide.width, closeTo(45 * glyph, 0.01));
      expect(wide.height, closeTo(line, 0.01), reason: 'plenty of room - no wrapping possible');
      expect(tester.getSize(find.text('бб')).width, closeTo(2 * glyph, 0.01));
    });

    testWidgets('justify: between spreads children of NATURAL width to the edges', (tester) async {
      await pump(tester, [
        row([chip(chars(40)), textNode('кінець', id: 'end')], justify: 'between'),
      ]);

      expect(tester.getTopLeft(find.text(chars(40))).dx, 0);
      expect(tester.getTopRight(find.text('кінець')).dx, closeTo(rowWidth, 0.01));
      expect(tester.getSize(find.text(chars(40))).height, closeTo(line, 0.01));
    });

    testWidgets('in right-to-left writing the row start is the right edge', (tester) async {
      await pump(tester, [
        row([textNode('перша', id: 'a'), textNode('друга', id: 'b')], gap: 'sm'),
      ], direction: TextDirection.rtl);

      final first = tester.getRect(find.text('перша'));
      final second = tester.getRect(find.text('друга'));
      expect(first.right, closeTo(rowWidth, 0.01));
      expect(second.right, closeTo(first.left - theme.space(SpacingToken.sm), 0.01));
    });
  });

  group('the row does not fit', () {
    testWidgets('children shrink PROPORTIONALLY to natural width, not equally', (tester) async {
      // 50 and 25 glyphs: 700 and 350 - together 1050 in a row of 800. Proportionally that
      // is 533 1/3 and 266 2/3; "equally" would give 400 and 350.
      await pump(tester, [
        row([textNode(chars(50), id: 'long'), textNode(chars(25, 'б'), id: 'short')]),
      ]);

      final long = tester.getSize(find.text(chars(50))).width;
      final short = tester.getSize(find.text(chars(25, 'б'))).width;
      expect(long + short, closeTo(rowWidth, 0.01));
      expect(long / short, closeTo(2, 0.001));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a widget as wide as its content does not shrink: the badge stays whole, the text yields', (tester) async {
      await pump(tester, [
        row([textNode(chars(80), id: 'long'), badgeNode('Новинка')]),
      ]);

      final badge = tester.getRect(find.text('Новинка'));
      final caption = theme.text(TypographyToken.caption);
      expect(
        badge.width,
        closeTo(7 * (caption.fontSize! + (caption.letterSpacing ?? 0)), 0.01),
        reason: 'the badge caption was not wrapped',
      );
      expect(badge.height, closeTo(caption.fontSize! * caption.height!, 0.01));
      // The badge sits flush to the row end, and the text takes the REST - not half.
      final long = tester.getRect(find.text(chars(80)));
      expect(long.left, 0);
      expect(long.width, greaterThan(rowWidth / 2 + 100));
      expect(badge.right, lessThanOrEqualTo(rowWidth + 0.01));
    });

    testWidgets('a named width stays named', (tester) async {
      await pump(tester, [
        row([
          textNode(chars(80), id: 'long'),
          {
            'id': 'card',
            'type': 'Container',
            'props': {'direction': 'column', 'gap': 'none'},
            'style': {'width': 300, 'background': colorBackground()},
            'children': [textNode('картка', id: 'card-text')],
          },
        ]),
      ]);

      final card = tester.getRect(
        find.ancestor(of: find.text('картка'), matching: find.byType(DecoratedBox)).first,
      );
      expect(card.width, 300);
      expect(card.right, closeTo(rowWidth, 0.01));
      expect(tester.getSize(find.text(chars(80))).width, closeTo(rowWidth - 300, 0.01));
    });

    testWidgets('a child without a weight next to a share does not overflow the row', (tester) async {
      // Previously a child without a weight in a row with shares got an axis WITHOUT LIMITS:
      // a long label went on one line past the screen edge.
      await pump(tester, [
        row([
          {...textNode('частка', id: 'share'), 'weight': 1},
          textNode(chars(80), id: 'long'),
        ]),
      ]);

      final long = tester.getRect(find.text(chars(80)));
      expect(long.right, lessThanOrEqualTo(rowWidth + 0.01));
      expect(long.height, greaterThan(line), reason: 'the label is wrapped, not clipped by the edge');
      expect(tester.takeException(), isNull);
    });
  });

  group('stretchy content without a weight', () {
    testWidgets('the progress bar takes the REMAINDER, the label its natural width', (tester) async {
      await pump(tester, [
        row([textNode('підпис', id: 'label'), bar()], gap: 'sm'),
      ]);

      final label = tester.getRect(find.text('підпис'));
      final track = tester.getRect(find.byType(ProgressTrack));
      expect(label.width, closeTo(6 * glyph, 0.01));
      expect(track.left, closeTo(label.right + theme.space(SpacingToken.sm), 0.01));
      expect(track.right, closeTo(rowWidth, 0.01));
    });
  });

  group('a row that was given no width', () {
    testWidgets('a chip in a wrapping row is as wide as its content, not as the row', (tester) async {
      await pump(tester, [
        row([chip('чіп'), chip('другий', id: 'second')], wrap: true),
      ]);

      final first = tester.getRect(find.ancestor(of: find.text('чіп'), matching: find.byType(DecoratedBox)).first);
      final second = tester.getRect(
        find.ancestor(of: find.text('другий'), matching: find.byType(DecoratedBox)).first,
      );
      expect(first.width, closeTo(3 * glyph, 0.01));
      // The second chip sits NEXT to the first, not under it.
      expect(second.top, first.top);
      expect(second.left, closeTo(first.right, 0.01));
    });

    testWidgets('a column without its own width measures a child row BY CONTENT', (tester) async {
      // A stack layer without `fill` has no width: the column in it is as wide as the
      // widest child. The row answered "how much do you need" with "all the room" - the
      // column spanned the whole stack, and the label under the number sat at the left
      // screen edge instead of the ring centre.
      await pump(tester, [
        {
          'id': 'stack',
          'type': 'Stack',
          'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
          'children': [
            {
              'id': 'column',
              'type': 'Column',
              'props': {'gap': 'none', 'align': 'center'},
              'children': [
                textNode('3', id: 'value'),
                {
                  'id': 'of',
                  'type': 'Container',
                  'props': {'direction': 'row', 'gap': 'none'},
                  'children': [textNode('з', id: 'of-label'), textNode('5', id: 'of-target')],
                },
              ],
            },
          ],
        },
      ]);

      final label = tester.getRect(find.text('з'));
      final target = tester.getRect(find.text('5'));
      expect(label.left, closeTo((rowWidth - 2 * glyph) / 2, 0.01), reason: 'the row «з 5» is centred in the stack');
      expect(target.left, closeTo(label.right, 0.01));
      expect(tester.getCenter(find.text('3')).dx, closeTo(rowWidth / 2, 0.01));
    });
  });

  // ─────────────────────────────── narrow screen and numbers from the contract reference

  group('row of 361 dp (contract 9)', () {
    void phoneWidth(WidgetTester tester) {
      tester.view.physicalSize = const Size(361, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('a bar without a label in a natural-width chip is ZERO, the chip is as wide as its caption', (tester) async {
      // A chip is a row child without a weight, i.e. a row of NATURAL width: share 1 of the
      // stretchy content does not apply there. Previously the width was given only as an
      // upper bound, and the bar still took "the remainder" and stretched the chip to the
      // whole screen.
      phoneWidth(tester);
      await pump(tester, [
        row([
          {
            'id': 'chip',
            'type': 'Container',
            'props': {'direction': 'row', 'gap': 'none'},
            'style': {'background': colorBackground()},
            'children': [textNode('чіп', id: 'chip-text'), bar()],
          },
          textNode('поруч', id: 'next'),
        ]),
      ]);

      final chip = tester.getRect(find.ancestor(of: find.text('чіп'), matching: find.byType(DecoratedBox)).first);
      expect(chip.width, closeTo(3 * glyph, 0.01));
      expect(tester.getSize(find.byType(ProgressTrack)).width, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rest of stretchy content in a chip is measured by content and does not crash', (tester) async {
      phoneWidth(tester);
      Map<String, Object?> inChip(String id, Map<String, Object?> node) => {
        'id': id,
        'type': 'Container',
        'props': {'direction': 'row', 'gap': 'none'},
        'style': {'background': colorBackground()},
        'children': [textNode('т', id: '$id-t'), node],
      };
      await pump(tester, [
        row([
          inChip('c1', {'id': 'd', 'type': 'Divider', 'props': {'orientation': 'horizontal', 'color': 'muted'}}),
          inChip('c2', {'id': 's', 'type': 'Spacer', 'props': {'size': 'md', 'orientation': 'horizontal'}}),
          inChip('c3', {
            ...bar(),
            'props': {...(bar()['props']! as Map<String, Object?>), 'labelFormat': 'percent'},
          }),
        ]),
      ]);

      expect(tester.takeException(), isNull);
      final chip = tester.getRect(find.ancestor(of: find.text('т'), matching: find.byType(DecoratedBox)).first);
      expect(chip.width, closeTo(glyph, 0.01), reason: 'a line and a spacer without content - zero');
      expect(tester.getSize(find.byType(ProgressTrack)).width, greaterThan(0), reason: 'the bar takes the label width');
    });

    testWidgets('paired case: the label is natural, the bar takes the remainder to the row edge', (tester) async {
      phoneWidth(tester);
      await pump(tester, [
        row([textNode('підпис', id: 'label'), bar()], gap: 'sm'),
      ]);

      final label = tester.getRect(find.text('підпис'));
      final track = tester.getRect(find.byType(ProgressTrack));
      expect(label.width, closeTo(6 * glyph, 0.01));
      expect(track.left, closeTo(label.right + theme.space(SpacingToken.sm), 0.01));
      expect(track.right, closeTo(361, 0.01));
    });

    // Numbers from the builder reference `rowChildWidths`: row 361, gap 8.
    Future<List<double>> widths(
      WidgetTester tester,
      List<RowSlot Function(Widget)> slots,
      List<double> naturals,
    ) async {
      final keys = [for (var i = 0; i < naturals.length; i++) GlobalKey()];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 361,
              child: RowLayout(
                gap: 8,
                justify: JustifyToken.start,
                align: AlignToken.start,
                hugsContent: false,
                children: [
                  for (var i = 0; i < naturals.length; i++)
                    slots[i](SizedBox(key: keys[i], width: naturals[i], height: 10)),
                ],
              ),
            ),
          ),
        ),
      );
      return [for (final key in keys) tester.getSize(find.byKey(key)).width];
    }

    testWidgets('natural 164 and 900 shrink proportionally: ~110.3 and ~242.7', (tester) async {
      // 900 is first limited to the row (361), then 353 is divided as 164 : 361.
      final result = await widths(tester, [
        (c) => RowSlot(child: c),
        (c) => RowSlot(child: c),
      ], [164, 900]);
      expect(result[0], closeTo(110.3, 0.5));
      expect(result[1], closeTo(242.7, 0.5));
    });

    testWidgets('natural 900 and weight 3: 353 and 0 - shares divide only the remainder', (tester) async {
      final result = await widths(tester, [
        (c) => RowSlot(child: c),
        (c) => RowSlot(share: 3, child: c),
      ], [900, 10]);
      expect(result[0], closeTo(353, 0.5));
      expect(result[1], closeTo(0, 0.5));
    });
  });
}
