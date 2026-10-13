/// The device locale finds the document language (schema 9.1.0).
///
/// Three layers of checks, none replaces the others:
///  1. TABLE: 38 rows of `locale-cases.json`, shared by all readers;
///     every row goes through the mirror, and the direction is checked against `Bidi`;
///  2. POLICY mirror: seven artifact rows against the constants in code;
///  3. BEHAVIOUR on screen: text, direction and date in one document, because
///     a mirror that matches the table but disagrees with the screen is worse
///     than no mirror.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/locale_resolve.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/direction.dart';

import 'support/fixtures.dart';

final String _wallClock = localIso(DateTime(2026, 10, 31, 21, 59, 59));

UiDocument _doc({
  required List<String> locales,
  String source = 'en',
  Map<String, Map<String, String>>? strings,
}) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'loc',
  'name': 'Локаль',
  'initialScreenId': 'inline',
  'screens': [
    screenEntry('inline', [
      textNode('Hello', id: 'greeting'),
      textNode(
        '',
        id: 'ends',
        extra: {
          'content': {'kind': 'binding', 'path': 'offer.endsAt', 'fallback': '—', 'format': 'date'},
        },
      ),
    ]),
  ],
  'localization': {
    'defaultLocale': source,
    'locales': locales,
    'strings': strings ??
        {
          for (final locale in locales)
            if (locale != source) locale: {'inline/greeting/content': 'text-$locale'},
        },
  },
});

TextDirection _directionAt(WidgetTester tester, String text) =>
    Directionality.of(tester.element(find.text(text).first));

/// DIVERGENCE FROM THE PLATFORM, named explicitly.
///
/// The table says CLDR answers for `directionLocale`; on the web that is
/// `Intl.Locale('ks-IN').textInfo` (with likely subtags: Kashmiri is written
/// in Arabic script, RTL). `Bidi.isRtlLanguage` from `intl` is NOT CLDR but its own short
/// list of languages and scripts, and bare `ks` is not in it. Our answer here is `ltr`;
/// the row is not weakened but pinned as a known divergence, so that it does not
/// change silently in either direction.
const Map<String, TextDirection> _platformDirection = {
  'direction is asked for the canonical spelling of the document key: ks_IN': TextDirection.ltr,
};

