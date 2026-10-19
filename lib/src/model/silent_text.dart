/// A NODE THAT PAINTS NOTHING SAYS NOTHING (`x-silentText`).
///
/// The name of a pressable card is its label, then the text of its content. A text drawn fully transparent is not
/// seen, so it must not be heard either: otherwise a document could show "Show offer" and have a screen reader say
/// "Show offer Confirm transfer".
///
/// "Paints nothing" is one of two things: the resolved `style.opacity` (with the state of `styleWhen`) is 0 on the
/// text or on a node between the card and the text, or the colour the text is drawn in (its own or inherited)
/// resolves with opacity 0. Exactly zero: 0.01 is a text that is seen. A control keeps its own name.
library;

/// Whether a text paints nothing: one of the [opacities] of the nodes from the card down to the text is 0, or the
/// opacity of its resolved colour is ([colorOpacity] `null` is a colour that did not resolve).
bool textPaintsNothing({required Iterable<double?> opacities, required double? colorOpacity}) =>
    opacities.any((opacity) => opacity == 0) || colorOpacity == 0;

/// Mirror of the scalar rows of `x-silentText`; checked against the artifact by a test.
const Map<String, String> kSilentTextRules = {
  'refines': 'x-style.layout.composition.pressable.semantics.name',
  'cases': 'contract/fixtures/accessible-name/silent-text-cases.json',
};
