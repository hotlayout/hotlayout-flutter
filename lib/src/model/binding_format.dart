/// The format of a bound value (schema 8.20.0): how a value from data becomes
/// text.
///
/// Mirror of the builder's `binding-format.ts`. The contract used to say WHAT to
/// substitute into text and said nothing about HOW to show it: a date in data is
/// an ISO string, and the screen would draw `2026-10-31T23:59:59.000Z` as is.
///
/// WHY THERE IS NO TEMPLATE HERE. The document names an INTENT ("date", "date
/// and time", "time") and CLDR, through `intl`, supplies the look, exactly as
/// the writing direction does in `direction.dart`. Day/month order, month names
/// and 12 or 24 hours are properties of the LANGUAGE; a custom template would
/// drift from the web at the first language, silently.
///
/// WHY EVERYTHING ENDS IN `null` AND NOT IN AN EXCEPTION. Both policy rows say
/// `render-as-is`:
///  * `unknownBindingFormat`: a format from a newer minor version.
///    [BindingFormat.parse] returns `null` and the binding behaves as if the
///    field were absent;
///  * `unparsableBoundValue`: the value does not parse as a date.
///    [formatBoundValue] returns `null` and the caller shows the value as is.
/// An ISO string on screen is ugly but truthful; an empty place would hide a
/// value that is in the data.
///
/// NUMBERS (9.4.0). Three words answer the same question as the date formats:
///  * `number`: the display language's group separators and decimal sign,
///    groups ALWAYS, from zero to three fraction digits
///    (`NumberFormat.decimalPattern`);
///  * `currency`: number, U+00A0, currency code ("120 JOD"). The composition is
///    the same in every language; as many fraction digits as the currency has,
///    and a whole amount without them. `NumberFormat.currency().format` is NOT
///    used: it writes "JOD120.000";
///  * `daysUntil`: the whole days up to the instant, rounded up and not below
///    zero; the clock is a parameter and the time zone is not part of the rule.
/// The parameters are in the artifact as structure (`x-template`), not only as
/// words; the case table is shared with the web:
/// `fixtures/template/template-cases.json`.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'date_parts.dart';
import 'locale_resolve.dart';

part 'money_format.dart';

/// The format of a binding. The list is closed and short, by decision of the contract.
enum BindingFormat {
  date('date'),
  dateTime('dateTime'),
  time('time'),
  // 9.4.0, numbers: what text a number, an amount and a future instant become.
  number('number'),
  currency('currency'),
  daysUntil('daysUntil');

  const BindingFormat(this.wire);

  /// The word the document uses for the format.
  final String wire;

  /// The format from the document, or `null` for "no format".
  ///
  /// An absent field and an UNKNOWN word give the same result, deliberately:
  /// the policy `unknownBindingFormat: 'render-as-is'` says that a reader that
  /// does not know a format shows the value as if the field were absent. So
  /// parsing neither throws nor spoils the neighbouring fields of the binding,
  /// the same device as `AlwaysVisibleCondition` for an unknown condition
  /// operator.
  static BindingFormat? parse(Object? raw) {
    if (raw == null) return null;
    for (final format in values) {
      if (format.wire == raw) return format;
    }
    if (kDebugMode) {
      debugPrint('[hotlayout] unknown binding format "$raw": the value is shown as is');
    }
    return null;
  }
}

/// Whether the date data for all CLDR languages that `intl` ships is loaded.
///
/// Without it `DateFormat` knows only `en_US` and throws for any other language.
/// `initializeDateFormatting` is asynchronous by signature, but it fills the
/// tables SYNCHRONOUSLY and returns an already completed `Future`; that is what
/// makes the format work from the very first frame, with no "wait for
/// initialization" in the host. If the package ever changes this, the first
/// frame shows the value as is (there is a `try` below), and
/// `binding_format_test.dart` would notice: it asks for Ukrainian synchronously.
///
/// A host that already wired up `flutter_localizations` loses nothing: the
/// tables are the same, just complete.
bool _dateDataReady = false;

void _ensureDateData() {
  if (_dateDataReady) return;
  _dateDataReady = true;
  initializeDateFormatting();
}

