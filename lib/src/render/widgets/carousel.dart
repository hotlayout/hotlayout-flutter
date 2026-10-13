/// The carousel: a scrolling row that snaps to cards, with dots under it.
library;

import 'package:flutter/material.dart';

import '../../model/carousel_rules.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/tokens.dart';
import '../carousel.dart';
import '../layout/quiet_flex.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import 'node_box.dart';
import 'render_tokens.dart';
import 'row.dart';

extension CarouselWidgets on NodeRenderer {
  /*
   * The CAROUSEL (schema 9.11.0, `x-style.layout.carousel`): a sideways scroll that snaps to
   * cards, with dots under it. Cards are the row's children or instances of a list template;
   * each comes with its OWN renderer (in a list it carries the record scope), hence the
   * "renderer, node" pair.
   *
   * The viewport is the width the parent gave (`nodeBox` has already removed the node's frame);
   * the node's padding lies inside the scroll. With `perView` every card has the width
   * `carouselCardWidth`, which beats the card's own `width`, `minWidth` and `maxWidth` (the
   * `weighted` slot drops them, as under a weight); `margin` is added on top. If no card width
   * can be computed (too narrow), the width is natural, as without the field.
   */
  Widget buildCarousel(
    ReaderCarousel carousel,
    NodeStyle? own, {
    required double gap,
    required AlignToken align,
    required String nodeId,
    required List<(NodeRenderer, ChildNode)> items,
  }) {
    final padding = theme.resolveBoxSpacing(own?.padding) ?? EdgeInsetsDirectional.zero;
    final peekRef = carousel.peek;
    final peek = (peekRef == null ? null : theme.resolveSpacing(peekRef)) ?? theme.spacing[kDefaultCarouselPeek] ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final perView = carousel.perView;
        final cardWidth = perView == null || !viewport.isFinite
            ? null
            : carouselCardWidth(
                viewport: viewport,
                paddingStart: padding.start,
                gap: gap,
                peek: peek,
                perView: perView,
              );
        final cards = <Widget>[];
        final widths = <double>[];
        for (final (renderer, node) in items) {
          if (cardWidth == null) {
            cards.add(renderer.scrollChild(node, viewport));
            continue;
          }
          final outer = cardWidth + renderer.marginInline(node);
          widths.add(outer);
          cards.add(SizedBox(width: outer, child: renderer.renderNode(node, flow: Axis.horizontal, slot: Slot.weighted)));
        }
        return Carousel(
          stateKey: carouselStateKey(nodeId, instance),
          memory: carouselMemory,
          cards: cards,
          cardWidths: cardWidth == null ? null : widths,
          viewport: viewport,
          padding: padding,
          gap: gap,
          dots: carousel.dots,
          indicatorGap: theme.spacing[kCarouselIndicatorGap] ?? 0,
          dotSize: theme.spacing[kCarouselDotSize] ?? 0,
          dotGap: theme.spacing[kCarouselDotGap] ?? 0,
          dotRadius: theme.radii[kCarouselDotRadius] ?? 0,
          activeColor: theme.color(ColorToken.primary),
          rowBuilder: (children) => QuietRow(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxis(align),
            children: children,
          ),
        );
      },
    );
  }
}
