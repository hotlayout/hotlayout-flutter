/// MONEY AS MONEY (schema 9.19.0): the currency sign, the number sign, the isolation of the composed form
/// in a right-to-left text, and the parts of an amount that a style can name.
///
/// Three groups of two shared case tables, every row of which runs:
///
///  1. `moneyCases` (73, `template/template-cases.json`) -- the text: as a pure function of the document
///     string, and as a `Text` node on a real screen. The rows with `pieces` also compare the pieces of
///     the value and the part each belongs to;
///  2. `amountPartCases` (19, `rich-text/rich-text-cases.json`) -- the runs of a composed text and the
///     style each is drawn with; and a real paragraph;
///  3. `amountPartStruts` (5) -- the line pitch with a declared part.
///
/// The model is the builder's `scripts/money-cases.test.tsx`. Digits and separators of a language are the
/// platform's (`mayDiffer`); the signs, the gaps, the order and the isolation marks are not.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/locale_resolve.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/shown_text.dart';
import 'package:hotlayout_flutter/src/model/text_spans.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _readJson(String path) => jsonDecode(File(path).readAsStringSync()) as _Json;

final _templates = _readJson('assets/contract/fixtures/template/template-cases.json');
final _richText = _readJson('assets/contract/fixtures/rich-text/rich-text-cases.json');
final _schema = _readJson('assets/contract/screen-schema.json');

List<_Json> _rows(_Json table, String key) => (table[key]! as List<Object?>).cast<_Json>();

_Json _obj(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();

const String _place = 'cases/row/content';

LocalizedStrings _stringsOf(_Json row) {
  final translation = row['translationLocale'] as String?;
  final source = row['sourceLocale'] as String?;
  final translations = _obj(row['translations']).cast<String, String>();
  return LocalizedStrings(
    locale: translation == source ? null : translation,
    table: translation == source
        ? const {}
        : {for (final entry in translations.entries) entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value},
    sourceLocale: source,
  );
}

/// A one-screen document around the row's content, with the localization section the row names.
UiDocument _documentOf(_Json row, {Object? spans}) {
  final translation = row['translationLocale'] as String?;
  final source = row['sourceLocale'] as String?;
  final translations = _obj(row['translations']).cast<String, String>();
  return UiDocument.fromJson({
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
                'content': row['value'] ?? row['content'],
                'align': 'start',
                'overflow': 'clip',
                'spans': ?spans,
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
              'cases/elsewhere/content': '·',
              for (final entry in translations.entries) entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value,
            },
        },
      },
  });
}

String? _partWire(AmountPart? part) => part?.wire;

