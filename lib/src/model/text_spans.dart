/// Rich text (schema 9.6.0): parts of one string, each with its own style.
/// Mirrors the reference implementation `text-spans.ts`; the field shape lives in `TextNode`,
/// this file holds the rule with no widget involved.
///
/// Why it exists: a real screen says "1,850 Points", a large number and a small caption on ONE
/// line. Two texts in a row cannot do that: a translator cannot reorder the parts
/// ("Points: 1 850"), the string does not wrap as a paragraph, and a screen reader hears two
/// fragments.
///
/// Rules that must not be "simplified":
///
///  1. A style attaches to the NAME of a template place, not to a run index: the translation
///     chooses the order of the parts. Only styles of places the `content` declares as its own
///     `values` key apply (`spanWithoutPlace`).
///  2. The text is exactly what it would be without `spans`. The runs come from the same parser
///     as substitution (`templateRuns`); there is no second parser for styles.
///  3. There is ONE line pitch per paragraph ([richTextStrut]): the tallest line (font size x
///     multiplier) among the base style and ALL declared parts, whether or not the string of
///     this locale mentions them. Otherwise the paragraph height would jump between
///     translations and between "data present" and "no data".
///  4. A span style is laid over the text style by the inheritance rule (9.0.0): a named field
///     replaces the base one entirely.
library;

import 'package:flutter/foundation.dart';

import 'bindable.dart';
import 'binding_format.dart' show AmountPart;
import 'style_values.dart';
import 'text_emphasis.dart';
import 'text_template.dart';

/// Policy rows of 9.6.0; checked against the artifact by a test, and the behaviour of each is
/// pinned by the case table `rich-text-cases.json`.
const Map<String, String> kTextSpansPolicy = {
  'spanWithoutPlace': 'ignore-style',
  'unreadableSpans': 'no-spans',
  'unreadableSpanStyle': 'base-style',
  'unknownSpanField': 'ignore-field',
  'unusedSpan': 'not-drawn-still-measured',
  'emptySpanText': 'no-run-neighbours-merge',
  'richTextSemantics': 'single-text-node',
};

/// Mirror of `x-style.layout.richText`, field by field; checked against the artifact.
const Map<String, Object> kRichTextLayout = {
  'spanAlign': 'baseline',
  'linePitch': 'uniform',
  'lineHeight': 'tallest-declared-part',
  'strutTieBreak': ['larger-font-size', 'base-style', 'span-name-ascending'],
  'wrap': 'paragraph',
  'bidi': 'no-isolation',
  'textWidth': 'sum-of-runs',
  'styleKeys': ['color', 'typography'],
};

/// What a span may own since 9.6.0: exactly the two fields the text INHERITS. The block
/// `x-style.layout.richText.styleKeys` was not widened in a minor version; the three fields added
/// in 9.17.0 live in `kTextEmphasisSpanKeys`.
const List<String> kTextSpanStyleKeys = ['color', 'typography'];

/// The own style of one part of a text. A `null` field means "not named": it stays as in the text.
///
/// Since 9.17.0 a part has three more fields: weight as a word, slant and line
/// ([kTextEmphasisSpanKeys]). A style in which AT LEAST ONE of the five fields is readable makes
/// the place a part; a 9.6-9.16 reader ignores a style that only has emphasis.
@immutable
final class TextSpanStyle {
  const TextSpanStyle({
    this.color,
    this.typography,
    this.weight,
    this.fontStyle,
    this.textDecoration,
    this.parts = const {},
  });

  final ColorRef? color;
  final TypographyRef? typography;

  /// Part weight as a word: it overrides the typography style of both the part and the text.
  final SpanWeight? weight;
  final EmphasisFontStyle? fontStyle;
  final EmphasisDecoration? textDecoration;

  /// The styles of the PARTS of a formatted number or amount (9.19.0, `Text.spans[place].parts`): the
  /// fraction and the currency. A part style has the same five fields (its own `parts` stays empty).
  final Map<AmountPart, TextSpanStyle> parts;

