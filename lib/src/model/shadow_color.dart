/// The colour of a shadow taken from the node's own background (schema 9.25.0, `style.shadowColor`).
///
/// Mirror of the contract's `x-shadowColor` block; `test/shadow_color_cases_test.dart` compares it with the artifact
/// and runs the shared table (`assets/contract/fixtures/shadow-color/shadow-color-cases.json`).
library;

/// The words of the field. The only one: every layer of the shadow takes the hue of the background and keeps its
/// own opacity.
enum ShadowColorWord {
  background;

  /// The word of the document, or `null` for "no field": an unknown word and a value that is not a string are no
  /// field, and the shadow keeps its own colour.
  static ShadowColorWord? tryParse(Object? raw) {
    for (final word in values) {
      if (word.name == raw) return word;
    }
    return null;
  }
}

/// The index of the stop whose colour a shadow takes from a gradient background: the stop nearest to the middle
/// (0.5); on a tie the earlier one. `null` when there are no stops.
int? middleStopIndex(List<double> positions) {
  int? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < positions.length; i += 1) {
    final distance = (positions[i] - 0.5).abs();
    if (distance < bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}
