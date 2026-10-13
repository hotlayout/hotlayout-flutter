import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Circular progress (8.7.0) -- the same scale as the bar, bent into an arc.
///
/// What matters here is not the drawing but the NUMBERS: diameter and thickness
/// come from the theme with the same multipliers as in the builder's preview model.
/// They must not diverge: the ring's height is part of the screen height, and
/// the builder computes its fold warning from that.
void main() {
  Map<String, Object?> ring({
    Object? value = 50,
    Object? max = 100,
    String color = 'primary',
    String size = 'md',
    // `null` -- the field is absent from the document entirely: exactly this case
    // must leave the center empty, since that is what every ring built before 8.16.0 looks like.
    String? labelFormat,
  }) => {
    'id': 'ring',
    'type': 'CircularProgress',
    'props': {
      'value': {'kind': 'literal', 'value': value},
      'max': {'kind': 'literal', 'value': max},
      'color': color,
      'size': size,
      'labelFormat': ?labelFormat,
    },
  };

  /// What the ring draws and the space it takes (9.7.0: a custom painter
  /// instead of Material, whose stroke sat on the circle's edge).
  RingPainter arcOf(WidgetTester tester) => tester
      .widget<CustomPaint>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)))
      .painter! as RingPainter;
  Finder circleOf() => find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint));

  group('model', () {
    CircularProgressNode parse(Map<String, Object?> node) =>
        flattenDocument(docWith([node])).whereType<CircularProgressNode>().single;

    test('size is read from the document', () {
      expect(parse(ring(size: 'lg')).size, CircularSizeToken.lg);
    });

    test('an unknown size degrades to medium instead of breaking the node', () {
      expect(parse(ring(size: 'велетенський')).size, CircularSizeToken.md);
    });

    test('the ring has no label at all -- the center belongs to the document', () {
      // Not "not implemented yet" but a contract decision: `labelFormat` exists only
      // on the bar. The test holds the boundary so it is not crossed silently.
      final node = parse(ring());
      expect(node.value, isNotNull);
      expect(node.max, isNotNull);
    });
  });

  group('layout', () {
    testWidgets('diameter is a few xl spacing units, one per size', (tester) async {
      final theme = RenderTheme.fallback();
      const scale = {'sm': 2, 'md': 3, 'lg': 4};

      for (final entry in scale.entries) {
        await pumpDocument(tester, docWith([ring(size: entry.key)]));

        final box = tester.getRect(circleOf());
        final expected = entry.value * theme.space(SpacingToken.xl);

        expect(box.width, closeTo(expected, 0.01), reason: entry.key);
        expect(box.height, closeTo(expected, 0.01), reason: entry.key);
      }
    });

    testWidgets('arc thickness equals the bar track height', (tester) async {
      // One scale in two forms: different thickness would read as different concepts.
      await pumpDocument(tester, docWith([ring()]));

      expect(arcOf(tester).thickness, RenderTheme.fallback().space(SpacingToken.sm));
    });

    testWidgets('arc share is value / max, clamped to the ring bounds', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 25, max: 100)]));
      expect(arcOf(tester).ratio, closeTo(0.25, 0.001));

      // A value above the bound is a full ring, not a second circle over the first.
      await pumpDocument(tester, docWith([ring(value: 250, max: 100)]));
      expect(arcOf(tester).ratio, 1.0);
    });

    testWidgets('zero bound means no scale, not a full ring', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 50, max: 0)]));

      expect(arcOf(tester).ratio, 0.0);
    });

    testWidgets('a ring around a badge is a Stack, not a ring field', (tester) async {
      // This is why the ring came after stacking: the center belongs to the
      // document, so the badge inside is an ordinary stack layer.
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'stack',
            'type': 'Stack',
            'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
            'children': [
              ring(size: 'sm'),
              {
                'id': 'badge',
                'type': 'Badge',
                'props': {
                  'label': {'kind': 'literal', 'value': '7'},
                  'tone': 'accent',
                },
              },
            ],
          },
        ]),
      );

      final arc = tester.getRect(circleOf());
      final badge = tester.getRect(find.text('7'));

      expect(tester.takeException(), isNull);
      expect(badge.center.dx, closeTo(arc.center.dx, 0.01));
      expect(badge.center.dy, closeTo(arc.center.dy, 0.01));
    });
  });

  /*
   * LABEL IN THE CENTER (8.16.0) -- closes the 8.7.0 gap: "75 %" could not be expressed,
   * since a percentage is a DERIVED number, and a stack over the ring holds only what is
   * already in the data.
   *
   * The costliest thing to break here is the DEFAULT. The contract promised the ring's
   * center to the document, and a label that appeared on its own would take that place from
   * every ring already built. The parser is especially tricky: the default
   * `fallback` in `ProgressLabelFormatToken.parse` is `valueOfMax`, the
   * opposite of what the ring needs.
   */
  group('label in the center', () {
    testWidgets('without the field the center stays empty', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 3, max: 4)]));

      expect(find.text('75%'), findsNothing);
      expect(find.text('3 / 4'), findsNothing);
    });

    testWidgets('explicit "none" behaves the same as a missing field', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 3, max: 4, labelFormat: 'none')]));

      expect(find.text('75%'), findsNothing);
    });

    testWidgets('percent is computed from the bound, not from a hundred', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 3, max: 4, labelFormat: 'percent')]));

      expect(find.text('75%'), findsOneWidget);
    });

    testWidgets('"value of max" shows both numbers', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 3, max: 4, labelFormat: 'valueOfMax')]));

      expect(find.text('3 / 4'), findsOneWidget);
    });

    /// The same arithmetic as the bar: a zero bound is not a "full ring" but
    /// no scale, so the label must say zero, not infinity.
    testWidgets('zero bound gives 0 %', (tester) async {
      await pumpDocument(tester, docWith([ring(value: 5, max: 0, labelFormat: 'percent')]));

      expect(find.text('0%'), findsOneWidget);
    });

    /// Without a label no extra `Stack` appears in the tree: the most common
    /// case must stay exactly as it was before 8.16.0.
    testWidgets('the wrapper appears only together with a label', (tester) async {
      await pumpDocument(tester, docWith([ring()]));
      final withoutLabel = find.descendant(
        of: find.byType(RingPlacement).hitTestable(),
        matching: find.byType(Text),
      );
      expect(withoutLabel, findsNothing);
    });
  });
}