  /// This style with the fields [part] names laid over it: a named field replaces, an unnamed one stays
  /// as in the place (the inheritance rule of 9.0.0).
  TextSpanStyle overlaid(TextSpanStyle part) => TextSpanStyle(
    color: part.color ?? color,
    typography: part.typography ?? typography,
    weight: part.weight ?? weight,
    fontStyle: part.fontStyle ?? fontStyle,
    textDecoration: part.textDecoration ?? textDecoration,
  );

  @override
  bool operator ==(Object other) =>
      other is TextSpanStyle &&
      other.color == color &&
      other.typography == typography &&
      other.weight == weight &&
      other.fontStyle == fontStyle &&
      other.textDecoration == textDecoration &&
      mapEquals(other.parts, parts);

  @override
  int get hashCode => Object.hash(
    color,
    typography,
    weight,
    fontStyle,
    textDecoration,
    Object.hashAll([for (final part in parts.entries) Object.hash(part.key, part.value)]),
  );

  @override
  String toString() =>
      'TextSpanStyle(color: $color, typography: $typography, weight: $weight, '
      'fontStyle: $fontStyle, textDecoration: $textDecoration, parts: $parts)';
}

final RegExp _placeName = RegExp(kTemplateValueNamePattern);

/// Span styles as the reader reads them: tolerantly, field by field. Never throws.
///
///  * `spans` is not an object (string, array): no parts (`unreadableSpans`);
///  * a key that does not match the place-name pattern is not a part;
///  * a style that is not an object, is empty, or has no readable field: the place is drawn with
///    the base style (`unreadableSpanStyle`);
///  * a field the reader does not know, or a known one of the wrong shape, is skipped and the
///    rest of the style applies (`unknownSpanField`).
///
/// Only the map's own keys count: `constructor` cannot become a style, since a Dart `Map` has no
/// prototype, and the "declared place" check is made by [activeTextSpans] against the own keys
/// of `values`.
Map<String, TextSpanStyle> readTextSpans(Object? raw) {
  if (raw is! Map) return const {};
  final spans = <String, TextSpanStyle>{};
  for (final entry in raw.entries) {
    final name = entry.key;
    if (name is! String || !_placeName.hasMatch(name)) continue;
    final style = entry.value;
    if (style is! Map) continue;
    final read = _readStyleFields(style);
    final parts = _readParts(style['parts']);
    // A place that names only `parts` is still a place (its rest is a run of its own).
    if (read == null && parts.isEmpty) continue;
    spans[name] = TextSpanStyle(
      color: read?.color,
      typography: read?.typography,
      weight: read?.weight,
      fontStyle: read?.fontStyle,
      textDecoration: read?.textDecoration,
      parts: parts,
    );
  }
  return spans;
}

/// The five fields of a style, each read on its own; `null` when none is readable.
TextSpanStyle? _readStyleFields(Map<Object?, Object?> style) {
  final color = ColorRef.tryParse(style['color']);
  final typography = TypographyRef.tryParse(style['typography']);
  // An unknown word (`black`, `oblique`, `overline`) or a number means the field is absent.
  final weight = readSpanWeight(style['weight']);
  final fontStyle = readFontStyle(style['fontStyle']);
  final textDecoration = readDecoration(style['textDecoration']);
  if (color == null && typography == null && weight == null && fontStyle == null && textDecoration == null) {
    return null;
  }
  return TextSpanStyle(
    color: color,
    typography: typography,
    weight: weight,
    fontStyle: fontStyle,
    textDecoration: textDecoration,
  );
}

/// `parts` (9.19.0): not an object means no parts; a name that is not `fraction` or `currency`, and a
/// style with no readable field, are skipped; the rest of the style works.
Map<AmountPart, TextSpanStyle> _readParts(Object? raw) {
  if (raw is! Map) return const {};
  final parts = <AmountPart, TextSpanStyle>{};
  for (final entry in raw.entries) {
    final part = AmountPart.parse(entry.key);
    final style = entry.value;
    if (part == null || style is! Map) continue;
    final read = _readStyleFields(style);
    if (read != null) parts[part] = read;
  }
  return parts;
}

