/// Shared table of template-text, number and plural cases (schema 9.4.0)
/// run ENTIRELY through the renderer.
///
/// There is ONE table for all readers (`fixtures/template/template-cases.json`),
/// and the test reads the artifact itself: a row added in the builder starts
/// being checked here after a `cp`, with no edits to this file.
///
/// TWO PASSES, and the second is not a repeat of the first:
///  1. RULE - a document string is parsed by `BindableString.parse` and turned
///     into text via `resolve`, with no widget at all;
///  2. SCREEN - a document is BUILT from the row (a `Text` node, a localization
///     section with the place keys) and drawn by `renderDocument`. This checks
///     what the first pass cannot see: that the template and plural-form translation
///     keys are composed from the node place exactly as the builder writes them; that
///     the source language reaches the plural; that the host clock reaches the text.
///
/// EXCEPTIONS are listed below by name, with a reason. No row is skipped silently:
/// the test counts the table rows and fails if an exception names a row that
/// no longer exists.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/locale_resolve.dart';
import 'package:hotlayout_flutter/src/model/text_template.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/model/shown_text.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Rows marked `mayDiffer` where Dart `intl` gives DIFFERENT CHARACTERS than the
/// table records: row name -> what this reader shows and why.
///
/// Marker rule: the answer depends on the platform CLDR data; the rule is the
/// same, the characters are not promised. So a marked row MAY stand here, and an
/// unmarked one never may: the test below guards that. An empty map means that
/// all `mayDiffer` rows matched the table character for character on this `intl`
/// version - and then they are compared as strictly as the rest.
const Map<String, ({String shown, String why})> _platformDiffers = {
  // 9.19.0, the parts of a date: the rows allow a plain space or U+202F before the year mark; Dart `intl` writes the latter.
  'WITHOUT the field nothing changed: year, short month, day (uk)': (
    shown: '15 жовт. 2026\u202fр.',
    why: 'U+202F before the year mark (platform CLDR data); which parts are shown is the point of the row',
  ),
  'dayMonthYear: day, month in full and year (uk)': (
    shown: '15 жовтня 2026\u202fр.',
    why: 'U+202F before the year mark (platform CLDR data); which parts are shown is the point of the row',
  ),
  'the year stands where the language puts it: Kazakh': (
    shown: '2026\u202fж. 15 қазан',
    why: 'U+202F before the year mark (platform CLDR data); the year stands first, the point of the row',
  ),
  // The row itself says: older ICU data writes U+202F before PM. Dart `intl` 0.20 (CLDR 4x) does too.
  'CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: en': (
    shown: 'Oct 31, 2026, 2:05\u202fPM',
    why: 'U+202F before PM (platform CLDR data); the comma between date and time is the point of the row',
  ),
  // The row allows both a plain space and U+202F between the year and the Cyrillic year abbreviation; Dart `intl` writes the latter.
  'CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: uk': (
    shown: '31 жовт. 2026\u202fр., 14:05',
    why: 'U+202F between the year and the year abbreviation (platform CLDR data); the comma between date and time is the point of the row',
  ),
  'CLARIFIED-3 dateTime joins date and time with the CLDR pattern of the language, not a space: ru': (
    shown: '31 окт. 2026\u202fг., 14:05',
    why: 'U+202F between the year and the year abbreviation (platform CLDR data); the comma between date and time is the point of the row',
  ),
};

/// Row fields that this pass does NOT substitute, by name and with a reason.
///
/// `timeZone` (rows "the time zone does not matter"): the process time zone does
/// not change in a Dart test, and the `daysUntil` rule does not read it - it
/// counts the difference in epoch milliseconds. The rows run like all others, in
/// the machine zone; that the zone does not enter the answer is held by a separate
/// test in `template_text_test.dart` (an instant with different offsets gives the same number).
const Set<String> _ignoredFields = {'timeZone'};

/// The offsets of the zones the date rows name at the instant they use (October 2026).
const Map<String, Duration> _zoneOffsets = {
  'Pacific/Kiritimati': Duration(hours: 14),
  'Pacific/Pago_Pago': Duration(hours: -11),
};