void main() {
  final cases =
      (jsonDecode(File('assets/contract/fixtures/locale/locale-cases.json').readAsStringSync())
              as Map<String, Object?>)['cases']!
          as List<Object?>;

  group('table of cases locale-cases.json (shared by all readers)', () {
    test('the table is not empty and has 38 rows', () {
      expect(cases, hasLength(38));
    });

    for (final raw in cases) {
      final row = raw! as Map<String, Object?>;
      test(row['name']! as String, () {
        final result = resolveLocale(
          row['requested'] as String?,
          (row['available']! as List<Object?>).cast<String>(),
          row['source'] as String?,
        );

        expect(result.translation, row['translation'], reason: 'translation');
        expect(result.formatting, row['formatting'], reason: 'formatting');
        expect(result.directionLocale, row['directionLocale'], reason: 'directionLocale');
        expect(result.matched, row['matched'], reason: 'matched');
        // We ask the PLATFORM (`Bidi`) for the direction instead of guessing: the table says
        // CLDR must answer for this tag.
        expect(
          directionOfLocale(result.directionLocale),
          _platformDirection[row['name']] ??
              (row['direction'] == 'rtl' ? TextDirection.rtl : TextDirection.ltr),
          reason: 'direction',
        );
      });
    }
  });

  group('locale policy: mirror against the artifact', () {
    final schema =
        jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
    final compatibility = schema['x-compatibility']! as Map<String, Object?>;
    final policy = compatibility['policy']! as Map<String, Object?>;

    test('seven rows match the artifact', () {
      for (final entry in kLocalePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      expect(
        policy.keys.where((key) => key.startsWith('locale') || key == 'unmatchedLocale' || key == 'directionFollows' || key == 'formattingLocale').toSet(),
        kLocalePolicy.keys.toSet(),
        reason: 'the artifact has a locale row that the renderer does not mirror',
      );
    });

    test('the localeLookup feature is in the catalog with version 9.1.0', () {
      // The feature appeared in 9.1.0 and does not change; the reader version
      // exceeds it (now 9.2.0), so we check `supportsFeature`, not the number.
      expect(kFeatureCatalog['localeLookup'], '9.1.0');
      expect(supportsFeature('localeLookup'), isTrue);
      expect(supportsFeature('localeLookup', readerVersion: '9.0.0'), isFalse);
    });
  });

  group('normalization and chain', () {
    test('normalization: underscores, case, non-tags', () {
      expect(normalizeLocaleTag('ar_EG'), 'ar-EG');
      expect(normalizeLocaleTag('AR-eg'), 'ar-EG');
      expect(normalizeLocaleTag('zh-hant-tw'), 'zh-Hant-TW');
      for (final bad in [null, '', '  ', 'ar--EG', 'x-ar', 'не-мова', 'a']) {
        expect(normalizeLocaleTag(bad), isNull, reason: '$bad');
      }
    });

    test('the chain drops parts, a single letter does not stay last', () {
      expect(localeLookupChain('zh-Hant-TW'), ['zh-Hant-TW', 'zh-Hant', 'zh']);
      expect(localeLookupChain('en-US-u-ca-gregory'), [
        'en-US-u-ca-gregory',
        'en-US-u-ca',
        'en-US',
        'en',
      ]);
    });
  });

  group('DocumentLocalization: one answer', () {
    test('shownLocale returns the document key, localeFor returns the requested tag', () {
      final table = _doc(locales: ['en', 'ar']).localization!;

      expect(table.shownLocale('ar-EG'), 'ar');
      expect(table.shownLocale('ar_EG'), 'ar');
      expect(table.shownLocale('AR-eg'), 'ar');
      expect(table.localeFor([const Locale('ar', 'EG')]), 'ar-EG');
      expect(table.resolve('ar-EG').translation, 'ar');
    });

    test('we do not guess in reverse: ar does not find ar-EG', () {
      final table = _doc(locales: ['en', 'ar-EG']).localization!;

      expect(table.shownLocale('ar'), 'en');
      expect(table.shownLocale('ar-EG'), 'ar-EG');
      expect(table.shownLocale('ar-SA'), 'en');
      expect(table.localeFor([const Locale('ar')]), 'en');
    });

    test('the document key is taken AS WRITTEN, and the table follows it', () {
      final table = _doc(locales: ['en', 'AR-eg'], strings: {
        'AR-eg': {'inline/greeting/content': 'x'},
      }).localization!;

      expect(table.shownLocale('ar-EG'), 'AR-eg');
      expect(table.stringsFor('ar_EG')['inline/greeting/content'], 'x');
    });

    test('the first device match wins, not the first device language', () {
      final table = _doc(locales: ['en', 'fr']).localization!;

      expect(table.localeFor([const Locale('he', 'IL'), const Locale('fr', 'CA')]), 'fr-CA');
    });
  });

  group('clarifications before release', () {
    test('a language in locales with no row in strings is not a document language', () {
      // A document `locales: [en, ar]` with empty `strings`: "Arabic" exists only in
      // the list. There is nothing to show for it, so direction and format stay with the source language.
      final table = _doc(locales: ['en', 'ar'], strings: {}).localization!;

      expect(table.availableLocales, ['en']);
      final shown = table.resolve('ar-EG');
      expect(shown.translation, 'en');
      expect(shown.matched, isFalse);
      expect(directionOfLocale(shown.directionLocale), TextDirection.ltr);
      expect(shown.formatting, 'en');
    });

    test('case twin: the answer is the spelling under which translations EXIST', () {
      final table = _doc(
        locales: ['en', 'ar-EG', 'ar-eg'],
        strings: {
          'ar-eg': {'inline/greeting/content': 'x'},
        },
      ).localization!;

      expect(table.shownLocale('ar-EG'), 'ar-eg');
      expect(table.stringsFor('ar-EG')['inline/greeting/content'], 'x');
    });

    test('formatting is the longest prefix of the tag with a valid structure', () {
      expect(wellFormedLocaleTag(normalizeLocaleTag('ja_JP_JP')), 'ja-JP');
      expect(wellFormedLocaleTag(normalizeLocaleTag('ar-EG-u')), 'ar-EG');
      expect(wellFormedLocaleTag(normalizeLocaleTag('ar-EG-EG')), 'ar-EG');
      expect(wellFormedLocaleTag(null), isNull);
      final shown = resolveLocale('ja_JP_JP', ['en', 'ja'], 'en');
      expect(shown.formatting, 'ja-JP');
      expect(shown.translation, 'ja');
    });

    test('a tag longer than 100 chars is not a tag: source language, no long chain', () {
      final monster = List.filled(60, 'a-b').join('-');
      expect(monster.length, greaterThan(kMaxLocaleTagLength));
      expect(normalizeLocaleTag(monster), isNull);
      expect(localeLookupChain(monster), isEmpty);
      final shown = resolveLocale(monster, ['en', 'ar'], 'en');
      expect(shown.translation, 'en');
      expect(shown.matched, isFalse);
      // Exactly at the limit it is still a tag: `ar` + 11 parts of eight chars = 100 chars.
      final edge = 'ar${'-abcdefgh' * 11}'.substring(0, kMaxLocaleTagLength);
      expect(edge.length, kMaxLocaleTagLength);
      expect(normalizeLocaleTag(edge), isNotNull);
    });

    test('document key ks_IN: translation as written, directionLocale canonical', () {
      final shown = resolveLocale('ks-IN', ['en', 'ks_IN'], 'en');
      expect(shown.translation, 'ks_IN');
      expect(shown.directionLocale, 'ks-IN');
    });

    testWidgets('screen: ja_JP_JP does not set a date format: Japanese text, date in Japanese', (tester) async {
      final data = {'offer.endsAt': _wallClock};
      final expected = formatBoundValue(_wallClock, BindingFormat.date, locale: 'ja-JP')!;
      await pumpDocument(tester, _doc(locales: ['en', 'ja']), data: data, locale: 'ja_JP_JP');

      expect(find.text('text-ja'), findsOneWidget);
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('screen: locales [en, ar] without Arabic rows gives an English LTR screen', (tester) async {
      await pumpDocument(
        tester,
        _doc(locales: ['en', 'ar'], strings: {}),
        data: {'offer.endsAt': _wallClock},
        locale: 'ar-EG',
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(_directionAt(tester, 'Hello'), TextDirection.ltr);
      expect(find.text(formatBoundValue(_wallClock, BindingFormat.date, locale: 'en')!), findsOneWidget);
    });
  });

  group('date format: intl data and the chain', () {
    test('ar_EG and ar-EG give one result', () {
      final a = formatBoundValue(_wallClock, BindingFormat.date, locale: 'ar-EG');
      final b = formatBoundValue(_wallClock, BindingFormat.date, locale: 'ar_EG');
      expect(a, isNotNull);
      expect(a, b);
    });

    test('intl has no full tag: parts are dropped by the same chain', () {
      expect(
        formatBoundValue(_wallClock, BindingFormat.date, locale: 'en-US-u-ca-gregory'),
        formatBoundValue(_wallClock, BindingFormat.date, locale: 'en-US'),
      );
      expect(
        formatBoundValue(_wallClock, BindingFormat.date, locale: 'uk-XX'),
        formatBoundValue(_wallClock, BindingFormat.date, locale: 'uk'),
      );
    });

    test('a language intl does not know at all gives the value as is, not the device language', () {
      expect(formatBoundValue(_wallClock, BindingFormat.date, locale: 'tlh'), isNull);
    });
  });

  group('on screen', () {
    final data = {'offer.endsAt': _wallClock};

    testWidgets('ar-EG and ar_EG on a document with ar: Arabic text, RTL, ar-EG date', (tester) async {
      final expected = formatBoundValue(_wallClock, BindingFormat.date, locale: 'ar-EG')!;

      for (final requested in ['ar-EG', 'ar_EG', 'AR-eg']) {
        await pumpDocument(tester, _doc(locales: ['en', 'ar']), data: data, locale: requested);

        expect(find.text('text-ar'), findsOneWidget, reason: requested);
        expect(find.text('Hello'), findsNothing, reason: requested);
        expect(_directionAt(tester, 'text-ar'), TextDirection.rtl, reason: requested);
        expect(find.text(expected), findsOneWidget, reason: requested);
      }
    });

    testWidgets('he-IL without he in the document: source language, LTR, source-language date', (tester) async {
      await pumpDocument(tester, _doc(locales: ['en', 'ar']), data: data, locale: 'he-IL');

      expect(find.text('Hello'), findsOneWidget);
      expect(_directionAt(tester, 'Hello'), TextDirection.ltr);
      expect(
        find.text(formatBoundValue(_wallClock, BindingFormat.date, locale: 'en')!),
        findsOneWidget,
      );
    });

    testWidgets('en-GB with source en: source text, British date format', (tester) async {
      await pumpDocument(tester, _doc(locales: ['en', 'ar']), data: data, locale: 'en-GB');

      expect(find.text('Hello'), findsOneWidget);
      expect(_directionAt(tester, 'Hello'), TextDirection.ltr);
      expect(find.text('31 Oct 2026'), findsOneWidget);
    });

    testWidgets('ar with only ar-EG present: source language, LTR', (tester) async {
      await pumpDocument(tester, _doc(locales: ['en', 'ar-EG']), data: data, locale: 'ar');

      expect(find.text('Hello'), findsOneWidget);
      expect(_directionAt(tester, 'Hello'), TextDirection.ltr);
    });

    testWidgets('locale: null on a document whose source is Arabic: direction of the source language', (tester) async {
      await pumpDocument(
        tester,
        _doc(locales: ['ar', 'en'], source: 'ar', strings: {
          'en': {'inline/greeting/content': 'text-en'},
        }),
        data: data,
      );

      expect(_directionAt(tester, 'Hello'), TextDirection.rtl);
    });

    testWidgets('a document without localization: direction and format follow the host word, ar_EG too', (tester) async {
      await pumpDocument(
        tester,
        docWith([textNode('Привіт', id: 'hello')]),
        locale: 'ar_EG',
      );

      expect(_directionAt(tester, 'Привіт'), TextDirection.rtl);
    });
  });
}
