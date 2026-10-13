/// Which language to show the document in; mirror of the builder's `locale-resolve.ts` (schema
/// 9.1.0).
///
/// The host app gives the DEVICE locale (`ar-EG`, `ar_EG`, `AR-eg`), while the document has
/// translations under short codes (`ar`). Before 9.1.0 the contract was silent and the renderer compared
/// literally: `ar-EG` on a document with an `ar` translation showed the source language left to right.
/// Now the rule is part of the contract and this file is its second copy. Do not be "smarter" than the
/// reference implementation here: the shared case table
/// (`assets/contract/fixtures/locale/locale-cases.json`) is run by a test row by row.
///
/// Five statements, each with a row in `x-compatibility.policy` ([kLocalePolicy]):
///  1. the tag is normalized: `_` is the same as `-`, case does not matter;
///  2. lookup DROPS PARTS from the end (RFC 4647 Lookup): `ar-EG` gives `ar`;
///  3. the other way is NOT guessed: `ar` does not find `ar-EG`;
///  4. there is one answer per document (whoever calls it also keeps it);
///  5. direction follows the language of the shown text; date formatting uses the requested locale if
///     a translation was found, otherwise the source language.
///
/// Three clarifications (the policy rows are the same):
///  * the formatting locale is the longest prefix of the tag that is WELL-FORMED
///    ([wellFormedLocaleTag]): `ja_JP_JP` gives `ja-JP`; otherwise the date engine threw and the
///    screen with Japanese text showed an ISO string;
///  * `directionLocale` is the canonical form of the language of the shown text (`ks_IN` in the
///    document gives `ks-IN`), while `translation` stays the key as written;
///  * a tag longer than [kMaxLocaleTagLength] is not a tag, and the chain has no quadratic cost. A
///    fourth rule (a language with no string in `strings` is not a document language) lives in
///    `DocumentLocalization.availableLocales`.
///
/// KNOWN LIMIT that must not be fixed here: `zh-TW` falls back to `zh`. The platform
/// (`Locale.fromSubtags`, likely subtags) could give `zh-Hant`, but a rule that relies on platform data
/// would silently diverge between readers.
library;

import 'package:intl/intl.dart' show Bidi;

/// Mirror of the seven locale policy rows; checked against the artifact by a test.
const Map<String, String> kLocalePolicy = {
  'localeNormalization': 'underscore-as-hyphen-case-insensitive',
  'localeMatching': 'bcp47-lookup-truncate',
  'localeChildFallback': 'none',
  'unmatchedLocale': 'use-default-locale',
  'localeResolution': 'once-per-document',
  'directionFollows': 'shown-translation-locale',
  'formattingLocale': 'requested-when-matched-else-default',
};

/// Longest string considered a language tag at all (`MAX_LOCALE_TAG_LENGTH` of the reference
/// implementation). The longest tag in the IANA registry is thirty-five characters; a hundred leaves
/// room for extensions. A longer string is not a tag: the locale comes from the host, and sixty
/// kilobytes of it must not cost seconds of CPU.
const int kMaxLocaleTagLength = 100;

final RegExp _subtag = RegExp(r'^[A-Za-z0-9]{1,8}$');
final RegExp _language = RegExp(r'^[A-Za-z]{2,8}$');
final RegExp _script = RegExp(r'^[A-Za-z]{4}$');
final RegExp _region = RegExp(r'^[A-Za-z]{2}$');

/// A tag in canonical form, or `null` if it is not a language tag.
///
/// The canonical form follows BCP 47 convention: language lowercase, script capitalized (`Hant`), region
/// uppercase (`EG`), everything after a one-letter part lowercase. Comparison ignores case; the canonical
/// form exists so that the formatting locale is the same STRING in every reader. A non-tag (empty,
/// `ar--EG`, `x-ar`, not Latin) means "no language was requested".
String? normalizeLocaleTag(Object? raw) {
  if (raw is! String || raw.length > kMaxLocaleTagLength) return null;
  final parts = raw.trim().replaceAll('_', '-').split('-');
  if (!_language.hasMatch(parts.first)) return null;
  if (!parts.every(_subtag.hasMatch)) return null;

  var afterSingleton = false;
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (i == 0 || afterSingleton) {
      out.add(part.toLowerCase());
    } else if (part.length == 1) {
      afterSingleton = true;
      out.add(part.toLowerCase());
    } else if (_script.hasMatch(part)) {
      out.add('${part[0].toUpperCase()}${part.substring(1).toLowerCase()}');
    } else if (_region.hasMatch(part)) {
      out.add(part.toUpperCase());
    } else {
      out.add(part.toLowerCase());
    }
  }
  return out.join('-');
}