/// The locale for `DateFormat` from a contract tag (`ar-EG`, `ar_EG`, `AR-eg`).
/// The caller filters out an empty [locale] earlier.
///
/// `DateFormat` expects an underscore form and must have data for that locale.
/// Data for the full tag may be missing (`en-US-u-ca-gregory`, a rare region);
/// then parts are dropped by the SAME chain as the language lookup
/// ([localeLookupChain]) until `DateFormat.localeExists` says yes. If nothing
/// is found the result is `null`: the format does not apply and the value is
/// shown as is (as for a language `intl` does not know at all). A blank
/// [locale] gives `null`, meaning the current `intl` language.
String? _dateLocaleFor(String? locale) {
  final normalized = normalizeLocaleTag(locale);
  if (normalized == null) return null;
  for (final candidate in localeLookupChain(normalized)) {
    final underscored = candidate.replaceAll('-', '_');
    if (DateFormat.localeExists(underscored)) return underscored;
  }
  return null;
}

/// A "day" of the `daysUntil` format: exactly 24 hours, not a calendar day
/// (`x-template.daysUntil.dayMilliseconds`).
const int kDayMilliseconds = 86400000;

/// Between the amount and the currency code goes a non-breaking space, so the
/// code does not wrap onto the next line (`x-template.currency.separator`).
const String kCurrencyCodeSeparator = '\u00A0';

/// How many fraction digits a currency unknown to `intl` has.
const int kCurrencyDefaultFractionDigits = 2;

/// The most fraction digits in the `number` format. It is what the pattern
/// `#,##0.###` of `NumberFormat.decimalPattern` already says; it is named
/// because the rounding of a number for a plural rests on it too.
const int kNumberFormatMaxFractionDigits = 3;

/// THE MAGNITUDE LIMIT (`x-template.number.maximumAbsoluteValue`, 2^53 - 1;
/// policy `numberBeyondSafeInteger: 'render-as-is'`). A larger absolute value
/// means `number` and `currency` do not apply (the value is shown as is) and
/// there is no number for a plural (`other`). Exactly at the limit the format
/// still applies.
///
/// The contract names the limit because `NumberFormat` silently writes
/// 922,337,203,685,477,580,700 in place of 1e21 beyond int64, while the web has
/// no exact integers beyond 2^53. One limit means the same screen in both.
const int kNumberFormatMaxAbsolute = 9007199254740991;

/// WHAT COUNTS AS A DATE (`x-template.dateTimePattern`, policy
/// `dateValueForm`): ISO 8601 with a time and a zone. ONE form for `date`,
/// `dateTime`, `time` and `daysUntil`. The expression comes first, then the
/// platform parse: `DateTime.tryParse` by itself reads `2026-10-14` as local
/// midnight, and also `20261014T090000Z` and a date with a space, which the web
/// does not read or reads differently.
const String kDateTimePattern =
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$';

final RegExp _dateTime = RegExp(kDateTimePattern);

/// The calendar of dates (`x-template.dateCalendar`): Gregorian. `intl` knows no
/// other, and Thai and Persian need not show 2569 and 1405.
const String kDateCalendar = 'gregory';

/// The limits of the date groups and the day rule (`x-template.dateCalendarCheck`);
/// a mirror for the test against the artifact. The code checks them in [_momentOf].
const Map<String, Object?> kDateCalendarCheck = {
  'month': {'min': 1, 'max': 12},
  'hour': {'min': 0, 'max': 23},
  'minute': {'min': 0, 'max': 59},
  'second': {'min': 0, 'max': 59},
  'offsetHour': {'min': 0, 'max': 23},
  'offsetMinute': {'min': 0, 'max': 59},
  'day': 'one-to-days-in-this-month-of-this-year-gregorian-leap-rule',
};

/// Rounding of a number and an amount (`x-template.rounding`): [roundHalfAwayFromZero].
const Map<String, String> kNumberRounding = {
  'mode': 'half-away-from-zero',
  'over': 'shortest-round-trip-decimal-string',
};

final RegExp _currencyCode = RegExp(r'^[A-Z]{3}$');

/// Whether this is an ISO 4217 currency code by form: three uppercase Latin
/// letters. The contract has no list of codes.
bool isCurrencyCode(Object? value) => value is String && _currencyCode.hasMatch(value);

/// The instant for a value from data, or `null` when it is not a date.
///
/// TWO checks, and the second does not replace the first
/// (`dateValueValidity: 'calendar-checked-by-reader-code'`): the expression
/// [kDateTimePattern] speaks only of the FORM, while Dart's `DateTime.parse`
/// reads month 13 as January and 30 February as 2 March (as V8 does). So the
/// code checks the groups against `x-template.dateCalendarCheck`: month 1-12,
/// day from 1 to the days in this month of this year (the Gregorian leap rule),
/// hour 0-23, minute and second 0-59, offset hours 0-23 and minutes 0-59. Not
/// a date means "as is".
DateTime? _momentOf(Object? value) {
  if (value is! String || !_dateTime.hasMatch(value)) return null;
  int at(int from, int to) => int.parse(value.substring(from, to));
  final year = at(0, 4);
  final month = at(5, 7);
  final day = at(8, 10);
  if (month < 1 || month > 12 || day < 1 || day > _daysInMonth(year, month)) return null;
  if (at(11, 13) > 23 || at(14, 16) > 59) return null;
  // Seconds only when present (`:ss` after the minutes); fractions of a second follow.
  if (value.length > 16 && value[16] == ':' && at(17, 19) > 59) return null;
  if (!value.endsWith('Z')) {
    final offset = value.length - 6;
    if (at(offset + 1, offset + 3) > 23 || at(offset + 4, offset + 6) > 59) return null;
  }
  return DateTime.tryParse(value);
}

