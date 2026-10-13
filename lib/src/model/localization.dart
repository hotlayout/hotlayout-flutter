import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'compatibility.dart';
import 'locale_resolve.dart';
import 'style_values.dart' show isForbiddenKey;

/// The languages of a document and their translations.
///
/// The source-language text is the literal inside each node; [strings] holds
/// the other languages. Which language a device gets is decided by the
/// contract rule of schema 9.1.0 — see [resolve].
///
/// Why it is read separately from the text: `literal.value` stays what it was, the text of the source
/// language. Translations arrive as a separate section of the document, so a reader that does not know
/// about it draws the literals as before. This is why 7.2.0 is a minor, and why this file affects
/// nothing while the document has no `localization` (schema 7.2.0).
///
/// Why the key is a PLACE, not a text: `<screenId>/<nodeId>/<field path>`. A key by text would break on
/// the first typo fix in the original, and every translation would silently detach. Binding to the
/// place does not do that.
///
/// Why there is no index: the key is built during the walk, where the reader already stands on the
/// right field (see `node.dart`). A "key to node" index would be a second structure that can drift from
/// the tree, and it would have to be built for every document whether or not it has translations.
@immutable
final class DocumentLocalization {
  /// Creates a table. Normally parsed together with the document.
  const DocumentLocalization({
    required this.defaultLocale,
    required this.locales,
    required this.strings,
  });

  /// The source language: the language the node literals are written in.
  ///
  /// The source language is NOT in [strings], by contract: duplicating the source text in the table would
  /// be two sources of truth for one string that drift apart silently.
  final String defaultLocale;

  /// All languages of the document, [defaultLocale] included.
  ///
  /// The order belongs to the editor, not the reader: the reader takes exactly the language the user
  /// asks for and never "the next one in the list".
  final List<String> locales;

  /// Language → (place key → text), for every language but the source one.
  final Map<String, Map<String, String>> strings;

  /// "No localization": the value of a one-language document.
  static const DocumentLocalization? none = null;

  /// Reads the `localization` section. Never throws; an unusable section is `null`.
  static DocumentLocalization? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      if (kDebugMode) debugPrint('[hotlayout] localization is not an object: drawing the literals');
      return null;
    }
    final defaultLocale = raw['defaultLocale'];
    if (defaultLocale is! String || defaultLocale.isEmpty) {
      // Without a default language the table is meaningless: it is unknown what the translations differ
      // from and what to fall back to when a key is missing.
      if (kDebugMode) debugPrint('[hotlayout] localization has no defaultLocale: drawing the literals');
      return null;
    }

    final locales = <String>[
      for (final item in (raw['locales'] as List<Object?>? ?? const []))
        if (item is String && item.isNotEmpty) item,
    ];

    final strings = <String, Map<String, String>>{};
    if (raw['strings'] case final Map<Object?, Object?> table) {
      for (final entry in table.entries) {
        final locale = entry.key;
        final values = entry.value;
        if (locale is! String || isForbiddenKey(locale) || values is! Map) continue;
        strings[locale] = {
          for (final value in values.entries)
            if (value.key is String && !isForbiddenKey(value.key! as String) && value.value is String)
              value.key! as String: value.value! as String,
        };
      }
    }

    return DocumentLocalization(
      defaultLocale: defaultLocale,
      // The default language must be in the list (the contract says so), but the document comes from the
      // network, so checking is cheaper than trusting.
      locales: List.unmodifiable(locales.contains(defaultLocale) ? locales : [defaultLocale, ...locales]),
      strings: Map.unmodifiable({
        for (final entry in strings.entries) entry.key: Map<String, String>.unmodifiable(entry.value),
      }),
    );
  }

  /// Whether the document declares exactly this tag. No matching is applied.
  bool has(String locale) => locales.contains(locale);

  /// The translations to draw for [locale], found by [resolve].
  ///
  /// The default language gives an EMPTY table, and this is the same rule rather than a special case: its
  /// text lies in the node literals, so there is nothing to substitute.
  LocalizedStrings stringsFor(String? locale) {
    if (locale == null) {
      return LocalizedStrings(locale: null, table: const {}, sourceLocale: defaultLocale);
    }
    final resolution = resolve(locale);
    final shown = resolution.translation;
    if (shown == null || shown == defaultLocale) {
      // `fall-back-to-default-locale`: the document has no such language, so the literals are drawn, i.e.
      // the default language; not "the nearest one in the list".
      if (kDebugMode && !resolution.matched) {
        debugPrint('[hotlayout] the document has no language for "$locale" → source language');
      }
      // The table is empty, but the SOURCE language is named: the plural of a template agrees by its
      // rules (9.4.0).
      return LocalizedStrings(locale: null, table: const {}, sourceLocale: defaultLocale);
    }
    return LocalizedStrings(locale: shown, table: strings[shown] ?? const {}, sourceLocale: defaultLocale);
  }

  /// Matches a device locale to the languages of the document.
  ///
  /// The tag is normalised (`ar_EG` equals `ar-EG`), then subtags are dropped
  /// from the end until a language of the document matches: `ar-EG` finds `ar`.
  /// Never the other way round: `ar` does not find `ar-EG`. No match gives
  /// [defaultLocale].
  ///
  /// There is ONE answer per document (schema 9.1.0): whoever draws computes it once and hands out its
  /// three values (translation key, formatting locale, direction tag).
  LocaleResolution resolve(String? requested) =>
      resolveLocale(requested, availableLocales, defaultLocale);

  /// The languages the document really has: the source language, and every
  /// language of [locales] that has at least one translated string.
  ///
  /// A language of `locales` whose `strings` table is empty or missing is not considered a language of
  /// the document: all its text would be the source text anyway, and the direction and date format would
  /// be foreign to it (an English screen laid out right to left). The same resolves twins that differ in
  /// case (`ar-EG` and `ar-eg` in the list): the answer is the spelling under which translations EXIST,
  /// because that is the one the table is read by. The source language is always present: its texts are
  /// the document itself.
  List<String> get availableLocales => [
    for (final locale in locales)
      if (locale == defaultLocale || (strings[locale]?.isNotEmpty ?? false)) locale,
  ];

  /// The document's own tag the text is shown in for [requested]; [defaultLocale]
  /// when nothing matches.
  ///
  /// Since 9.1.0 this is not a literal match: `ar-EG` finds `ar` (dropping parts), and `ar` does NOT find
  /// `ar-EG`. The FORMATTING locale ([LocaleResolution.formatting]) stays separate and takes the region
  /// from the request.
  String shownLocale(String? requested) => resolve(requested).translation ?? defaultLocale;

  /// The locale to pass to `renderDocument` for a device's list of preferred
  /// languages.
  ///
  /// Walks [preferred] in order and returns the first locale the document has a
  /// language for — as the **requested** tag in canonical form (`ar-EG`, not
  /// `ar`), so that dates keep the regional format. Returns [defaultLocale] when
  /// nothing matches. To learn which translation is shown, ask
  /// [shownLocale].
  ///
  /// Since 9.1.0 this rule is part of the contract (`localeMatching`): [resolve] runs for each device
  /// language in turn, the first match wins, and with none the default language applies. It returns the
  /// REQUESTED tag (canonical, `pt-BR`) rather than the document key, so that the date format gets the
  /// region while `renderDocument` reduces it to the translation language itself.
  String localeFor(Iterable<Locale> preferred) {
    for (final locale in preferred) {
      final requested = locale.toLanguageTag();
      final resolution = resolve(requested);
      if (resolution.matched) return resolution.formatting ?? requested;
    }
    return defaultLocale;
  }
}

