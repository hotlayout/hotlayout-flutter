/// The box of a node: the one place where style, size and surface of every
/// widget are applied.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../model/bindable.dart';
import '../../model/node.dart';
import '../../model/node_style.dart';
import '../../model/scrolled_bar.dart';
import '../../model/style_values.dart';
import '../../model/tokens.dart';
import '../layout/styled_size.dart';
import '../node_motion.dart';
import '../node_renderer.dart';
import '../render_scope.dart';
import 'image.dart';
import 'pressable.dart';

extension NodeBoxWidgets on NodeRenderer {
  /// Renders a node: its style, box and body.
  ///
  /// [flow] is the axis of the parent container. `Spacer` and `Divider` have their own
  /// `orientation`, so it is used only for text alignment; see [buildText].
  ///
  /// [stretchAlign]: the node is a STRETCHED column child (`columnChildWidth`), and the parent's
  /// `align` says where it goes if `minWidth` / `maxWidth` made it narrower than the space
  /// (`constrainedStretch: 'clamp-then-same-align'`).
  ///
  /// [naturalRow]: by the contract's rule (`rowInUnboundedWidth`) the parent gave the node no
  /// finite width: a stack layer or a child of a scrolling row. A row is then measured by its
  /// children's natural widths and weights do not apply in it.
  Widget renderNode(
    ChildNode node, {
    required Axis flow,
    Slot slot = Slot.free,
    AlignToken? stretchAlign,
    bool naturalRow = false,
  }) => styledNode(
    node,
    slot,
    (renderer, own) => renderer.renderBody(node, own, naturalRow: naturalRow, slot: slot),
    stretchAlign: stretchAlign,
  );

  /*
   * NODE STYLE: ONE PLACE FOR ALL WIDGETS (schema 9.0.0).
   *
   * Every node passes through this point, and three steps are taken here whose order is a
   * contract rule:
   *
   *  1. STATE: the base `style` plus the first state whose condition holds on THIS data
   *     (`resolveNodeStyle`). It is evaluated at render time, not at parse time: data changes
   *     without re-reading the document (another screen, other `params`, another repeater
   *     record);
   *  2. INHERITANCE: `color` and `typography`, state already applied, go down into the subtree
   *     (`inheriting`);
   *  3. THE BOX around what the widget itself drew (`nodeBox`).
   *
   * None of the widget drawing methods below knows about padding, background or radius, and a new
   * widget gets them without doing anything.
   *
   * TWO EXCEPTIONS, both named by the contract or by the layout itself:
   *
   *  - widgets with a ROLE (`Button`, `Badge`): the seven style fields go onto the widget's own
   *    surface and override the theme role, so they are not applied a second time on a box around
   *    it (`x-style.roles`);
   *  - a scrolling row: `padding` goes inside the scroll view; see `buildRow`.
   */
  ///
  /// [scrolledLayer] is the style an app bar takes while its body is scrolled (`styleScrolled`, already filtered
  /// by the theme), laid over the resolved style.
  ///
  /// [around] replaces what wraps the finished box (by default the press of a pressable container);
  /// [extraTop] is room added to the TOP INSIDE the box (the top safe inset in an app bar, 9.19.0): the
  /// box is taller by it, so a named background covers it.
  Widget styledNode(
    ChildNode node,
    Slot slot,
    Widget Function(NodeRenderer renderer, NodeStyle? own) build, {
    AlignToken? stretchAlign,
    Widget Function(Widget box)? around,
    double extraTop = 0,
    NodeStyle? scrolledLayer,
  }) {
    // AN UNKNOWN WIDGET WITH A STYLE: the style is ignored entirely and the children are drawn in
    // the PARENT's context. The reader builds no box around a node it does not understand: it
    // cannot know whether it is a card, a layer or something without a size.
    final resolved = node is UnknownNode
        ? null
        : resolveNodeStyle(node.style, node.styleWhen, data, applicable: theme.applicableStyle);
    // The layer of an app bar that is scrolled now (9.21.0) lies LAST: over the base, the width layers and the
    // state; its children inherit the colour from the result.
    final own = withScrolledLayer(resolved, scrolledLayer);
    final hasRole = node is ButtonNode || node is BadgeNode || node is IconButtonNode;
    // A role does not override an inherited color, and these widgets have no children, so there
    // is nobody to pass their own color on to.
    final renderer = hasRole ? this : inheriting(own);
    return renderer.nodeBox(
      hasRole ? own?.withoutRoleSurface : own,
      build(renderer, own),
      slot: slot,
      paddingInside: (node is RowNode && node.scrollable) || (node is RepeaterNode && node.carousel != null),
      stretchAlign: stretchAlign,
      around: _withMotion(node, around ?? renderer.pressWrapperOf(node, own)),
      extraTop: extraTop,
    );
  }

