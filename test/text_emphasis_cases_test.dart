/// TEXT EMPHASIS (schema 9.17.0): `style.fontStyle`,
/// `style.textDecoration` of a node and `weight`, `fontStyle`, `textDecoration` of a part.
///
/// The test reads the NEW groups of the shared table
/// `assets/contract/fixtures/rich-text/rich-text-cases.json` (described by the key
/// `emphasisNote`) and runs every row twice:
///
///  1. `emphasis` (38) - RULE: the emphasis of each chunk from the node's own and
///     inherited emphasis and the part's; SCREEN: a real document, and `Text` draws each
///     chunk with the same slant, line and weight (the line is on the chunk itself);
///  2. `emphasisStruts` (6) - the line strut does not depend on emphasis: the formula and
///     the step on a real screen.
///
/// Separately: inheritance through a real tree (only `Text` reads it, a button in an italic
/// card stays upright), a state that cancels the line, mirrors of the data block.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/text_emphasis.dart';
import 'package:hotlayout_flutter/src/model/text_spans.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

const String _place = 'cases/row/content';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/rich-text/rich-text-cases.json').readAsStringSync())
      as Map<String, Object?>;
  final rows = (table['emphasis']! as List<Object?>).cast<_Row>();
  final struts = (table['emphasisStruts']! as List<Object?>).cast<_Row>();
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
  final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;

  test('table read in full: 38 + 6 rows, known fields, unique names', () {
    expect(rows, hasLength(38));
    expect(struts, hasLength(6));
    const known = {
      'name', 'content', 'spans', 'style', 'inherited', 'sourceLocale', 'translationLocale', 'formattingLocale',
      'translations', 'data', 'now', 'direction', 'readerOnly', 'expected', //
    };
    for (final row in rows) {
      expect(row.keys.toSet().difference(known), isEmpty, reason: '${row['name']}: unknown row field');
    }
    expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length));
    expect(struts.map((row) => row['name']).toSet(), hasLength(struts.length));
  });

  LocalizedStrings stringsOf(_Row row) {
    final translation = row['translationLocale'] as String?;
    final source = row['sourceLocale'] as String?;
    final translations = (row['translations']! as Map<String, Object?>).cast<String, String>();
    return LocalizedStrings(
      locale: translation == source ? null : translation,
      table: translation == source
          ? const {}
          : {
              for (final entry in translations.entries)
                entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value,
            },
      sourceLocale: source,
    );
  }

  /// Text emphasis: inherited, with the node's own words on top (each separately).
  TextEmphasis textOf(_Row row) {
    final inherited = (row['inherited'] as Map?)?.cast<String, Object?>() ?? const {};
    final style = (row['style'] as Map?)?.cast<String, Object?>() ?? const {};
    final parent = inheritTextEmphasis(
      TextEmphasis.root,
      fontStyle: readFontStyle(inherited['fontStyle']),
      textDecoration: readDecoration(inherited['textDecoration']),
    );
    return inheritTextEmphasis(
      parent,
      fontStyle: readFontStyle(style['fontStyle']),
      textDecoration: readDecoration(style['textDecoration']),
    );
  }

  group('rule: the emphasis of each chunk', () {
    for (final row in rows) {
      test(row['name']! as String, () {
        final content = BindableString.parse(row['content'], key: _place);
        final expected = row['expected']! as _Row;
        final data = ScreenData(row['data']! as Map<String, Object?>);
        final formatting = row['formattingLocale'] as String?;
        final now = DateTime.parse(row['now']! as String);
        final active = activeTextSpans(content, readTextSpans(row['spans']));
        final runs = content is TemplateString
            ? spanRuns(content.runs(data, stringsOf(row), formatting, now), active)
            : spanRuns([(text: content.resolve(data, stringsOf(row), formatting, now), place: null)], active);

        final want = (expected['runs']! as List<Object?>).cast<_Row>();
        expect(runs.map((run) => (text: run.text, span: run.span)).toList(), [
          for (final run in want) (text: run['text']! as String, span: run['span'] as String?),
        ], reason: 'chunks (merged by place)');
        final text = textOf(row);
        for (var i = 0; i < runs.length; i++) {
          final emphasis = runEmphasisOf(text, runs[i].span == null ? null : active[runs[i].span]);
          expect(emphasis.fontStyle.wire, want[i]['fontStyle'], reason: 'slant of chunk $i');
          expect(emphasis.textDecoration.wire, want[i]['textDecoration'], reason: 'line of chunk $i');
          expect(emphasis.weight, want[i]['weight'], reason: 'weight of chunk $i');
        }
      });
    }
  });

  group('screen: the same Text node in a document', () {
    for (final row in rows) {
      testWidgets(row['name']! as String, (tester) async {
        final translation = row['translationLocale'] as String?;
        final source = row['sourceLocale'] as String?;
        final translations = (row['translations']! as Map<String, Object?>).cast<String, String>();
        final expected = row['expected']! as _Row;
        final inherited = row['inherited'] as Map?;

        final textNode = {
          'id': 'row',
          'type': 'Text',
          'props': {
            'content': row['content'],
            'align': 'start',
            'overflow': 'clip',
            if (row.containsKey('spans')) 'spans': row['spans'],
          },
          if (row['style'] != null) 'style': row['style'],
        };
        final doc = UiDocument.fromJson({
          'schemaVersion': kSupportedSchemaVersion,
          'documentId': 'cases',
          'name': 'cases',
          'initialScreenId': 'cases',
          'screens': [
            {
              'screenId': 'cases',
              'name': 'cases',
              'root': {
                'id': 'root',
                'type': 'Screen',
                'props': {'gap': 'none'},
                'children': [
                  // The ancestor names the emphasis - the text inherits it.
                  if (inherited != null)
                    {
                      'id': 'card',
                      'type': 'Container',
                      'props': {'direction': 'column', 'gap': 'none'},
                      'style': inherited,
                      'children': [textNode],
                    }
                  else
                    textNode,
                ],
              },
            },
          ],
          if (source != null)
            'localization': {
              'defaultLocale': source,
              'locales': {source, ?translation}.toList(),
              'strings': {
                if (translation != null && translation != source)
                  translation: {
                    'cases/elsewhere/content': '·',
                    for (final entry in translations.entries)
                      entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value,
                  },
              },
            },
        });

        final theme = RenderTheme.fallback();
        await pumpDocument(
          tester,
          doc,
          theme: theme,
          data: row['data']! as Map<String, Object?>,
          locale: row['formattingLocale'] as String?,
          now: DateTime.parse(row['now']! as String),
        );
        expect(tester.takeException(), isNull);

        final widget = tester.widget<Text>(find.byType(Text));
        final want = (expected['runs']! as List<Object?>).cast<_Row>();
        final parts = widget.textSpan == null ? null : (widget.textSpan! as TextSpan).children!.cast<TextSpan>();

        // Style of each chunk: slant, line, weight. The paragraph (`Text.style`) carries no line.
        for (var i = 0; i < want.length; i++) {
          final style = parts == null ? widget.style : parts[i].style;
          final fontStyle = style?.fontStyle ?? FontStyle.normal;
          final decoration = style?.decoration ?? TextDecoration.none;
          expect(fontStyle, want[i]['fontStyle'] == 'italic' ? FontStyle.italic : FontStyle.normal, reason: 'slant of chunk $i');
          expect(
            decoration,
            switch (want[i]['textDecoration']) {
              'underline' => TextDecoration.underline,
              'lineThrough' => TextDecoration.lineThrough,
              _ => TextDecoration.none,
            },
            reason: 'line of chunk $i',
          );
          final weight = want[i]['weight'];
          if (weight != null) {
            expect(style!.fontWeight!.value, weight, reason: 'weight of chunk $i');
          }
          // The line takes the chunk's colour: there is no own `decorationColor`.
          expect(style?.decorationColor, isNull, reason: 'line of chunk $i has the colour of its text');
        }
        if (parts != null) {
          expect(parts, hasLength(want.length));
          // The paragraph carries no line: a descendant could not cancel it.
          expect(widget.style?.decoration, anyOf(isNull, TextDecoration.none), reason: 'paragraph without a line');
        }
      });
    }
  });

  group('line strut does not depend on emphasis: emphasisStruts rows', () {
    for (final row in struts) {
      LineMetric metric(Object? raw) {
        final map = raw! as Map<String, Object?>;
        return (fontSize: (map['fontSize']! as num).toDouble(), lineHeight: (map['lineHeight']! as num).toDouble());
      }

      test('formula: ${row['name']}', () {
        final result = richTextStrut(metric(row['base']), {
          for (final entry in (row['spans']! as Map<String, Object?>).entries) entry.key: metric(entry.value),
        });
        final expected = row['expected']! as _Row;
        expect(result.span, expected['span']);
        expect(result.lineBlock, closeTo((expected['lineBlock']! as num).toDouble(), 1e-9));
      });

      testWidgets('real screen: ${row['name']}', (tester) async {
        // Each part is the `bodyM` font with size and multiplier tweaks; the emphasis
        // of parts and node goes on top, and the line step stays the same.
        Map<String, Object?> typography(Object? raw) {
          final m = metric(raw);
          return {'token': 'bodyM', 'fontSize': m.fontSize, 'lineHeight': m.lineHeight};
        }

        final names = (row['spans']! as Map<String, Object?>).keys.toList();
        final emphasis = (row['emphasis']! as Map<String, Object?>).cast<String, Object?>();
        final spans = {
          for (final name in names)
            name: {
              'typography': typography((row['spans']! as Map)[name]),
              ...((emphasis[name] as Map?)?.cast<String, Object?>() ?? const {}),
            },
        };
        final doc = UiDocumentBuilder.bare([
          {
            'id': 'row',
            'type': 'Text',
            'props': {
              'content': {
                'kind': 'template',
                'template': names.map((name) => '{$name}').join(' '),
                'values': {for (final name in names) name: {'kind': 'text', 'text': name}},
              },
              'align': 'start',
              'overflow': 'clip',
              'spans': spans,
            },
            'style': {
              'typography': typography(row['base']),
              ...((row['style'] as Map?)?.cast<String, Object?>() ?? const {}),
            },
          },
        ]);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);
        final strut = tester.widget<Text>(find.byType(Text)).strutStyle!;
        final expected = row['expected']! as _Row;
        expect(strut.forceStrutHeight, isTrue);
        expect(strut.fontSize! * strut.height!, closeTo((expected['lineBlock']! as num).toDouble(), 1e-6), reason: 'line step');
      });
    }
  });

  group('inheritance through a real tree', () {
    TextStyle? styleOfText(WidgetTester tester, String value) {
      final widget = tester.widget<Text>(find.text(value));
      return widget.style;
    }

    testWidgets('italic on a card applies to the text in it, while the button label stays upright (only Text reads it)', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            'id': 'card',
            'type': 'Container',
            'props': {'direction': 'column', 'gap': 'none'},
            'style': {'fontStyle': 'italic', 'textDecoration': 'underline'},
            'children': [
              textNode('У картці', id: 't1'),
              {
                'id': 'b',
                'type': 'Button',
                'props': {
                  'label': {'kind': 'literal', 'value': 'Кнопка'},
                  'variant': 'primary',
                  'action': {'type': 'none'},
                  'fullWidth': false,
                },
                'style': {'fontStyle': 'italic'},
              },
              textNode('Прямий', id: 't2', style: {'fontStyle': 'normal', 'textDecoration': 'none'}),
            ],
          },
        ]),
      );
      expect(styleOfText(tester, 'У картці')!.fontStyle, FontStyle.italic);
      expect(styleOfText(tester, 'У картці')!.decoration, TextDecoration.underline);
      final button = tester.widget<Text>(find.text('Кнопка'));
      final effective = DefaultTextStyle.of(tester.element(find.text('Кнопка'))).style.merge(button.style);
      expect(effective.fontStyle, isNot(FontStyle.italic), reason: 'the button label does not read emphasis');
      expect(effective.decoration, isNot(TextDecoration.underline));
      // `normal` and `none` are real words: they cancel the inherited value.
      expect(styleOfText(tester, 'Прямий')!.fontStyle ?? FontStyle.normal, FontStyle.normal);
      expect(styleOfText(tester, 'Прямий')!.decoration ?? TextDecoration.none, TextDecoration.none);
    });

    testWidgets('a state with none over a base lineThrough removes the line', (tester) async {
      Future<void> pump(Map<String, Object?> data) => pumpDocument(
        tester,
        UiDocumentBuilder.bare([
          {
            ...textNode('Стара ціна', id: 'old', style: {'textDecoration': 'lineThrough'}),
            'styleWhen': [
              {
                'when': {'path': 'user.isPremium', 'op': 'isTrue'},
                'style': {'textDecoration': 'none'},
              },
            ],
          },
        ]),
        data: data,
      );
      await pump({});
      expect(tester.widget<Text>(find.text('Стара ціна')).style!.decoration, TextDecoration.lineThrough);
      await pump({'user': {'isPremium': true}});
      expect(tester.widget<Text>(find.text('Стара ціна')).style?.decoration ?? TextDecoration.none, TextDecoration.none);
    });

    test('words the reader does not know mean no field', () {
      final style = NodeStyle.parse({'fontStyle': 'oblique', 'textDecoration': 'overline', 'color': 'primary'});
      expect(style!.fontStyle, isNull);
      expect(style.textDecoration, isNull);
      expect(NodeStyle.parse({'fontStyle': true, 'textDecoration': 1}), isNull);
      expect(NodeStyle.parse({'fontStyle': 'normal'})!.fontStyle, EmphasisFontStyle.normal);
      expect(NodeStyle.parse({'textDecoration': 'none'})!.textDecoration, EmphasisDecoration.none);
    });
  });

  group('9.17.0 mirrors against the artifact', () {
    final block = layout['textEmphasis']! as Map<String, Object?>;

    test('x-style.layout.textEmphasis holds the rules the renderer computes with', () {
      for (final entry in kTextEmphasisLayout.entries) {
        expect(block[entry.key], entry.value, reason: entry.key);
      }
      expect(block['nodeKeys'], kTextEmphasisNodeKeys);
      expect(block['spanKeys'], kTextEmphasisSpanKeys);
      expect(block['fontStyles'], [for (final v in EmphasisFontStyle.values) v.wire]);
      expect(block['decorations'], [for (final v in EmphasisDecoration.values) v.wire]);
      expect(block['root'], {'fontStyle': 'normal', 'textDecoration': 'none'});
      expect(block['weights'], kSpanWeights);
      expect({for (final v in SpanWeight.values) v.wire: v.number}, kSpanWeights);
      expect(block.keys.toSet(), {
        ...kTextEmphasisLayout.keys, 'nodeKeys', 'spanKeys', 'fontStyles', 'decorations', 'root', 'weights', 'cases',
      });
    });

    test('the richText.styleKeys block is not extended: the React package mirrors it by equality', () {
      expect((layout['richText']! as Map)['styleKeys'], kTextSpanStyleKeys);
    });

    test('capabilities: textEmphasis from 9.17.0', () {
      final features = ((schema['x-compatibility']! as Map)['features']! as Map).cast<String, Object?>();
      expect(features['textEmphasis'], '9.17.0');
      expect(kFeatureCatalog['textEmphasis'], '9.17.0');
      expect(supportsFeature('textEmphasis'), isTrue);
      expect(supportsFeature('textEmphasis', readerVersion: '9.16.0'), isFalse);
    });

    test('a part with emphasis only is a part; an unknown word is not a field', () {
      expect(readTextSpans({'a': {'weight': 'bold'}}).keys, ['a']);
      expect(readTextSpans({'a': {'weight': 'black'}}), isEmpty);
      expect(readTextSpans({'a': {'weight': 700}}), isEmpty);
      expect(readTextSpans({'a': {'fontStyle': 'oblique', 'color': 'accent'}})['a']!.fontStyle, isNull);
      expect(readTextSpans({'a': {'textDecoration': 'lineThrough'}})['a']!.textDecoration, EmphasisDecoration.lineThrough);
    });
  });
}
