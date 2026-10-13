/// A collapsible block with a header.
library;

import 'package:flutter/material.dart';

import '../model/tokens.dart';
import 'icon_glyph.dart';
import 'layout/quiet_flex.dart';
import 'motion.dart';
import 'tap_target.dart';

/// Expandable block. Custom rather than `ExpansionTile`, to avoid requiring a `Material`
/// ancestor and fighting its built-in insets.
class AccordionBlock extends StatefulWidget {
  const AccordionBlock({
    super.key,
    required this.title,
    required this.titleStyle,
    required this.iconColor,
    required this.initiallyExpanded,
    required this.chevronSize,
    required this.gap,
    required this.body,
  });

  final String title;
  final TextStyle titleStyle;
  final Color iconColor;
  final bool initiallyExpanded;

  /// Size of the chevron glyph.
  final double chevronSize;

  /// Gap between title and chevron, and between title and content.
  final double gap;
  final Widget body;

  @override
  State<AccordionBlock> createState() => _AccordionBlockState();
}

class _AccordionBlockState extends State<AccordionBlock> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return QuietColumn(
      // `stretch`: the block's content is a column child, and it must receive the parent's content
      // width (`columnChildWidth`) as TIGHT. The title with `Expanded` fills all the space given
      // anyway, so the block does not get wider.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TapTarget(
          child:
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            /*
             * The header is a caption row plus a chevron, with no insets of its own. The block has no
             * built-in insets (the card and padding come from the document's `style`); 8 dp above and
             * below the title and a 24 dp chevron would make a collapsed block 40 tall instead of 22 and
             * push everything below it 18 dp lower than on the builder canvas. The chevron is a glyph of
             * size `md` (font size `titleM`), as in the canvas and the preview model.
             */
            child: QuietRow(
              children: [
                Expanded(child: Text(widget.title, style: widget.titleStyle)),
                SizedBox(width: widget.gap),
                /*
                 * The block's chevron is the icon set's `chevron`: collapsed it points to the end of the
                 * line, expanded it points down, i.e. a quarter turn. In RTL the drawing is already mirrored
                 * (`IconGlyph`), so "down" is a quarter turn in the OTHER direction.
                 */
                AnimatedRotation(
                  turns: !_expanded
                      ? 0
                      : Directionality.of(context) == TextDirection.rtl
                      ? -0.25
                      : 0.25,
                  duration: motionOf(context, Motion.quick),
                  curve: Motion.standard,
                  child: IconGlyph(IconToken.chevron, size: widget.chevronSize, color: widget.iconColor),
                ),
              ],
            ),
          ),
        ),
        /*
         * The content EXPANDS rather than appearing: if only the arrow rotated smoothly while
         * everything under it jumped, half the gesture would be animated and half not, and together
         * they would read as a glitch rather than motion.
         *
         * `AnimatedSize` measures the child and animates the height from zero to its own, so the
         * code never needs to know how many pixels it is; that matters here because the block holds
         * an arbitrary subtree of the document.
         *
         * Collapsed, the body is REPLACED by an empty box, not hidden: a zero-height widget that is
         * still built would cost as much as a visible one, and cheap collapsed blocks are the reason
         * to have them on long screens.
         */
        AnimatedSize(
          duration: motionOf(context, Motion.quick),
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          // The `sm` gap is BETWEEN the title and the content, so a collapsed block has none; there
          // is no inset below the content either.
          child: _expanded
              ? Padding(padding: EdgeInsets.only(top: widget.gap), child: widget.body)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
