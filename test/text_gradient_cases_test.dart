/// A GRADIENT ON THE GLYPHS OF A TEXT (schema 9.23.0, `style.textGradient`).
///
/// The shared tables (`assets/contract/fixtures/rich-text/rich-text-cases.json`) run row by row:
///
///  1. `textGradientCases` -- which gradient paints the letters (a base style, a state, a parent that does not pass
///     it on, a widget that does not read it), by the style rule AND on a real screen;
///  2. `textGradientPartCases` -- a part with a colour of its own keeps it, the others take the gradient;
///  3. `textGradientDocumentCases` -- every document is read and drawn without a crash.
///
/// Plus what the table cannot say: the gradient lies over one box for every line, a line of an underline takes
/// the colour of the text, and a gradient that does not resolve leaves the colour.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/rich-text/rich-text-cases.json').readAsStringSync()) as _Row;
final _Row _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

Map<String, Object?> _node(_Row row, {String label = 'hello'}) {
  final style = row['style'] as _Row?;
  final styleWhen = row['styleWhen'];
  final Map<String, Object?> node = switch (row['type']) {
    'Button' => buttonNode(label, action: {'type': 'none'}),
    'Badge' => badgeNode(label),
    'Container' => {'id': 'node', 'type': 'Container', 'children': [textNode(label, id: 'inner')]},
    _ => textNode(label),
  };
  if (style != null) node['style'] = style;
  if (styleWhen != null) node['styleWhen'] = styleWhen;
  return node;
}

/// The gradient the table says paints the letters, as the theme resolves it.
LinearGradient? _expected(RenderTheme theme, Object? gradient) =>
    gradient == null ? null : theme.resolveGradient(GradientRef.tryParse(gradient)!);

