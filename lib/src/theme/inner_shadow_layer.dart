/// The data of an inner layer of a shadow, resolved by the theme and painted by the renderer.
library;

import 'package:flutter/material.dart';

/// One INNER layer of a shadow, in logical pixels, with its colour already resolved.
@immutable
final class InnerShadow {
  const InnerShadow({required this.color, this.offset = Offset.zero, this.blurRadius = 0, this.spreadRadius = 0});

  final Color color;
  final Offset offset;
  final double blurRadius;
  final double spreadRadius;

  /// The same layer with another colour (a shadow tinted by the hue of its background).
  InnerShadow withColor(Color value) =>
      InnerShadow(color: value, offset: offset, blurRadius: blurRadius, spreadRadius: spreadRadius);

  @override
  bool operator ==(Object other) =>
      other is InnerShadow &&
      other.color == color &&
      other.offset == offset &&
      other.blurRadius == blurRadius &&
      other.spreadRadius == spreadRadius;

  @override
  int get hashCode => Object.hash(color, offset, blurRadius, spreadRadius);
}
