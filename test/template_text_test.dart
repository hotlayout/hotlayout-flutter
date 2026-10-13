/// Template text, number formats and plurals (schema 9.4.0) - what the shared
/// case table (`template_cases_test.dart`) does not see.
///
/// The table checks the RULE on one row. Here:
///  * SCREEN - the `template-text-screens` fixture in three languages: a template in text,
///    in a bar subtitle, in row slots, on a badge and in a data-driven list
///    row; the no-data state; Arabic right to left;
///  * CLOCK - "now" is substitutable and reaches the text from the host;
///  * Dart TRAPS that the table has no row for (`two ?? few` in
///    `Intl.pluralLogic`, int64 saturation in `NumberFormat`, `toInt()` in the "as is"
///    record);
///  * ROBUSTNESS - a document from the network: any names and forms, thousands of places,
///    `of` pointing at itself, a number that is not a number. Parsing does not throw, substitution is linear.
library;

// The `intl` tables are read directly only here - to prove the assumption that the
// plural language lookup in `text_template.dart` relies on.
// ignore_for_file: implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/text_template.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:intl/number_symbols_data.dart' show numberFormatSymbols;
import 'package:intl/src/plural_rules.dart' as plural_rules;

import 'support/demo_data.dart';
import 'support/fixtures.dart';

final DateTime _now = DateTime.parse(kSampleNow);

Map<String, Object?> _binding(String path, {String fallback = '—', String? format, String? currency}) => {
  'kind': 'binding',
  'path': path,
  'fallback': fallback,
  'format': ?format,
  'currency': ?currency,
};

Map<String, Object?> _template(String template, Map<String, Object?> values) => {
  'kind': 'template',
  'template': template,
  'values': values,
};

Map<String, Object?> _plural(String of, Map<String, Object?> forms) => {
  'kind': 'plural',
  'of': of,
  'forms': forms,
};

Map<String, Object?> _text(Object? content, {String id = 'txt'}) => {
  'id': id,
  'type': 'Text',
  'props': {'content': content, 'align': 'start', 'overflow': 'clip'},
};

/// A document with one screen and, if needed, localization.
UiDocument _doc(List<Map<String, Object?>> children, {Map<String, Object?>? localization}) =>
    UiDocument.fromJson({
      'schemaVersion': UiDocument.supportedSchemaVersion,
      'documentId': 'inline',
      'name': 'inline',
      'initialScreenId': 's',
      'screens': [screenEntry('s', children)],
      'localization': ?localization,
    });