  /// [around] with the node's endless motion (9.20.0) on the outside of the box: the shift, scale and opacity are
  /// painted over the box the node has at rest, inside its margin. A node this reader does not understand is not
  /// moved.
  Widget Function(Widget box)? _withMotion(ChildNode node, Widget Function(Widget box)? around) {
    final motion = node is UnknownNode ? null : node.motion;
    if (motion == null) return around;
    return (box) => NodeMotionBox(motion: motion, child: around == null ? box : around(box));
  }

  /// THE NODE BOX. One model for all types:
  ///
  ///     margin → box (size, background, border, radius, shadow, opacity)
  ///            → padding → content
  ///
  /// The radius clips the background and content; the shadow lies OUTSIDE the clip, otherwise it
  /// would vanish together with what is past the edge. The size is the size of the BOX, including
  /// border and padding (like `box-sizing: border-box`).
  ///
  /// A property whose token the theme does not declare is not applied (`tokenWithoutFieldDefault:
  /// 'omit-field'`): the theme resolver returns `null` and the corresponding wrapper is simply
  /// absent.
  ///
  /// [paddingInside]: the widget itself already applied the padding (inside a scroll view).
  ///
  /// [around] wraps the finished box, inside the margin (a pressable container, 9.19.0: its target is the
  /// box without the margin).
  ///
  /// [extraTop] adds room at the top of the box, above the padding and the content: the padding grows by
  /// it and so does every height the style names, so the box is exactly [extraTop] taller.
  ///
  /// The glass of the node (`style.backdropBlur`, 9.20.0) blurs whatever lies under the box, within its radius.
  /// On a widget with a role the field is not in the box style: it lies on the role surface.
  Widget nodeBox(
    NodeStyle? style,
    Widget child, {
    Slot slot = Slot.free,
    bool paddingInside = false,
    AlignToken? stretchAlign,
    Widget Function(Widget box)? around,
    double extraTop = 0,
  }) {
    if (style == null) {
      final room = extraTop > 0 ? Padding(padding: EdgeInsetsDirectional.only(top: extraTop), child: child) : child;
      return around == null ? room : around(room);
    }

    final border = borderSide(style.border);
    final radius = theme.resolveBoxRadius(style.radius);
    final limits = _sizeLimits(style, slot, extraTop: extraTop);

    Widget result = child;

    // The border consumes layout pixels, as in CSS: content starts inside it.
    final padding = paddingInside ? null : theme.resolveBoxSpacing(style.padding);
    var inset = border == null ? padding : EdgeInsetsDirectional.all(border.width).add(padding ?? EdgeInsets.zero);
    if (extraTop > 0) inset = (inset ?? EdgeInsetsDirectional.zero).add(EdgeInsetsDirectional.only(top: extraTop));
    if (inset != null) result = Padding(padding: inset, child: result);

    final background = style.background;
    result = nodeSurface(
      color: background is ColorBackground ? theme.resolveColor(background.color) : null,
      gradient: background is GradientBackground ? theme.resolveGradient(background.gradient) : null,
      image: background is ImageBackground ? background : null,
      radius: radius,
      shadow: style.shadow == null ? null : theme.resolveShadow(style.shadow!),
      border: border,
      blur: style.backdropBlur,
      child: result,
    );

    if (limits != null) result = StyledSize(limits: limits, stretchAlign: stretchAlign, child: result);

    // Opacity applies to the WHOLE box, shadow and border included, as in CSS. Zero is legal: the
    // node is invisible but still takes its space.
    final opacity = style.opacity;
    if (opacity != null && opacity < 1) result = Opacity(opacity: opacity, child: result);

    if (around != null) result = around(result);

    final margin = theme.resolveBoxSpacing(style.margin);
    if (margin != null) result = Padding(padding: margin, child: result);

    return result;
  }

  /// The border from the style, or `null` if there is none or its color did not resolve. Without
  /// a color the border is absent, not "transparent": a transparent one would consume pixels.
  BorderSide? borderSide(NodeBorder? border) {
    if (border == null) return null;
    final color = theme.resolveColor(border.color);
    return color == null ? null : BorderSide(color: color, width: border.width);
  }