/// The translations of one language, as `renderScreen` takes them. Obtain it
/// from `UiDocument.stringsFor`.
///
/// A separate type rather than a `Map`, for exactly one policy row: [operator []] returns `null` for an
/// unknown key, and that `null` means "draw the node literal"
/// (`missingTranslation: 'fall-back-to-default-locale'`). A map can express it too, but then the rule
/// would live at every call site.
@immutable
final class LocalizedStrings {
  /// Creates a table for [locale].
  const LocalizedStrings({
    required this.locale,
    required Map<String, String> table,
    this.sourceLocale,
  }) : _table = table;

  /// No translations: every text is drawn as written in the document.
  ///
  /// Nothing to translate with: a document without localization, the default language, or a language the
  /// document lacks. All three draw the same thing, the literals, so the value is one.
  static const LocalizedStrings none = LocalizedStrings(locale: null, table: {});

  /// The document's tag of this language; `null` for the source language.
  final String? locale;

  /// The source language of the document the table was taken from; `null`
  /// when the document has no `localization`. Plural words that are not
  /// translated follow the rules of this language.
  ///
  /// It lives in the table rather than in a separate render parameter because the table is the answer to
  /// "which words do we draw with": a host that already passes `doc.stringsFor(locale)` to `renderScreen`
  /// gets plural agreement without adding anything.
  final String? sourceLocale;

  final Map<String, String> _table;

  /// Whether there is no translation at all.
  bool get isEmpty => _table.isEmpty;

  /// The translation for a place key, or `null`.
  ///
  /// `null` is neither an error nor rare: a partial translation is the normal state of a document in
  /// progress (the English of the `localized-promo` fixture is one). Every untranslated place shows the
  /// LITERAL, never the key, an empty string or the text of a neighbouring language.
  String? operator [](String? key) => key == null ? null : _table[key];

  /// The number of translated places.
  int get length => _table.length;

  /// The language whose script decides the direction of the text shown with these strings
  /// (`directionLocale` of the locale resolution): the translation's language, else the document's
  /// source language, else - a document without localization - [formatting], the locale the host asked.
  String? shownLanguage(String? formatting) => locale ?? sourceLocale ?? formatting;
}

/// Whether this code supports localization at all.
///
/// The question is not rhetorical: `x-compatibility.features` exists so that "the translation is not
/// shown because there is none" and "the translation is not shown because the app is old" can be
/// told apart.
bool get supportsLocalization => supportsFeature('localization');

/// Builder of localization keys: what the reader uses instead of an index.
///
/// The key is assembled in exactly one place in the program, on purpose: `screenId`, `nodeId` and the
/// field path are separated by `/` and the path within by `.`, and if it were assembled in two
/// different ways, half the translations would silently stop being found.
@immutable
final class LocalizationKeys {
  const LocalizationKeys(this.screenId);

  /// A document without translations. Then there are no keys at all: not empty strings but `null`,
  /// meaning "this field takes no part in substitution".
  static const LocalizationKeys off = LocalizationKeys(null);

  /// The screen whose nodes are being parsed, or `null` for "no keys are built".
  ///
  /// The screen is in the key because `nodeId` is unique within a SCREEN, not the document (a contract
  /// decision: a copy of a screen must stay valid). Without `screenId`, two screens with the same node
  /// ids would share one translation.
  final String? screenId;

  String? of(String nodeId, String path) {
    final screen = screenId;
    if (screen == null) return null;
    return '$screen/$nodeId/$path';
  }
}
