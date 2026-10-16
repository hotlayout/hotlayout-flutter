/// THE GLOW OF A SCALE (schema 9.25.0, `glow` on `ProgressBar` and `CircularProgress`; rules in `x-progressGlow`).
///
/// A blurred copy of the paint of the FILL (its colour, or its gradient along the fill) lies under the scale. The
/// track does not glow. It takes no room, moves nothing and is not clipped by the box of the node.
/// `test/progress_cases_test.dart` (`glowRuleCases`, `glowStepCases`) compares these numbers with the artifact.
library;

/// The strength of a glow: the standard deviation of the Gaussian blur in logical pixels and the factor of the alpha
/// of the paint of the copy.
enum ProgressGlow {
  soft('soft', sigma: 4, opacity: 0.55),
  strong('strong', sigma: 8, opacity: 0.9);

  const ProgressGlow(this.wire, {required this.sigma, required this.opacity});

  final String wire;
  final double sigma;
  final double opacity;

  /// The word of the document, or `null` for "no glow": an absent field, an unknown word and a value that is not a
  /// string are all no field.
  static ProgressGlow? parse(Object? raw) {
    for (final glow in values) {
      if (glow.wire == raw) return glow;
    }
    return null;
  }
}

/// What glows in a bar with steps.
enum GlowStepKind {
  /// The current step, painted by `currentColor`: the whole step glows in that colour.
  current,

  /// The last step with any fill: the drawn part of its fill glows in the fill paint.
  front,

  /// No glow.
  none,
}

/// The step that glows and how.
final class GlowingStep {
  const GlowingStep(this.kind, [this.index = -1, this.fill = 1]);

  static const GlowingStep none = GlowingStep(GlowStepKind.none);

  final GlowStepKind kind;
  final int index;

  /// For [GlowStepKind.front]: the share of the step that is drawn.
  final double fill;
}

/// Which step of a bar with steps glows (`glowingStepOf`). [fills] are the fills of the steps (0…1);
/// [currentPainted] says that `currentColor` is there and resolves.
GlowingStep glowingStepOf(List<double> fills, {required bool currentPainted}) {
  if (currentPainted) {
    for (var i = 0; i < fills.length; i += 1) {
      if (fills[i] < 1) return GlowingStep(GlowStepKind.current, i);
    }
  }
  for (var i = fills.length - 1; i >= 0; i -= 1) {
    if (fills[i] > 0) return GlowingStep(GlowStepKind.front, i, fills[i]);
  }
  return GlowingStep.none;
}
