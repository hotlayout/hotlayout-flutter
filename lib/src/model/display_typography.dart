/// Display typography: how a large font size meets the system text scale, and letter spacing as a share of the font
/// size.
library;

import 'dart:math' as math;

/// A font size above this is not multiplied directly by the system text scale.
const double kDisplayTextScaleCeilingPx = 96;

/// The font size after the system text scale [textScale].
///
/// Scale 2 does not turn a 240 poster number into 480. One rule serves every place that grows with the font size:
/// `s <= 1 ? f * s : max(f, min(f, 96) * s)`. Up to the ceiling it is exactly `f * s`; above it the size grows no
/// further than `96 * s` and is never below `f`. The function is continuous and does not decrease in `f`.
double scaledFontSize(double fontSize, double textScale) {
  if (textScale <= 1) return fontSize * textScale;
  return math.max(fontSize, math.min(fontSize, kDisplayTextScaleCeilingPx) * textScale);
}

/// The letter spacing in logical pixels for the EFFECTIVE font size [effectiveFontSize]: a share of it when the style
/// gives [letterSpacingEm] (the share wins over pixels), else [letterSpacing] as written (the text scale does not
/// multiply pixels).
double trackingPx({double? letterSpacing, double? letterSpacingEm, required double effectiveFontSize}) {
  if (letterSpacingEm != null) return letterSpacingEm * effectiveFontSize;
  return letterSpacing ?? 0;
}