/// Rows that the second pass draws through `renderScreen`, not `renderDocument`,
/// by name and with a reason.
///
/// The row names the ANSWERS of the language rule (translation `en`, format `tlh`), while
/// `renderDocument` computes them itself from the host request - and for a document with
/// source `en` no request gives "text `en`, format `tlh`": the format takes the requested
/// locale only when a translation is found. A host using `renderScreen` names the format
/// locale itself, so the row passes through the screen exactly there.
const Set<String> _formattingOnlyThroughRenderScreen = {
  'CLARIFIED no locale data: number is shown as it is',
  'CLARIFIED no locale data: currency is shown as it is',
  'CLARIFIED no locale data: daysUntil is the counted days in plain digits, no separators',
  // The same for dates (9.5.0 clarification): source `en` does not give "text `en`, format
  // `th`", because the format takes the requested locale only when a translation is found.
  'CLARIFIED-2 calendar: Thai shows the Gregorian year 2026, not the Buddhist 2569',
  'CLARIFIED-2 calendar: Persian shows the Gregorian year 2026 (in the digits of the language), not the Persian 1405',
  'CLARIFIED-2 no locale data: date is shown as it is (dv)',
  'CLARIFIED-2 no locale data: date is shown as it is (la)',
  'CLARIFIED-2 no locale data: dateTime is shown as it is (dv)',
};

const String _place = 'cases/row/content';

/// "no locale data" rows name a language that exists in NO known CLDR/ICU release (`tlh`, `dv`, `la`),
/// while `mayDiffer` says: a platform that has the data formats it. The `intl` package version may add
/// them, so the test asks what the reader asks (`localeExists` along the lookup chain): if data exists,
/// the row is checked only for the reader not crashing and giving non-empty text; if not, strictly like
/// the rest. No language is assumed "known to have no data" in advance.
bool _platformHasData(Map<String, Object?> row) {
  if (!(row['name']! as String).contains('no locale data')) return false;
  initializeDateFormatting(); // as the reader does: date tables are loaded synchronously
  final tag = normalizeLocaleTag(row['formattingLocale'] as String?);
  if (tag == null) return false;
  return localeLookupChain(tag).any((candidate) {
    final underscored = candidate.replaceAll('-', '_');
    return DateFormat.localeExists(underscored) || NumberFormat.localeExists(underscored);
  });
}

