import 'package:flutter/foundation.dart';

import 'bindable.dart';
import 'input_rules.dart';
import 'style_values.dart';
import 'tokens.dart';

/// THE PARTS OF A TEXT FIELD (schema 9.19.0, `x-style.layout.inputParts`): the look of the box itself, a mark at the
/// start and at the end of it, the character counter and the row under the box. Pure rules; the drawing is
/// `render/inputs/input_text_field.dart`.

// ───────────────────────────── the box of the field ─────────────────────────────

const int kFieldBorderWidthMin = 1;
const int kFieldBorderWidthMax = 4;
const int kFieldHeightMin = 32;
const int kFieldHeightMax = 120;

/// The built-in look of the box, said in tokens: the radius `sm`, the background `surface`, the border `border` and
/// one logical pixel of it.
const RadiusToken kFieldRadiusToken = RadiusToken.sm;
const ColorToken kFieldBackgroundToken = ColorToken.surface;
const ColorToken kFieldBorderToken = ColorToken.border;
const int kFieldBorderWidth = 1;

/// The border width of the box (`fieldBorderWidthOf`): a whole number from 1 to 4, anything else is the built-in 1.
int fieldBorderWidthOf(Object? raw) => wholeNumberIn(raw, kFieldBorderWidthMin, kFieldBorderWidthMax) ?? kFieldBorderWidth;

/// The named height of a ONE-line field (`fieldHeightOf`): a whole number from 32 to 120. A field of several lines
/// does not read it, and a value out of range or of another form is no height.
int? fieldHeightOf(Object? raw, int lines) => lines == 1 ? wholeNumberIn(raw, kFieldHeightMin, kFieldHeightMax) : null;

/// The height of the box with its border (`fieldBoxHeightOf`): the named height, exact (the border is inside it),
/// or the natural one: the border twice, the vertical padding twice and the lines.
double fieldBoxHeightOf({
  required double textLine,
  required double paddingBlock,
  required int lines,
  Object? height,
  Object? borderWidth,
}) {
  final named = fieldHeightOf(height, lines);
  if (named != null) return named.toDouble();
  return 2 * fieldBorderWidthOf(borderWidth) + 2 * paddingBlock + lines * textLine;
}

// ───────────────────────────── the marks ─────────────────────────────

/// The longest text of a mark, in code points.
const int kFieldAffixTextMax = 8;

/// A mark inside the box, at the start (`prefix`) or at the end (`suffix`): a short text or an icon.
sealed class FieldAffix {
  const FieldAffix();
}

final class AffixText extends FieldAffix {
  const AffixText(this.text);

  final BindableString text;
}

final class AffixIcon extends FieldAffix {
  const AffixIcon(this.icon);

  /// [IconToken.unknown] draws an empty box of the same size, and the gap stays.
  final IconToken icon;
}

/// A mark of the raw shape, or `null`: not an object, a kind that is neither `text` nor `icon`, a text mark without
/// a text object, an icon mark without the `icon` key. [key] is the localization key of the mark's text.
FieldAffix? readFieldAffix(Object? raw, {String? key}) {
  if (raw is! Map) return null;
  switch (raw['kind']) {
    case 'text':
      final text = raw['text'];
      return text is Map ? AffixText(BindableString.parse(text, key: key)) : null;
    case 'icon':
      return raw.containsKey('icon') ? AffixIcon(IconToken.parse(raw['icon'])) : null;
  }
  return null;
}

/// The text of a mark as drawn (`affixTextShown`): the first [kFieldAffixTextMax] code points of the SHOWN text
/// (after the translation and the data), never splitting a surrogate pair.
String affixTextShown(String shown) => clampInputText(shown, kFieldAffixTextMax);

/// The gap between a mark and the text of the field.
const SpacingToken kFieldAffixGap = SpacingToken.sm;

/// Where the pieces of the row inside the box stand (`affixRowOf`), measured from the LOGICAL start of the box by
/// the direction of the SCREEN. The marks never shrink: the text of the field takes the rest, not less than nothing.
typedef AffixRow = ({double? prefixStart, double textStart, double textInline, double? suffixStart});

AffixRow affixRowOf({
  required double boxInline,
  required double border,
  required double paddingInline,
  required double gap,
  double? prefix,
  double? suffix,
}) {
  final edge = border + paddingInline;
  final before = prefix == null ? 0.0 : prefix + gap;
  final after = suffix == null ? 0.0 : suffix + gap;
  final textStart = edge + before;
  final free = boxInline - 2 * edge - before - after;
  final textInline = free < 0 ? 0.0 : free;
  return (
    prefixStart: prefix == null ? null : edge,
    textStart: textStart,
    textInline: textInline,
    suffixStart: suffix == null ? null : textStart + textInline + gap,
  );
}

// ───────────────────────────── the counter ─────────────────────────────

/// The separator of the counter text: `{count} / {max}`.
const String kFieldCounterSeparator = ' / ';

/// The text of the counter (`inputCounterText`), or `null` when there is none: it is read only when `counter` is
/// exactly `true` and `maxLength` is a whole number from 1. The count is in code points of the SHOWN text (cut to
/// the limit), the digits are ASCII without groups.
String? inputCounterText({required Object? counter, required Object? maxLength, required String shown}) {
  final limit = wholeNumberIn(maxLength, 1, 1 << 31);
  if (counter != true || limit == null) return null;
  return '${clampInputText(shown, limit).runes.length}$kFieldCounterSeparator$limit';
}

/// The row under the box (`noteRowOf`): the helper or the error from the start takes the rest, the counter stands
/// at the logical end and never shrinks. A counter wider than the row leaves the note nothing.
typedef NoteRow = ({double noteInline, double? counterStart});

NoteRow noteRowOf({required double rowInline, required double gap, double? counter}) {
  if (counter == null) return (noteInline: rowInline, counterStart: null);
  final note = rowInline - gap - counter;
  final start = rowInline - counter;
  return (noteInline: note < 0 ? 0.0 : note, counterStart: start < 0 ? 0.0 : start);
}

/// What the document says about the look of the box and its marks, as read from the props of a text field.
@immutable
final class FieldParts {
  const FieldParts({
    this.radius,
    this.background,
    this.borderColor,
    this.borderWidth,
    this.height,
    this.prefix,
    this.suffix,
    this.counter = false,
  });

  /// No part named: the built-in field.
  static const FieldParts none = FieldParts();

  final ScaleRef? radius;
  final ColorRef? background;
  final ColorRef? borderColor;

  /// As written; [fieldBorderWidthOf] decides what it is.
  final Object? borderWidth;
  final Object? height;
  final FieldAffix? prefix;
  final FieldAffix? suffix;

  /// The word `counter`: exactly `true`.
  final bool counter;
}

/// Reads the 9.19.0 props of a text field. Each is read on its own and a bad one is "no field". [prefixKey] and
/// [suffixKey] are the localization keys of the marks' texts.
FieldParts readFieldParts(Map<Object?, Object?> props, {String? prefixKey, String? suffixKey}) => FieldParts(
  radius: strictRadiusRef(props['fieldRadius']),
  background: ColorRef.tryParse(props['fieldBackground']),
  borderColor: ColorRef.tryParse(props['fieldBorderColor']),
  borderWidth: props['fieldBorderWidth'],
  height: props['fieldHeight'],
  prefix: readFieldAffix(props['prefix'], key: prefixKey),
  suffix: readFieldAffix(props['suffix'], key: suffixKey),
  counter: props['counter'] == true,
);
