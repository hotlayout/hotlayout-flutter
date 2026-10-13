/// The parts of a list row (schema 9.19.0): the tile under the leading icon, the trailing text with its own
/// style and the caption under it.
library;

import 'package:flutter/material.dart';

import '../../model/layout_rules.dart';
import '../../model/list_tile_parts.dart';
import '../../model/node.dart';
import '../../model/part_style.dart';
import '../../model/tokens.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import 'button.dart';
import 'image.dart';

extension ListTilePartsWidgets on NodeRenderer {
  /// The style of one part now: the base, with the first state that holds laid over it, with every field the
  /// theme will not apply left out.
  PartStyle? _partStyle(PartStyle? base, List<PartStyleCase> cases) =>
      resolvePartStyle(base, cases, (when) => when.evaluate(data), applicable: theme.applicablePartStyle);

  /// The leading icon: its colour (`leading.color`, then the named colour of the node, then `primary`) and, with a
  /// tile, the square under it. The glyph keeps its size and stands in the centre; a glyph larger than the tile is
  /// clipped by it. The box of a tile does not grow with the system font scale, the glyph does.
  Widget leadingIconSlot(LeadingIcon leading) {
    final own = leading.color == null ? null : theme.resolveColor(leading.color!);
    final glyph = buildIconBox(kListTileLeadingIconSize, leading.icon, own ?? partColor(ColorToken.primary));
    final tile = leading.tile;
    if (tile == null) return glyph;
    final side = tile.size.toDouble();
    final radius = theme.resolveRadius(tile.radius) ?? theme.radius(kLeadingTileRadius);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: side,
        // An unknown colour token leaves the box without a background.
        child: ColoredBox(
          color: theme.resolveColor(tile.color) ?? const Color(0x00000000),
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: glyph,
          ),
        ),
      ),
    );
  }

  /// The trailing text (and the icon beside it) over its caption, both pushed to the logical end, without a gap.
  ///
  /// The colour of the text: the state of the part, the style of the part, the named colour of the node (with its
  /// states), `onSurface`; the font: the state, the style, `bodyM`. The icon takes the colour of the text and keeps
  /// its own size. One line, not wrapped. The caption: one line in `bodyS`, its own colour (`captionStyle`), or the
  /// named colour of the node with the secondary opacity, or `muted`; the style of the text does not reach it.
  Widget trailingTextSlot(TrailingText trailing) {
    final style = _partStyle(trailing.style, trailing.styleWhen);
    final color = (style?.color == null ? null : theme.resolveColor(style!.color!)) ?? partColor(kListTileTrailingColor);
    final font = (style?.typography == null ? null : theme.resolveTypography(style!.typography!)) ?? theme.text(TypographyToken.bodyM);
    final line = buildIconBesideText(
      Text(text(trailing.text), style: font.copyWith(color: color), softWrap: false),
      icon: trailing.icon,
      position: IconPositionToken.end,
      color: color,
      box: theme.iconBox(kListTileTrailingIconSize),
    );
    final captionText = trailing.caption == null ? '' : text(trailing.caption!);
    if (captionText.isEmpty) return line;

    final captionStyle = _partStyle(trailing.captionStyle, trailing.captionStyleWhen);
    final captionColor =
        (captionStyle?.color == null ? null : theme.resolveColor(captionStyle!.color!)) ??
        partColor(ColorToken.muted, secondary: true);
    final captionFont =
        (captionStyle?.typography == null ? null : theme.resolveTypography(captionStyle!.typography!)) ??
        theme.text(TypographyToken.bodyS);
    return QuietColumn(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        Text(captionText, style: captionFont.copyWith(color: captionColor), softWrap: false),
      ],
    );
  }
}