void main() {
  final table =
      jsonDecode(File('assets/contract/fixtures/template/template-cases.json').readAsStringSync())
          as Map<String, Object?>;
  final rows = (table['cases']! as List<Object?>).cast<Map<String, Object?>>();
  final shownRows = (table['shownTemplateCases']! as List<Object?>).cast<Map<String, Object?>>();
  // 9.19.0: the parts of a date (`dateParts` beside `format: 'date'`).
  final dateRows = (table['datePartsCases']! as List<Object?>).cast<Map<String, Object?>>();
  final shownTextRows = (table['shownTextCases']! as List<Object?>).cast<Map<String, Object?>>();

  test('the table is read in full, and every field of it is known to this test', () {
    // Guard of the test itself: a field it does not know is a row condition it
    // would silently not fulfil.
    expect(rows, hasLength(179));
    expect(dateRows, hasLength(37));
    const known = {
      'name',
      'value',
      'sourceLocale',
      'translationLocale',
      'formattingLocale',
      'translations',
      'data',
      'now',
      'expected',
      'mayDiffer',
      'readerOnly',
    };
    for (final row in [...rows, ...dateRows, ...shownRows]) {
      expect(
        row.keys.toSet().difference({...known, ..._ignoredFields, if (shownRows.contains(row)) 'shown'}),
        isEmpty,
        reason: '${row['name']}: unknown row field',
      );
    }
    expect(
      [...rows, ...dateRows].map((row) => row['name']).toSet(),
      hasLength(rows.length + dateRows.length),
      reason: 'row names are unique',
    );
  });

  test('table: exactly the groups this test knows', () {
    expect(table.keys.toSet(), {
      'description', 'now', 'cases', 'shownTextCases', 'shownTemplateCases',
      // 9.19.0: money as money -- run by `money_cases_test.dart`.
      'moneyNote', 'moneyCases',
      // 9.19.0: the parts of a date.
      'datePartsNote', 'datePartsCases',
    });
  });

  test('an exception is named only for a row marked mayDiffer that EXISTS in the table', () {
    final byName = {for (final row in [...rows, ...dateRows]) row['name']! as String: row};
    expect(byName.keys, containsAll(_formattingOnlyThroughRenderScreen));
    for (final name in _platformDiffers.keys) {
      expect(byName, contains(name), reason: 'exception for a row that is not in the table');
      expect(byName[name]!['mayDiffer'], isA<String>(), reason: '$name: the characters of this row are promised');
    }
  });

  /// Row data. `CLARIFIED-3 dateTime...` rows name the `UTC` zone, while the reader takes the
  /// DEVICE zone (`toLocal()`), which does not change in a Dart test. So the instant in the data is shifted
  /// so that the WALL time in the machine zone equals the one named in the row (14:05): the same rule is
  /// checked - "device zone" and joining by the language pattern - not the machine zone matching UTC.
  Map<String, Object?> dataOf(Map<String, Object?> row) {
    final data = Map<String, Object?>.of(row['data']! as Map<String, Object?>);
    // A date row names a time zone: the reader takes the DEVICE zone, which does not change in a Dart test, so the
    // instant is moved until the wall clock of the machine zone reads what that zone reads at the instant of the row.
    final zone = _zoneOffsets[row['timeZone']];
    if (zone != null) {
      for (final entry in data.entries.toList()) {
        final at = DateTime.parse(entry.value! as String).add(zone);
        data[entry.key] = DateTime(at.year, at.month, at.day, at.hour, at.minute, at.second).toUtc().toIso8601String();
      }
    }
    if ((row['name']! as String).startsWith('CLARIFIED-3 dateTime') && row['timeZone'] == 'UTC') {
      for (final entry in data.entries.toList()) {
        final at = DateTime.parse(entry.value! as String); // UTC
        data[entry.key] = DateTime(at.year, at.month, at.day, at.hour, at.minute, at.second).toUtc().toIso8601String();
      }
    }
    return data;
  }

  String expectedOf(Map<String, Object?> row) =>
      _platformDiffers[row['name']]?.shown ?? row['expected']! as String;

  group('rule: document string -> text', () {
    // `shownTemplateCases` are the same rows as `cases`, plus `shown`: `expected` stands BEFORE the whitespace
    // rule, so document string -> text is checked the same way, and `shown` - below.
    for (final row in [...rows, ...dateRows, ...shownRows]) {
      test(row['name']! as String, () {
        final value = BindableString.parse(row['value'], key: _place);
        final translation = row['translationLocale'] as String?;
        final source = row['sourceLocale'] as String?;
        final translations = (row['translations']! as Map<String, Object?>).cast<String, String>();

        // The translation table exactly as `UiDocument.stringsFor` gives it:
        // empty for the source language, but it names the source language.
        final strings = LocalizedStrings(
          locale: translation == source ? null : translation,
          table: translation == source
              ? const {}
              : {
                  for (final entry in translations.entries)
                    entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value,
                },
          sourceLocale: source,
        );

        final shown = value.resolve(
          ScreenData(dataOf(row)),
          strings,
          row['formattingLocale'] as String?,
          DateTime.parse(row['now']! as String),
        );
        if (_platformHasData(row)) {
          expect(shown, isNotEmpty, reason: 'the platform has the language data: the row is formatted (mayDiffer)');
          return;
        }
        expect(shown, expectedOf(row));
      });
    }
  });

  group('screen: the same row as a Text node in a document', () {
    for (final row in [...rows, ...dateRows, ...shownRows]) {
      testWidgets(row['name']! as String, (tester) async {
        final translation = row['translationLocale'] as String?;
        final source = row['sourceLocale'] as String?;
        final translations = (row['translations']! as Map<String, Object?>).cast<String, String>();

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
                    'props': {'content': row['value'], 'align': 'start', 'overflow': 'clip'},
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
                    // A language with no string in the document language does not count
                    // as present (rule 9.1.0), while the table row says "translation in this
                    // language is shown, this place just is not in it". A row of
                    // another place makes the language present and translates nothing.
                    'cases/elsewhere/content': '·',
                    for (final entry in translations.entries)
                      entry.key.isEmpty ? _place : '$_place.${entry.key}': entry.value,
                  },
              },
            },
        });

        // We ask for the row FORMAT locale: `ar-EG` finds the `ar` translation and
        // stays the number locale - exactly the answer recorded in the row.
        final requested = row['formattingLocale'] as String?;
        if (_formattingOnlyThroughRenderScreen.contains(row['name'])) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: renderScreen(
                  doc.initialScreen,
                  theme: RenderTheme.fallback(),
                  data: dataOf(row),
                  strings: doc.stringsFor(translation),
                  locale: requested,
                  now: DateTime.parse(row['now']! as String),
                ),
              ),
            ),
          );
        } else {
          if (source != null) {
            final answer = doc.localeResolution(requested);
            expect(answer.translation, translation, reason: 'translation language named by the row');
            expect(answer.formatting, requested, reason: 'format locale named by the row');
          }
          await pumpDocument(
            tester,
            doc,
            data: dataOf(row),
            locale: requested,
            now: DateTime.parse(row['now']! as String),
          );
        }

        if (_platformHasData(row)) {
          expect(tester.takeException(), isNull);
          return;
        }
        expect(
          tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList(),
          // `cases` rows do not know the whitespace rule (their `expected` stands BEFORE it), so
          // on screen it is `expected` after `shownTextOf`; `shownTemplateCases` rows name
          // the shown text themselves (`shown`), and it must match the rule.
          [if (row.containsKey('shown')) row['shown']! as String else collapseShownWhitespace(expectedOf(row))],
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('whitespace in shown text (9.18.0): `shownTextCases`', () {
    test('26 rows, names are unique', () {
      expect(shownTextRows, hasLength(26));
      expect(shownTextRows.map((row) => row['name']).toSet(), hasLength(26));
    });
    for (final row in shownTextRows) {
      test(row['name']! as String, () {
        final text = row['text']! as String;
        expect(collapseShownWhitespace(text), row['expected']);
        // Idempotence: a shown string does not change a second time.
        expect(collapseShownWhitespace(collapseShownWhitespace(text)), collapseShownWhitespace(text));
      });
    }
  });

  group('whitespace after template and translation: `shownTemplateCases`', () {
    test('nine rows; names do not overlap with `cases`', () {
      expect(shownRows, hasLength(9));
      final names = {...rows, ...shownRows}.map((row) => row['name']).toSet();
      expect(names, hasLength(rows.length + shownRows.length));
    });
    for (final row in shownRows) {
      test(row['name']! as String, () {
        expect(collapseShownWhitespace(row['expected']! as String), row['shown'], reason: 'the rule over the row before it');
      });
    }
  });

  group('9.4.0 mirror against the artifact', () {
    final schema =
        jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
    final compatibility = schema['x-compatibility']! as Map<String, Object?>;
    final policy = compatibility['policy']! as Map<String, Object?>;
    final template = schema['x-template']! as Map<String, Object?>;

    test('nineteen policy rows (13 + 6 clarifications) match the artifact and run consecutively from unknownStringKind', () {
      expect(kTemplatePolicy, hasLength(19));
      for (final entry in kTemplatePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // Everything the artifact appended from `unknownStringKind` on is the rows of this minor;
      // a new row after them the renderer must notice.
      final keys = policy.keys.toList();
      final start = keys.indexOf('unknownStringKind');
      // After them come the 9.5.0 rows - guarded by `schema_version_test.dart`.
      expect(keys.sublist(start, start + kTemplatePolicy.length), kTemplatePolicy.keys.toList());
    });

    test('five policy rows from the 9.5.0 clarifications match the artifact and stand before the 9.6.0 rows', () {
      expect(kTemplateClarifiedPolicy, hasLength(5));
      for (final entry in kTemplateClarifiedPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // After them come seven 9.6.0 rows (guarded by `rich_text_cases_test.dart`).
      expect(
        policy.keys.toList().sublist(policy.length - 12 - kActionPolicy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - 7 - kActionPolicy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length)),
        kTemplateClarifiedPolicy.keys.toList(),
      );
    });

    test('reader version and capabilities', () {
      // A claim about a NUMBER ("the reader is 9.4.0") expired at minor 9.5.0; the test
      // question is capabilities, and it stands: the reader goes with the artifact and is not
      // older than the minor in which they appeared.
      expect(schema['x-schemaVersion'], kSupportedSchemaVersion);
      expect(
        SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 4, 0)),
        greaterThanOrEqualTo(0),
      );
      final features = compatibility['features']! as Map<String, Object?>;
      for (final feature in ['textTemplate', 'numberFormats']) {
        expect(features[feature], '9.4.0');
        expect(kFeatureCatalog[feature], '9.4.0');
        expect(supportsFeature(feature), isTrue);
        expect(supportsFeature(feature, readerVersion: '9.3.0'), isFalse);
      }
    });

    test('x-template parameters are the ones the renderer computes with', () {
      expect(template['valueNamePattern'], kTemplateValueNamePattern);
      expect(template['pluralCategories'], kPluralCategories);
      expect((template['pluralNumber']! as Map)['maximumFractionDigits'], kPluralNumberFractionDigits);
      expect((template['pluralNumber']! as Map)['absolute'], isTrue);
      // Clarification: three parameters the renderer computes with.
      expect(template['dateTimePattern'], kDateTimePattern);
      expect((template['number']! as Map)['maximumAbsoluteValue'], kNumberFormatMaxAbsolute);
      expect((template['pluralNumber']! as Map)['fallbackPattern'], BoundString.numericFallbackPattern);
      expect(template['translationKeys'], {
        'template': '<screenId>/<nodeId>/<field path>.template',
        'pluralForm': '<screenId>/<nodeId>/<field path>.values.<name>.forms.<category>',
        // 9.6.0: the template word (`kind: 'text'`).
        'word': '<screenId>/<nodeId>/<field path>.values.<name>.text',
      });
      // 9.5.0 clarification.
      expect(template['dateCalendar'], kDateCalendar);
      expect(template['dateCalendarCheck'], kDateCalendarCheck);
      expect(template['rounding'], kNumberRounding);
      expect(template['cases'], 'contract/fixtures/template/template-cases.json');
    });
  });
}
