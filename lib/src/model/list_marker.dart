/// List item marker (schema 9.17.0): the `Text.marker` field. Mirror of the builder's
/// `list-marker.ts`.
///
/// Decisions that must not be "simplified":
///
///  1. THE MARKER IS A FIELD OF TEXT, not a widget: a 9.16 reader would not draw an unknown widget at
///     all, whereas it skips an unknown field and the text stays plain.
///  2. GEOMETRY IS FRACTIONS OF THE FONT SIZE from data ([kListMarkerColumn], [kListMarkerGap]), not
///     the measured width of the glyph: "10." in two typefaces of different widths, yet the text must
///     start on the same vertical line in every reader. Numbers are not rounded.
///  3. A GROUP IS SIBLINGS IN A ROW, by the DOCUMENT: any other node between numbered ones (a hidden
///     one too) breaks the group; a hidden NUMBERED node does not. The number counts VISIBLE items,
///     the column width follows the group by the document: "1, 2, 4" reads as an error, and the
///     column must not jump as the data changes.
///  4. ABOUT THE PARENT the rule says only one thing: an item that is the template of a `Repeater`
///     ([numbersByInstance]) counts its INSTANCES. For any other parent (column, row, stack, carousel
///     row) the group is the children of THIS parent in a row, as they stand in the document: the
///     reference implementation has no special case for `Stack` or a carousel card (`numberRun` over
///     `children`).
library;

import 'binding_format.dart';

/// Words of `Text.marker`.
enum TextMarker {
  none,
  bullet,
  number;

  String get wire => name;
}

/// Which marker is ACTUALLY drawn: `none` and anything unrecognized mean no marker.
enum DrawnTextMarker { bullet, number }

/// Mirror of `x-style.layout.listMarker` (scalar rows); checked against the artifact.
const Map<String, Object> kListMarkerLayout = {
  'field': 'marker',
  'values': ['none', 'bullet', 'number'],
  'default': 'none',
  'unknown': 'no-marker',
  'before917': 'plain-text',
  'unit': 'text-font-size',
  'textScale': 'applies',
  'placement': 'inline-start',
  'mirroredInRtl': true,
  'markerAlign': 'column-end',
  'overflow': 'visible-toward-start',
  'baseline': 'first-line-of-text',
  'hangingIndent': 'under-first-line-of-text',
  'font': 'text-base-typography',
  'color': 'text-color',
  'fontStyle': 'normal',
  'textDecoration': 'none',
  'spans': 'do-not-style-marker',
  'textAlign': 'within-text-column',
  'maxLines': 'text-only',
  'naturalWidth': 'column-plus-gap-plus-text',
};

/// The bullet glyph (U+2022) and the number suffix.
const String kListBulletGlyph = '•';
const String kListNumberSuffix = '.';

/// Marker column in fractions of the font size: a bullet is 1; a number is
/// `max(1, 0.6 x digits + 0.4)`.
const double kListMarkerBulletColumn = 1;
const double kListMarkerDigit = 0.6;
const double kListMarkerSuffix = 0.4;
const double kListMarkerMinColumn = 1;

/// Gap between the column and the text, as a fraction of the font size.
const double kListMarkerGap = 0.5;

/// The field's word: a word from the list, or [TextMarker.none] (`unknown: no-marker`).
TextMarker readTextMarker(Object? raw) {
  if (raw is! String) return TextMarker.none;
  for (final value in TextMarker.values) {
    if (value.wire == raw) return value;
  }
  return TextMarker.none;
}

/// The marker that is drawn, or `null` when the node is not a list item.
DrawnTextMarker? drawnMarkerOf(TextMarker marker) => switch (marker) {
  TextMarker.none => null,
  TextMarker.bullet => DrawnTextMarker.bullet,
  TextMarker.number => DrawnTextMarker.number,
};

/// A numbered item that is a DIRECT child of a repeater is the template of a data-driven list: the
/// group is the drawn instances.
bool numbersByInstance(String? parentType) => parentType == 'Repeater';

/// Bounds (inclusive) of the run of numbered items among [markers], the markers of the siblings of ONE
/// parent in document order (`null` is not an item); `null` when [index] is not numbered.
(int, int)? _numberRun(List<DrawnTextMarker?> markers, int index) {
  if (markers[index] != DrawnTextMarker.number) return null;
  var first = index;
  while (first > 0 && markers[first - 1] == DrawnTextMarker.number) {
    first--;
  }
  var last = index;
  while (last < markers.length - 1 && markers[last + 1] == DrawnTextMarker.number) {
    last++;
  }
  return (first, last);
}

/// How many items the group of numbered [index] has BY THE DOCUMENT (hidden ones included); `null` when
/// not numbered. The column width depends on this number.
int? listMarkerGroupSize(List<DrawnTextMarker?> markers, int index) {
  final run = _numberRun(markers, index);
  return run == null ? null : run.$2 - run.$1 + 1;
}

/// Number of numbered [index]: how many VISIBLE items of the group stand up to and including it. A
/// hidden item takes no number; for the hidden item itself, the number it would have if it became
/// visible.
int? listNumberOf(List<DrawnTextMarker?> markers, int index, List<bool> visible) {
  final run = _numberRun(markers, index);
  if (run == null) return null;
  var number = 0;
  for (var at = run.$1; at < index; at++) {
    if (visible[at]) number++;
  }
  return number + 1;
}

/// Numbers of the instances of an item template: an instance whose template is visible gets "how many
/// visible ones are drawn up to and including it"; a hidden one gets `null`.
List<int?> listInstanceNumbers(List<bool> templateVisible) {
  var drawn = 0;
  return [
    for (final visible in templateVisible)
      if (visible) ++drawn else null,
  ];
}

int _digitsOf(int groupSize) => (groupSize < 1 ? 1 : groupSize).toString().length;

/// Column, gap and hanging indent of an item, in logical pixels (rounded to six decimals so that
/// `0.6 x 3 + 0.4` does not give `2.2000000000000006`).
typedef ListMarkerGeometry = ({double column, double gap, double indent});

ListMarkerGeometry listMarkerGeometry(DrawnTextMarker marker, double fontSize, {int groupSize = 1}) {
  final size = fontSize.isFinite && fontSize > 0 ? fontSize : 0.0;
  final em = marker == DrawnTextMarker.bullet
      ? kListMarkerBulletColumn
      : _max(kListMarkerMinColumn, _digitsOf(groupSize) * kListMarkerDigit + kListMarkerSuffix);
  final column = _round6(em * size);
  final gap = _round6(kListMarkerGap * size);
  return (column: column, gap: gap, indent: _round6(column + gap));
}

double _max(double a, double b) => a > b ? a : b;

double _round6(double value) => (value * 1e6).roundToDouble() / 1e6;

/// What the marker says: "•" or a number (digits in the document's formatting language, like the
/// `number` format of 9.4.0) and a period. A language without platform data gets plain digits.
String listMarkerText(DrawnTextMarker marker, int number, String? formattingLocale) {
  if (marker == DrawnTextMarker.bullet) return kListBulletGlyph;
  final digits = formatBoundValue(number, BindingFormat.number, locale: formattingLocale) ?? '$number';
  return '$digits$kListNumberSuffix';
}
