part of 'binding_format.dart';

// MONEY AS MONEY (schema 9.19.0, `x-money`): a currency sign, a number sign and the pieces of an
// amount.
//
// Three optional fields of a binding sit next to `format` and `currency`: `currencyDisplay` (`symbol`),
// `currencyPosition` (`before`) and `sign` (`always`). With none of them readable the text is exactly
// what 9.4.0 wrote, character for character. With at least one the amount takes the COMPOSED form, whose
// order is the same in every language:
//
//     [number sign][currency before][amount][currency after]
//
// The reader writes the signs itself. `Intl` with a sign display, or the platform's own plus and minus,
// would give platform characters with direction marks, and the readers would part at the first language.
// The currency sign comes from the embedded table below, never from the platform's currency data.

/// The currency signs the contract names (`x-money.symbols`). A code that is not here is shown as the
/// code, in the same place and with the code's own gap (`symbolMissing`).
const Map<String, String> kMoneySymbols = {
  'UAH': '₴',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'PLN': 'zł',
  'JPY': '¥',
  'CZK': 'Kč',
  'TRY': '₺',
  'INR': '₹',
  'ILS': '₪',
  'KZT': '₸',
  'GEL': '₾',
};

/// The negative sign: U+2212 MINUS SIGN, not the hyphen (`x-money.signs.negative`).
const String kMoneyMinus = '\u2212';

/// The positive sign, written only with `sign: 'always'` (`x-money.signs.positive`).
const String kMoneyPlus = '+';

/// The gap between an amount and its currency, and after a code placed before the amount
/// (`x-money.gap`): U+00A0. A sign placed before the amount has no gap.
const String kMoneyGap = '\u00A0';

/// The marks that isolate the composed form in a right-to-left text (`x-money.isolation`): U+2066
/// LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE. They are characters of the string, not
/// a property of a text span: Flutter has no direction of a separate span.
const String kMoneyIsolateOpen = '\u2066';
const String kMoneyIsolateClose = '\u2069';

/// The part of a formatted value that a style may name (`x-money.parts.names`).
enum AmountPart {
  /// The decimal separator and the digits after it.
  fraction('fraction'),

  /// The currency sign or code, with its gap.
  currency('currency');

  const AmountPart(this.wire);

  final String wire;

  /// The part named in the document, or `null` for an unknown name.
  static AmountPart? parse(Object? raw) {
    for (final part in values) {
      if (part.wire == raw) return part;
    }
    return null;
  }
}

/// A piece of a formatted value: its text and the part it belongs to (`null`: the rest, i.e. the number
/// sign and the integer digits).
typedef AmountPiece = ({String text, AmountPart? part});

/// The three money fields of a binding, as the reader reads them for ITS format.
///
/// A field is read only on a format that reads it (`fieldOnAnotherFormat: ignored`): `currencyDisplay`
/// and `currencyPosition` by `currency`, `sign` by `number` and `currency`. A word the reader does not
/// know, or a value that is not a string, is no field (`unknownWord`).
@immutable
final class MoneyLook {
  const MoneyLook({this.symbol = false, this.before = false, this.signAlways = false, this.compact = false});

  /// A binding with none of the three fields.
  static const MoneyLook none = MoneyLook();

  /// Reads the fields of the binding [raw] that [format] reads.
  static MoneyLook read(Map<Object?, Object?> raw, BindingFormat? format) {
    if (format != BindingFormat.number && format != BindingFormat.currency) return none;
    final isCurrency = format == BindingFormat.currency;
    return MoneyLook(
      symbol: isCurrency && raw['currencyDisplay'] == 'symbol',
      before: isCurrency && raw['currencyPosition'] == 'before',
      signAlways: raw['sign'] == 'always',
      // 9.23.0: the compact notation belongs to `number` only; on another format the field is ignored.
      compact: format == BindingFormat.number && raw['notation'] == 'compact',
    );
  }

  /// The currency sign instead of the code.
  final bool symbol;

  /// The currency before the amount.
  final bool before;

  /// The plus sign for a positive number.
  final bool signAlways;

  /// `notation: 'compact'` (schema 9.23.0): 48 200 as «48.2K». It is not a money field and does not make the
  /// composed form: only `sign` does.
  final bool compact;

  /// Whether the composed form applies: at least one readable money field.
  bool get composed => symbol || before || signAlways;

  @override
  bool operator ==(Object other) =>
      other is MoneyLook &&
      other.symbol == symbol &&
      other.before == before &&
      other.signAlways == signAlways &&
      other.compact == compact;

  @override
  int get hashCode => Object.hash(symbol, before, signAlways, compact);
}