/// Lookup chain: the tag itself and everything left after dropping parts. `zh-Hant-TW` gives
/// `zh-Hant-TW`, `zh-Hant`, `zh`. A one-letter part that would be left last (`en-US-u`) is dropped
/// together with the preceding one.
///
/// Prefixes are taken by slicing at the hyphen position rather than rebuilt at every step (which would
/// cost quadratic time in the length). A tag longer than [kMaxLocaleTagLength] has no chain.
List<String> localeLookupChain(String normalized) {
  final chain = <String>[];
  if (normalized.length > kMaxLocaleTagLength) return chain;
  var end = normalized.length;
  while (end > 0) {
    chain.add(normalized.substring(0, end));
    end = normalized.lastIndexOf('-', end - 1);
    // A one-letter part is never left last: it goes together with the preceding one.
    while (end > 0 && (end == 1 || normalized[end - 2] == '-')) {
      end = normalized.lastIndexOf('-', end - 1);
    }
  }
  return chain;
}

/// Tag structure accepted by the date and number engine (BCP 47 as read by Unicode): a language (2-3
/// or 5-8 letters), then optional script (4 letters), region (2 letters or 3 digits), variants,
/// extensions (one letter and at least one part of 2-8 characters) and a private-use part `x-...`.
/// Applied to the CANONICAL form, word for word from the reference implementation.
final RegExp _wellFormed = RegExp(
  r'^(?:[a-z]{2,3}|[a-z]{5,8})(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?'
  r'(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*(?:-[a-wyz0-9](?:-[a-z0-9]{2,8})+)*'
  r'(?:-x(?:-[a-z0-9]{1,8})+)?$',
);

/// Longest prefix of a tag with a well-formed structure: `ja-JP-JP` gives `ja-JP`, `ar-EG-u` gives
/// `ar-EG`. `null` means there is no such prefix.
///
/// The question is about the STRUCTURE, not "does this engine accept it": another engine's answer
/// would differ, and the formatting locale would stop being the same string in every reader. An engine
/// that does not accept even such a tag drops parts further itself ([formatBoundValue]).
String? wellFormedLocaleTag(String? normalized) {
  if (normalized == null) return null;
  for (final candidate in localeLookupChain(normalized)) {
    if (_wellFormed.hasMatch(candidate)) return candidate;
  }
  return null;
}

/// Whether a language tag is written right to left, from CLDR data (`package:intl`). An unknown
/// language, `null` and garbage are left to right. No list of right-to-left languages is kept here:
/// a script, not a language, decides (`ku` is left to right, `ckb` is right to left).
bool isRtlLanguageTag(String? locale) {
  final tag = normalizeLocaleTag(locale);
  return tag != null && Bidi.isRtlLanguage(tag);
}

/// The one answer to "which language is this document shown in" for one
/// requested locale.
final class LocaleResolution {
  /// Creates an answer. Use `UiDocument.localeResolution`.
  const LocaleResolution({
    required this.translation,
    required this.formatting,
    required this.directionLocale,
    required this.matched,
  });

  /// The document's tag of the language the text is shown in; `null` when the
  /// document has no `localization`.
  final String? translation;

  /// The locale dates are formatted in: the requested one when a translation
  /// was found, the source language otherwise.
  final String? formatting;

  /// The locale whose script decides the writing direction: the language of
  /// the text that is actually shown.
  final String? directionLocale;

  /// Whether the requested locale found a language of the document.
  final bool matched;
}

/// Mirror of the reference implementation's `resolveLocale`.
///
/// [requested] is the host's locale as is (`Locale.toLanguageTag()` or `ar_EG`), [available] is
/// `localization.locales`, [source] is `defaultLocale` (`null` for a document without localization).
LocaleResolution resolveLocale(String? requested, List<String> available, String? source) {
  final asked = normalizeLocaleTag(requested);
  // The formatting locale is only a well-formed tag: otherwise the date engine throws on it.
  final askedFormat = wellFormedLocaleTag(asked);

  // A document without localization names no language: the only word about it is the host's.
  if (source == null) {
    return LocaleResolution(
      translation: null,
      formatting: askedFormat,
      directionLocale: askedFormat ?? asked,
      matched: false,
    );
  }

  String canonical(String locale) => normalizeLocaleTag(locale) ?? locale;
  final unmatched = LocaleResolution(
    translation: source,
    formatting: wellFormedLocaleTag(normalizeLocaleTag(source)) ?? canonical(source),
    directionLocale: canonical(source),
    matched: false,
  );
  if (asked == null) return unmatched;

  // Comparison key to DOCUMENT key; the first in the list wins over a twin that differs only in case.
  final keys = <String, String>{};
  for (final locale in [...available, source]) {
    final key = normalizeLocaleTag(locale)?.toLowerCase();
    if (key != null) keys.putIfAbsent(key, () => locale);
  }

  for (final candidate in localeLookupChain(asked)) {
    final found = keys[candidate.toLowerCase()];
    if (found != null) {
      final shown = canonical(found);
      return LocaleResolution(
        translation: found,
        formatting: askedFormat ?? wellFormedLocaleTag(shown) ?? shown,
        directionLocale: shown,
        matched: true,
      );
    }
  }
  return unmatched;
}
