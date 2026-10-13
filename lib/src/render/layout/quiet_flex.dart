// Row and column that clip an overflowing child instead of reporting it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/*
 * A ROW AND A COLUMN THAT DO NOT REPORT OVERFLOW.
 *
 * A plain `Flex` whose content does not fit paints a striped banner in debug builds and reports
 * an ERROR. For a hand-written app that is right: overflow is the developer's oversight. Here
 * the layout is written by the document, and since every node can have `style.width` / `height`,
 * "content larger than its box" is a legal document: a card 40 high with three lines of text,
 * a list row in a box 60 wide. The contract is silent about overflow, so the reader does the
 * quietest thing possible: it clips at the box edge, as a release build does, and does not
 * report as an error what is not a document error.
 */
class QuietRow extends Row {
  const QuietRow({super.key, super.mainAxisSize, super.crossAxisAlignment, super.children});

  @override
  RenderFlex createRenderObject(BuildContext context) => _QuietRenderFlex(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    textDirection: getEffectiveTextDirection(context),
    verticalDirection: verticalDirection,
  );
}

class QuietColumn extends Column {
  const QuietColumn({super.key, super.mainAxisSize, super.crossAxisAlignment, super.children});

  @override
  RenderFlex createRenderObject(BuildContext context) => _QuietRenderFlex(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    textDirection: getEffectiveTextDirection(context),
    verticalDirection: verticalDirection,
  );
}

class _QuietRenderFlex extends RenderFlex {
  _QuietRenderFlex({
    super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
  });

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    // Does any child stick out past the edge? Ask the geometry, not the private
    // `RenderFlex` flag: it is not visible from outside.
    var overflows = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final origin = (child.parentData! as FlexParentData).offset;
      const slack = 0.01;
      if (origin.dx < -slack ||
          origin.dy < -slack ||
          origin.dx + child.size.width > size.width + slack ||
          origin.dy + child.size.height > size.height + slack) {
        overflows = true;
        break;
      }
    }
    if (!overflows) {
      defaultPaint(context, offset);
      return;
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, defaultPaint);
  }
}