int _daysInMonth(int year, int month) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  return month == 2 && leap ? 29 : days[month - 1];
}

/// A number from data that formats and plurals accept at all: finite and within
/// the limit BY ABSOLUTE VALUE (`-9007199254740994` is "as is" too; in Dart
/// `int.abs()` of `-9223372036854775808` stays negative, so both sides are compared).
num? _formattableNumber(Object? value) {
  if (value is! num || !value.isFinite) return null;
  if (value > kNumberFormatMaxAbsolute || value < -kNumberFormatMaxAbsolute) return null;
  return value;
}

/// The decimal form of a number, rounded to [fractionDigits] fraction digits by
/// the "half away from zero" rule over the SHORTEST decimal form of the number
/// (`numberRounding: 'half-away-from-zero-over-shortest-decimal'`).
///
/// Binary arithmetic in `NumberFormat` is wrong here: `1.005` sits in memory as
/// 1.00499999999999989... and `toStringAsFixed(2)` gives `1.00`, while a person
/// (and the web reader) sees `1.005` become `1.01`. `double.toString()` gives
/// exactly the shortest form that reads back as the same number, so the
/// calculation works on that string.
///
/// Returns the integer part and a fraction part of exactly [fractionDigits]
/// digits; [negative] is the sign of the input (`-0.0004` keeps its minus, as
/// the web's `Intl` does: "-0").
({bool negative, String integer, String fraction}) roundHalfAwayFromZero(num value, int fractionDigits) {
  final negative = value.isNegative;
  final plain = _plainDecimal(value.abs());
  final dot = plain.indexOf('.');
  var integer = dot < 0 ? plain : plain.substring(0, dot);
  var fraction = dot < 0 ? '' : plain.substring(dot + 1);
  if (fraction.length > fractionDigits) {
    final up = fraction.codeUnitAt(fractionDigits) >= 0x35; // '5'
    fraction = fraction.substring(0, fractionDigits);
    if (up) {
      final bumped = (BigInt.parse('$integer$fraction') + BigInt.one).toString().padLeft(
        integer.length + fractionDigits,
        '0',
      );
      integer = bumped.substring(0, bumped.length - fractionDigits);
      fraction = bumped.substring(bumped.length - fractionDigits);
    }
  } else {
    fraction = fraction.padRight(fractionDigits, '0');
  }
  return (negative: negative, integer: integer, fraction: fraction);
}

/// The shortest form of a non-negative number WITHOUT an exponent: `1e-7` becomes
/// `0.0000001`, `1.5e+21` becomes `1500000000000000000000`.
String _plainDecimal(num magnitude) {
  final text = magnitude.toString();
  final e = text.indexOf('e');
  if (e < 0) return text;
  final mantissa = text.substring(0, e);
  final exponent = int.parse(text.substring(e + 1));
  final dot = mantissa.indexOf('.');
  final digits = mantissa.replaceFirst('.', '');
  final integerLength = (dot < 0 ? mantissa.length : dot) + exponent;
  if (integerLength <= 0) return '0.${'0' * -integerLength}$digits';
  if (integerLength >= digits.length) return digits + '0' * (integerLength - digits.length);
  return '${digits.substring(0, integerLength)}.${digits.substring(integerLength)}';
}

/// The NUMBER a value becomes under this format: what the format writes and what
/// selects a plural form. `null` means there is no number: the value is not a
/// number (the string "12" is NOT a number; the backend has to send a number as
/// a number), it is not finite, the date does not parse, or the format is not
/// numeric.
///
/// Without a format a number from data stays itself: "{count} {unit}" has to
/// agree even where group separators were not asked for.
///
/// `daysUntil`: `max(0, ceil((instant - now) / 24 h))`. The DURATION is rounded
/// up; this is not a difference of calendar dates, and the time zone is not
/// part of the rule. The calculation is in milliseconds, as in the reference
/// implementation: Dart microseconds would give a different number from the
/// web at a day boundary.
num? numericBoundValue(Object? value, BindingFormat? format, {DateTime? now}) {
  switch (format) {
    case BindingFormat.daysUntil:
      final moment = _momentOf(value);
      if (moment == null) return null;
      final left = moment.millisecondsSinceEpoch - (now ?? DateTime.now()).millisecondsSinceEpoch;
      return left <= 0 ? 0 : (left / kDayMilliseconds).ceil();
    case null || BindingFormat.number || BindingFormat.currency:
      return _formattableNumber(value);
    case BindingFormat.date || BindingFormat.dateTime || BindingFormat.time:
      return null;
  }
}

