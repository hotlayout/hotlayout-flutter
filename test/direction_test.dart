/// Writing direction (RTL), contract 8.15.0.
///
/// Two statements, and both must agree with the web:
///
///  1. which language is written right to left - we ask CLDR, not a private list;
///  2. which icons are mirrored - the CONTRACT says (`x-mirroredIcons`), because glyphs
///     are platform-specific while the decision must be one.
///
/// The third is ours alone: direction comes from the DOCUMENT language, not the app locale.
/// An Arabic document inside an English app is a common thing, and
/// that is exactly why `Directionality` sits on the screen flow rather than above it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/icon_set.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/direction.dart';

import 'support/fixtures.dart';

void main() {
  group('which language counts as RTL - answered by CLDR', () {
    for (final locale in ['ar', 'he', 'fa', 'ur', 'ps', 'ckb', 'pa-Arab']) {
      test('$locale - right to left', () {
        expect(directionOfLocale(locale), TextDirection.rtl);
      });
    }

    for (final locale in ['en', 'uk', 'ru', 'kk', 'sr-Cyrl']) {
      test('$locale - left to right', () {
        expect(directionOfLocale(locale), TextDirection.ltr);
      });
    }

    /// The most important example: direction is a property of the SCRIPT, not the language.
    /// Kurdish in Latin script is LTR, in Arabic script RTL. A list of languages
    /// cannot tell them apart in principle, which is why we have none.
    test('script outranks language: ku is ltr, ckb is rtl', () {
      expect(directionOfLocale('ku'), TextDirection.ltr);
      expect(directionOfLocale('ckb'), TextDirection.rtl);
    });

    test('no language named - stay left to right', () {
      expect(directionOfLocale(null), TextDirection.ltr);
      expect(directionOfLocale(''), TextDirection.ltr);
      expect(directionOfLocale('   '), TextDirection.ltr);
    });

    /// Garbage instead of a tag comes from the document, and the document comes from
    /// the network: crashing here would take down the whole screen over one stray letter.
    test('an unusable tag does not crash', () {
      expect(() => directionOfLocale('не-мова!!'), returnsNormally);
      expect(directionOfLocale('не-мова!!'), TextDirection.ltr);
    });
  });

  group('mirrored icons match the contract', () {
    test('the list in code = `x-mirroredIcons` in the artifact', () {
      final artifact =
          jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync())
              as Map<String, Object?>;
      final mirrored = (artifact['x-mirroredIcons']! as List<Object?>).cast<String>();

      // 9.3.0: the list grew from one name to 29, and typing it by hand is pointless -
      // `kMirroredIcons` is generated from the artifact. The order is
      // checked too: a generated copy must be a copy.
      expect(kMirroredIcons.toList(), mirrored);
      expect(mirrored, hasLength(29));
      expect(mirrored.first, 'chevron');
    });

    test('every mirrored name is in the set', () {
      for (final name in kMirroredIcons) {
        expect(IconToken.parse(name).isKnown, isTrue, reason: name);
        expect(IconToken.parse(name).isMirrored, isTrue, reason: name);
      }
    });

    /// Previously the chevron mirrored a Material glyph (`matchTextDirection`), and the code had
    /// no correction of our own. Nobody flips a drawing that comes from data,
    /// so the rule is now OURS - one, in `IconGlyph`. That it acts exactly once and
    /// only on the listed names is held by `icon_library_test.dart` in pixels.
    test('the rest of the set is not mirrored', () {
      final plain = IconToken.values.where((icon) => !icon.isMirrored).map((icon) => icon.wire).toSet();
      expect(plain, hasLength(IconToken.values.length - 29));
      expect(
        plain,
        containsAll(['play', 'skip-forward', 'refresh-cw', 'rotate-ccw', 'list-ordered', 'circle-help', 'truck', 'plane', 'volume-2']),
        reason: 'the contract did not ask for objects, playback and rotation to be mirrored',
      );
    });
  });

  group('direction comes from the DOCUMENT language', () {
    testWidgets('an Arabic document lays out right to left', (tester) async {
      await pumpDocument(
        tester,
        docWith([textNode('Привіт', id: 'hello')]),
        locale: 'ar',
      );

      expect(_directionAtText(tester), TextDirection.rtl);
    });

    testWidgets('the same document in Ukrainian stays left to right', (tester) async {
      await pumpDocument(
        tester,
        docWith([textNode('Привіт', id: 'hello')]),
        locale: 'uk',
      );

      expect(_directionAtText(tester), TextDirection.ltr);
    });

    /// The app LOCALE does not affect the document: an English app can
    /// show an Arabic screen and vice versa. A single shared direction would make
    /// this pair impossible, and it is the most common one.
    testWidgets('the document flips INDEPENDENTLY of the app around it', (tester) async {
      await pumpDocument(
        tester,
        docWith([textNode('Привіт', id: 'hello')]),
        locale: 'ar',
      );

      // The surrounding `MaterialApp` is LTR by default and the document inside
      // it is Arabic: exactly this pair proves the directions are independent.
      expect(_directionAtText(tester), TextDirection.rtl);
    });

    testWidgets('a document without a language stays left to right', (tester) async {
      await pumpDocument(tester, docWith([textNode('Привіт', id: 'hello')]));

      expect(_directionAtText(tester), TextDirection.ltr);
    });

    /// Direction was computed from the language the host ASKED for, while texts came
    /// from the one the document HAS. The fixture has no Arabic,
    /// so the screen is shown in English and must lay out as English.
    testWidgets('a language the document does not have does not flip the screen', (tester) async {
      await pumpDocument(tester, loadFixture('localized-promo'), locale: 'ar');

      expect(_directionAtFirstText(tester), TextDirection.ltr);
    });

    /// The flip side, without which the previous test would pass even on a renderer
    /// that flips nothing: the same fixture with an Arabic translation.
    testWidgets('a language the document has flips it', (tester) async {
      final json = jsonDecode(readFixture('localized-promo')) as Map<String, Object?>;
      final localization = json['localization']! as Map<String, Object?>;
      final strings = localization['strings']! as Map<String, Object?>;
      (localization['locales']! as List<Object?>).add('ar');
      strings['ar'] = strings['de'];

      await pumpDocument(tester, UiDocument.fromJson(json), locale: 'ar');

      expect(_directionAtFirstText(tester), TextDirection.rtl);
    });
  });
}

TextDirection _directionAtFirstText(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(Text).first));

/// Direction in effect at the place where the document label is drawn.
///
/// We ask the TEXT, not the root: between them sits everything that could
/// override the direction, and a check on the root would pass even when it
/// does not reach the content.
TextDirection _directionAtText(WidgetTester tester) =>
    Directionality.of(tester.element(find.text('Привіт').first));
