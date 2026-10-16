/// The colour of a shadow taken from the node's own background (schema 9.25.0, `style.shadowColor: 'background'`):
/// the shared table `fixtures/shadow-color/shadow-color-cases.json`, every row run through the rule (the theme resolves
/// the shadow of a style) and through a real node on screen (the layers the box really paints).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/scrolled_bar.dart';
import 'package:hotlayout_flutter/src/model/shadow_color.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/shadow-color/shadow-color-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final middleStops = rowsOf('middleStopCases');
  final tints = rowsOf('tintCases');
  final rules = rowsOf('ruleCases');
  final block = schema['x-shadowColor']! as _Row;

  // The table's theme laid on the built-in one: the colours and the shadow it names, the rest as shipped.
  final tableTheme = RenderTheme.fromJson({
    ...(table['theme']! as _Row),
    'id': 'shadow-color-cases',
    'name': 'Shadow colour cases',
    'brightness': 'light',
  });


  /// The layers as the table writes them (first = nearest) from the BoxShadows Flutter paints (last = nearest).
  List<_Row> layersOf(List<BoxShadow> shadows) => [
    for (final shadow in shadows.reversed)
      {
        'offsetX': shadow.offset.dx,
        'offsetY': shadow.offset.dy,
        'blur': shadow.blurRadius,
        'spread': shadow.spreadRadius,
        'color': '#${(shadow.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        'opacity': shadow.color.a,
      },
  ];

  void expectLayers(List<_Row> actual, List<Object?> expected) {
    expect(actual, hasLength(expected.length));
    for (var i = 0; i < expected.length; i += 1) {
      final want = expected[i]! as _Row;
      final got = actual[i];
      for (final key in ['offsetX', 'offsetY', 'blur', 'spread']) {
        expect((got[key]! as num).toDouble(), closeTo((want[key]! as num).toDouble(), 1e-9), reason: 'layer $i: $key');
      }
      expect(got['color'], want['color'], reason: 'layer $i: colour');
      // The opacity travels as the 8-bit alpha of a colour.
      expect((got['opacity']! as num).toDouble(), closeTo((want['opacity']! as num).toDouble(), 0.005), reason: 'layer $i: opacity');
    }
  }

  test('the table is read in full', () {
    expect(middleStops, hasLength(5));
    expect(tints, hasLength(7));
    expect(rules, hasLength(2));
  });

  group('middleStopCases: the stop nearest to the middle, the earlier one on a tie', () {
    for (final row in middleStops) {
      test(row['name']! as String, () {
        final positions = [for (final p in row['positions']! as List<Object?>) (p! as num).toDouble()];
        expect(middleStopIndex(positions), row['expected']);
      });
    }
  });

  group('tintCases', () {
    for (final row in tints) {
      final name = row['name']! as String;
      final style = NodeStyle.parse(row['style'])!;
      // `null`: no shadow is drawn at all.
      final expected = (row['expect'] as List<Object?>?) ?? const <Object?>[];

      test('rule: $name', () {
        final shadow = tableTheme.resolveNodeShadow(style);
        if (expected.isEmpty) {
          expect(shadow == null || shadow.isEmpty, isTrue);
          return;
        }
        expectLayers(layersOf(shadow!), expected);
      });

      testWidgets('screen: $name', (tester) async {
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([
            {
              'id': 'card',
              'type': 'Container',
              'props': {'direction': 'column', 'gap': 'sm'},
              'style': {...(row['style']! as _Row), 'padding': 'md'},
              'children': [
                {
                  'id': 't',
                  'type': 'Text',
                  'props': {'content': {'kind': 'literal', 'value': 'x'}},
                },
              ],
            },
          ]),
          theme: tableTheme,
        );
        final boxes = tester
            .widgetList<DecoratedBox>(find.descendant(of: find.byType(Scaffold), matching: find.byType(DecoratedBox)))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) => decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty)
            .toList();
        if (expected.isEmpty) {
          expect(boxes, isEmpty);
          return;
        }
        expect(boxes, hasLength(1));
        expectLayers(layersOf(boxes.single.boxShadow!), expected);
      });
    }
  });

  group('ruleCases and the mirror of the artifact', () {
    test('the only word', () {
      final row = rules.firstWhere((r) => r['rule'] == 'words');
      expect(ShadowColorWord.values.map((w) => w.name).toList(), row['expect']);
      expect(block['words'], row['expect']);
    });

    test('not inherited', () {
      final row = rules.firstWhere((r) => r['rule'] == 'inherited');
      expect(block['inherited'], row['expect']);
      expect(block['prop'], 'style.shadowColor');
    });

    test('an unknown word, an empty string and a number are no field', () {
      for (final raw in ['', 'Background', 'foreground', 1, true, null, const <Object?>[]]) {
        expect(NodeStyle.parse({'shadow': 'medium', 'shadowColor': raw})!.shadowColor, isNull, reason: '$raw');
      }
      expect(NodeStyle.parse({'shadow': 'medium', 'shadowColor': 'background'})!.shadowColor, ShadowColorWord.background);
    });

    test('without «shadow» the field does nothing', () {
      final style = NodeStyle.parse({'shadowColor': 'background', 'background': {'kind': 'color', 'color': 'accent'}})!;
      expect(tableTheme.resolveNodeShadow(style), isNull);
    });

    test('a state lays the field over the base like any other, and it is not in the scrolled layer', () {
      final base = NodeStyle.parse({'shadow': 'medium', 'shadowColor': 'background'})!;
      final state = NodeStyle.parse({'background': {'kind': 'color', 'color': 'success'}})!;
      expect(state.over(base).shadowColor, ShadowColorWord.background);
      expect(base.shadowColor, ShadowColorWord.background);
      // The scrolled layer of a bar names four fields and this is not one of them.
      expect(readScrolledStyle({'shadow': 'medium', 'shadowColor': 'background'})!.shadowColor, isNull);
    });

    testWidgets('a widget with a role: the field goes with the shadow to the surface of the role', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'go',
            'type': 'Button',
            'props': {'label': {'kind': 'literal', 'value': 'Go'}, 'variant': 'primary', 'action': {'type': 'none'}},
            'style': {
              'background': {'kind': 'color', 'color': 'success'},
              'shadow': 'medium',
              'shadowColor': 'background',
            },
          },
        ]),
        theme: tableTheme,
      );
      final shadows = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byType(FilledButton), matching: find.byType(DecoratedBox)))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((decoration) => decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty)
          .boxShadow!;
      expectLayers(layersOf(shadows), [
        {'offsetX': 0, 'offsetY': 8, 'blur': 24, 'spread': -4, 'color': '#059669', 'opacity': 0.3},
        {'offsetX': 0, 'offsetY': 0, 'blur': 12, 'spread': 0, 'color': '#059669', 'opacity': 0.5},
      ]);
    });
  });
}