  /// A surface: background (color, gradient or image), border, radius and shadow.
  ///
  /// Shared by the node box and by the surface of a widget with a role: a second copy would drift
  /// from the first on the first edit.
  ///
  /// The border is the same on all sides, which is why it can be drawn together with DIFFERENT
  /// corner radii: Flutter does not draw different side widths with rounding, and the contract
  /// has no such shape.
  ///
  /// [blur] is the glass (schema 9.20.0, `style.backdropBlur`): whatever lies under the box is blurred within the
  /// radius, the background lies over the blur, and the content stays sharp. The shadow lies OUTSIDE the clip that
  /// bounds the blur, or it would vanish with what is past the edge.
  Widget nodeSurface({
    Color? color,
    Gradient? gradient,
    ImageBackground? image,
    BorderRadiusGeometry? radius,
    List<BoxShadow>? shadow,
    BorderSide? border,
    int? blur,
    required Widget child,
  }) {
    final hasRadius = radius != null && radius != BorderRadiusDirectional.zero && radius != BorderRadius.zero;
    final hasShadow = shadow != null && shadow.isNotEmpty;
    final frame = border == null ? null : Border.fromBorderSide(border);

    Widget content = child;
    if (image != null) {
      /*
       * A background image is a LAYER under the content, not a `DecorationImage`: its source is
       * the same as the `Image` widget's (asset, address, SVG, binding), with the same "loading"
       * and "unavailable" states. `passthrough` keeps the stack from loosening the content's
       * constraints: the content sets the box size, not the layer.
       */
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          // `compact`: the "loading" and "unavailable" states here are an icon, not a caption. A
          // background can be as tall as one line of text, and an error message does not fit.
          Positioned.fill(child: imageContent(image.source, compact: true, fit: image.fit)),
          content,
        ],
      );
    }
    if (hasRadius) {
      content = ClipRRect(borderRadius: radius, child: content);
    } else if (image != null) {
      content = ClipRect(child: content);
    }
    // The border goes over the image, not under it: the background layer would cover it.
    if (frame != null && image != null) {
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: frame, borderRadius: hasRadius ? radius : null),
        child: content,
      );
    }

    final glass = blur != null;
    // With glass the shadow is drawn outside the blur clip (below), not by the background box.
    final plain = color == null && gradient == null && !hasShadow && (frame == null || image != null);
    final Widget surface = plain
        ? content
        : DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              gradient: gradient,
              borderRadius: hasRadius ? radius : null,
              boxShadow: hasShadow && !glass ? shadow : null,
              border: image == null ? frame : null,
            ),
            child: content,
          );
    if (!glass) return surface;

    final blurred = BackdropFilter(filter: ImageFilter.blur(sigmaX: blur.toDouble(), sigmaY: blur.toDouble()), child: surface);
    final clipped = hasRadius ? ClipRRect(borderRadius: radius, child: blurred) : ClipRect(child: blurred);
    if (!hasShadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: hasRadius ? radius : null, boxShadow: shadow),
      child: clipped,
    );
  }

  /// The box's size limits, or `null` if the style names no size.
  ///
  /// `invertedSizeRange: 'min-wins'`: a `minWidth` greater than `maxWidth` wins. Flutter's
  /// `BoxConstraints` CRASHES on such a pair, so the rule is applied here, before the
  /// constructor. A given `width` is clamped between them, as in CSS.
  ///
  /// [slot] says whether the PARENT has already set the size: a weight beats `style.width`
  /// (`x-style.weightOverridesWidth`), and a layer stretched over the stack takes the stack's
  /// size whole.
  BoxConstraints? _sizeLimits(NodeStyle style, Slot slot, {double extraTop = 0}) {
    if (slot == Slot.fill) return null;
    final (minWidth, maxWidth) = slot == Slot.weighted
        ? (0.0, double.infinity)
        : _axisLimits(style.width, style.minWidth, style.maxWidth);
    var (minHeight, maxHeight) = _axisLimits(style.height, style.minHeight, style.maxHeight);
    // The room added at the top belongs to the box: a height the style names grows by it.
    if (extraTop > 0) {
      minHeight += minHeight > 0 ? extraTop : 0;
      maxHeight += maxHeight.isFinite ? extraTop : 0;
    }
    final limits = BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
    return limits == const BoxConstraints() ? null : limits;
  }

  (double, double) _axisLimits(BindableNumber? exact, BindableNumber? min, BindableNumber? max) {
    var lower = dimension(min) ?? 0;
    var upper = dimension(max) ?? double.infinity;
    if (lower > upper) upper = lower;
    final size = dimension(exact);
    if (size != null) lower = upper = size.clamp(lower, upper).toDouble();
    return (lower, upper);
  }

  /// A size in dp.
  ///
  /// A value from DATA that is not a number or lies outside the schema's range (1..1200) yields
  /// the binding's FALLBACK value: an out-of-range number is not an element size but a data error,
  /// and a negative height is an assertion failure in Flutter. That a "non-number" yields the
  /// fallback is already stated by the binding itself ([BoundNumber.resolve]).
  double? dimension(BindableNumber? value) {
    if (value == null) return null;
    final resolved = value.resolve(data);
    final valid = resolved.isFinite && resolved >= kStyleSizeMin && resolved <= kStyleSizeMax;
    if (valid) return resolved;
    return value is BoundNumber ? value.fallback : null;
  }

  /// Whether the node NAMES its own width (`style.width`, state applied).
  bool namesOwnWidth(ChildNode node) =>
      resolveNodeStyle(node.style, node.styleWhen, data, applicable: theme.applicableStyle)?.width != null;

  /// The smallest width the node names itself (including the margin around the box). Needed by a
  /// scrolling row; see `_scrollRow`.
  double declaredWidth(ChildNode node) {
    final own = resolveNodeStyle(node.style, node.styleWhen, data, applicable: theme.applicableStyle);
    if (own == null) return 0;
    final (lower, _) = _axisLimits(own.width, own.minWidth, own.maxWidth);
    return lower + (theme.resolveBoxSpacing(own.margin)?.horizontal ?? 0);
  }
}
