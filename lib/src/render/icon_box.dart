// The box an icon glyph is drawn in.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/tokens.dart';
import 'icon_glyph.dart';

/// An icon in its box: as wide as the font token's size, as tall as its line, with a glyph of
/// the token's size centred in it. The system font scale multiplies both sides, as it would
/// the text of the same token, so the box grows with the glyph instead of keeping the old
/// height.
class IconBox extends StatelessWidget {
  const IconBox({required this.box, required this.icon, required this.color, this.glyph, super.key});

  /// Box before scaling (`RenderTheme.iconBox`): the width is the font size.
  final Size box;

  /// Side of the drawing before scaling; `null` means the box width (the font size). An icon
  /// button names it separately: there the box is a SQUARE the height of a text line and the
  /// drawing is font-sized (`iconButton.contentBox` / `glyph`).
  final double? glyph;

  /// A name from the contract's icon set; [IconToken.unknown] gives a box with no drawing.
  final IconToken icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final scale = box.width == 0 ? 1.0 : scaler.scale(box.width) / box.width;
    return SizedBox(
      width: box.width * scale,
      height: box.height * scale,
      child: Center(child: IconGlyph(icon, size: glyph ?? box.width, color: color)),
    );
  }
}

/// A drawing with its own size (`glyphSize`, schema 9.16.0): the content box is a square with
/// side [side], the drawing centred in it. The system font scale does NOT multiply the number
/// (these are logical pixels, like `style.width`).
///
/// A named side of the node CLAMPS the drawing: when the box the parent gave (`style.width` or
/// `height` minus insets and border) is smaller than [side], the drawing is exactly its
/// shorter side, no more. Without a named side the box is exactly [side] and there is nothing
/// to clamp.
class OwnGlyphBox extends StatelessWidget {
  const OwnGlyphBox({required this.side, required this.icon, required this.color, super.key});

  final double side;
  final IconToken icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: side,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final room = math.min(constraints.maxWidth, constraints.maxHeight);
        final glyph = math.max(0.0, math.min(side, room.isFinite ? room : side));
        // `IconGlyph` multiplies the side by the system font scale; this number is not a font.
        return Center(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
            child: IconGlyph(icon, size: glyph, color: color),
          ),
        );
      },
    ),
  );
}
