/// Text emphasis (schema 9.17.0): italic, underline or strikethrough, and the weight of a span.
/// Mirrors the reference implementation `text-emphasis.ts`.
///
/// Rules that must not be "simplified":
///
///  1. `normal` and `none` are real values, not "field absent": a descendant, a state or a span
///     uses them to cancel what it inherits. Replacing them with a boolean `true` would leave an
///     ordinary word inside an italic paragraph with no way to be set back to normal.
///  2. A word outside the list (`oblique`, `overline`), a non-string or `null` means "field
///     absent": the inherited value applies and the document is not rejected
///     (`unknownWord: 'field-not-applied'`).
///  3. Emphasis is inherited by the same rule as colour and font, each field on its own, and only
///     `Text` reads it. Italic set on a card does not reach a button inside it.
///  4. Every run draws its own line, in the colour of that run. The paragraph does not carry it.
///  5. A span weight is a word; the numbers come from DATA ([kSpanWeights]). It overrides the
///     typography style of both the span and the text.
///  6. The line strut and run merging do not depend on emphasis.
library;

import 'package:flutter/foundation.dart';

import 'text_spans.dart';

/// Words of `style.fontStyle` and `TextSpanStyle.fontStyle`.
enum EmphasisFontStyle {
  normal,
  italic;

  String get wire => name;
}

/// Words of `style.textDecoration` and `TextSpanStyle.textDecoration`.
enum EmphasisDecoration {
  none,
  underline,
  lineThrough;

  String get wire => name;
}

/// Span weight words (`TextSpanWeight`) and their numbers (`textEmphasis.weights`).
enum SpanWeight {
  regular(400),
  medium(500),
  semibold(600),
  bold(700);

  const SpanWeight(this.number);

  /// Numeric font weight (`font-weight` / `FontWeight.wNNN`).
  final int number;

  String get wire => name;
}

/// Weight numbers as the artifact states them (`x-style.layout.textEmphasis.weights`).
const Map<String, int> kSpanWeights = {'regular': 400, 'medium': 500, 'semibold': 600, 'bold': 700};

/// Mirror of the scalar rows of `x-style.layout.textEmphasis`; checked against the artifact.
const Map<String, Object> kTextEmphasisLayout = {
  'inheritance': 'nearest-named-per-field',
  'readers': ['Text'],
  'unknownWord': 'field-not-applied',
  'spanWeight': 'over-typography',
  'span': 'replaces-per-field',
  'decorationColor': 'text-color-of-run',
  'decorationSpans': 'run-text-only',
  'decorationThickness': 'platform',
  'decorationOffset': 'platform',
  'decorationSkipInk': 'platform',
  'missingFace': 'platform-synthesis',
  'strut': 'unchanged',
  'merge': 'by-place',
  'heard': 'unchanged',
};

/// Emphasis keys on a node (inherited) and on a span (`spanKeys`).
const List<String> kTextEmphasisNodeKeys = ['fontStyle', 'textDecoration'];
const List<String> kTextEmphasisSpanKeys = ['weight', 'fontStyle', 'textDecoration'];

/// The `fontStyle` word the reader understands, or `null`.
EmphasisFontStyle? readFontStyle(Object? raw) {
  if (raw is! String) return null;
  for (final value in EmphasisFontStyle.values) {
    if (value.wire == raw) return value;
  }
  return null;
}

/// The `textDecoration` word the reader understands, or `null`.
EmphasisDecoration? readDecoration(Object? raw) {
  if (raw is! String) return null;
  for (final value in EmphasisDecoration.values) {
    if (value.wire == raw) return value;
  }
  return null;
}

/// The span weight word, or `null`. A number (`700`) is not a word; only own keys are matched, so
/// `constructor` never resolves.
SpanWeight? readSpanWeight(Object? raw) {
  if (raw is! String) return null;
  for (final value in SpanWeight.values) {
    if (value.wire == raw) return value;
  }
  return null;
}

/// Emphasis of a TEXT at a point in the tree: both words are already resolved. At the root they
/// are `normal` and `none`.
@immutable
final class TextEmphasis {
  const TextEmphasis({this.fontStyle = EmphasisFontStyle.normal, this.textDecoration = EmphasisDecoration.none});

  final EmphasisFontStyle fontStyle;
  final EmphasisDecoration textDecoration;

  /// The root: nothing is named.
  static const TextEmphasis root = TextEmphasis();

  /// Nothing differs from the root, so the run style adds nothing.
  bool get isRoot => fontStyle == EmphasisFontStyle.normal && textDecoration == EmphasisDecoration.none;

  @override
  bool operator ==(Object other) =>
      other is TextEmphasis && other.fontStyle == fontStyle && other.textDecoration == textDecoration;

  @override
  int get hashCode => Object.hash(fontStyle, textDecoration);

  @override
  String toString() => 'TextEmphasis($fontStyle, $textDecoration)';
}

/// Emphasis of a node after inheritance: the word of the nearest ancestor that names it, per
/// field. If an ancestor names a line and the text names italic, both apply. With no input it
/// returns [parent] itself.
TextEmphasis inheritTextEmphasis(
  TextEmphasis parent, {
  EmphasisFontStyle? fontStyle,
  EmphasisDecoration? textDecoration,
}) {
  if (fontStyle == null && textDecoration == null) return parent;
  return TextEmphasis(
    fontStyle: fontStyle ?? parent.fontStyle,
    textDecoration: textDecoration ?? parent.textDecoration,
  );
}

/// Emphasis of a RUN: the text emphasis with the span's own fields on top. `weight` is the number
/// for the span's weight word, or `null` (then the run's typography style gives the weight).
typedef RunEmphasis = ({EmphasisFontStyle fontStyle, EmphasisDecoration textDecoration, int? weight});

/// Emphasis of a run: [text] is the text emphasis, [span] the span style or `null` for a base run.
/// The span replaces each of its fields separately.
RunEmphasis runEmphasisOf(TextEmphasis text, TextSpanStyle? span) {
  final merged = inheritTextEmphasis(text, fontStyle: span?.fontStyle, textDecoration: span?.textDecoration);
  return (
    fontStyle: merged.fontStyle,
    textDecoration: merged.textDecoration,
    weight: span?.weight?.number,
  );
}
