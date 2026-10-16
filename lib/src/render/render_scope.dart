/// Values the renderer carries down a subtree: inherited foreground, list
/// numbering, the slot a node stands in and the surface of a role.
library;

import 'package:flutter/material.dart';

import '../model/node.dart';
import '../model/style_values.dart';
import '../model/text_emphasis.dart';

/// Foreground at a point of the tree: colour and font, already resolved against the theme.
///
/// [named] says whether anyone (the node or an ancestor) named a colour at all. Without it,
/// composite widgets could not tell "inherited `onSurface`" from "nobody said anything", and
/// they paint those two cases differently.
///
/// [emphasis] is the slant and line of the text (schema 9.17.0). It is inherited by the same
/// rule, EACH FIELD separately, but only `Text` reads it. That is why it is a separate field
/// and not part of [style]: other widgets read the style, and an italic on a card must not
/// reach a button inside it.
typedef Foreground = ({Color color, TextStyle style, bool named, TextEmphasis emphasis});

/// Number of a numbered item and the size of its group, BY THE DOCUMENT.
typedef ListNumber = ({int number, int groupSize});

/// An instance of an item template: which node is the template, and its index in the data list.
typedef ListInstance = ({ChildNode template, int number, int groupSize});

/// Item numbers among siblings; written by [NodeRenderer._numberSiblings], read by
/// [NodeRenderer.buildText] in the same build pass.
final Expando<ListNumber> siblingNumbers = Expando<ListNumber>('listNumber');

/// Who sets the size of a node: the node itself or its parent.
enum Slot {
  /// The node states its own size (`style.width`, `height`, `min…`, `max…`).
  free,

  /// The parent set the width: a row child with a weight. A weight beats `style.width`
  /// (`x-style.weightOverridesWidth`); the height stays with the node.
  weighted,

  /// The parent set both sizes: a layer stretched over the whole stack, and the screen root.
  fill,
}

/// A role-bearing widget's surface, ready to paint.
///
/// `null` in [color], [gradient], [image] and [border] means "none" (transparent, no border);
/// in [radius], [shadow], [padding] and [typography] it means "the widget's built-in
/// geometry", the one it was painted with before schema 9.0.0.
@immutable
final class RoleSurface {
  const RoleSurface({
    required this.foreground,
    this.color,
    this.gradient,
    this.image,
    this.border,
    this.radius,
    this.shadow,
    this.padding,
    this.typography,
    this.blur,
  });

  final Color foreground;
  final Color? color;
  final Gradient? gradient;
  final ImageBackground? image;
  final BorderSide? border;
  final BorderRadiusGeometry? radius;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;
  final TextStyle? typography;

  /// Glass on the surface (9.20.0, `style.backdropBlur`): the blur under the box, where the background and the radius are.
  final int? blur;

  bool get hasBackground => color != null || gradient != null || image != null;
  bool get hasShadow => shadow != null && shadow!.isNotEmpty;
}

