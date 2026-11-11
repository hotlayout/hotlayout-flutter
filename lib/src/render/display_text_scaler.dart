/// The system text scale for a large font size.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../model/display_typography.dart';

/// A [TextScaler] that follows the system one up to a font size of 96 and keeps a larger size from growing with it
/// (see [scaledFontSize]): 240 stays 240 on every scale, 100 on scale 1.3 becomes 124.8, never less than itself on a
/// scale above one. A system scaler that is not linear is asked as it is.
///
/// Everything in the reader that grows with the text (the glyphs, the line, an icon beside a text, the marker column of
/// a list item) asks the scaler of its [MediaQuery], so wrapping a screen in this one is the whole rule.
class DisplayTextScaler implements TextScaler {
  /// A scaler over [base]; a scaler that already is one is not wrapped twice.
  factory DisplayTextScaler(TextScaler base) => base is DisplayTextScaler ? base : DisplayTextScaler._(base);

  const DisplayTextScaler._(this.base);

  final TextScaler base;

  @override
  double scale(double fontSize) {
    final scaled = base.scale(fontSize);
    if (fontSize <= kDisplayTextScaleCeilingPx || scaled <= fontSize) return scaled;
    return math.max(fontSize, base.scale(kDisplayTextScaleCeilingPx));
  }

  @override
  // The deprecated getter is part of the interface; the scaler is asked through [scale].
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor;

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = double.infinity}) =>
      DisplayTextScaler(base.clamp(minScaleFactor: minScaleFactor, maxScaleFactor: maxScaleFactor));

  @override
  bool operator ==(Object other) => other is DisplayTextScaler && other.base == base;

  @override
  int get hashCode => Object.hash(DisplayTextScaler, base);
}
