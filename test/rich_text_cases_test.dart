/// Shared table of COMPOSED TEXT cases (schema 9.6.0) - run WHOLE through the renderer.
///
/// There is ONE table for all readers (`fixtures/rich-text/rich-text-cases.json`), and the
/// test reads the artifact itself: a row added in the builder starts being checked here
/// after a `cp`, with no edits to this file. No row is skipped silently: `readerOnly` rows
/// (documents the builder would not produce) are just as mandatory for a reader.
///
/// THREE PASSES:
///  1. RULE - text, chunks and read styles without any widget;
///  2. SCREEN - a document is BUILT from the row (a `Text` node with `spans`) and drawn by
///     `renderDocument`: paragraph text, chunks with real styles,
///     ONE semantics node with the whole line, paragraph direction;
///  3. STRUT (`struts`) - the line pitch and whose style gave it; and by size on
///     screen: a two-line paragraph with a big part is exactly 2 x the pitch tall.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/text_spans.dart';
import 'package:hotlayout_flutter/src/model/shown_text.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

const String _place = 'cases/row/content';

void main() {
  final table =
      jsonDecode(File('assets/contract/fixtures/rich-text/rich-text-cases.json').readAsStringSync())
          as Map<String, Object?>;
  final rows = (table['cases']! as List<Object?>).cast<Map<String, Object?>>();
  final struts = (table['struts']! as List<Object?>).cast<Map<String, Object?>>();

  test('the table is read whole, and each of its fields is known to this test', () {
    expect(rows, hasLength(34));
    expect(rows.where((row) => row['readerOnly'] != null), hasLength(13));
    expect(struts, hasLength(10));
    const known = {
      'name', 'content', 'spans', 'sourceLocale', 'translationLocale', 'formattingLocale',
      'translations', 'data', 'now', 'direction', 'readerOnly', 'expected', //
    };
    for (final row in rows) {
      expect(row.keys.toSet().difference(known), isEmpty, reason: '${row['name']}: unknown row field');
    }
    expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: 'row names are unique');
    expect(struts.map((row) => row['name']).toSet(), hasLength(struts.length));
  });

  LocalizedStrings stringsOf(Map<String, Object?> row) {
    final translation = row['translationLocale'] as String?;
    final source = row['sourceLocale'] as String?;
    final translations = (row['translations']! as Map<String, Object?>).cast<String, String>();
    // The translation table exactly as `UiDocument.stringsFor` gives it.
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

  /// What the row's `styles` should say, as this reader's style.
  Map<String, TextSpanStyle> expectedStyles(Map<String, Object?> expected) => {
    for (final entry in (expected['styles']! as Map<String, Object?>).entries)
      entry.key: TextSpanStyle(
        color: ColorRef.tryParse((entry.value! as Map)['color']),
        typography: TypographyRef.tryParse((entry.value! as Map)['typography']),
      ),
  };

  List<TextSpanRun> expectedRuns(Map<String, Object?> expected) => [
    for (final run in (expected['runs']! as List<Object?>).cast<Map<String, Object?>>())
      (text: run['text']! as String, span: run['span'] as String?),
  ];

  group('rule: text, chunks, read styles', () {
    for (final row in rows) {
      test(row['name']! as String, () {
        final content = BindableString.parse(row['content'], key: _place);
        final expected = row['expected']! as Map<String, Object?>;
        final strings = stringsOf(row);
        final data = ScreenData(row['data']! as Map<String, Object?>);
        final locale = row['formattingLocale'] as String?;
        final now = DateTime.parse(row['now']! as String);

        // 1. Text - exactly the one without `spans`.
        expect(content.resolve(data, strings, locale, now), expected['text']);

        // 2. The styles that APPLY - what the reader read for the declared places.
        final active = activeTextSpans(content, readTextSpans(row['spans']));
        expect(active, expectedStyles(expected), reason: 'styles');

        // 3. Chunks. Not a template - one chunk of the base style.
        final runs = content is TemplateString
            ? spanRuns(content.runs(data, strings, locale, now), active)
            : spanRuns([(text: content.resolve(data, strings, locale, now), place: null)], active);
        expect(runs, expectedRuns(expected), reason: 'runs');
        expect(runs.map((run) => run.text).join(), expected['text'], reason: 'chunks make up the text');
      });
    }
  });

  group('screen: the same Text node with spans in a document', () {
    for (final row in rows) {
      testWidgets(row['name']! as String, (tester) async {
        final translation = row['translationLocale'] as String?;
        final source = row['sourceLocale'] as String?;
        final translations = (row['translations']! as Map<String, Object?>).cast<String, String>();
        final expected = row['expected']! as Map<String, Object?>;

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
                  {
                    'id': 'row',
                    'type': 'Text',
                    'props': {
                      'content': row['content'],
                      'align': 'start',
                      'overflow': 'clip',
                      if (row.containsKey('spans')) 'spans': row['spans'],
                    },
                  },
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
                    // A line for a foreign place makes the language present and
                    // translates nothing (as in the template table).
                    'cases/elsewhere/content': '·',
                    for (final entry in translations.entries)
                      entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value,
                  },
              },
            },
        });

        final requested = row['formattingLocale'] as String?;
        final theme = RenderTheme.fallback();
        final handle = tester.ensureSemantics();
        await pumpDocument(
          tester,
          doc,
          theme: theme,
          data: row['data']! as Map<String, Object?>,
          locale: requested,
          now: DateTime.parse(row['now']! as String),
        );
        expect(tester.takeException(), isNull);

        final texts = tester.widgetList<Text>(find.byType(Text)).toList();
        expect(texts, hasLength(1));
        final widget = texts.single;
        // The whitespace rule for shown text (`shown_text.dart`) is newer than the table:
        // a double space in place of an empty chunk is shown as one. Expectations are
        // checked after the same rule until it lands in `rich-text-cases.json`.
        final text = collapseShownWhitespace(expected['text']! as String);
        expect(widget.textSpan?.toPlainText() ?? widget.data, text, reason: 'paragraph text');

        // Chunks on screen: the same texts and the same styles as in the table.
        final runs = collapseShownRuns<TextSpanRun>(
          expectedRuns(expected),
          (run) => run.text,
          (run, text) => (text: text, span: run.span),
        );
        final styles = expectedStyles(expected);
        final base = tester.widget<Text>(find.byType(Text)).style!;
        if (widget.textSpan == null) {
          // No effective styles - a plain Text, as before 9.6.0.
          expect(runs.every((run) => run.span == null), isTrue);
          expect(
            styles.keys.where(
              (name) => (BindableString.parse(row['content']) is TemplateString) &&
                  (BindableString.parse(row['content']) as TemplateString).values.containsKey(name),
            ),
            isEmpty,
            reason: 'there are effective styles, yet the Text is plain',
          );
        } else {
          final children = (widget.textSpan! as TextSpan).children!.cast<TextSpan>();
          expect(children.map((child) => child.text), runs.map((run) => run.text), reason: 'chunks');
          for (var i = 0; i < runs.length; i++) {
            final name = runs[i].span;
            final style = children[i].style;
            if (name == null) {
              expect(style, isNull, reason: 'chunk ${runs[i].text}: text style');
              continue;
            }
            final color = styles[name]!.color == null ? null : theme.resolveColor(styles[name]!.color!);
            final font = styles[name]!.typography == null
                ? null
                : theme.resolveTypography(styles[name]!.typography!);
            expect(style!.color, color ?? base.color, reason: 'colour of part $name');
            expect(style.fontSize, (font ?? base).fontSize, reason: 'size of part $name');
            expect(style.fontWeight, (font ?? base).fontWeight, reason: 'weight of part $name');
          }
          expect(widget.strutStyle?.forceStrutHeight, isTrue, reason: 'line strut');
        }

        // ONE semantics node with the whole line (`richTextSemantics`).
        if (text.isNotEmpty) {
          final labelled = find.bySemanticsLabel(text);
          expect(labelled, findsOneWidget, reason: 'one node with the whole line');
        }

        // Paragraph direction follows the language of the shown text (9.1.0).
        final direction = Directionality.of(tester.element(find.byType(Text)));
        if (row['direction'] != null) {
          expect(direction, row['direction'] == 'rtl' ? TextDirection.rtl : TextDirection.ltr);
        }
        handle.dispose();
      });
    }
  });

  group('strut: struts rows', () {
    for (final row in struts) {
      test(row['name']! as String, () {
        LineMetric metric(Object? raw) {
          final map = raw! as Map<String, Object?>;
          return (fontSize: (map['fontSize']! as num).toDouble(), lineHeight: (map['lineHeight']! as num).toDouble());
        }

        final result = richTextStrut(metric(row['base']), {
          for (final entry in (row['spans']! as Map<String, Object?>).entries) entry.key: metric(entry.value),
        });
        final expected = row['expected']! as Map<String, Object?>;
        expect(result.span, expected['span']);
        expect(result.lineBlock, closeTo((expected['lineBlock']! as num).toDouble(), 1e-9));
      });
    }
  });

  group('9.6.0 mirrors against the artifact', () {
    final schema =
        jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
    final compatibility = schema['x-compatibility']! as Map<String, Object?>;
    final policy = compatibility['policy']! as Map<String, Object?>;
    final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;

    test('reader version, features, seven policy rows at the end', () {
      // The reader moved on (9.7.0 added no policy rows), and the test asks
      // what 9.6.0 can do.
      expect(schema['x-schemaVersion'], kSupportedSchemaVersion);
      expect(
        SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 6, 0)),
        greaterThanOrEqualTo(0),
      );
      final features = compatibility['features']! as Map<String, Object?>;
      for (final feature in ['textSpans', 'templateWord']) {
        expect(features[feature], '9.6.0');
        expect(kFeatureCatalog[feature], '9.6.0');
        expect(supportsFeature(feature), isTrue);
        expect(supportsFeature(feature, readerVersion: '9.5.0'), isFalse);
      }
      expect(kTextSpansPolicy, hasLength(7));
      for (final entry in kTextSpansPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      expect(policy.keys.toList().sublist(policy.length - 7 - kActionPolicy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - kActionPolicy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length)), kTextSpansPolicy.keys.toList());
    });

    test('x-style.layout.richText - the rules the renderer computes with', () {
      final rich = layout['richText']! as Map<String, Object?>;
      for (final entry in kRichTextLayout.entries) {
        expect(rich[entry.key], entry.value, reason: entry.key);
      }
      expect(rich['places'], {'Text': {'spans': 'spans', 'text': 'content'}});
      expect(rich.keys.toSet(), {...kRichTextLayout.keys, 'places'});
      expect(kTextSpanStyleKeys, rich['styleKeys']);
    });

    test('the template word has its own translation key', () {
      final template = schema['x-template']! as Map<String, Object?>;
      expect((template['translationKeys']! as Map)['word'], '<screenId>/<nodeId>/<field path>.values.<name>.text');
    });
  });
}