/// All labels on the screen, in tree order.
List<String?> _shown(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList();

String _resolve(
  Object? raw, {
  Map<String, Object?> data = const {},
  String? locale = 'en',
  String? source = 'en',
  DateTime? now,
}) => BindableString.parse(raw).resolve(
  ScreenData(data),
  LocalizedStrings(locale: null, table: const {}, sourceLocale: source),
  locale,
  now ?? _now,
);

void main() {
  group('template-text-screens fixture on samples', () {
    final doc = loadFixture('template-text-screens');

    Future<void> pump(WidgetTester tester, String? locale, {Map<String, Object?>? data}) async {
      // The screen is taller than the default test window; the height lets the row tap
      // land, not fit everything (the content scrolls anyway).
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpDocument(tester, doc, data: data ?? sampleScreenData, locale: locale, now: _now);
    }

    testWidgets('the 9.4.0 document reads, and no node is left without text', (tester) async {
      expect(doc.schemaVersion, '9.4.0');
      await pump(tester, 'en');
      expect(tester.takeException(), isNull);
      // An empty label on this screen would mean a template that failed to parse
      // (`unknownStringKind: 'render-empty'`) - exactly what a 9.3 reader would show.
      expect(_shown(tester), isNot(contains('')));
    });

    testWidgets('English: template in text, bar, row slots, badge and list row', (tester) async {
      await pump(tester, 'en');
      expect(_shown(tester), [
        'Your week',
        // Bar subtitle: value as is, a number with groups, a word after the number.
        'Level 3 · 1,250 points',
        '3 / 5 steps',
        // 52 days from the samples' "now" to `campaign.endsAt`.
        '52 days left',
        'Balance',
        // A separate binding with `format: 'number'` - the same rule as in the template.
        '1,250',
        // Badge: minus U+2212 and percent - literal template text.
        '−20%',
        'Double points this weekend',
        'Ends in 22 days',
        // Trailing row slot: amount, non-breaking space, code.
        '120 JOD',
        'Missions',
        // Data-driven list: one template, three records - each with its own number.
        'Spend 500 with your card', '3 of 5', '+100 points',
        'Set up a recurring payment', '1 of 1', '+50 points',
        'Invite a friend', '0 of 1', '+200 points',
      ]);
    });

    testWidgets('Ukrainian: the translation reorders values, the word agrees by the Ukrainian rule', (tester) async {
      await pump(tester, 'uk');
      expect(_shown(tester), [
        'Ваш тиждень',
        // 1250 is `many`; the group separator is a non-breaking space.
        'Рівень 3 · 1 250 балів',
        'Кроків: 3 з 5',
        // 52 is `few` ("дні"), not "днів" and not the English "days".
        'Лишилося 52 дні',
        'Баланс',
        '1 250',
        '−20%',
        'Double points this weekend',
        'Закінчиться через 22 дні',
        '120 JOD',
        'Місії',
        'Spend 500 with your card', '3 з 5', '+100 балів',
        'Set up a recurring payment', '1 з 1', '+50 балів',
        'Invite a friend', '0 з 1', '+200 балів',
      ]);
    });

    testWidgets('Arabic: right to left, six categories, digits left to the platform', (tester) async {
      await pump(tester, 'ar');
      expect(Directionality.of(tester.element(find.text('أسبوعك'))), TextDirection.rtl);
      expect(_shown(tester), [
        'أسبوعك',
        // 1250: n % 100 = 50 — `many`.
        'المستوى 3 · 1,250 نقطة',
        '3 من 5 خطوات',
        // 52 is `many` ("يومًا"), and so is 22.
        'باقي 52 يومًا',
        'الرصيد',
        '1,250',
        '−20%',
        'Double points this weekend',
        'ينتهي خلال 22 يومًا',
        // The amount composition is the same in a right-to-left language; the on-screen order
        // is set by the bidirectional algorithm, the string does not change.
        '120 JOD',
        'المهام',
        'Spend 500 with your card', '3 من 5', '+100 نقطة',
        'Set up a recurring payment', '1 من 1', '+50 نقطة',
        'Invite a friend', '0 من 1', '+200 نقطة',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ar-EG: the `ar` translation, with FORMAT numbers in Egyptian digits; a value without a format stays as is', (tester) async {
      await pump(tester, 'ar-EG');
      final shown = _shown(tester);
      // `user.level` has no format - "3"; `user.points` has - Arabic-Indic
      // digits and the Arabic group separator. The word follows the same number 1250.
      expect(shown, contains('المستوى 3 · ١٬٢٥٠ نقطة'));
      expect(shown, contains('باقي ٥٢ يومًا'));
      expect(shown, contains('١٢٠ JOD'));
      // Without a format - as in the data, whatever the locale.
      expect(shown, contains('3 من 5 خطوات'));
    });

    testWidgets('no data: the fallback text of EVERY value, the sentence stays, the word is `other`', (tester) async {
      await pump(tester, 'en', data: const {});
      expect(_shown(tester), [
        'Your week',
        'Level 1 · 0 points',
        '— / — steps',
        '— days left',
        'Balance',
        '0',
        '−0%',
        'Offer',
        'Ends in — days',
        '—',
        'Missions',
      ]);
    });

    testWidgets('no data in Ukrainian: the Ukrainian `other` ("дня"), not the English one', (tester) async {
      await pump(tester, 'uk', data: const {});
      // Revised by the 9.4.0 clarification: the fallback text "0"
      // looks like a number, so the word agrees with it - "0 балів" (`many`),
      // not "0 бала". "—" is not a number: there and further it is `other`.
      expect(_shown(tester), containsAll(['Кроків: — з —', 'Лишилося — дня', 'Рівень 1 · 0 балів']));
    });

    testWidgets('a row with an action leads to the offer screen: money, date and days in one template', (tester) async {
      await pump(tester, 'en');
      await tester.tap(find.text('Ends in 22 days'));
      await tester.pumpAndSettle();
      final shown = _shown(tester);
      expect(shown, contains('22 days left'));
      expect(shown, contains('Use code WEEKEND20 at checkout'));
      // The date is in the machine time zone (rule 8.20.0), so the day is not checked; the amount and
      // that `date` in the template is formatted, not left as an ISO string, are.
      final price = shown.singleWhere((text) => text!.startsWith('Only '))!;
      expect(price, startsWith('Only 120 JOD until '));
      expect(price, endsWith(', 2026'));
      expect(price, isNot(contains('T23:59')));
    });

    testWidgets('the same fixture through renderScreen: a host that drives the stack itself gets the same', (tester) async {
      // `renderScreen` does not know the document - only the translation table. The source
      // language for plurals travels in the table itself (`LocalizedStrings.sourceLocale`),
      // so the host has nothing to add.
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final (locale, expected) in [('en', '52 days left'), ('uk', 'Лишилося 52 дні')]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: renderScreen(
                doc.initialScreen,
                theme: RenderTheme.fallback(),
                data: sampleScreenData,
                strings: doc.stringsFor(locale),
                locale: locale,
                now: _now,
              ),
            ),
          ),
        );
        expect(_shown(tester), contains(expected));
      }
    });
  });

  group('9.4.0 showcase: points with group separators', () {
    testWidgets('six bindings got format: number, and the balance reads "1,250"', (tester) async {
      final doc = loadFixture('rewards-showcase-screens');
      // The showcase version number is not checked here: it grows with every minor
      // (9.5.0 gave it icons), and the test is about the points format.
      expect(doc.versionVerdict.canRender, isTrue);
      var formatted = 0;
      void count(Object? node) {
        if (node is Map) {
          if (node['kind'] == 'binding' && node['format'] == 'number') formatted++;
          node.values.forEach(count);
        } else if (node is List) {
          node.forEach(count);
        }
      }

      count(jsonFixture('rewards-showcase-screens'));
      // There were five (points and prices of the examples); in 9.5.0 the redeem-list
      // catalog prices got `format: 'number'` - the sixth.
      expect(formatted, 6);

      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpDocument(
        tester,
        doc,
        data: sampleScreenData,
        theme: fixtureTheme('rewards-showcase-screens'),
        now: _now,
      );
      expect(_shown(tester), contains('1,250'));
      expect(_shown(tester), isNot(contains('1250')));
      expect(tester.takeException(), isNull);
    });
  });

  group('reader clock (readerClock: injectable-read-at-render)', () {
    final days = _template('{days} {unit} left', {
      'days': _binding('campaign.endsAt', format: 'daysUntil'),
      'unit': _plural('days', {'one': 'day', 'other': 'days'}),
    });
    final doc = _doc(
      [_text(days)],
      localization: {
        'defaultLocale': 'en',
        'locales': ['en'],
        'strings': <String, Object?>{},
      },
    );
    const data = {'campaign.endsAt': '2026-10-14T09:00:00.000Z'};

    testWidgets('"now" comes from the host, and both the number and the word depend on it', (tester) async {
      await pumpDocument(tester, doc, data: data, now: DateTime.utc(2026, 10, 10, 9));
      expect(find.text('4 days left'), findsOneWidget);

      // The same document, the same data, another moment - another text. The host
      // re-rendered: the screen itself does not update with time.
      await pumpDocument(tester, doc, data: data, now: DateTime.utc(2026, 10, 13, 9, 0, 1));
      expect(find.text('1 day left'), findsOneWidget);

      await pumpDocument(tester, doc, data: data, now: DateTime.utc(2027));
      expect(find.text('0 days left'), findsOneWidget);
    });

    testWidgets('without a substitute - the device clock', (tester) async {
      // A moment 36 hours from the real "now": two days, whenever it runs.
      final soon = DateTime.now().toUtc().add(const Duration(hours: 36)).toIso8601String();
      await pumpDocument(tester, doc, data: {'campaign.endsAt': soon});
      expect(find.text('2 days left'), findsOneWidget);
    });

    test('the time zone is not part of the rule: one moment at different offsets is one number', () {
      // The table rows with `timeZone` run in the machine time zone; here the same
      // statement is made in a way that can be checked in Dart.
      final now = DateTime.parse('2026-10-10T09:00:00.000Z');
      for (final moment in [
        '2026-10-14T09:00:00.000Z',
        '2026-10-14T18:00:00.000+09:00',
        '2026-10-14T02:00:00.000-07:00',
        '2026-10-14T12:00:00.000+03:00',
      ]) {
        expect(numericBoundValue(moment, BindingFormat.daysUntil, now: now), 4, reason: moment);
        // And a "now" given in local time is the same moment.
        expect(numericBoundValue(moment, BindingFormat.daysUntil, now: now.toLocal()), 4, reason: moment);
      }
    });

    test('duration rounds up with millisecond precision, and never below zero', () {
      final now = DateTime.parse('2026-10-10T09:00:00.000Z');
      num? days(String moment) => numericBoundValue(moment, BindingFormat.daysUntil, now: now);
      expect(days('2026-10-11T09:00:00.000Z'), 1);
      expect(days('2026-10-11T09:00:00.001Z'), 2);
      expect(days('2026-10-10T09:00:00.001Z'), 1);
      expect(days('2026-10-10T09:00:00.000Z'), 0);
      expect(days('2026-10-10T08:59:59.999Z'), 0);
      expect(days('1970-01-01T00:00:00.000Z'), 0);
      expect(days('not a date'), isNull);
    });
  });

  group('plural: a CLDR category, not an Intl.pluralLogic "improvement"', () {
    test('TRAP absent from the table: category `two` without a form is `other`, not `few`', () {
      // `Intl.pluralLogic` with forms would return the `few` form for `two`
      // (`two ?? few ?? other`). The contract says `missingPluralForm: 'use-other'`.
      // In Arabic 2 is `two`.
      expect(pluralCategoryOf(2, 'ar'), 'two');
      expect(pluralFormFor(2, {'few': 'أيام', 'other': 'يوم'}, 'ar'), 'يوم');
      // And on the screen, through a template:
      expect(
        _resolve(
          _template('{n} {unit}', {
            'n': _binding('n'),
            'unit': _plural('n', {'few': 'few-form', 'other': 'other-form'}),
          }),
          data: {'n': 2},
          source: 'ar',
        ),
        '2 other-form',
      );
    });

    test('categories of the most common languages are what CLDR says', () {
      String row(String locale) =>
          [0, 1, 2, 3, 5, 11, 21, 22, 100, 1.5].map((n) => pluralCategoryOf(n, locale)).join(' ');
      expect(row('en'), 'other one other other other other other other other other');
      expect(row('uk'), 'many one few few many many one few many other');
      expect(row('pl'), 'many one few few many many many few many other');
      expect(row('ar'), 'zero one two few few many many many other other');
      expect(row('ja'), 'other other other other other other other other other other');
      // A regional key has its OWN rules: in Brazilian Portuguese 0 is `one`.
      expect(pluralCategoryOf(0, 'pt-BR'), 'one');
      expect(pluralCategoryOf(0, 'pt-PT'), 'other');
      // The tag spelling does not matter, as for the document language.
      expect(pluralCategoryOf(0, 'pt_br'), 'one');
    });

    test('a language intl does not know is NOT guessed: `other`, not the device language rules or the first letters', () {
      for (final locale in [null, '', 'xx', 'zz-ZZ', 'ckb', 'це не тег', 'en' * 60]) {
        for (final n in [0, 1, 2, 5]) {
          expect(pluralCategoryOf(n, locale), 'other', reason: '$locale / $n');
        }
      }
      // A region absent from the data falls back to the language - by the same chain as
      // the document language.
      expect(pluralCategoryOf(1, 'uk-PL'), 'one');
      expect(pluralCategoryOf(1, 'en-Latn-US-u-nu-arab'), 'one');
    });

    test('lookup assumption: every language with intl number symbols has plural rules', () {
      // `text_template.dart` asks "does intl know the language" through
      // `NumberFormat.localeExists` - the package has no public question of its own about plural
      // rules. If a new intl version splits these two lists, a language without rules
      // would go into its own lookup (first letters of the tag), and
      // this test will say so.
      final withoutRules = numberFormatSymbols.keys
          .cast<String>()
          .where((locale) => !plural_rules.localeHasPluralRules(locale));
      expect(withoutRules, isEmpty);
    });

    test('number for plurals: by absolute value, three decimal places', () {
      expect(pluralNumber(-1), 1);
      expect(pluralNumber(1.0004), 1);
      expect(pluralNumber(1.004), 1.004);
      expect(pluralNumber(-1.0004), 1);
      expect(pluralCategoryOf(1.0004, 'en'), 'one');
      expect(pluralCategoryOf(1.004, 'en'), 'other');
      expect(pluralCategoryOf(-1, 'en'), 'one');
      // 3.0 from JSON is a `double`; it agrees as the integer 3.
      expect(pluralCategoryOf(3.0, 'uk'), 'few');
    });

    test('a non-number, infinity and a huge number do not break form selection', () {
      for (final n in <num>[double.nan, double.infinity, double.negativeInfinity]) {
        expect(pluralCategoryOf(n, 'uk'), 'other');
      }
      for (final n in <num>[1e21, 1e300, -1e300, 5e-324, 9007199254740993]) {
        expect(kPluralCategories, contains(pluralCategoryOf(n, 'uk')), reason: '$n');
        expect(kPluralCategories, contains(pluralCategoryOf(n, 'ar')), reason: '$n');
      }
    });
  });

  group('number formats: limits the table does not name', () {
    test('a number intl cannot write is shown as is, not with false digits', () {
      // Beyond int64 `NumberFormat` writes 922,337,203,685,477,580,700 in place of
      // 1e21. The contract named the limit: 2^53 - 1, the format applies exactly at it.
      expect(formatBoundValue(9007199254740991, BindingFormat.number, locale: 'en'), '9,007,199,254,740,991');
      expect(formatBoundValue(9007199254740992, BindingFormat.number, locale: 'en'), isNull);
      expect(formatBoundValue(-9007199254740992.0, BindingFormat.currency, locale: 'en', currency: 'USD'), isNull);
      // Beyond the limit there is no plural number either: `other`, even though in Ukrainian it is `many`.
      expect(numericBoundValue(9007199254740992, null), isNull);
      expect(formatBoundValue(1e21, BindingFormat.number, locale: 'en'), isNull);
      expect(formatBoundValue(-1e300, BindingFormat.number, locale: 'en'), isNull);
      expect(formatBoundValue(1e21, BindingFormat.currency, locale: 'en', currency: 'USD'), isNull);
      expect(_resolve(_binding('n', format: 'number'), data: {'n': 1e21}), '1e+21');
      // Below the limit - as usual.
      expect(formatBoundValue(999999999999999, BindingFormat.number, locale: 'en'), '999,999,999,999,999');
      expect(formatBoundValue(double.nan, BindingFormat.number, locale: 'en'), isNull);
      expect(formatBoundValue(double.infinity, BindingFormat.currency, locale: 'en', currency: 'USD'), isNull);
    });

    test('a language intl does not know: number and amount as is, days computed, no separators', () {
      expect(formatBoundValue(1850, BindingFormat.number, locale: 'xx'), isNull);
      expect(formatBoundValue(1850.5, BindingFormat.currency, locale: 'xx', currency: 'USD'), isNull);
      expect(_resolve(_binding('n', format: 'number'), data: {'n': 1850}, locale: 'xx'), '1850');
      // "As is" for `daysUntil` would be an ISO string in the middle of a sentence; the days are
      // already computed, so they are shown.
      expect(
        formatBoundValue(
          '2030-11-18T09:00:00.000Z',
          BindingFormat.daysUntil,
          locale: 'xx',
          now: DateTime.parse('2026-10-10T09:00:00.000Z'),
        ),
        '1500',
      );
      // A region without data falls back to the language.
      expect(formatBoundValue(1850, BindingFormat.number, locale: 'uk-PL'), '1 850');
    });

    test('currency code: only three uppercase Latin letters', () {
      for (final code in <String?>[null, '', 'usd', 'US', 'USDT', 'U\$D', 'ЮСД', ' USD', 'USD ', 'U5D']) {
        expect(
          formatBoundValue(120, BindingFormat.currency, locale: 'en', currency: code),
          isNull,
          reason: '$code',
        );
      }
      expect(isCurrencyCode('JOD'), isTrue);
      // A code in the document that is not a string - no field, the number as is.
      expect(
        _resolve({'kind': 'binding', 'path': 'p', 'fallback': '—', 'format': 'currency', 'currency': 840}, data: {'p': 120}),
        '120',
      );
      // A code without the `currency` format is ignored by the reader.
      expect(_resolve(_binding('p', currency: 'USD'), data: {'p': 1850}), '1850');
      expect(_resolve(_binding('p', format: 'number', currency: 'USD'), data: {'p': 1850}), '1,850');
    });

    test('amount: whole without minor units, fractional with currency digits; negative with a sign', () {
      String? money(num amount, String code, [String locale = 'en']) =>
          formatBoundValue(amount, BindingFormat.currency, locale: locale, currency: code);
      expect(money(120, 'JOD'), '120 JOD');
      expect(money(120.0, 'JOD'), '120 JOD');
      expect(money(12.5, 'JOD'), '12.500 JOD');
      expect(money(-1850.5, 'USD'), '-1,850.50 USD');
      expect(money(1200.4, 'JPY'), '1,200 JPY');
      expect(money(1850.5, 'USD', 'uk'), '1 850,50 USD');
      expect(money(1850.5, 'USD', 'es'), '1.850,50 USD');
      // The code is the same in a right-to-left language: one composition.
      expect(money(120, 'JOD', 'ar'), '120 JOD');
    });

    test('"as is" value: an integer without a fraction, and without int64 saturation', () {
      expect(BoundString.stringify(3.0), '3');
      expect(BoundString.stringify(3), '3');
      expect(BoundString.stringify(-0.0), '0');
      expect(BoundString.stringify(1.5), '1.5');
      expect(BoundString.stringify(1.0004), '1.0004');
      expect(BoundString.stringify(150000.0), '150000');
      // `toInt()` would give 9223372036854775807.
      expect(BoundString.stringify(1e21), '1e+21');
      expect(BoundString.stringify(1e300), '1e+300');
      expect(BoundString.stringify(true), 'true');
      expect(BoundString.stringify('Ada'), 'Ada');
    });

    test('separate binding: a map or list at the path is not text but the fallback string', () {
      for (final value in <Object?>[
        {'value': 3},
        [1, 2],
        null,
      ]) {
        expect(_resolve(_binding('p', fallback: 'no data'), data: {'p': value}), 'no data', reason: '$value');
      }
      // `false` and 0 are values, not "absent".
      expect(_resolve(_binding('p'), data: {'p': false}), 'false');
      expect(_resolve(_binding('p'), data: {'p': 0}), '0');
      // Revised by the clarification (`emptyBoundString: 'use-fallback'`):
      // an empty string in the data means "no value". A string of spaces is a value.
      expect(_resolve(_binding('p'), data: {'p': ''}), '—');
      expect(_resolve(_binding('p', format: 'number'), data: {'p': ''}), '—');
      expect(_resolve(_binding('p'), data: {'p': '  '}), '  ');
    });
  });

  group('9.4.0 clarifications: what is easy to do differently in Dart', () {
    test('a date only by the contract expression: what `DateTime.tryParse` reads on its own is not yet a date', () {
      final now = DateTime.parse('2026-10-10T09:00:00.000Z');
      // Dart parses all of this without hesitation - and the web either does not parse it or
      // understands it differently (local midnight, year 1850).
      for (final value in [
        '2026-10-14',
        '2026-10-14T09:00:00',
        '2026-10-14 09:00:00Z',
        '20261014T090000Z',
        '2026-10-14T09:00:00+0300',
        '2026-10-14T09Z',
        '+002026-10-14T09:00:00Z',
        ' 2026-10-14T09:00:00Z',
        '2026-10-14T09:00:00.1234567890Z',
        '1850',
      ]) {
        for (final format in [BindingFormat.date, BindingFormat.dateTime, BindingFormat.time, BindingFormat.daysUntil]) {
          expect(formatBoundValue(value, format, locale: 'en', now: now), isNull, reason: '$value / ${format.wire}');
        }
        expect(numericBoundValue(value, BindingFormat.daysUntil, now: now), isNull, reason: value);
        // On the screen - the value as is, the word is `other`.
        expect(
          _resolve(
            _template('{d} {w}', {
              'd': _binding('d', format: 'daysUntil'),
              'w': _plural('d', {'one': 'day', 'other': 'days'}),
            }),
            data: {'d': value},
            now: now,
          ),
          '$value days',
        );
      }
      // And the contract form is a date: without seconds, with fractions up to nine digits, with an offset.
      for (final value in ['2026-10-11T09:00Z', '2026-10-11T08:59:59.123456789Z', '2026-10-11T12:00:00+03:00']) {
        expect(numericBoundValue(value, BindingFormat.daysUntil, now: now), 1, reason: value);
      }
      // The expression allows nine fraction digits - and `DateTime.tryParse` reads them.
      expect(formatBoundValue('2026-10-31T12:00:00.123456789Z', BindingFormat.date, locale: 'en'), isNotNull);
    });

    test('an empty string is the fallback text for TEXT, but not for an option name', () {
      final doc = _doc([
        {
          'id': 'group',
          'type': 'ChoiceGroup',
          'props': {'value': _binding('pick', fallback: 'first'), 'gap': 'sm'},
          'children': <Object?>[],
        },
      ]);
      final group = flattenDocument(doc).whereType<ChoiceGroupNode>().single;
      // `emptyBoundString` is about a string that becomes text. It does not touch the name of the
      // chosen option: an empty name means "nothing chosen", not a fallback option.
      expect(group.value.resolve(const ScreenData({'pick': ''})), '');
      expect(group.value.resolve(const ScreenData({})), 'first');
    });

    test('an empty string in the record layer still CLOSES the layer below - and as text yields to the fallback', () {
      // The clarification does not change the layer order (`absentInDataLayer`): "absent" in a layer
      // is a missing key or `null`, while `""` is a value.
      const data = ScreenData.scoped(document: {'item.name': 'from data'}, record: {'item.name': ''});
      expect(data.lookup('item.name'), '');
      expect(BindableString.parse(_binding('item.name', fallback: 'no name')).resolve(data), 'no name');
    });

    test('a plural number from the fallback text - only when the fallback is SHOWN and is a number', () {
      String run(String fallback, Object? value, {String? format}) => _resolve(
        _template('{n} {w}', {
          'n': _binding('n', fallback: fallback, format: format),
          'w': _plural('n', {'one': 'бал', 'few': 'бали', 'many': 'балів', 'other': 'бала'}),
        }),
        data: {'n': value},
        source: 'uk',
        locale: 'uk',
      );
      expect(run('0', null), '0 балів');
      expect(run('1', ''), '1 бал');
      expect(run('-2', {'a': 1}), '-2 бали');
      expect(run('1.5', null), '1.5 бала');
      // The fallback "3" under `daysUntil` is 3, not a date.
      expect(run('3', null, format: 'daysUntil'), '3 бали');
      // Not a number by the expression: a space, a group separator, an exponent, a plus.
      for (final fallback in ['—', ' 1', '1 000', '1e3', '+1', '1.', '.5', '']) {
        expect(run(fallback, null), '$fallback бала', reason: fallback);
      }
      // Data EXISTS but is not a number: the fallback is not shown and gives no number.
      expect(run('1', 'many'), 'many бала');
      // A fallback number beyond the magnitude limit gives no number.
      expect(run('9007199254740993', null), '9007199254740993 бала');
    });
  });

  group('substitution: a single pass', () {
    test('a place is only {name} by the name pattern, declared by its own key', () {
      final values = {'done': _binding('p')};
      String run(String template) => _resolve(_template(template, values), data: {'p': 3});
      expect(run('{done}'), '3');
      expect(run('{{done}}'), '{3}');
      expect(run('{done}{done}'), '33');
      expect(run('{ done } {Done} {} {dONE} {done '), '{ done } {Done} {} {dONE} {done ');
      expect(run('{a{done}b}'), '{a3b}');
      // 24 characters is still a name, 25 is not (and a value with such a name cannot be reached).
      final long = 'a' * 24;
      expect(_resolve(_template('{$long}', {long: _binding('p')}), data: {'p': 3}), '3');
      final tooLong = 'a' * 25;
      expect(_resolve(_template('{$tooLong}', {tooLong: _binding('p')}), data: {'p': 3}), '{$tooLong}');
    });

    test('the result is not parsed a second time - not from data, nor fallback text, nor a form', () {
      expect(
        _resolve(
          _template('{a} {b} {w}', {
            'a': _binding('a'),
            'b': _binding('missing', fallback: '{a}'),
            'w': _plural('a', {'other': '{b}'}),
          }),
          data: {'a': '{b}'},
        ),
        '{b} {a} {b}',
      );
    });

    test('a place in a TRANSLATION that is absent from values is literal text with braces', () {
      final value = BindableString.parse(_template('{done} steps', {'done': _binding('p')}), key: 's/n/content');
      const strings = LocalizedStrings(
        locale: 'uk',
        table: {'s/n/content.template': 'Кроків: {done}, лишилось {left}'},
        sourceLocale: 'en',
      );
      expect(value.resolve(const ScreenData({'p': 3}), strings, 'uk', _now), 'Кроків: 3, лишилось {left}');
    });
  });

  group('robustness: a document from the network', () {
    test('a malformed template does not throw and does not break neighbouring values', () {
      final cases = <(Object?, String)>[
        ({'kind': 'template'}, ''),
        ({'kind': 'template', 'template': 42, 'values': {}}, ''),
        ({'kind': 'template', 'template': 'a {x} b', 'values': null}, 'a {x} b'),
        ({'kind': 'template', 'template': 'a {x} b', 'values': 'x'}, 'a {x} b'),
        ({'kind': 'template', 'template': 'a {x} b', 'values': [1]}, 'a {x} b'),
        // A declared value that cannot be read is an empty place without braces.
        (_template('a {x} b', {'x': null}), 'a  b'),
        (_template('a {x} b', {'x': 7}), 'a  b'),
        (_template('a {x} b', {'x': []}), 'a  b'),
        (_template('a {x} b', {'x': {'kind': 'future'}}), 'a  b'),
        (_template('a {x} b', {'x': {'kind': 'binding'}}), 'a  b'),
        (_template('a {x} b', {'x': {'kind': 'binding', 'path': 7}}), 'a  b'),
        // A binding without fallback text has an empty fallback, not `null`.
        (_template('a {x} b', {'x': {'kind': 'binding', 'path': 'nope'}}), 'a  b'),
        // Plural without forms, with non-map forms, with non-string forms.
        (_template('{n} {w}', {'n': _binding('n'), 'w': {'kind': 'plural'}}), '1 '),
        (_template('{n} {w}', {'n': _binding('n'), 'w': {'kind': 'plural', 'of': 'n', 'forms': 'x'}}), '1 '),
        (_template('{n} {w}', {'n': _binding('n'), 'w': _plural('n', {'one': 1, 'other': null})}), '1 '),
        (_template('{n} {w}', {'n': _binding('n'), 'w': {'kind': 'plural', 'of': 5, 'forms': {'one': 'a', 'other': 'b'}}}), '1 b'),
        // Plural without `forms.other` is a known kind of the wrong shape: an empty place,
        // even though the form of the needed category (`one` for 1) is written.
        (_template('{n} {w}', {'n': _binding('n'), 'w': _plural('n', {'one': 'ONE'})}), '1 '),
        // A form key is anything: only the six categories are read.
        (_template('{n} {w}', {'n': _binding('n'), 'w': _plural('n', {'__proto__': 'x', 'ONE': 'x', 'one ': 'x', 'other': 'ok'})}), '1 ok'),
      ];
      for (final (raw, expected) in cases) {
        expect(_resolve(raw, data: {'n': 1}), expected, reason: '$raw');
      }
    });

    test('`of` pointing at itself, at another plural, at a value without a number, and at nothing - `other`, no recursion', () {
      final forms = {'one': 'ONE', 'other': 'OTHER'};
      String run(Map<String, Object?> values, [Map<String, Object?> data = const {'n': 1}]) =>
          _resolve(_template('{w}', values), data: data);

      expect(run({'w': _plural('w', forms)}), 'OTHER');
      expect(run({'w': _plural('v', forms), 'v': _plural('w', forms)}), 'OTHER');
      expect(run({'w': _plural('nope', forms)}), 'OTHER');
      expect(run({'w': _plural('', forms)}), 'OTHER');
      // A number as a string, a flag, a date without `daysUntil`, a date under a date format.
      for (final value in <Object?>['1', true, '2026-10-11T09:00:00.000Z', null, {'a': 1}]) {
        expect(run({'w': _plural('n', forms), 'n': _binding('n')}, {'n': value}), 'OTHER', reason: '$value');
      }
      expect(
        run({'w': _plural('n', forms), 'n': _binding('n', format: 'date')}, {'n': '2026-10-11T09:00:00.000Z'}),
        'OTHER',
      );
      // But a number and `daysUntil` give a number.
      expect(run({'w': _plural('n', forms), 'n': _binding('n')}), 'ONE');
      expect(
        run({'w': _plural('n', forms), 'n': _binding('n', format: 'daysUntil')}, {'n': '2026-10-11T09:00:00.000Z'}),
        'ONE',
      );
    });

    test('a value name is anything: an unfit name sits in the map and weighs nothing', () {
      final values = <String, Object?>{
        '__proto__': _binding('p'),
        'constructor': _binding('p'),
        'toString': _binding('p'),
        '': _binding('p'),
        'Done': _binding('p'),
        'has space': _binding('p'),
        'a' * 5000: _binding('p'),
        'ok': _binding('p'),
      };
      expect(
        _resolve(_template('{__proto__} {} {Done} {has space} {ok}', values), data: {'p': 'v'}),
        '{__proto__} {} {Done} {has space} v',
      );
      // `constructor` and `toString` fit the name pattern, and if the document
      // DECLARED them - they are values like any other. If not declared - text.
      expect(_resolve(_template('{constructor} {toString}', values), data: {'p': 'v'}), 'v v');
      expect(_resolve(_template('{constructor} {toString}', const {}), data: {'p': 'v'}), '{constructor} {toString}');
    });

    test('thousands of places and a very long string: linear, a value is computed once per name', () {
      const places = 20000;
      final template = List.filled(places, '{n} {w}{nope}{').join(' ');
      final value = BindableString.parse(
        _template(template, {
          'n': _binding('n', format: 'daysUntil'),
          'w': _plural('n', {'one': 'day', 'other': 'days'}),
        }),
      );

      var lookups = 0;
      final data = _CountingData({'n': '2026-10-14T09:00:00.000Z'}, () => lookups++);
      final watch = Stopwatch()..start();
      final text = value.resolve(
        data,
        const LocalizedStrings(locale: null, table: {}, sourceLocale: 'en'),
        'en',
        _now,
      );
      watch.stop();

      expect(text, List.filled(places, '4 days{nope}{').join(' '));
      // Two names - two reads of the value `n` (text and plural number), not
      // forty thousand.
      expect(lookups, 2);
      // A margin of hundreds of times: on this machine it is milliseconds. A quadratic parse of
      // twenty thousand places in four hundred kilobytes does not fit here.
      expect(watch.elapsedMilliseconds, lessThan(2000));

      // A megabyte of braces without a single place is also a string, not a hang.
      final braces = '{' * 500000 + '}' * 500000;
      expect(_resolve(_template(braces, {'n': _binding('n')})), braces);
      final almost = '{a' * 200000;
      expect(_resolve(_template(almost, {'a': _binding('n')})), almost);
    });

    testWidgets('a screen with malformed templates in EVERY text slot renders without an exception', (tester) async {
      final broken = <Object?>[
        {'kind': 'template'},
        {'kind': 'template', 'template': '{a} {b}', 'values': {'a': 7, 'b': {'kind': 'plural', 'of': 'b'}}},
        _template('{w}', {'w': _plural('w', {'other': 'x'})}),
        _template('{p}', {'p': _binding('p', format: 'currency', currency: 'nope')}),
        _template('{p}', {'p': _binding('p', format: 'number')}),
        {'kind': 'future', 'template': '{a}'},
      ];
      for (final value in broken) {
        final doc = _doc([
          {
            'id': 'bar',
            'type': 'AppBar',
            'props': {'title': value, 'subtitle': value, 'showBack': false},
          },
          _text(value),
          {
            'id': 'bdg',
            'type': 'Badge',
            'props': {'label': value, 'tone': 'neutral'},
          },
          {
            'id': 'btn',
            'type': 'Button',
            'props': {'label': value, 'variant': 'primary', 'action': {'type': 'x'}, 'fullWidth': true},
          },
          {
            'id': 'tile',
            'type': 'ListTile',
            'props': {
              'leading': {'kind': 'none'},
              'title': value,
              'subtitle': value,
              'trailing': {'kind': 'text', 'text': value},
            },
          },
          _text({'kind': 'literal', 'value': 'still here'}, id: 'after'),
        ]);
        await pumpDocument(tester, doc, data: const {'p': 'not a number'}, now: _now);
        expect(tester.takeException(), isNull, reason: '$value');
        // The neighbour is intact: one broken string does not take down the node next to it.
        expect(find.text('still here'), findsOneWidget, reason: '$value');
      }
    });
  });

  group('unknown string kind and places where a template cannot occur', () {
    testWidgets('unknownStringKind: render-empty - the node is intact, neighbours intact, no text', (tester) async {
      final doc = _doc([
        _text({'kind': 'markdown', 'value': '**{done}**', 'template': '{done}'}),
        _text({'kind': 'literal', 'value': 'neighbour'}, id: 'next'),
      ]);
      await pumpDocument(tester, doc, now: _now);
      expect(_shown(tester), ['', 'neighbour']);
      expect(tester.takeException(), isNull);
    });

    test('ChoiceGroup.value has no template: it is an option name, not text for a person', () {
      final doc = _doc([
        {
          'id': 'group',
          'type': 'ChoiceGroup',
          'props': {
            'value': _template('{a}', {'a': _binding('p')}),
            'gap': 'sm',
          },
          'children': <Object?>[],
        },
      ]);
      final group = flattenDocument(doc).whereType<ChoiceGroupNode>().single;
      expect(group.value, isA<LiteralString>());
      expect(group.value.resolve(const ScreenData({'p': 'x'})), '');
    });

    test('translation keys come from the node place: <place>.template and <place>.values.<name>.forms.<category>', () {
      final doc = _doc(
        [
          {
            'id': 'tile',
            'type': 'ListTile',
            'props': {
              'leading': {'kind': 'none'},
              'title': {'kind': 'literal', 'value': 't'},
              'trailing': {
                'kind': 'text',
                'text': _template('{n} {unit}', {
                  'n': _binding('n'),
                  'unit': _plural('n', {'one': 'point', 'other': 'points'}),
                }),
              },
            },
          },
        ],
        localization: {
          'defaultLocale': 'en',
          'locales': ['en', 'uk'],
          'strings': {
            'uk': {
              's/tile/trailing.text.template': '{unit}: {n}',
              's/tile/trailing.text.values.unit.forms.one': 'бал',
              's/tile/trailing.text.values.unit.forms.few': 'бали',
              's/tile/trailing.text.values.unit.forms.many': 'балів',
              's/tile/trailing.text.values.unit.forms.other': 'бала',
            },
          },
        },
      );
      final tile = flattenDocument(doc).whereType<ListTileNode>().single;
      final text = (tile.trailing as TrailingText).text;
      expect(text, isA<TemplateString>());
      expect((text as TemplateString).key, 's/tile/trailing.text');
      const data = ScreenData({'n': 22});
      expect(text.resolve(data, doc.stringsFor('uk'), 'uk', _now), 'бали: 22');
      // Source language: the table is empty but names the language - "22 points", not an arbitrary `other`.
      expect(doc.stringsFor('en').sourceLocale, 'en');
      expect(doc.stringsFor(null).sourceLocale, 'en');
      expect(text.resolve(const ScreenData({'n': 1}), doc.stringsFor('en'), 'en', _now), '1 point');
      // The language is absent from the document - the source one, with its own rules.
      expect(text.resolve(const ScreenData({'n': 1}), doc.stringsFor('de'), 'en', _now), '1 point');
    });
  });
}

/// Data that counts reads - so that "a value is computed once per name" is
/// a statement about code, not about a stopwatch.
class _CountingData extends ScreenData {
  _CountingData(super.document, this._onLookup);

  final void Function() _onLookup;

  @override
  Object? lookup(String path) {
    _onLookup();
    return super.lookup(path);
  }
}