void main() {
  final money = _rows(_templates, 'moneyCases');

  group('moneyCases: the table is read whole', () {
    test('73 rows, names are unique, every field is known', () {
      expect(money, hasLength(73));
      expect(money.map((row) => row['name']).toSet(), hasLength(73));
      const known = {
        'name', 'value', 'sourceLocale', 'translationLocale', 'formattingLocale', 'direction',
        'translations', 'data', 'now', 'expected', 'pieces', 'mayDiffer', 'readerOnly', //
      };
      for (final row in money) {
        expect(row.keys.toSet().difference(known), isEmpty, reason: '${row['name']}: unknown row field');
      }
    });
  });

  group('moneyCases, rule: document string -> text', () {
    for (final row in money) {
      test(row['name']! as String, () {
        final value = BindableString.parse(row['value'], key: _place);
        final strings = _stringsOf(row);
        final locale = row['formattingLocale'] as String?;
        final data = ScreenData(_obj(row['data']));
        final now = DateTime.parse(row['now']! as String);

        final shown = value.resolve(data, strings, locale, now);
        expect(shown, row['expected'], reason: row['mayDiffer'] as String?);

        // The direction the reader recovers from the strings is the one the row names.
        expect(
          isRtlLanguageTag(strings.shownLanguage(locale)) ? 'rtl' : 'ltr',
          row['direction'],
          reason: 'direction of the shown text',
        );

        final pieces = row['pieces'] as List<Object?>?;
        if (pieces != null) {
          final bound = value as BoundString;
          final got = bound.pieces(data, strings, locale, now);
          expect([for (final piece in got) {'text': piece.text, 'part': _partWire(piece.part)}], [
            for (final piece in pieces.cast<_Json>()) {'text': piece['text'], 'part': piece['part']},
          ]);
          expect(got.map((piece) => piece.text).join(), shown, reason: 'the pieces joined are the text');
        }
      });
    }
  });

  group('moneyCases, screen: the same row as a Text node', () {
    // The row names the ANSWERS of the language rule (text `en`, format `tlh`); `renderDocument` computes
    // them from the host request, and no request gives that pair. A host that uses `renderScreen` names
    // the format locale itself.
    const throughRenderScreen = {'sign: no number data for the formatting locale, the number as it is'};
    for (final row in money) {
      testWidgets(row['name']! as String, (tester) async {
        final doc = _documentOf(row);
        if (throughRenderScreen.contains(row['name'])) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: renderScreen(
                  doc.initialScreen,
                  theme: RenderTheme.fallback(),
                  data: _obj(row['data']),
                  strings: doc.stringsFor(row['translationLocale'] as String?),
                  locale: row['formattingLocale'] as String?,
                  now: DateTime.parse(row['now']! as String),
                ),
              ),
            ),
          );
        } else {
          await pumpDocument(
            tester,
            doc,
            data: _obj(row['data']),
            locale: row['formattingLocale'] as String?,
            now: DateTime.parse(row['now']! as String),
          );
        }
        expect(tester.takeException(), isNull);
        expect(
          tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? text.textSpan?.toPlainText()).toList(),
          [collapseShownWhitespace(row['expected']! as String)],
        );
      });
    }
  });

  group('amountPartCases: the runs of a composed text and their styles', () {
    final cases = _rows(_richText, 'amountPartCases');

    test('19 rows, names are unique', () {
      expect(cases, hasLength(19));
      expect(cases.map((row) => row['name']).toSet(), hasLength(19));
    });

    for (final row in cases) {
      test('rule: ${row['name']}', () {
        final content = BindableString.parse(row['content'], key: _place);
        final expected = _obj(row['expected']);
        final strings = _stringsOf(row);
        final data = ScreenData(_obj(row['data']));
        final locale = row['formattingLocale'] as String?;
        final now = DateTime.parse(row['now']! as String);

        expect(content.resolve(data, strings, locale, now), expected['text']);
        final read = readTextSpans(row['spans']);
        final active = activeTextSpans(content, read);
        // What was read of `spans`, parts included.
        final styles = _obj(expected['styles']);
        expect(active.keys.toSet(), styles.keys.toSet(), reason: 'the places that apply');
        for (final entry in styles.entries) {
          final style = active[entry.key]!;
          final written = _obj(entry.value);
          final parts = written['parts'] == null ? <String, Object?>{} : _obj(written['parts']);
          expect(style.parts.keys.map((part) => part.wire).toSet(), parts.keys.toSet(), reason: '${entry.key}: parts read');
        }
        final runs = content is TemplateString
            ? spanPartRuns(content.partedRuns(data, strings, locale, now), active)
            : spanPartRuns([(text: content.resolve(data, strings, locale, now), place: null, part: null)], active);
        expect(
          [for (final run in runs) {'text': run.text, 'span': run.span, 'part': _partWire(run.part)}],
          [for (final run in (expected['runs']! as List<Object?>).cast<_Json>()) {'text': run['text'], 'span': run['span'], 'part': run['part']}],
          reason: 'runs',
        );
        expect(runs.map((run) => run.text).join(), expected['text']);
      });
    }

    for (final row in cases) {
      testWidgets('screen: ${row['name']}', (tester) async {
        final expected = _obj(row['expected']);
        final theme = RenderTheme.fallback();
        await pumpDocument(
          tester,
          _documentOf(row, spans: row['spans']),
          theme: theme,
          data: _obj(row['data']),
          locale: row['formattingLocale'] as String?,
          now: DateTime.parse(row['now']! as String),
        );
        expect(tester.takeException(), isNull);
        final widget = tester.widget<Text>(find.byType(Text));
        final shown = collapseShownWhitespace(expected['text']! as String);
        if (widget.textSpan == null) {
          // No effective style: a plain Text, as before 9.6.0.
          expect(widget.data, shown);
          expect((expected['runs']! as List<Object?>).cast<_Json>().every((run) => run['span'] == null), isTrue);
          return;
        }
        expect(widget.textSpan!.toPlainText(), shown);
        final base = widget.style!;
        final children = (widget.textSpan! as TextSpan).children!.cast<TextSpan>();
        final runs = collapseShownRuns<_Json>(
          (expected['runs']! as List<Object?>).cast<_Json>(),
          (run) => run['text']! as String,
          (run, text) => {...run, 'text': text},
        );
        expect(children.map((child) => child.text), runs.map((run) => run['text']), reason: 'runs on screen');
        final spans = readTextSpans(row['spans']);
        for (var index = 0; index < runs.length; index += 1) {
          final span = runs[index]['span'] as String?;
          final part = AmountPart.parse(runs[index]['part']);
          final style = children[index].style;
          if (span == null) {
            expect(style, isNull, reason: 'run ${index + 1} has the style of the text');
            continue;
          }
          // The style of the run: the part laid over its place, over the text.
          final place = spans[span]!;
          final own = part == null ? place : place.overlaid(place.parts[part]!);
          final color = own.color == null ? null : theme.resolveColor(own.color!);
          final font = own.typography == null ? null : theme.resolveTypography(own.typography!);
          expect(style!.color, color ?? base.color, reason: 'colour of run ${index + 1}');
          expect(style.fontSize, (font ?? base).fontSize, reason: 'size of run ${index + 1}');
        }
      });
    }
  });

  group('amountPartStruts: the line pitch with a declared part', () {
    final struts = _rows(_richText, 'amountPartStruts');
    test('five rows', () => expect(struts, hasLength(5)));
    for (final row in struts) {
      test(row['name']! as String, () {
        LineMetric metric(Object? raw) {
          final map = _obj(raw);
          return (fontSize: (map['fontSize']! as num).toDouble(), lineHeight: (map['lineHeight']! as num).toDouble());
        }

        final result = richTextStrut(metric(row['base']), {
          for (final entry in _obj(row['spans']).entries) entry.key: metric(entry.value),
        });
        final expected = _obj(row['expected']);
        expect(result.span, expected['span']);
        expect(result.lineBlock, closeTo((expected['lineBlock']! as num).toDouble(), 1e-9));
      });
    }

    testWidgets('a declared part is the strut of a real paragraph, whether or not the amount shows it', (tester) async {
      // A whole amount has no fraction, yet the fraction's tall style sets the pitch of the line.
      final row = {
        'value': {
          'kind': 'template',
          'template': '{limit}',
          'values': {
            'limit': {'kind': 'binding', 'path': 'offer.price', 'fallback': '—', 'format': 'currency', 'currency': 'UAH'},
          },
        },
        'sourceLocale': null,
        'translationLocale': null,
        'translations': <String, Object?>{},
      };
      await pumpDocument(
        tester,
        _documentOf(row, spans: {
          'limit': {
            'parts': {
              'fraction': {'typography': 'displayL'},
            },
          },
        }),
        data: const {'offer.price': 500},
        locale: 'en',
      );
      final strut = tester.widget<Text>(find.byType(Text)).strutStyle!;
      final theme = RenderTheme.fallback();
      final display = theme.resolveTypography(TypographyRef.tryParse('displayL')!)!;
      expect(strut.fontSize, display.fontSize, reason: 'the declared fraction counts');
    });
  });

  group('x-money: the mirror against the artifact', () {
    final block = _obj(_schema['x-money']);

    test('the currency signs, the number signs, the gap and the isolation marks', () {
      expect(_obj(block['symbols']), kMoneySymbols);
      final signs = _obj(block['signs']);
      expect(signs['negative'], kMoneyMinus);
      expect(signs['positive'], kMoneyPlus);
      expect(_obj(block['gap'])['after'], kMoneyGap);
      final isolation = _obj(block['isolation']);
      expect(isolation['open'], kMoneyIsolateOpen);
      expect(isolation['close'], kMoneyIsolateClose);
    });

    test('the words of the three fields and the formats that read them', () {
      final fields = _obj(block['fields']);
      expect(_obj(fields['currencyDisplay'])['words'], ['symbol']);
      expect(_obj(fields['currencyPosition'])['words'], ['before']);
      expect(_obj(fields['sign'])['words'], ['always']);
      expect(_obj(fields['currencyDisplay'])['formats'], ['currency']);
      expect(_obj(fields['currencyPosition'])['formats'], ['currency']);
      expect(_obj(fields['sign'])['formats'], ['number', 'currency']);
      expect(_obj(block['parts'])['names'], [for (final part in AmountPart.values) part.wire]);
    });

    test('the composed form of a binding with no readable field is the old one', () {
      final plain = BoundString.tryParse({'kind': 'binding', 'path': 'a', 'format': 'number', 'currencyDisplay': 'symbol'});
      expect(plain!.look.composed, isFalse, reason: '`currencyDisplay` is read by `currency` only');
      final unknown = BoundString.tryParse({'kind': 'binding', 'path': 'a', 'format': 'currency', 'currency': 'USD', 'sign': 'exceptZero'});
      expect(unknown!.look.composed, isFalse, reason: 'a word of a newer minor is no field');
      final daysUntil = BoundString.tryParse({'kind': 'binding', 'path': 'a', 'format': 'daysUntil', 'sign': 'always'});
      expect(daysUntil!.look.composed, isFalse);
    });
  });
}
