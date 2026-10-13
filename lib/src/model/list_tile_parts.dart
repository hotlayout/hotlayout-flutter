import 'package:flutter/foundation.dart';

import 'style_values.dart';
import 'tokens.dart';

/// THE PARTS OF A LIST ROW (schema 9.19.0, `x-style.layout.listTileParts`): the line limits of the title and the
/// subtitle, the tile under the leading icon, the column of the trailing part with its caption and the three
/// columns of the row. Pure rules; the drawing is `render/widgets/list_tile.dart`.

// ───────────────────────────── line limits ─────────────────────────────

const int kListTileLinesMin = 1;
const int kListTileLinesMax = 5;



/// A line limit (`titleMaxLines`, `subtitleMaxLines`): a whole number from 1 to 5. Anything else (zero, six, a
/// fraction, a string, absent) is no limit.
int? listTileLinesOf(Object? raw) => wholeNumberIn(raw, kListTileLinesMin, kListTileLinesMax);

/// How many lines a text of [naturalLines] lines takes under [limit], and whether it is cut with an ellipsis at
/// the logical end of the last line (`listTileShownLines`).
({int lines, bool cut}) listTileShownLines(int naturalLines, Object? limit) {
  final max = listTileLinesOf(limit);
  return max == null || naturalLines <= max ? (lines: naturalLines, cut: false) : (lines: max, cut: true);
}

// ───────────────────────────── the tile under the leading icon ─────────────────────────────

const int kLeadingTileSize = 40;
const int kLeadingTileSizeMin = 24;
const int kLeadingTileSizeMax = 96;

/// The radius of a tile that names none (or a bad one): the radius of the leading image.
const RadiusToken kLeadingTileRadius = RadiusToken.sm;

/// A tinted square (a circle with the radius `pill`) under the leading icon of a row.
@immutable
final class LeadingTile {
  const LeadingTile({required this.color, required this.radius, required this.size});

  final ColorRef color;

  /// A token name or a number of logical pixels, as the document wrote it or the default `sm`.
  final ScaleRef radius;

  /// The side in logical pixels.
  final int size;

  @override
  bool operator ==(Object other) =>
      other is LeadingTile && other.color == color && other.radius == radius && other.size == size;

  @override
  int get hashCode => Object.hash(color, radius, size);

  @override
  String toString() => 'LeadingTile($color, $radius, $size)';
}

/// The tile of a leading slot of the raw shape (`leadingTileOf`), or `null`: only a slot of kind `icon` has one,
/// and only with a readable `color`. A radius or a side out of range or of the wrong form is the default one.
LeadingTile? leadingTileOf(Object? leading) {
  if (leading is! Map || leading['kind'] != 'icon') return null;
  final tile = leading['tile'];
  if (tile is! Map) return null;
  final color = ColorRef.tryParse(tile['color']);
  if (color == null) return null;
  return LeadingTile(
    color: color,
    radius: strictRadiusRef(tile['radius']) ?? ScaleRef.token(kLeadingTileRadius.wire),
    size: wholeNumberIn(tile['size'], kLeadingTileSizeMin, kLeadingTileSizeMax) ?? kLeadingTileSize,
  );
}

/// The box of the leading slot and where the glyph stands in it (`leadingIconBoxOf`). Without a tile the box is the
/// glyph's. With one it is the tile's square, the glyph keeps its size and stands in the centre; a glyph larger than
/// the tile has negative offsets (the tile clips it).
typedef LeadingBox = ({double inline, double block, double glyphInline, double glyphBlock});

LeadingBox leadingIconBoxOf(LeadingTile? tile, ({double inline, double block}) glyph) {
  if (tile == null) return (inline: glyph.inline, block: glyph.block, glyphInline: 0, glyphBlock: 0);
  final side = tile.size.toDouble();
  return (inline: side, block: side, glyphInline: (side - glyph.inline) / 2, glyphBlock: (side - glyph.block) / 2);
}

// ───────────────────────────── the trailing column and the row ─────────────────────────────

/// The trailing text over its caption, both pushed to the logical end, without a gap (`trailingColumnOf`). The
/// column is as wide as the wider line and as tall as both.
typedef TrailingColumn = ({double inline, double block, double textStart, double? captionStart});

TrailingColumn trailingColumnOf({
  required double textInline,
  required double textLine,
  ({double inline, double line})? caption,
}) {
  final inline = caption == null || textInline >= caption.inline ? textInline : caption.inline;
  return (
    inline: inline,
    block: textLine + (caption?.line ?? 0),
    textStart: inline - textInline,
    captionStart: caption == null ? null : inline - caption.inline,
  );
}

/// A rectangle of the row, `x` from the LEFT edge of the content.
typedef RowRect = ({double x, double y, double width, double height});

/// The three columns of a row (`listTileRowRects`): the leading and the trailing column are of their own width,
/// the texts take the rest (not less than nothing), each is centred on the height of the row. In a right-to-left
/// screen the whole row is mirrored.
({double block, RowRect? leading, RowRect body, RowRect? trailing}) listTileRowRects({
  required double rowInline,
  required double gap,
  ({double inline, double block})? leading,
  ({double inline, double block})? trailing,
  required double bodyBlock,
  required bool rtl,
}) {
  final tallest = [leading?.block ?? 0, bodyBlock, trailing?.block ?? 0].reduce((a, b) => a > b ? a : b);
  final before = leading == null ? 0.0 : leading.inline + gap;
  final after = trailing == null ? 0.0 : trailing.inline + gap;
  final bodyInline = (rowInline - before - after) < 0 ? 0.0 : rowInline - before - after;
  RowRect place(double start, ({double inline, double block}) column) => (
    x: rtl ? rowInline - start - column.inline : start,
    y: (tallest - column.block) / 2,
    width: column.inline,
    height: column.block,
  );
  return (
    block: tallest,
    leading: leading == null ? null : place(0, leading),
    body: place(before, (inline: bodyInline, block: bodyBlock)),
    trailing: trailing == null ? null : place(before + bodyInline + gap, trailing),
  );
}
