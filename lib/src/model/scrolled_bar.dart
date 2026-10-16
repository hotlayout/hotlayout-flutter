import 'dart:math' as math;

import 'node_style.dart';

/// THE APP BAR AFTER SCROLLING (schema 9.21.0, `x-style.layout.appBarScrolled`): the node field
/// `styleScrolled` (on `AppBar` only) and the prop `titleShown: 'scrolled'`.
///
/// Over a hero (`bodyTop: 'screenTop'`) the bar is transparent; scrolled, the text of the body goes under
/// transparent buttons. The mobile habit is a bar that becomes solid and shows its title.
///
/// THE THRESHOLD is one formula for both modes:
///
///     scrolled  <=>  scrollTop > max(0, barBottom - bodyTop)
///
/// `barBottom` is the bottom edge of the app bar zone from the top of the screen (the top safe inset is
/// inside it), `bodyTop` the top of the BODY AREA from the top of the screen: without `screenTop` it is the
/// bar's bottom edge (less the overlap of a pulled first child), with it `0`. So without `screenTop` any
/// scroll counts ("the content went under the bar"), and with it "what stood right under the bar went under
/// it". Strictly greater: at rest the bar is at rest.
///
/// The bar's box never changes on scroll (the threshold is measured by it), which is why the layer may carry
/// only `background`, `color`, `shadow` and `backdropBlur`.
enum TitleShown {
  scrolled('scrolled');

  const TitleShown(this.wire);

  final String wire;

  /// The word of the document, or `null` for "no field" (always shown): an unknown word and a value that is
  /// not a string are no field.
  static TitleShown? parse(Object? raw) {
    for (final word in values) {
      if (word.wire == raw) return word;
    }
    return null;
  }
}

/// The four fields the scrolled layer may name; the structure of the schema accepts nothing else.
const Set<String> kScrolledStyleKeys = {'background', 'color', 'shadow', 'backdropBlur'};

/// The scrolled style of a bar, as the reader reads it: only the four fields, each on its own. `null` when
/// the value is not an object or no readable field is left (the schema refuses an empty style too).
NodeStyle? readScrolledStyle(Object? raw) {
  if (raw is! Map) return null;
  return NodeStyle.parse({
    for (final key in kScrolledStyleKeys)
      if (raw.containsKey(key)) key: raw[key],
  });
}

/// From which scroll the bar counts as scrolled. Never below zero.
double scrolledThreshold({required double barBottom, required double bodyTop}) => math.max(0, barBottom - bodyTop);

/// Whether the bar is scrolled by [scrollTop] logical pixels of the body. A scroll that is not a finite number
/// is rest.
bool isBarScrolled(double scrollTop, {required double barBottom, required double bodyTop}) =>
    scrollTop.isFinite && scrollTop > scrolledThreshold(barBottom: barBottom, bodyTop: bodyTop);

/// The style of the bar NOW: the resolved style (the base, the width layers, the `styleWhen` state), and over
/// it, LAST, the scrolled layer, field by field at the top level. Without a layer the style is returned as is.
NodeStyle? withScrolledLayer(NodeStyle? resolved, NodeStyle? scrolled) => scrolled?.over(resolved) ?? resolved;

/// Mirror of `x-style.layout.appBarScrolled` (scalar rows); checked against the artifact by a test.
const Map<String, Object> kAppBarScrolledRules = {
  'prop': 'styleScrolled',
  'titleProp': 'titleShown',
  'transition': 'immediate; a short fade is up to the reader',
  'unknownToken': 'a field whose token the theme does not know is dropped — the field under it stays',
};
