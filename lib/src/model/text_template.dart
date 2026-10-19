/// Template text and plurals (schema 9.4.0): how a `kind: 'template'` string becomes text.
/// Mirrors the reference implementation `text-template.ts`; the shape lives in `bindable.dart`
/// (`TemplateString`), this file holds the rule with no widget involved.
///
/// Why it exists: a string used to be either a literal or ONE binding. A real screen says
/// "3 / 5 steps", "4 days left", "1 850 points", which meant gluing several texts in a row that a
/// translator could not reorder, and a word like "days" could not agree with the number at all.
///
/// Three decisions in this file that are easy to "simplify" back:
///
///  1. Substitution is ONE regular-expression pass over the string; the result is collected into
///     a buffer and never parsed again. A data value of `{total}` stays the text `{total}`, and
///     a string with thousands of places costs linear time.
///
///  2. We ask `intl` for the plural category by NAME, and choose the form ourselves.
///     `Intl.pluralLogic`, given the real forms, is wrong twice:
///      - by default it treats `zero` / `one` / `two` as the EXACT numbers 0 / 1 / 2 in every
///        language (English "0 points" would become "no points");
///      - for category `two` without a form it returns `few`, not `other`
///        (`two ?? few ?? other`), while the contract says `missingPluralForm: 'use-other'`.
///     So it is given category NAMES, not forms (`zero: 'zero', one: 'one', ...`), with
///     `useExplicitNumberCases: false`: the answer is the honest CLDR category and neither
///     "improvement" reaches the forms. We do not import `package:intl/src/plural_rules.dart`
///     directly: it is an internal directory of someone else's package.
///
///  3. We look up the language for the rules ourselves, with the same chain as the document
///     language ([localeLookupChain]), and `intl` is only given a tag it HAS; if none is found
///     the result is `other`. Its own lookup for `null` takes the DEVICE language and, on
///     failure, walks its own fallbacks, whose order has changed between package versions. On
///     `intl` 0.20.3 both lookups agree on the tags checked (removing the gate does not fail the
///     tests: it is an equivalent mutant, not a test gap); the gate is there so the answer does
///     not depend on the next version of a third-party package.
library;

import '../report/report_hub.dart';
import 'package:intl/intl.dart';

import 'binding_format.dart';
import 'locale_resolve.dart';
import 'plural_rules.dart';

/// Mirror of the nineteen policy rows of 9.4.0; checked against the artifact by a test
/// (`template_cases_test.dart`), and the behaviour of each row is pinned by the case table.
const Map<String, String> kTemplatePolicy = {
  'unknownStringKind': 'render-empty',
  'undeclaredPlaceholder': 'render-literally-with-braces',
  'unusedTemplateValue': 'allowed-not-shown',
  'missingTemplateValue': 'value-fallback-keep-sentence',
  'missingCurrencyCode': 'render-as-is',
  'pluralCategory': 'cldr-cardinal-categories-not-exact-numbers',
  'pluralNumber': 'absolute-value-rounded-to-three-fraction-digits',
  'missingPluralForm': 'use-other',
  'pluralLanguage': 'language-of-shown-forms',
  'pluralWithoutNumber': 'use-other',
  'pluralWithoutLanguage': 'use-other',
  'daysUntil': 'ceil-of-remaining-24h-not-below-zero',
  'readerClock': 'injectable-read-at-render',
  // Six cases the contract had been silent about, now named.
  'unknownTemplateValueKind': 'render-empty',
  'emptyBoundString': 'use-fallback',
  'dateValueForm': 'iso-8601-with-time-and-zone-else-as-is',
  'pluralNumberWithoutData': 'numeric-fallback-else-other',
  'numberBeyondSafeInteger': 'render-as-is',
  'missingNumberLocaleData': 'render-as-is-days-as-plain-integer',
};