void main() {
  final theme = RenderTheme.fallback();

  test('the tables have the promised rows', () {
    expect(_rows('textGradientCases'), hasLength(9));
    expect(_rows('textGradientPartCases'), hasLength(3));
    expect(_rows('textGradientDocumentCases'), hasLength(8));
  });

  group('textGradientCases -- which gradient paints the letters', () {
    for (final row in _rows('textGradientCases')) {
      final name = row['name']! as String;
      final met = (row['met'] as List<Object?>?)?.cast<bool>() ?? const <bool>[];
      final data = {'user.isPremium': met.isNotEmpty && met.first};

      if (row['type'] == 'Text') {
        test('rule: $name', () {
          final node = rootOf(docWith([_node(row)])).children.single;
          final style = resolveNodeStyle(node.style, node.styleWhen, ScreenData(data), applicable: theme.applicableStyle);
          final ref = style?.textGradient;
          final resolved = ref == null ? null : theme.resolveGradient(ref);
          expect(resolved, _expected(theme, row['gradient']));
        });
      }

      testWidgets('screen: $name', (tester) async {
        final inner = _node(row);
        final parent = row['parent'] as _Row?;
        final doc = docWith([
          if (parent == null) inner else {'id': 'card', 'type': 'Container', 'style': parent, 'children': [inner]},
        ]);
        await pumpDocument(tester, doc, data: data);
        expect(find.byType(ShaderMask), row['gradient'] == null ? findsNothing : findsOneWidget);
        expect(find.text('hello'), findsWidgets);
      });
    }
  });

  group('textGradientPartCases -- a part with its own colour keeps it', () {
    for (final row in _rows('textGradientPartCases')) {
      final name = row['name']! as String;
      testWidgets(name, (tester) async {
        final spans = (row['spans']! as _Row).cast<String, Object?>();
        final text = {
          'id': 'row',
          'type': 'Text',
          'props': {
            'content': {
              'kind': 'template',
              'template': '{count} | {star} | pts',
              'values': {
                'count': {'kind': 'binding', 'path': 'user.points', 'fallback': '0'},
                'star': {'kind': 'text', 'text': '✦'},
              },
            },
            'align': 'start',
            'overflow': 'clip',
            'spans': spans,
          },
          'style': {if (row['gradient'] != null) 'textGradient': row['gradient']},
        };
        await pumpDocument(tester, docWith([text]), data: {'user.points': 77});
        final gradient = row['gradient'] != null;
        expect(find.byType(ShaderMask), gradient ? findsOneWidget : findsNothing);
        if (!gradient) return;

        // The mask layer: white glyphs show the gradient, transparent ones belong to the overlay.
        final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
        final layer = (mask.child! as Text).textSpan! as TextSpan;
        final runs = <String, Color?>{};
        layer.visitChildren((span) {
          if (span is TextSpan && span.text != null) runs[span.text!] = span.style?.color ?? layer.style?.color;
          return true;
        });
        final parts = (row['parts']! as _Row).cast<String, bool>();
        const places = {'count': '77', 'star': '✦', '': ' | '};
        for (final entry in parts.entries) {
          final piece = runs.entries.firstWhere((run) => run.key.contains(places[entry.key]!)).value;
          expect(piece == Colors.white, entry.value, reason: 'place "${entry.key}" takes the gradient: ${entry.value}');
        }
      });
    }
  });

  group('textGradientDocumentCases -- read and drawn without a crash', () {
    for (final row in _rows('textGradientDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await pumpDocument(tester, docWith([_node(row)]), data: {'user.isPremium': true});
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the gradient lies over ONE box for every line: one mask for a text of many lines', (tester) async {
    final text = textNode(
      'one two three four five six seven eight nine ten eleven twelve',
      style: {'textGradient': 'brandBackdrop'},
    );
    await tester.binding.setSurfaceSize(const Size(160, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpDocument(tester, docWith([text]));
    expect(find.byType(ShaderMask), findsOneWidget);
    final box = tester.getRect(find.byType(ShaderMask));
    final paragraph = tester.getRect(find.byType(Text).first);
    expect(box.height, greaterThan(40), reason: 'the text wrapped to several lines');
    expect(paragraph.height, box.height, reason: 'the gradient box is the content box of the whole text');
  });

  testWidgets('a line takes the colour of the text, not the gradient', (tester) async {
    final text = textNode('lined', style: {'textGradient': 'brandBackdrop', 'color': 'accent', 'textDecoration': 'underline'});
    await pumpDocument(tester, docWith([text]));
    final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    expect((mask.child! as Text).style!.decoration, anyOf(isNull, TextDecoration.none), reason: 'no line under the gradient');
    final lines = find.byWidgetPredicate((widget) => widget is Text && widget.style?.decoration == TextDecoration.underline);
    expect(lines, findsOneWidget);
    final over = tester.widget<Text>(lines);
    expect(over.style!.decorationColor, theme.color(ColorToken.accent));
    expect(over.style!.color, Colors.transparent, reason: 'the overlay draws the line only');
  });

  testWidgets('a gradient that does not resolve leaves the colour (unknown token, stops out of order)', (tester) async {
    await pumpDocument(tester, docWith([textNode('x', style: {'textGradient': 'noSuchGradient'})]));
    expect(find.byType(ShaderMask), findsNothing);
    await pumpDocument(
      tester,
      docWith([
        textNode(
          'x',
          style: {
            'textGradient': {
              'angle': 90,
              'stops': [
                {'color': 'primary', 'position': 0.8},
                {'color': 'accent', 'position': 0.2},
              ],
            },
          },
        ),
      ]),
    );
    expect(find.byType(ShaderMask), findsNothing);
  });

  test('x-textGradient: the block of the artifact', () {
    final block = _schema['x-textGradient']! as _Row;
    expect(block['prop'], 'style.textGradient');
    expect(block['inherited'], false);
    expect(block['readers'], ['Text']);
    expect(block['partWithOwnColor'], 'keeps-its-colour');
    expect((block['fallback']! as _Row)['color'], 'style.color-or-the-inherited-colour');
    expect(block['decoration'], 'the-fallback-colour');
  });

  test('the style field is parsed as a gradient reference, and a wrong shape is dropped', () {
    expect(NodeStyle.parse({'textGradient': 'aurora'})!.textGradient, isA<TokenGradientRef>());
    expect(NodeStyle.parse({'textGradient': {'kind': 'gradient', 'gradient': 'x'}}), isNull);
  });
}
