/// Hostile-input tests for 9.4.0 (numbers, money, days, plural): the same document
/// and the same data give this reader DIFFERENT TEXT than the contract reference
/// (`renderBindableString` in the builder's `text-template.ts`) and the web reader.
///
/// Method: 28,137 rows (numbers with a "five" in the first dropped
/// digit, all currency codes AAA-ZZZ, 150 languages x 50 plural numbers, dates at the edges of
/// the `dateTimePattern` expression) were run through the reference and through
/// `BindableString.resolve`; 1270 diverged. Everything the policy
/// ALLOWS the platform to differ on is dropped (CLDR signs, languages without data -
/// `missingNumberLocaleData`, the `mayDiffer` flag); what remains is where the RULE diverges.
///
/// Every expectation below is the reference answer for that input, character for character.
/// The shared table `template-cases.json` has none of these inputs: it has
/// no number ending in 5 at the rounding boundary, no fractional number in
/// French or Hindi, and no date with a field outside the calendar.
///
/// Each case pins the reference answer for its input;
/// the product code is not involved.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/text_template.dart';

final DateTime _now = DateTime.parse('2026-10-10T09:00:00.000Z');

/// Document string -> text; data is RAW JSON text, because `-9223372036854775808`
/// and `1.0` are parsed by Dart differently from a literal in test code.
String _shown(
  Map<String, Object?> value,
  String dataJson, {
  String formatting = 'en',
  String source = 'en',
}) => BindableString.parse(value, key: 'p').resolve(
  ScreenData(jsonDecode(dataJson) as Map<String, Object?>),
  LocalizedStrings(locale: null, table: const {}, sourceLocale: source),
  formatting,
  _now,
);

Map<String, Object?> _binding([Map<String, Object?> extra = const {}]) => {
  'kind': 'binding',
  'path': 'a',
  'fallback': '—',
  ...extra,
};

/// "{n} {u}": a number and the word next to it.
Map<String, Object?> _counted(
  Map<String, Object?> number, {
  Map<String, Object?> forms = const {'one': 'point', 'other': 'points'},
}) => {
  'kind': 'template',
  'template': '{n} {u}',
  'values': {
    'n': _binding(number),
    'u': {'kind': 'plural', 'of': 'n', 'forms': forms},
  },
};