/// Five further policy rows of 9.4.0 (dates, calendar, rounding, plural operands); checked against
/// the artifact by a test, and the behaviour is pinned by the `CLARIFIED-2` rows of the case table.
const Map<String, String> kTemplateClarifiedPolicy = {
  'missingDateLocaleData': 'render-as-is',
  'dateCalendar': 'gregory',
  'dateValueValidity': 'calendar-checked-by-reader-code',
  'numberRounding': 'half-away-from-zero-over-shortest-decimal',
  'pluralFractionOperands': 'cldr-with-fraction-digits',
};

/// Pattern of a value name (`x-template.valueNamePattern`).
const String kTemplateValueNamePattern = r'^[a-z][A-Za-z0-9]{0,23}$';

/// CLDR plural categories in standard order (`x-template.pluralCategories`).
const List<String> kPluralCategories = ['zero', 'one', 'two', 'few', 'many', 'other'];

/// The category that answers every "don't know": no form, no number, no language.
const String kPluralOther = 'other';

/// Fraction digits of the number a form is chosen by (`x-template.pluralNumber`): exactly as many
/// as the `number` format writes.
const int kPluralNumberFractionDigits = 3;

// The same name pattern as in the schema, without anchors and with a capture group.
final RegExp _placeholder = RegExp(r'\{([a-z][A-Za-z0-9]{0,23})\}');

/// A piece of a template string in LOGICAL order: [place] is the name of the declared place it
/// came from, or `null` for literal text.
///
/// Rich text (9.6.0) splits a string into runs with the SAME parser as substitution: there is no
/// second parser that looks for places for the sake of styles.
typedef TemplateRun = ({String text, String? place});

/// The string split into runs: literal text and the content of each DECLARED place (the "places"
/// step of the rule).
///
/// [declared] tells whether the name is an OWN key of `values`; [textOf] gives the text of a
/// declared value. A place with an undeclared name stays literal text, braces included
/// (`undeclaredPlaceholder`): a translator who wrote `{dayz}` sees `{dayz}` on screen, not an
/// empty place.
///
/// [textOf] is called once per NAME, not once per place: a place may repeat thousands of times,
/// and the value (with its format and clock) does not change. The result has no empty runs;
/// adjacent runs are not merged (rich text does that, since only it knows the styles).
List<TemplateRun> templateRuns(
  String template, {
  required bool Function(String name) declared,
  required String Function(String name) textOf,
}) => [
  for (final run in partedTemplateRuns(
    template,
    declared: declared,
    piecesOf: (name) => [(text: textOf(name), part: null)],
  ))
    (text: run.text, place: run.place),
];

/// A run of a template string with the part of a formatted number it is (9.19.0): [part] is `null` for
/// literal text, a word and the rest of a number.
typedef PartedRun = ({String text, String? place, AmountPart? part});

/// [templateRuns] where the content of a place may come in PIECES (`x-money.parts`): a formatted amount
/// is the integer digits, the fraction and the currency, each with its part. Pieces of one place keep
/// their order; empty ones are dropped.
List<PartedRun> partedTemplateRuns(
  String template, {
  required bool Function(String name) declared,
  required List<AmountPiece> Function(String name) piecesOf,
}) {
  // The most common template has no braces at all: do not parse it.
  if (!template.contains('{')) return template.isEmpty ? const [] : [(text: template, place: null, part: null)];

  final runs = <PartedRun>[];
  final pieces = <String, List<AmountPiece>>{};
  var cursor = 0;
  void literal(int end) {
    if (end > cursor) runs.add((text: template.substring(cursor, end), place: null, part: null));
  }

  for (final match in _placeholder.allMatches(template)) {
    final name = match.group(1)!;
    if (!declared(name)) continue;
    literal(match.start);
    for (final piece in pieces[name] ??= piecesOf(name)) {
      if (piece.text.isNotEmpty) runs.add((text: piece.text, place: name, part: piece.part));
    }
    cursor = match.end;
  }
  literal(template.length);
  return runs;
}

/// The string with values substituted: the [templateRuns] joined.
String substituteTemplate(
  String template, {
  required bool Function(String name) declared,
  required String Function(String name) textOf,
}) {
  // The most common template has no braces at all: do not parse it.
  if (!template.contains('{')) return template;
  return templateRuns(template, declared: declared, textOf: textOf).map((run) => run.text).join();
}

