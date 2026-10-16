/// The stack: layers placed over one another, with alignment, offset and turn.
library;

import 'package:flutter/material.dart';

import '../../model/layout_rules.dart';
import '../../model/node.dart';
import '../../model/offset_rules.dart';
import '../layer_place.dart';
import '../node_motion.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import 'node_box.dart';
import 'render_tokens.dart';

extension OverlayWidgets on NodeRenderer {
  /// The stack: layers at one point, the first in the list is the lowest.
  ///
  /// WHY THERE IS NO `SizedBox(width: double.infinity)` HERE. The stack's size follows its
  /// non-stretched layers; an unbounded width comes only from a PARENT that stretches: a column
  /// (`ColumnStretch` sets a tight width, and the `Stack` fills it by itself), a grid cell, a
  /// list instance, a row share with `weight`. In a row without weights the stack takes the
  /// natural width of its widest layer, as other readers do. An infinite width here would make
  /// the stack take the whole row together with its neighbors.
  ///
  /// There is no gap between layers by construction, so the contract has no `gap` and nothing
  /// to substitute.
  Widget buildOverlay(StackNode node) {
    final layers = visibleNodes(node.children);
    if (layers.isEmpty) return const SizedBox.shrink();

    /*
     * A STACK WHOSE LAYERS ARE ALL STRETCHED has nothing to measure it by: `Positioned.fill`
     * takes the stack's size, and the stack takes the size of its non-stretched layers. The
     * builder rejects such a document, but it may not have come from the builder, and in Flutter
     * this is not an empty space but an infinite height inside a scroll view, that is, a crash.
     * In that case the layers take their own size, like nodes without `fill`.
     */
    final measurable = layers.any((layer) => !layer.fill);

    /*
     * OVERLAYS (schema 9.10.0, `layer`). A layer that carries a placement is positioned RELATIVE
     * to the stack's box and does not measure the stack, but only when the stack has a layer
     * that sets the size (`noSizingLayer: ignore-layer`); otherwise the field is read on no
     * layer at all, not "on all but the first". `readerLayerOf` decides this, not the code here.
     *
     * "THE STACK STILL HAS A SIZING LAYER" IS COUNTED FROM THE DOCUMENT, NOT FROM VISIBILITY.
     * A sizing layer hidden by a condition does not turn overlays into sizing layers: the stack
     * is then ZERO-sized, and overlays stay overlays positioned relative to it. Passing only the
     * visible siblings would make a badge jump from the corner into the flow as soon as a
     * condition hid the icon under it. So `readerLayerOf` / `sizesStack` are given
     * `node.children`.
     */
    final sizerShown = layers.any((layer) => sizesStack(layer, node));
    final zeroSized = measurable && !sizerShown;
    final stack = Stack(
      alignment: AlignmentDirectional(
        alignFactor(node.alignHorizontal),
        alignFactor(node.alignVertical),
      ),
      // The stack itself does NOT clip (`layerClip`): a badge past a tile's corner shows in full.
      // Clipping is done by the radius, a named size, a scroll view and the root. `Stack` clips
      // by default (`hardEdge`), which would hide the overhang.
      clipBehavior: Clip.none,
      children: [
        /*
         * A layer behaves like a column child: its width is full, so `flow: Axis.vertical`
         * gives text alignment something to measure from.
         *
         * A STRETCHED LAYER (schema 8.14.0) is `Positioned.fill`, and this is not decoration but
         * a difference in WHO sets the size. A regular layer gets loose constraints and takes
         * its own size; a gradient strip has no content of its own, so without this its width
         * is zero and it is simply invisible. `Positioned.fill` says "take the whole stack",
         * while the stack is measured by the remaining layers.
         *
         * Own sizes from `style` do not apply to such a layer for the same reason a weight beats
         * `style.width`: the parent has already set the size.
         *
         * The stack's `alignment` does not apply to it at all: it has nowhere to shift, since it
         * already fills everything.
         */
        for (final layer in layers)
          if (layer.fill && measurable)
            Positioned.fill(child: renderNode(layer, flow: Axis.vertical, slot: Slot.fill))
          else if (readerLayerOf(layer, node) case final place?)
            Positioned.fill(child: _placedLayer(node, layer, place))
          else
            // A layer without `fill` gets no reserved space (`rowInUnboundedWidth`).
            renderNode(layer, flow: Axis.vertical, naturalRow: true),
      ],
    );
    // All visible layers are overlays (the sizing layer is hidden): a stack with no unpositioned
    // children would take all of the parent's space, and in a scrolling column that is an
    // infinite height. So a zero-sized box, with the overlays sticking out of it
    // (`clipBehavior: none`).
    return zeroSized ? SizedBox.shrink(child: stack) : stack;
  }

  /// An overlay: its own alignment word or the stack's word (each axis separately), an offset in
  /// theme pixels, a rotation. A token the theme does not know means "no offset on this axis"
  /// (`tokenWithoutFieldDefault: 'omit-field'`).
  Widget _placedLayer(StackNode stack, ChildNode layer, LayerPlacement place) {
    LayerPixelOffset? pixels(LayerAxisOffset? axis) {
      if (axis == null) return null;
      final by = theme.resolveSpacing(axis.by);
      return by == null ? null : LayerPixelOffset(axis.toward, by);
    }

    final placed = LayerPlace(
      alignHorizontal: place.alignHorizontal ?? stack.alignHorizontal,
      alignVertical: place.alignVertical ?? stack.alignVertical,
      offsetX: pixels(place.offsetX),
      offsetY: pixels(place.offsetY),
      rotate: place.rotate,
      child: renderNode(layer, flow: Axis.vertical, naturalRow: true),
    );
    if (place.rotate == 0) return placed;
    // A motion inside a rotated layer shifts along the axes of the screen: tell it how far the frame is turned.
    return Builder(
      builder: (context) {
        final turned = Directionality.of(context) == TextDirection.rtl ? -place.rotate : place.rotate;
        return PaintRotation(degrees: PaintRotation.of(context) + turned, child: placed);
      },
    );
  }
}