/// The styles that APPLY: only for places [content] declares as its own `values` key
/// (`spanWithoutPlace`). A literal or a single binding has none.
Map<String, TextSpanStyle> activeTextSpans(BindableString content, Map<String, TextSpanStyle> spans) {
  if (spans.isEmpty || content is! TemplateString) return const {};
  return {
    for (final entry in spans.entries)
      if (content.values.containsKey(entry.key)) entry.key: entry.value,
  };
}

/// A run of rich text: what is written and in whose style. `span == null` means the style of the
/// text itself.
typedef TextSpanRun = ({String text, String? span});

/// A run of rich text with the part of a formatted number it is (9.19.0): `part` is the part whose OWN
/// style the run is drawn with, or `null` for the style of the place (or of the text, when `span` is
/// `null`).
typedef TextPartRun = ({String text, String? span, AmountPart? part});

/// Styled runs: empty ones are dropped, adjacent runs of the SAME style are merged. [active] holds
/// the styles already in effect ([activeTextSpans]).
///
/// Merging is part of the rule, not an optimisation: the number of runs is observable, and it
/// must be the same in every reader. A place without a style merges with the surrounding text;
/// the same name twice in a row is one run; two different styled places are two.
List<TextSpanRun> spanRuns(Iterable<TemplateRun> runs, Map<String, TextSpanStyle> active) => [
  for (final run in spanPartRuns([for (final run in runs) (text: run.text, place: run.place, part: null)], active))
    (text: run.text, span: run.span),
];

/// [spanRuns] over runs that carry the part of a number (`TemplateString.partedRuns`). A piece of a
/// part is a run of its own only when its place gave THAT part a readable style; otherwise it merges
/// with its neighbours of the same place, as if the part had not been cut out.
List<TextPartRun> spanPartRuns(Iterable<PartedRun> runs, Map<String, TextSpanStyle> active) {
  final result = <TextPartRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) continue;
    final place = run.place;
    final span = place != null && active.containsKey(place) ? place : null;
    final part = span != null && run.part != null && active[span]!.parts.containsKey(run.part) ? run.part : null;
    if (result.isNotEmpty && result.last.span == span && result.last.part == part) {
      result[result.length - 1] = (text: result.last.text + run.text, span: span, part: part);
    } else {
      result.add((text: run.text, span: span, part: part));
    }
  }
  return result;
}

/// The styles of places AND of their declared parts, by the key the line strut uses: `place` for a
/// place and `place.part` for a part (9.19.0). A part style is laid over the style of its place; a part
/// counts whether or not the shown amount has it (a whole amount has no fraction).
Map<String, TextSpanStyle> spanStylesWithParts(Map<String, TextSpanStyle> active) => {
  for (final entry in active.entries) ...{
    entry.key: entry.value,
    for (final part in entry.value.parts.entries) '${entry.key}.${part.key.wire}': entry.value.overlaid(part.value),
  },
};

/// Font size in logical pixels and line-height multiplier, in theme units.
typedef LineMetric = ({double fontSize, double lineHeight});

/// The paragraph strut: whose style sets the line pitch.
typedef RichTextStrut = ({String? span, double fontSize, double lineHeight, double lineBlock});

/// The paragraph STRUT: the tallest line (font size x multiplier) among the base style and ALL
/// active parts. Ties go to the larger font size, then the base style, then the part name in
/// ascending code-unit order (JSON key order is not part of the rule). `span == null` means the
/// base style is the strut.
///
/// The system font scale multiplies every font size equally, so it does not change which strut
/// wins; the pitch on screen is `lineBlock x scale`.
RichTextStrut richTextStrut(LineMetric base, Map<String, LineMetric> spans) {
  String? bestSpan;
  var best = base;
  double block(LineMetric metric) => metric.fontSize * metric.lineHeight;

  for (final name in spans.keys.toList()..sort()) {
    final metric = spans[name]!;
    final candidate = block(metric);
    final current = block(best);
    if (candidate > current || (candidate == current && metric.fontSize > best.fontSize)) {
      bestSpan = name;
      best = metric;
    }
  }
  return (span: bestSpan, fontSize: best.fontSize, lineHeight: best.lineHeight, lineBlock: block(best));
}
