/// OWN STYLE OF THE RING LABEL (schema 9.17.0): `labelTypography` and `labelColor` of the
/// `CircularProgress` node.
///
/// The test reads the NEW groups `ringLabelCases` (20) and `ringLabelNoneCases` (2) of the
/// table `assets/contract/fixtures/progress/progress-cases.json` (description - `labelNote`,
/// row theme - `labelTheme`) and runs each through a REAL screen: text, style (token,
/// overrides, weight, multiplier), colour with opacity, node box (the label does not change
/// it), one centred line, not clipped by the ring, not inherited from the node.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/progress_rules.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/progress/progress-cases.json').readAsStringSync())
      as Map<String, Object?>;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
  final baseTheme = (table['theme']! as Map<String, Object?>).cast<String, Object?>();
  final labelTheme = (table['labelTheme']! as Map<String, Object?>).cast<String, Object?>();
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();

  // Row theme: ring sizes from `theme`, label fonts and colours from `labelTheme`.
  final theme = RenderTheme.fromJson({
    ...baseTheme,
    'typography': labelTheme['typography'],
    'color': {...(baseTheme['color']! as Map), ...(labelTheme['color']! as Map)},
    'id': 'ring-label',
    'name': 'Ring label',
    'brightness': 'light',
  });

  test('table: 20 + 2 rows, names are unique', () {
    expect(rowsOf('ringLabelCases'), hasLength(20));
    expect(rowsOf('ringLabelNoneCases'), hasLength(2));
    for (final key in ['ringLabelCases', 'ringLabelNoneCases']) {
      final names = rowsOf(key).map((row) => row['name']).toList();
      expect(names.toSet(), hasLength(names.length), reason: key);
    }
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpRing(WidgetTester tester, _Row row) async {
    phone(tester);
    final style = row['style'] as Map?;
    await pumpDocument(
      tester,
      UiDocumentBuilder.bare([
        {
          'id': 'ring',
          'type': 'CircularProgress',
          'props': {
            'value': {'kind': 'literal', 'value': row['value']},
            'max': {'kind': 'literal', 'value': row['max']},
            'color': 'primary',
            ...(row['props']! as Map<String, Object?>),
          },
          if (style != null && style.isNotEmpty) 'style': style,
        },
      ]),
      theme: theme,
    );
    expect(tester.takeException(), isNull);
  }

  group('ringLabelCases: ring label style', () {
    for (final row in rowsOf('ringLabelCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await pumpRing(tester, row);
        final expected = row['expect']! as _Row;
        final placement = find.byType(RingPlacement);
        final label = find.descendant(of: placement, matching: find.byType(Text));
        expect(label, findsOneWidget);
        final widget = tester.widget<Text>(label);
        expect(widget.data, expected['text']);

        // Diameter and node box are the ring itself: the label does not change them.
        final diameter = (expected['diameter']! as num).toDouble();
        final ring = find.descendant(of: placement, matching: find.byType(CustomPaint));
        expect(tester.getSize(ring.first).width, closeTo(diameter, 0.01), reason: 'diameter');
        final box = tester.getSize(placement);
        expect(box.width, closeTo((expected['boxInline']! as num).toDouble(), 0.01), reason: 'box along');
        expect(box.height, closeTo((expected['boxBlock']! as num).toDouble(), 0.01), reason: 'box across');

        // Style: the token gives the family and numbers, overrides go on top.
        final typography = expected['typography']! as _Row;
        final style = widget.style!;
        expect(style.fontSize, closeTo((typography['fontSize']! as num).toDouble(), 1e-9), reason: 'size');
        expect(style.fontWeight!.value, typography['fontWeight'], reason: 'weight');
        expect(style.height, closeTo((typography['lineHeight']! as num).toDouble(), 1e-9), reason: 'multiplier');
        expect(style.fontSize! * style.height!, closeTo((typography['lineBlock']! as num).toDouble(), 1e-3), reason: 'line');

        // Colour with opacity.
        final color = expected['color']! as _Row;
        final hex = int.parse((color['hex']! as String).substring(1), radix: 16);
        expect(style.color!.toARGB32() & 0xFFFFFF, hex, reason: 'colour');
        expect(style.color!.a, closeTo((color['opacity']! as num).toDouble(), 0.01), reason: 'opacity');

        // One centred line, not clipped by the ring; no italics or line.
        expect(widget.maxLines, expected['lines']);
        expect(widget.softWrap, isFalse, reason: 'wrap: none');
        expect(widget.overflow, TextOverflow.visible, reason: 'overflow: not-clipped-by-ring');
        expect(style.fontStyle ?? FontStyle.normal, FontStyle.normal);
        expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
        expect(
          find.descendant(
            of: placement,
            matching: find.byWidgetPredicate((w) => w is ClipOval || w is ClipRRect || w is ClipRect || w is ClipPath),
          ),
          findsNothing,
          reason: 'the ring does not clip the label',
        );
        final stack = tester.widget<Stack>(find.descendant(of: placement, matching: find.byType(Stack)).first);
        expect(stack.clipBehavior, Clip.none, reason: 'the ring box does not clip the label');
        expect(tester.getCenter(label).dx, closeTo(tester.getCenter(ring.first).dx, 0.5), reason: 'centred (x)');
        expect(tester.getCenter(label).dy, closeTo(tester.getCenter(ring.first).dy, 0.5), reason: 'centred (y)');
      });
    }
  });

  group('ringLabelNoneCases: fields present, no label', () {
    for (final row in rowsOf('ringLabelNoneCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await pumpRing(tester, row);
        final expected = row['expect']! as _Row;
        final placement = find.byType(RingPlacement);
        expect(find.descendant(of: placement, matching: find.byType(Text)), findsNothing);
        final ring = find.descendant(of: placement, matching: find.byType(CustomPaint));
        expect(tester.getSize(ring.first).width, closeTo((expected['diameter']! as num).toDouble(), 0.01));
      });
    }
  });

  group('9.17.0 mirrors against the artifact', () {
    final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;

    test('x-style.layout.progressLabel - the rules the renderer computes with', () {
      final block = layout['progressLabel']! as Map<String, Object?>;
      for (final entry in kRingLabelStyle.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
      expect(block.keys.toSet(), {...kRingLabelStyle.keys, 'cases'});
      // The fallback look is exactly the tokens in the `progress.ring` block (unchanged).
      final ring = (layout['progress']! as Map)['ring']! as Map;
      expect(ring['labelTypography'], kRingLabelStyle['defaultTypography']);
      expect(ring['labelColor'], kRingLabelStyle['defaultColor']);
    });

    test('features: ringLabelStyle since 9.17.0', () {
      final features = ((schema['x-compatibility']! as Map)['features']! as Map).cast<String, Object?>();
      expect(features['ringLabelStyle'], '9.17.0');
      expect(kFeatureCatalog['ringLabelStyle'], '9.17.0');
      expect(supportsFeature('ringLabelStyle', readerVersion: '9.16.0'), isFalse);
    });
  });
}