/// The locale for `NumberFormat`: the same lookup as for dates, but against the
/// table of number symbols.
String? _numberLocaleFor(String locale) {
  final normalized = normalizeLocaleTag(locale);
  if (normalized == null) return null;
  for (final candidate in localeLookupChain(normalized)) {
    final underscored = candidate.replaceAll('-', '_');
    if (NumberFormat.localeExists(underscored)) return underscored;
  }
  return null;
}

/// Fraction digits of a currency, from the `intl` package's table; two when
/// there is no entry. There is no table of our own: it would go stale at the
/// first ISO 4217 change.
int _currencyFractionDigits(String code) {
  try {
    // The locale is named explicitly so `intl` does not look up the current
    // one: only the digit count is needed here, and it does not depend on the language.
    return NumberFormat.currency(locale: 'en', name: code).decimalDigits ?? kCurrencyDefaultFractionDigits;
  } catch (_) {
    return kCurrencyDefaultFractionDigits;
  }
}

/// A number with the language's group separators and decimal sign.
///
/// [fractionDigits] gives exactly that many fraction digits (an amount); `null`
/// means from zero to three (`number`). Groups ALWAYS appear: the pattern
/// `#,##0.###` has no `minimumGroupingDigits` rule, so Spanish gives "1.850",
/// the same as the web does with `useGrouping: 'always'`.
///
/// `null` means the language is not in `intl` (`missingNumberLocaleData`).
String? _groupedNumber(num number, String? locale, {int? fractionDigits}) =>
    _groupedParts(number, locale, fractionDigits: fractionDigits)?.text;

/// [_groupedNumber] together with the decimal separator of the language, which is where the fraction
/// is cut off the integer digits (the LAST occurrence of the separator in the text).
({String text, String decimal})? _groupedParts(num number, String? locale, {int? fractionDigits}) {
  final blank = locale == null || locale.trim().isEmpty;
  final tag = blank ? null : _numberLocaleFor(locale);
  if (!blank && tag == null) return null;
  final formatter = NumberFormat.decimalPattern(tag);
  // The CONTRACT rounds, not `NumberFormat`: here the number already has
  // exactly the digits needed, and the formatter only places groups, the
  // decimal sign and the language's digits. Reading the decimal form of the
  // same number back does not round a second time.
  final digits = fractionDigits ?? kNumberFormatMaxFractionDigits;
  final rounded = roundHalfAwayFromZero(number, digits);
  final signed = num.parse('${rounded.negative ? '-' : ''}${rounded.integer}${digits == 0 ? '' : '.${rounded.fraction}'}');
  formatter
    ..minimumFractionDigits = fractionDigits ?? 0
    ..maximumFractionDigits = digits;
  return (text: formatter.format(signed), decimal: formatter.symbols.DECIMAL_SEP);
}

/// The text of a bound value under a format, or `null` for "the format did not
/// apply here".
///
/// [locale] is the FORMAT locale (`formatting` of the 9.1.0 rule): the language
/// the document is shown in, with the region of the request. `null` means the
/// language `intl` considers current; the renderer always passes it explicitly.
///
/// [currency] is the neighbouring field of the binding; without a code of the
/// right form `currency` does not apply (`missingCurrencyCode`).
///
/// [now] is "now" for `daysUntil`: the reader's clock has to be replaceable
/// (`readerClock`). `null` means the device clock at the moment of the call;
/// the renderer reads it once per screen and always passes it in.
///
/// The time zone of dates is the DEVICE's: the value is an instant, and
/// "until 21:59 GMT" reads as 23:59 to a person in Kyiv, because for them the
/// promotion ends exactly then. `daysUntil` does not depend on the zone at all.
String? formatBoundValue(
  Object? value,
  BindingFormat format, {
  String? locale,
  String? currency,
  DateTime? now,
  MoneyLook look = MoneyLook.none,
  bool rtl = false,
  DateParts? dateParts,
}) => formatBoundPieces(value, format, locale: locale, currency: currency, now: now, look: look, rtl: rtl, dateParts: dateParts)
    ?.map((piece) => piece.text)
    .join();

