import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

import 'support/fixtures.dart';

/// Contract 9: policy rows that readers used to guess. Each test names the
/// policy KEY, so a divergence from the artifact and from the words of the contract shows
/// by name, not by coincidence of numbers.
///
/// Column child widths and badge fields are held by
/// `column_width_test.dart`.
void main() {
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
          as Map<String, Object?>;
  final policy = (schema['x-compatibility']! as Map<String, Object?>)['policy']! as Map<String, Object?>;
  final themeArtifact =
      jsonDecode(File('assets/contract/theme.json').readAsStringSync()) as Map<String, Object?>;
  final themePolicy =
      (themeArtifact['x-compatibility']! as Map<String, Object?>)['policy']! as Map<String, Object?>;

  Map<String, Object?> card(String id, String label, {int? weight}) => {
    'id': id,
    'type': 'Container',
    'props': {'gap': 'none'},
    'style': {
      'background': {'kind': 'color', 'color': 'surface'},
    },
    'children': [textNode(label, id: '$id-t')],
    'weight': ?weight,
  };

  Map<String, Object?> row(List<Map<String, Object?>> children, {bool scrollable = false}) => {
    'id': 'row-${children.length}-${scrollable ? 's' : 'f'}',
    'type': 'Row',
    'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false, 'scrollable': scrollable},
    'children': children,
  };

  Size boxOf(WidgetTester tester, String label) =>
      tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first);

  // ───────────────────────────────────────────── rowInUnboundedWidth

  group('rowInUnboundedWidth: natural-width-ignore-weights', () {
    test('policy key', () {
      expect(policy['rowInUnboundedWidth'], 'natural-width-ignore-weights');
    });

    testWidgets('control: a row with a tight width - weights APPLY', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          row([card('a', 'Один', weight: 1), card('b', 'Два', weight: 3)]),
        ]),
      );
      expect(boxOf(tester, 'Один').width, 200);
      expect(boxOf(tester, 'Два').width, 600);
    });

    testWidgets('a stack layer row: width is the sum of naturals, weights do not apply', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'st',
            'type': 'Stack',
            'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
            'children': [
              row([card('a', 'Один', weight: 1), card('b', 'Два', weight: 3)]),
            ],
          },
        ]),
      );
      expect(tester.takeException(), isNull);
      final a = boxOf(tester, 'Один');
      final b = boxOf(tester, 'Два');
      expect(a.width + b.width, lessThan(200), reason: 'natural widths of two short labels');
      expect(b.width, isNot(closeTo(a.width * 3, 1)), reason: 'shares do not apply');
    });

    testWidgets('a row child of a scrolling row: weights do not apply', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          row([
            row([card('a', 'Один', weight: 1), card('b', 'Два', weight: 3)]),
          ], scrollable: true),
        ]),
      );
      expect(tester.takeException(), isNull);
      final a = boxOf(tester, 'Один');
      final b = boxOf(tester, 'Два');
      expect(a.width + b.width, lessThan(200));
    });

    testWidgets('a stretched layer (fill) gets width from the stack: weights apply', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'st',
            'type': 'Stack',
            'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
            'children': [
              {...row([card('a', 'Один', weight: 1), card('b', 'Два', weight: 3)]), 'fill': true},
              {
                ...card('c', 'Власний'),
                'style': {
                  'background': {'kind': 'color', 'color': 'surface'},
                  'height': 40,
                },
              },
            ],
          },
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(boxOf(tester, 'Один').width, 200);
      expect(boxOf(tester, 'Два').width, 600);
    });
  });

  // ─────────────────────────────────────────── nullNumericField

  group('nullNumericField: absent', () {
    test('policy key', () {
      expect(policy['nullNumericField'], 'absent');
    });

    testWidgets('"opacity": null does not hide the node', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          textNode('Видно', style: {'opacity': null}),
        ]),
      );
      expect(find.text('Видно'), findsOneWidget);
      expect(find.byType(Opacity), findsNothing, reason: 'absent opacity - no wrapper');
    });

    testWidgets('"opacity": 0 - zero is legal: the place stays, opacity is zero', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          textNode('Нуль', style: {'opacity': 0}),
        ]),
      );
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    });

    test('optional sizes with null - no field', () {
      final style = NodeStyle.parse({
        'width': null,
        'height': null,
        'minWidth': null,
        'maxWidth': null,
        'minHeight': null,
        'maxHeight': null,
        'color': 'primary',
      })!;
      expect(style.width, isNull);
      expect(style.maxHeight, isNull);
    });

    test('Text.maxLines, Repeater.limit and Repeater.columns with null - no field', () {
      final text = rootOf(
        docWith([
          textNode('А', extra: {'maxLines': null}),
        ]),
      ).children.single as TextNode;
      expect(text.maxLines, isNull);

      final repeater = rootOf(
        docWith([
          {
            'id': 'r',
            'type': 'Repeater',
            'props': {'source': 'x', 'item': 'y', 'limit': null, 'columns': null},
            'children': [textNode('Б', id: 'rt')],
          },
        ]),
      ).children.single as RepeaterNode;
      expect(repeater.limit, isNull);
      expect(repeater.columns, isNull);
    });
  });

  // ────────────────────────────────────────────── invalidWeight

  group('invalidWeight: no-weight', () {
    test('policy key', () {
      expect(policy['invalidWeight'], 'no-weight');
    });

    test('non-number, zero and negative - no weight; positive is clamped to 1..4', () {
      int? weightOf(Object? raw) => rootOf(
        docWith([
          {...card('c', 'А'), 'weight': raw},
        ]),
      ).children.single.weight;

      for (final broken in <Object?>[0, -1, 'три', true, null, double.nan]) {
        expect(weightOf(broken), isNull, reason: '$broken');
      }
      expect(weightOf(1), 1);
      expect(weightOf(4), 4);
      expect(weightOf(9), 4, reason: 'literalOutOfRange: clamp');
      expect(weightOf(2.0), 2, reason: 'an integer written as 2.0');
    });
  });

  // ─────────────────────────────────── missingShadowLayerField

  group('missingShadowLayerField: zero', () {
    test('policy key', () {
      expect(policy['missingShadowLayerField'], 'zero');
    });

    test('absent and null in the four layer fields - zero', () {
      for (final field in ['offsetX', 'offsetY', 'blur', 'spread']) {
        for (final withNull in [false, true]) {
          final parsed = NodeStyle.parse({
            'shadow': [
              {'color': 'onSurface', if (withNull) field: null},
            ],
          })!;
          final layer = (parsed.shadow! as CustomShadowRef).layers.single;
          expect(
            [layer.offsetX, layer.offsetY, layer.blur, layer.spread],
            everyElement(0),
            reason: '$field${withNull ? ' = null' : ' absent'}',
          );
        }
      }
    });
  });

  // ──────────────────────────────── protoKeyWithoutValidation

  group('protoKeyWithoutValidation: drop-entry', () {
    test('policy key of the document and the theme', () {
      expect(policy['protoKeyWithoutValidation'], 'drop-entry');
      expect(themePolicy['protoKeyWithoutValidation'], 'drop-entry');
      expect(kThemeCompatibilityPolicy['protoKeyWithoutValidation'], 'drop-entry');
    });

    test('the key is rejected, the rest of the record is read: params of an action', () {
      final action = ButtonAction.parse({
        'type': 'navigate',
        'params': {'__proto__': 'x', 'screenId': 'next'},
      });
      expect(action.params, {'screenId': 'next'});
    });

    test('...localization strings, and the language name', () {
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'p',
        'name': 'p',
        'initialScreenId': 's',
        'localization': {
          'defaultLocale': 'uk',
          'locales': ['uk', 'en'],
          'strings': {
            '__proto__': {'s/t/content': 'чужий'},
            'en': {'__proto__': 'x', 's/t/content': 'Hello'},
          },
        },
        'screens': [screenEntry('s', [textNode('Привіт', id: 't')])],
      });
      final en = doc.stringsFor('en');
      expect(en['s/t/content'], 'Hello');
      expect(en.length, 1, reason: 'the `__proto__` key did not get into the language table');
      expect(doc.stringsFor('__proto__').isEmpty, isTrue);
    });

    test('…entryPoints', () {
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'p',
        'name': 'p',
        'initialScreenId': 's',
        'entryPoints': {'__proto__': 's', 'home': 's'},
        'screens': [screenEntry('s', [textNode('А')])],
      });
      expect(doc.entryPoints, {'home': 's'});
    });
  });

  // ─────────────────────────── incompleteThemeAppliesTo (theme)

  test('incompleteThemeAppliesTo: reader-without-validation', () {
    expect(themePolicy['incompleteThemeAppliesTo'], 'reader-without-validation');
    expect(kThemeCompatibilityPolicy['incompleteThemeAppliesTo'], 'reader-without-validation');
  });
}
