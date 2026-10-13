// Clarifications to schema 9.5.0: what the template case table does not
// cover -- mirrors of the new artifact keys, plural operands against `intl`
// itself, date bounds and the accessible name.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/plural_rules.dart';
import 'package:hotlayout_flutter/src/model/text_template.dart';
import 'package:hotlayout_flutter/src/render/tap_target.dart';
import 'package:intl/intl.dart';
import 'package:intl/src/plural_rules.dart' as intl_rules;

import 'support/demo_data.dart';
import 'support/fixtures.dart';

void main() {
  final schema =
      jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;

  group('mirrors of the new artifact keys', () {
    test('x-accessibleName: class of silent characters and flag', () {
      final block = schema['x-accessibleName']! as Map<String, Object?>;
      expect(block['silentCharacters'], kSilentCharactersPattern);
      expect(block['flags'], kSilentCharactersUnicode ? 'u' : '');
    });

    test('x-style.layout.buttonLabelAlign', () {
      final layout = (schema['x-style']! as Map<String, Object?>)['layout']! as Map<String, Object?>;
      expect(layout['buttonLabelAlign'], kButtonLabelAlign);
    });
  });

  group('accessible name: "no label" is decided by x-accessibleName, not trim()', () {
    test('NBSP, BOM, zero width and a mix -- empty name, i.e. the name comes from the icon', () {
      for (final silent in ['', ' ', ' ', '﻿', '​', ' ​ ﻿ ', ' ‍']) {
        expect(isSilentAccessibleName(silent), isTrue, reason: silent.runes.toList().toString());
        expect(iconButtonNameOf(silent, 'chevron-left'), 'chevron left');
      }
      expect(iconButtonNameOf('​', null), '');
    });

    test('a visible character among silent ones -- the label stays as is', () {
      expect(isSilentAccessibleName('​x'), isFalse);
      expect(iconButtonNameOf('​Back', 'chevron-left'), '​Back');
    });
  });

  group('date -- a real calendar instant', () {
    String? date(String iso) => formatBoundValue(iso, BindingFormat.date, locale: 'en');

    test('leap year: 29 Feb 2028 yes, 2026 and 1900 no, 2000 yes', () {
      expect(date('2028-02-29T12:00:00Z'), isNotNull);
      expect(date('2000-02-29T12:00:00Z'), isNotNull);
      expect(date('2026-02-29T12:00:00Z'), isNull);
      expect(date('1900-02-29T12:00:00Z'), isNull);
    });

    test('group bounds', () {
      expect(date('2026-13-01T00:00Z'), isNull);
      expect(date('2026-12-31T23:59Z'), isNotNull);
      expect(date('2026-04-31T00:00Z'), isNull);
      expect(date('2026-10-14T12:00:60Z'), isNull);
      expect(date('2026-10-14T12:00:59+23:59'), isNotNull);
      expect(date('2026-10-14T12:00:00-24:00'), isNull);
      expect(date('2026-10-14T12:00:00+05:60'), isNull);
    });

    test('daysUntil and time use the same check', () {
      expect(formatBoundValue('2030-02-30T09:00:00Z', BindingFormat.daysUntil, locale: 'en'), isNull);
      expect(formatBoundValue('2026-10-14T24:00:00Z', BindingFormat.time, locale: 'en'), isNull);
      expect(numericBoundValue('2026-11-31T09:00:00Z', BindingFormat.daysUntil), isNull);
    });
  });

  group('rounding -- half away from zero over the shortest decimal representation', () {
    test('roundHalfAwayFromZero', () {
      String r(num v, int k) {
        final x = roundHalfAwayFromZero(v, k);
        return '${x.negative ? '-' : ''}${x.integer}.${x.fraction}';
      }

      expect(r(1.005, 2), '1.01');
      expect(r(2.675, 2), '2.68');
      expect(r(1.0005, 3), '1.001');
      expect(r(1.0004, 3), '1.000');
      expect(r(-1.0005, 3), '-1.001');
      expect(r(9.9995, 3), '10.000');
      expect(r(0.0005, 3), '0.001');
      expect(r(1e-7, 3), '0.000');
      expect(r(5e-4, 3), '0.001');
      expect(r(1.5e20, 1), '150000000000000000000.0');
      expect(r(3, 2), '3.00');
    });

    test('format: groups and the locale sign stay, the contract does the counting', () {
      expect(formatBoundValue(1.005, BindingFormat.currency, locale: 'en', currency: 'USD'), '1.01 USD');
      expect(formatBoundValue(1234.0005, BindingFormat.number, locale: 'en'), '1,234.001');
      expect(formatBoundValue(1234.0005, BindingFormat.number, locale: 'de'), '1.234,001');
    });

    test('modulus bound: a negative beyond the bound is also "as is"', () {
      for (final format in [BindingFormat.number, BindingFormat.currency]) {
        expect(
          formatBoundValue(-9223372036854775808, format, locale: 'en', currency: 'USD'),
          isNull,
          reason: format.wire,
        );
        expect(formatBoundValue(-9007199254740994, format, locale: 'en', currency: 'USD'), isNull);
      }
      expect(formatBoundValue(-9007199254740991, BindingFormat.number, locale: 'en'), isNotNull);
    });
  });

  group('plural operands (own rules against intl)', () {
    test('on integers the generated rules match intl for EVERY locale', () {
      for (final locale in intl_rules.pluralRules.keys) {
        for (final n in [0, 1, 2, 3, 4, 5, 6, 10, 11, 12, 14, 19, 21, 22, 25, 71, 100, 101, 111, 1000, 1000000]) {
          final expected = Intl.pluralLogic<String>(
            n,
            locale: locale,
            zero: 'zero',
            one: 'one',
            two: 'two',
            few: 'few',
            many: 'many',
            other: 'other',
            useExplicitNumberCases: false,
          );
          expect(kPluralRules[locale]!(n, n, 0, 0, 0), expected, reason: '$locale $n');
        }
      }
      expect(kPluralRules.keys.toSet(), intl_rules.pluralRules.keys.toSet());
    });

    test('fractional: fr 1.5, hi 0.5, en 1.5, ru 1.5, uk 0.5', () {
      expect(pluralCategoryOf(1.5, 'fr'), 'one');
      expect(pluralCategoryOf(1.9, 'fr'), 'one');
      expect(pluralCategoryOf(2.5, 'fr'), 'other');
      expect(pluralCategoryOf(0.5, 'hi'), 'one');
      expect(pluralCategoryOf(1.5, 'en'), 'other');
      expect(pluralCategoryOf(1.5, 'ru'), 'other');
      expect(pluralCategoryOf(0.5, 'uk'), 'other');
    });

    test('number rounded to three digits: 1.0004 is an integer, 1.004 is fractional', () {
      expect(pluralFractionDigits(1.0004), 0);
      expect(pluralFractionDigits(1.004), 3);
      expect(pluralFractionDigits(1.5), 1);
      expect(pluralFractionDigits(2), 0);
      expect(pluralCategoryOf(1.0004, 'en'), 'one');
      expect(pluralCategoryOf(1.004, 'en'), 'other');
    });
  });

  group('tap on a mission row opens the mission screen (showcase)', () {
    testWidgets('home -> mission ListTile -> mission', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      const id = 'rewards-showcase-screens';
      final doc = loadFixture(id);
      final screens = <String>[];
      await pumpDocument(
        tester,
        doc,
        theme: fixtureTheme(id),
        data: sampleScreenData,
        entry: 'home',
        locale: 'en',
        onScreenChanged: (screen) => screens.add(screen.screenId),
      );
      await tester.pumpAndSettle();
      expect(screens, ['home']);

      // The mission row is a document `ListTile` with a `navigate` action; in Flutter it is
      // a `TapTarget` around a `GestureDetector`; we search by the first mission's label.
      final row = find.ancestor(of: find.text('Spend 500 with your card'), matching: find.byType(TapTarget));
      expect(row, findsWidgets, reason: 'home has mission rows');
      await tester.ensureVisible(row.first);
      await tester.tap(row.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(screens, ['home', 'mission']);
    });
  });
}