/// The number a form is chosen by: the absolute value rounded to three fraction digits, i.e. as
/// the `number` format writes it. 1.0004 is written "1" and agrees as 1, whatever format the
/// value itself has.
num pluralNumber(num value) {
  final magnitude = value.abs();
  if (magnitude is int) return magnitude;
  // The same rounding as the number on screen: half away from zero over the shortest decimal
  // representation, not binary arithmetic.
  final rounded = roundHalfAwayFromZero(magnitude, kPluralNumberFractionDigits);
  return num.tryParse('${rounded.integer}.${rounded.fraction}') ?? magnitude;
}

/// How many fraction digits [pluralNumber] has WITHOUT trailing zeros: the CLDR operand `v`
/// (`pluralFractionOperands: 'cldr-with-fraction-digits'`). `fr` 1.5 gives `one`, `hi` 0.5 gives
/// `one`, and an integer has 0 digits.
int pluralFractionDigits(num value) {
  final magnitude = value.abs();
  if (magnitude is int) return 0;
  final fraction = roundHalfAwayFromZero(magnitude, kPluralNumberFractionDigits).fraction;
  return fraction.replaceFirst(RegExp(r'0+$'), '').length;
}

/// The language for plural rules in `intl` notation, or `null` if `intl` does not know it.
///
/// We ask `NumberFormat.localeExists`: the set of languages with number symbols is contained in
/// the set of languages with plural rules (pinned by `template_text_test.dart`, which reads both
/// tables of the package). The public `intl` API has no direct "are there rules" query.
String? _pluralLocaleFor(String locale) {
  final normalized = normalizeLocaleTag(locale);
  if (normalized == null) return null;
  for (final candidate in localeLookupChain(normalized)) {
    final underscored = candidate.replaceAll('-', '_');
    if (NumberFormat.localeExists(underscored)) return underscored;
  }
  return null;
}

/// The plural category of a number in a language: the CLDR cardinal rules.
///
/// [locale] is the translation table key as the document writes it (`uk`, `pt-BR`), or the source
/// language. `null`, a non-tag and a language `intl` does not know give `other`, NOT the rules of
/// the device language.
String pluralCategoryOf(num value, String? locale) {
  if (locale == null || !value.isFinite) return kPluralOther;
  final tag = _pluralLocaleFor(locale);
  if (tag == null) return kPluralOther;
  try {
    final rule = _pluralRuleFor(tag);
    // We compute the CLDR operands ourselves: `Intl.pluralLogic` takes the integer part as
    // `n.round()` (1.5 -> 2, 0.5 -> 1) and the fraction from double arithmetic, so `fr` 1.5 would
    // come out `other`, and so would `hi` 0.5. The rule conditions come from `intl` verbatim
    // (generated `plural_rules.dart`); the operands are ours.
    final number = pluralNumber(value);
    final rounded = roundHalfAwayFromZero(number, kPluralNumberFractionDigits);
    final visible = rounded.fraction.replaceFirst(RegExp(r'0+$'), '');
    final f = visible.isEmpty ? 0 : int.parse(visible);
    return rule(number, int.parse(rounded.integer), visible.length, f, f);
  } catch (error) {
    // A document from the network must not be able to crash the screen: a number the rules
    // cannot handle agrees as `other`.
    ReportHub.ignored('plural form', 'the category failed for locale "$locale" ($error): "other" is used');
    return kPluralOther;
  }
}

/// The rule for a language in `intl` notation (`pt_BR`): exact entry, then the short language,
/// then `default` (`other`), the same order as in `intl`.
PluralRuleFn _pluralRuleFor(String tag) {
  final short = tag.split('_').first;
  return kPluralRules[tag] ?? kPluralRules[short] ?? kPluralRules['default']!;
}

/// The plural form for a number: the category of the language; without a number, a language or a
/// form it is `other` (three policy rows, one answer).
String pluralFormFor(num? count, Map<String, String> forms, String? locale) {
  final other = forms[kPluralOther] ?? '';
  if (count == null) return other;
  return forms[pluralCategoryOf(count, locale)] ?? other;
}
