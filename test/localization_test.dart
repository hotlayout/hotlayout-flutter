import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

/// Document localization guard (schema 7.2.0).
///
/// The main point here is not that "the translation got substituted" but what
/// does NOT happen: a mixture of languages. The policy `missingTranslation:
/// 'fall-back-to-default-locale'` says to fall back to the node literal, not to
/// the next language in the list, and no screenshot shows that difference —
/// it is only visible on a document with an INCOMPLETE translation. In the
/// `localized-promo` fixture the French one is incomplete on purpose.
void main() {
  UiDocument promo() => loadFixture('localized-promo');

  group('translation table is read', () {
    test('section parsed, default locale absent from the table', () {
      final table = promo().localization!;

      expect(table.defaultLocale, 'en');
      expect(table.locales, ['en', 'de', 'fr']);
      // A contract guarantee, not a fixture accident: the default-locale text
      // lives in the node literal, and duplicating it in the table would mean
      // two sources of truth for one string.
      expect(table.strings.containsKey('en'), isFalse);
      expect(table.strings.keys, containsAll(['de', 'fr']));
    });

    test('key is built during the walk — there is no index', () {
      // Key = `<screenId>/<nodeId>/<field path>`. Checked on the parsed tree:
      // that is where it must appear, because that is where the reader stands
      // on the needed field.
      final heading = flattenDocument(promo()).whereType<TextNode>().first;

      expect((heading.content as LiteralString).key, 'promo/promo-heading/content');
    });

    test('field path, not name: text inside a slot has a key too', () {
      final tile = flattenDocument(promo()).whereType<ListTileNode>().single;
      final trailing = tile.trailing as TrailingText;

      expect((trailing.text as LiteralString).key, 'promo/promo-item/trailing.text');
    });

    test('a document without a keys section builds none', () {
      // The most important compatibility check: 7.2.0 is a minor exactly because
      // a single-language document parses the same as before it.
      final plain = flattenDocument(docWith([textNode('Привіт')])).whereType<TextNode>().single;

      expect((plain.content as LiteralString).key, isNull);
      expect(docWith([textNode('Привіт')]).localization, isNull);
      expect(docWith([textNode('Привіт')]).stringsFor('de').isEmpty, isTrue);
    });

    test('a pre-7.2.0 document was read by a 7.x reader — a claim about the RULE', () {
      // The assertion had to be flipped on the 7.3.0 → 8.0.0 move, precisely
      // because it used to be about a CONSTANT: a 7.0.0 document was readable only
      // while the reader itself sat on seven. Now 7.0.0 is a foreign major, and
      // `isSupportedVersion` is honestly false on it. The claim the test really
      // wanted to make ("the localization section arrived as a minor, so a document
      // without it is readable by a reader that already knows it") does not depend
      // on the reader's version — so the reader is a parameter here, as in neighbouring tests.
      expect(
        checkSchemaVersion('7.0.0', readerVersion: '7.2.0'),
        VersionVerdict.ok,
        reason: 'localization was added as a minor — a document without it stayed readable',
      );
      expect(checkSchemaVersion('7.0.0').canRender, isFalse, reason: 'but major 8.0.0 is already foreign');

      // The second half of the claim is structural and lives on: a document WITHOUT
      // the section is parsed as if localization did not exist in the contract.
      final plain = docWith([textNode('Старий документ')]);

      expect(plain.isSupportedVersion, isTrue);
      expect(plain.localization, isNull);
      expect(
        (flattenDocument(plain).whereType<TextNode>().single.content).resolve(const ScreenData({})),
        'Старий документ',
      );
    });
  });

  group('translation substitution', () {
    testWidgets('the chosen locale replaces the literals', (tester) async {
      await pumpDocument(tester, promo(), locale: 'de');

      expect(find.text('Wochenendangebot'), findsOneWidget); // AppBar.title
      expect(find.text('Wählen Sie Ihre Belohnung des Monats'), findsOneWidget); // Text.content
      expect(find.text('Ausgewählt'), findsOneWidget); // ListTile.trailing.text
      expect(find.text('Neu'), findsOneWidget); // Badge.label
      expect(find.text('Bestätigen'), findsOneWidget); // Button.label

      // No originals left on screen — the translation REPLACES the literal.
      expect(find.text('Weekend offer'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
    });

    testWidgets('without a locale the literals are drawn, i.e. the default locale', (tester) async {
      await pumpDocument(tester, promo());

      expect(find.text('Weekend offer'), findsOneWidget);
      expect(find.text('Pick your reward of the month'), findsOneWidget);
    });

    testWidgets('explicit default locale — same as no locale', (tester) async {
      await pumpDocument(tester, promo(), locale: 'en');

      expect(find.text('Weekend offer'), findsOneWidget);
      // There is no table for it and there must not be, so nothing to substitute.
      expect(promo().stringsFor('en').isEmpty, isTrue);
    });

    testWidgets('locale absent from the document → literal, not blank and not a key', (tester) async {
      await pumpDocument(tester, promo(), locale: 'uk');

      expect(find.text('Weekend offer'), findsOneWidget);
      expect(find.text('promo/promo-bar/title'), findsNothing);
      expect(find.text(''), findsNothing);
    });

    testWidgets('key missing in the chosen locale → THIS node\'s literal', (tester) async {
      // The French one in the fixture is incomplete: `promo-bar/subtitle` and
      // `promo-badge/label` are not translated in it.
      await pumpDocument(tester, promo(), locale: 'fr');

      // Translated — in French…
      expect(find.text('Offre du week-end'), findsOneWidget);
      expect(find.text('Choisissez votre récompense du mois'), findsOneWidget);
      // …untranslated — the literal, i.e. the default locale.
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('a partial translation is NOT completed from a neighbouring locale', (tester) async {
      // The costliest test in the file. A chain "not in en → take from kk" looks
      // helpful and yields a screen that is partly English, partly Kazakh — while
      // both languages are in the document, so the mistake does not look like one.
      await pumpDocument(tester, promo(), locale: 'fr');

      expect(find.text('Oktober 2026'), findsNothing); // de translation of the subtitle
      expect(find.text('Neu'), findsNothing); // de translation of the badge
      expect(find.text('Kabellose Kopfhörer'), findsNothing); // de translation of the caption
    });

    testWidgets('bound text is not translated — its source is in the data', (tester) async {
      // The localization boundary, which should be said out loud: `{kind:'binding'}`
      // takes text from the data at runtime, so the data source has to be
      // translated, not the document. The builder draws the line the same way.
      await pumpDocument(
        tester,
        promo(),
        locale: 'de',
        data: const {
          'offer': {'description': 'Zahlen Sie am Wochenende mit Ihrer Karte'},
        },
      );

      expect(find.text('Zahlen Sie am Wochenende mit Ihrer Karte'), findsOneWidget);
      final amount = flattenDocument(promo()).whereType<TextNode>().toList()[1];
      expect(amount.content, isA<BoundString>());
    });
  });

  group('locale selection', () {
    // 9.1.0: `localeFor` returns the REQUESTED tag (canonical), not the document
    // key — the date format takes its region from it. Which translation goes
    // with it is asked from `shownLocale`.
    test('the full device tag beats the bare language', () {
      final table = DocumentLocalization.parse(const {
        'defaultLocale': 'en',
        'locales': ['en', 'pt', 'pt-BR'],
        // The document language is the one that has at least one string.
        'strings': {
          'pt': {'s/t/content': 'x'},
          'pt-BR': {'s/t/content': 'x'},
        },
      })!;

      expect(table.localeFor([const Locale('pt', 'BR')]), 'pt-BR');
      expect(table.shownLocale('pt-BR'), 'pt-BR');
      // Used to be `'pt'` — the document key; now the requested tag, same key.
      expect(table.localeFor([const Locale('pt', 'PT')]), 'pt-PT');
      expect(table.shownLocale('pt-PT'), 'pt');
      expect(table.localeFor([const Locale('pt')]), 'pt');
    });

    test('no device locale matched → default locale', () {
      final table = promo().localization!;

      expect(table.localeFor([const Locale('uk'), const Locale('pl')]), 'en');
      expect(table.localeFor(const []), 'en');
      // Used to be `'de'`: the region stays in the request, the translation is `de`.
      expect(table.localeFor([const Locale('de', 'AT')]), 'de-AT');
      expect(table.shownLocale('de-AT'), 'de');
    });

    test('device preference order is respected', () {
      final table = promo().localization!;

      expect(table.localeFor([const Locale('pl'), const Locale('fr')]), 'fr');
    });
  });

  group('what is NOT translated', () {
    test('the selected option name has no key: translating it would break the choice', () {
      // `ChoiceGroup.value` is compared with the row's `optionValue`. In the
      // builder registry this field is `localizable: false` too, for the same reason.
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'choice',
        'name': 'Вибір',
        'initialScreenId': 's',
        'screens': [
          screenEntry('s', [
            choiceGroupNode(
              [optionNode('Навушники', optionValue: 'headphones')],
              value: const {'kind': 'literal', 'value': 'headphones'},
            ),
          ]),
        ],
        'localization': {
          'defaultLocale': 'en',
          'locales': ['en', 'de'],
          'strings': <String, Object?>{},
        },
      });

      final group = flattenDocument(doc).whereType<ChoiceGroupNode>().single;
      expect((group.value as LiteralString).key, isNull);
      // But the row's own label is translatable.
      final tile = flattenDocument(doc).whereType<ListTileNode>().single;
      expect((tile.title as LiteralString).key, 's/opt-headphones/title');
    });
  });

  group('a corrupted section does not break display', () {
    test('not an object, no defaultLocale, junk in the table', () {
      expect(DocumentLocalization.parse(null), isNull);
      expect(DocumentLocalization.parse('kk'), isNull);
      expect(DocumentLocalization.parse(const {'locales': <String>[]}), isNull);

      final salvaged = DocumentLocalization.parse(const {
        'defaultLocale': 'en',
        // The default locale is absent from the list — the contract will not emit
        // that, but the document comes from the network, so we recover, not reject.
        'locales': ['de'],
        'strings': {
          'de': {'s/n/title': 'Überschrift', 's/n/broken': 42},
          'bad': 'не таблиця',
        },
      })!;

      expect(salvaged.locales, ['en', 'de']);
      expect(salvaged.stringsFor('de')['s/n/title'], 'Überschrift');
      // A non-string value in the table simply does not make it in.
      expect(salvaged.stringsFor('de')['s/n/broken'], isNull);
      expect(salvaged.stringsFor('bad').isEmpty, isTrue);
    });
  });

  group('capability catalog', () {
    test('the renderer declares that it supports localization', () {
      // Not rhetoric: without this block "translation not shown because there is none"
      // and "translation not shown because the app is old" look the same.
      expect(supportsLocalization, isTrue);
    });

    test('fewer than two locales for the switcher — nothing to switch', () {
      // After 7.3.0 `reward-catalog-screens` has a localization section with one language.
      expect(loadFixture('reward-catalog-screens').localization, isNotNull);
      expect(loadFixture('reward-catalog-screens').locales, isEmpty);
      expect(promo().locales, ['en', 'de', 'fr']);
    });
  });
}