/// [formatBoundValue] as PIECES (schema 9.19.0, `x-money.parts`): a formatted number or amount is up to
/// five pieces of one place in logical order, each with the part it belongs to. A date, a time and
/// `daysUntil` are one piece without a part. The pieces joined are the text.
///
/// [look] is the money fields of the binding; [dateParts] is the word of `date` (it changes nothing on another
/// format); [rtl] says the text this value is shown in is written
/// right to left, which isolates the composed form. Without a readable field neither changes anything.
List<AmountPiece>? formatBoundPieces(
  Object? value,
  BindingFormat format, {
  String? locale,
  String? currency,
  DateTime? now,
  MoneyLook look = MoneyLook.none,
  bool rtl = false,
  DateParts? dateParts,
}) {
  try {
    switch (format) {
      case BindingFormat.number:
        final number = numericBoundValue(value, format, now: now);
        return number == null ? null : _amountPieces(number, locale, look: look, rtl: rtl);
      case BindingFormat.daysUntil:
        final days = numericBoundValue(value, format, now: now);
        if (days == null) return null;
        // `missingNumberLocaleData: 'render-as-is-days-as-plain-integer'`:
        // "as is" here would be an ISO string in the middle of a sentence like
        // "... days left". The days are already counted, and a language `intl`
        // does not know leaves them as plain digits without separators.
        return [(text: _groupedNumber(days, locale) ?? days.toString(), part: null)];
      case BindingFormat.currency:
        final number = numericBoundValue(value, format, now: now);
        if (number == null || !isCurrencyCode(currency)) return null;
        // A whole amount has no minor units ("120 JOD", not "120.000 JOD");
        // otherwise exactly as many digits as the currency has.
        final whole = number is int || number == number.truncateToDouble();
        // ONE composition in every language: number, U+00A0, code (or, with the money fields, the
        // composed form). `NumberFormat.currency` would write "JOD120.000": no space, minor
        // units on a whole amount, and in another language the code on the other side.
        return _amountPieces(
          number,
          locale,
          fractionDigits: whole ? 0 : _currencyFractionDigits(currency!),
          currency: currency,
          look: look,
          rtl: rtl,
        );
      case BindingFormat.date || BindingFormat.dateTime || BindingFormat.time:
        final text = _formatMoment(value, format, locale, dateParts);
        return text == null ? null : [(text: text, part: null)];
    }
  } catch (error) {
    // `intl` may not know a language, number or code (a foreign tag from the
    // document); it throws `ArgumentError`, which is an `Error` and not an
    // `Exception`, so everything is caught. The format does not apply and the
    // value is shown as is.
    if (kDebugMode) debugPrint('[hotlayout] format ${format.wire} failed for locale "$locale": $error');
    return null;
  }
}

String? _formatMoment(Object? value, BindingFormat format, String? locale, DateParts? dateParts) {
  final moment = _momentOf(value);
  if (moment == null) return null;

  _ensureDateData();
  final blank = locale == null || locale.trim().isEmpty;
  final tag = blank ? null : _dateLocaleFor(locale);
  if (!blank && tag == null) {
    // For a language `intl` has no data for, the format does not apply (the
    // "show as is" policy), rather than falling back to the device language.
    if (kDebugMode) debugPrint('[hotlayout] format ${format.wire}: no date data for locale "$locale"');
    return null;
  }
  final local = moment.toLocal();
  if (format == BindingFormat.dateTime) {
    // Date and time are joined by the LANGUAGE's pattern (CLDR, the "medium"
    // joiner: abbreviated month), not by a space: `add_jm()` would write
    // "Oct 31, 2026 2:00 PM", while the web (Intl) and CLDR say
    // "Oct 31, 2026, 2:00 PM". The `intl` data is the same CLDR: `{1}` is the
    // date and `{0}` is the time.
    final date = DateFormat.yMMMd(tag);
    final glues = date.dateSymbols.DATETIMEFORMATS;
    final glue = glues.length > 2 ? glues[2] : '{1} {0}';
    return glue
        .replaceAll("'", '')
        .replaceAll('{1}', date.format(local))
        .replaceAll('{0}', DateFormat.jm(tag).format(local));
  }
  // `dateParts` is read by `date` only (the caller passes it so); without it the date is the 9.4.0 one.
  final formatter = format == BindingFormat.time
      ? DateFormat.jm(tag)
      : format == BindingFormat.date && dateParts != null
      ? dateParts.formatter(tag)
      : DateFormat.yMMMd(tag);
  return formatter.format(local);
}