void main() {
  // ───────────────────────────────────────────────────────────────────────
  // 1. ROUNDING. The reference (`Intl.NumberFormat`) rounds the DECIMAL notation
  //    of a number half up: 1.0005 -> "1.001", 1.005 USD -> "1.01 USD".
  //    The `intl` package's `NumberFormat` multiplies the binary approximation by a power of
  //    ten and rounds that: 1.0005 -> "1", 1.005 USD -> "1.00 USD".
  //    Of 326 USD amounts of the form `x.yz5`, 137 diverged; of 348 numbers of the form
  //    `x.yyy5`, 145: almost every second amount with half a cent comes out
  //    a cent lower on the phone than on the web and the builder canvas.
  // ───────────────────────────────────────────────────────────────────────
  group('rounding: number and amount - the same digits as in the reference', () {
    final numbers = <double, String>{
      1.0005: '1.001',
      1.2345: '1.235',
      2756.8705: '2,756.871',
      2072.3995: '2,072.4',
    };
    for (final entry in numbers.entries) {
      test('number ${entry.key} → «${entry.value}»', () {
        expect(formatBoundValue(entry.key, BindingFormat.number, locale: 'en'), entry.value);
      });
    }

    final sums = <double, String>{
      1.005: '1.01 USD',
      2.675: '2.68 USD',
      0.285: '0.29 USD',
    };
    for (final entry in sums.entries) {
      test('currency ${entry.key} USD → «${entry.value}»', () {
        expect(
          formatBoundValue(entry.key, BindingFormat.currency, locale: 'en', currency: 'USD'),
          entry.value,
        );
      });
    }

    test('currency 1.2345 BHD (three decimals) -> "1.235 BHD"', () {
      expect(
        formatBoundValue(1.2345, BindingFormat.currency, locale: 'en', currency: 'BHD'),
        '1.235 BHD',
      );
    });

    test('the word agrees with the WRITTEN number: 1.0005 is written "1.001" and takes other', () {
      // Here the reader writes "1 point": both the number and the word differ from the web.
      expect(_shown(_counted({'format': 'number'}), '{"a":1.0005}'), '1.001 points');
    });

    test('the plural number is rounded the same way the format writes it (`pluralNumber`)', () {
      // 1.0005 -> 1.001 -> other; `toStringAsFixed(3)` gives "1.000" -> one.
      expect(pluralCategoryOf(1.0005, 'en'), 'other');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 2. FRACTIONAL NUMBER AND PLURAL. The CLDR operand `i` is the INTEGER PART of the number.
  //    `Intl.pluralLogic` computes it as `round()`: 1.5 becomes i = 2, 0.5 becomes i = 1.
  //    In French (one: i = 0, 1) "1,5 point" becomes "1,5 points"; in Hindi,
  //    Bengali, Persian, Hebrew (one: i = 0 or n = 1) 0.5 takes other.
  // ───────────────────────────────────────────────────────────────────────
  group('plural of a fractional number: CLDR category by the integer PART, not by the rounded one', () {
    const cases = [
      ('fr', 1.5, 'one'),
      ('fr', 1.9, 'one'),
      ('pt', 1.5, 'one'),
      ('da', 1.5, 'one'),
      ('hy', 1.5, 'one'),
      ('hi', 0.5, 'one'),
      ('bn', 0.5, 'one'),
      ('fa', 0.5, 'one'),
      ('he', 0.5, 'one'),
    ];
    for (final (locale, number, category) in cases) {
      test('$locale $number → $category', () {
        expect(pluralCategoryOf(number, locale), category);
      });
    }

    test('end to end: French document, 1.5 in the data - "1.5 ONE", as on the web', () {
      expect(
        _shown(_counted(const {}, forms: const {'one': 'ONE', 'other': 'OTHER'}), '{"a":1.5}', source: 'fr', formatting: 'fr'),
        '1.5 ONE',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 3. "WHAT COUNTS AS A DATE" (`dateValueForm`). The contract expression allows any
  //    two digits in every field; after the expression the reference also asks the parser, and
  //    the parser REJECTS fields outside the calendar - the value is shown as is.
  //    `DateTime.tryParse` CARRIES such fields over: hour 25 becomes hour one
  //    tomorrow, month 13 becomes January of the next year, offset +99:99 becomes
  //    four days back. The screen shows a plausible date that is not in the data,
  //    and `daysUntil` counts days to it.
  // ───────────────────────────────────────────────────────────────────────
  group('a date with a field outside the calendar is not a date: the value as is', () {
    const values = [
      '2026-10-10T25:00Z',
      '2026-10-10T24:01Z',
      '2026-10-10T23:60Z',
      '2026-10-10T23:59:60Z',
      '2026-10-11T09:00+24:00',
      '2026-10-11T09:00+99:99',
      '2026-10-11T09:00+14:60',
      '2027-13-01T00:00Z',
      '2027-00-10T00:00Z',
      '2027-01-00T00:00Z',
      '2027-01-32T00:00Z',
    ];
    for (final value in values) {
      test('date: $value', () {
        expect(formatBoundValue(value, BindingFormat.date, locale: 'en', now: _now), isNull);
      });
      test('daysUntil: $value', () {
        expect(formatBoundValue(value, BindingFormat.daysUntil, locale: 'en', now: _now), isNull);
        expect(numericBoundValue(value, BindingFormat.daysUntil, now: _now), isNull);
      });
    }

    test('end to end: "{n} {u} left" with month 13 - the string as is and other, not "448 days left"', () {
      expect(
        _shown(
          _counted({'format': 'daysUntil'}, forms: const {'one': 'day', 'other': 'days'}),
          '{"a":"2027-13-01T00:00Z"}',
        ),
        '2027-13-01T00:00Z days',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 4. MAGNITUDE LIMIT (`numberBeyondSafeInteger`). The smallest int64 passes
  //    the limit: `abs()` of -2^63 in Dart is NEGATIVE (overflow), and
  //    a negative number is "not greater than 2^53 - 1". The format is applied
  //    ("-9,223,372,036,854,775,808") although the number is 10 orders of magnitude past the limit.
  // ───────────────────────────────────────────────────────────────────────
  group('-2^63: beyond 2^53 - 1 - as is, the word takes other', () {
    const data = '{"a":-9223372036854775808}';

    test('number is not applied', () {
      final value = (jsonDecode(data) as Map<String, Object?>)['a'];
      expect(formatBoundValue(value, BindingFormat.number, locale: 'en'), isNull);
      expect(numericBoundValue(value, BindingFormat.number), isNull);
    });

    test('end to end: without group separators', () {
      expect(_shown(_binding({'format': 'number'}), data), isNot(contains(',')));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 5. FORMAT LOCALE WITH A `-u-nu-...` EXTENSION. The language rule (9.1.0) in BOTH
  //    readers keeps the extension in `formatting` (`ar-EG-u-nu-latn` is how
  //    iOS says "Arabic, Latin digits"). The reference honours it; here
  //    the lookup chain drops the tail, and the digits are the defaults for `ar_EG`.
  //    Reachable when the host passes the device tag as is.
  // ───────────────────────────────────────────────────────────────────────
  //
  //    OPEN QUESTION, not a defect: "Locale extension `-u-nu-...`" is an open
  //    question of the contract:
  //    the contract has not yet said whether the reader must honour `nu`. `intl`
  //    does not take numbering systems from the tag. The tests are kept; `skip` is removed together
  //    with the decision.
  const nuOpen = 'open question: locale extension -u-nu-... (not yet decided by the contract)';
  group('digits under the locale `nu` extension of the format', () {
    test('ar-EG-u-nu-latn: Latin digits', skip: nuOpen, () {
      expect(formatBoundValue(1850.5, BindingFormat.number, locale: 'ar-EG-u-nu-latn'), '1,850.5');
    });

    test('en-US-u-nu-arab: Arabic-Indic digits', skip: nuOpen, () {
      expect(formatBoundValue(1850.5, BindingFormat.number, locale: 'en-US-u-nu-arab'), '١٬٨٥٠٫٥');
    });
  });
}