/// The pieces of a number or an amount: [number] under [fractionDigits] (`null`: from zero to three),
/// with [currency] when it is an amount.
///
/// Without a readable money field the pieces are exactly the 9.4.0 text split in two or three: the
/// integer digits (with the platform's own minus), the fraction, and the currency code with its gap.
List<AmountPiece>? _amountPieces(
  num number,
  String? locale, {
  int? fractionDigits,
  String? currency,
  MoneyLook look = MoneyLook.none,
  bool rtl = false,
  String suffix = '',
}) {
  final composed = look.composed;
  final digits = fractionDigits ?? kNumberFormatMaxFractionDigits;
  final grouped = _groupedParts(composed ? number.abs() : number, locale, fractionDigits: fractionDigits);
  if (grouped == null) return null;

  // What is WRITTEN decides the sign and the fraction, not the value: -0.0004 under three digits is
  // written "0", and an amount written as zero has no sign.
  final written = roundHalfAwayFromZero(number.abs(), digits);
  final writtenZero = !written.integer.contains(RegExp('[1-9]')) && !written.fraction.contains(RegExp('[1-9]'));
  final hasFraction = digits > 0 && (fractionDigits != null || !written.fraction.codeUnits.every((unit) => unit == 0x30));

  var integerText = grouped.text;
  var fractionText = '';
  if (hasFraction) {
    final at = grouped.text.lastIndexOf(grouped.decimal);
    if (at >= 0) {
      integerText = grouped.text.substring(0, at);
      fractionText = grouped.text.substring(at);
    }
  }

  final pieces = <AmountPiece>[];
  if (!composed) {
    pieces
      ..add((text: integerText, part: null))
      ..add((text: fractionText, part: AmountPart.fraction));
    if (suffix.isNotEmpty) pieces.add((text: suffix, part: null));
    if (currency != null) pieces.add((text: '$kMoneyGap$currency', part: AmountPart.currency));
    return _joined(pieces);
  }

  final sign = writtenZero ? '' : (number.isNegative ? kMoneyMinus : (look.signAlways ? kMoneyPlus : ''));
  final isKnownSymbol = currency != null && look.symbol && kMoneySymbols.containsKey(currency);
  final mark = currency == null ? '' : (look.symbol ? (kMoneySymbols[currency] ?? currency) : currency);
  pieces.add((text: sign, part: null));
  // Before the amount the sign stands flush and the code takes its gap; after it both take the gap.
  if (look.before && currency != null) pieces.add((text: isKnownSymbol ? mark : '$mark$kMoneyGap', part: AmountPart.currency));
  pieces
    ..add((text: integerText, part: null))
    ..add((text: fractionText, part: AmountPart.fraction));
  // The suffix of a compact number follows the number, before any currency placed after it.
  if (suffix.isNotEmpty) pieces.add((text: suffix, part: null));
  if (!look.before && currency != null) pieces.add((text: '$kMoneyGap$mark', part: AmountPart.currency));

  final result = _joined(pieces);
  if (rtl && result.isNotEmpty) {
    result[0] = (text: '$kMoneyIsolateOpen${result.first.text}', part: result.first.part);
    final last = result.length - 1;
    result[last] = (text: '${result.last.text}$kMoneyIsolateClose', part: result.last.part);
  }
  return result;
}

/// The pieces without empty ones, and with neighbours of the same part merged (the number sign and the
/// integer digits are one piece when no currency stands between them).
List<AmountPiece> _joined(List<AmountPiece> pieces) {
  final result = <AmountPiece>[];
  for (final piece in pieces) {
    if (piece.text.isEmpty) continue;
    if (result.isNotEmpty && result.last.part == piece.part) {
      result[result.length - 1] = (text: result.last.text + piece.text, part: piece.part);
    } else {
      result.add(piece);
    }
  }
  return result;
}

// COMPACT NUMBER (schema 9.23.0, `x-compactNumber`): 48 200 as «48.2K» / «48,2 тис.». The rule is the contract's
// own arithmetic and table, never `Intl` compact or `NumberFormat.compact`: they disagree between platforms and
// between versions of their data.

/// The steps, ascending: from which magnitude each one applies (`x-compactNumber.steps`).
const List<({String name, num from})> kCompactSteps = [
  (name: 'thousand', from: 1000),
  (name: 'million', from: 1000000),
  (name: 'billion', from: 1000000000),
];

/// The suffixes by the language of the format locale (`x-compactNumber.suffixes`): the gap before the suffix
/// (U+00A0 in Ukrainian) and the suffix of each step. Any other language writes the `en` suffixes.
const Map<String, ({String gap, Map<String, String> steps})> kCompactSuffixes = {
  'en': (gap: '', steps: {'thousand': 'K', 'million': 'M', 'billion': 'B'}),
  'uk': (gap: '\u00A0', steps: {'thousand': 'тис.', 'million': 'млн', 'billion': 'млрд'}),
};

/// The precision of the quotient before it is rounded to tenths: six digits.
const double kCompactPrecision = 1e6;

/// The step and the mantissa of a magnitude, or `null` below the first step (the number is written whole).
({double mantissa, String step})? compactPartsOf(num value) {
  final magnitude = value.abs().toDouble();
  if (!magnitude.isFinite || magnitude < kCompactSteps.first.from) return null;
  var index = kCompactSteps.length - 1;
  while (index > 0 && magnitude < kCompactSteps[index].from) {
    index -= 1;
  }
  int tenthsOf(int at) =>
      (((magnitude * 10) / kCompactSteps[at].from * kCompactPrecision).round() / kCompactPrecision + 0.5).floor();
  var tenths = tenthsOf(index);
  // A mantissa that reaches 1 000 is written with the next step; beyond billions it stays «1,000B».
  if (tenths >= 10000 && index < kCompactSteps.length - 1) {
    index += 1;
    tenths = tenthsOf(index);
  }
  return (mantissa: tenths / 10, step: kCompactSteps[index].name);
}

/// The suffix with its gap for the step in the language of [locale] (the first subtag; unknown means `en`).
String compactSuffixOf(String step, String? locale) {
  final language = (locale ?? 'en').split(RegExp('[-_]')).first.toLowerCase();
  final table = kCompactSuffixes[language == 'uk' ? 'uk' : 'en']!;
  return '${table.gap}${table.steps[step]}';
}

/// The pieces of a compact number, or `null` when the language has no number data. Below the first step the
/// number is written exactly as `number` writes it.
List<AmountPiece>? _compactPieces(num number, String? locale, {required MoneyLook look, required bool rtl}) {
  final parts = compactPartsOf(number);
  if (parts == null) return _amountPieces(number, locale, look: look, rtl: rtl);
  final signed = number.isNegative ? -parts.mantissa : parts.mantissa;
  return _amountPieces(signed, locale, look: look, rtl: rtl, suffix: compactSuffixOf(parts.step, locale));
}
