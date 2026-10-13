/// The writing direction of a document language.
///
/// There is no hand-written list of right-to-left languages. A list would have to be kept
/// identical in every reader of the contract (Flutter, web, builder) and would silently
/// diverge on whichever language one of them forgot. The answer comes from CLDR instead: on
/// the web via `Intl.Locale().textInfo`, here via `Bidi.isRtlLanguage` from `intl`; the data
/// underneath is the same, so there is nothing to agree on. That is why `intl` is a
/// dependency: the alternative is a private copy of knowledge that is already standardised.
///
/// Direction is a property of the SCRIPT, not the language: Kurdish in Latin script (`ku`) is
/// left to right, the same language in Arabic script (`ckb`) is right to left. A language list
/// cannot tell these apart.
library;

import 'package:flutter/widgets.dart';

import '../model/locale_resolve.dart';

/// The writing direction of a language tag, from CLDR data (`package:intl`).
///
/// An unknown language is [TextDirection.ltr]. `null`, an empty string and garbage also give
/// `ltr`: that is the right answer to "how to draw when no language was named", and the screen
/// stays usable instead of flipping at random.
TextDirection directionOfLocale(String? locale) =>
    // Same normalisation as the locale resolution rule: `ar_EG` and `AR-eg` are one tag.
    isRtlLanguageTag(locale) ? TextDirection.rtl : TextDirection.ltr;

/// Whether [locale] is written right to left. See [directionOfLocale].
bool isRtlLocale(String? locale) => directionOfLocale(locale) == TextDirection.rtl;
