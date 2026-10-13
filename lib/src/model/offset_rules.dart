import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import 'style_values.dart';
import 'tokens.dart';

// Overlay with offset (schema 9.10.0): mirror of the builder's `layer-placement.ts`.
//
// Two fields of a NODE, asking different questions:
//
//  * `layer` is the PLACE OF A LAYER IN A STACK: its own alignment, offset and rotation. Such a layer
//    is an overlay: it stands relative to the stack's box and never changes it;
//  * `pull` pulls the node in the FLOW towards the start of the parent's main axis: the node and
//    everything after it move, the node lies over the previous one, and the parent gets shorter.
//
// Only the shape of the values and the GEOMETRY are here, with no theme and no nodes. Which nodes are
// overlays and where the fields are legal is decided by `layout_rules.dart` (`readerLayerOf`,
// `effectivePull`); they are drawn by `LayerPlace` (stack) and `RenderStretchColumn` /
// `RenderRowLayout` (flow). The formulas are not copied into widgets: `LayerPlace` and the flow layout
// call these same functions, and `offset_cases_test.dart` runs them through a table shared by all
// readers.

/// Where a layer shifts horizontally. Logical: in right-to-left writing "start" is on the right.
const List<String> kLayerOffsetXToward = ['start', 'end'];

/// Where a layer shifts vertically. The sides are physical: top is top in any writing system.
const List<String> kLayerOffsetYToward = ['top', 'bottom'];

/// Bounds of the angle: a whole number of degrees clockwise.
const int kMinLayerRotate = -180;
const int kMaxLayerRotate = 180;

/// A spacing reference the reader understands: a token name or an integer 0..128. Unlike
/// [ScaleRef.tryParse] it does NOT clamp: an out-of-range or fractional number is "unreadable", not
/// "the nearest allowed" (`unreadablePull`, `unreadableLayer`). `3.0` is an integer (a parsing trap:
/// JSON gives a `double`).
ScaleRef? readSpacingRef(Object? raw) {
  if (raw is String) return isTokenName(raw) ? ScaleRef.token(raw) : null;
  if (raw is! num || !raw.isFinite || raw != raw.truncate()) return null;
  if (raw < 0 || raw > kMaxSpacingPx) return null;
  return ScaleRef.value(raw.toDouble());
}

/// One offset axis: a direction word and a magnitude (not yet resolved by the theme).
@immutable
final class LayerAxisOffset {
  const LayerAxisOffset(this.toward, this.by);

  /// `start` / `end` for horizontal, `top` / `bottom` for vertical.
  final String toward;
  final ScaleRef by;

  @override
  bool operator ==(Object other) => other is LayerAxisOffset && other.toward == toward && other.by == by;

  @override
  int get hashCode => Object.hash(toward, by);

  @override
  String toString() => 'LayerAxisOffset($toward ${by.token ?? by.value})';
}

/// The place of a layer as the READER draws it: everything unreadable has already been discarded.
@immutable
final class LayerPlacement {
  const LayerPlacement({
    this.alignHorizontal,
    this.alignVertical,
    this.offsetX,
    this.offsetY,
    this.rotate = 0,
  });

  /// `null` means the word is not named or unknown: the STACK's word (`align`) applies.
  final AlignToken? alignHorizontal;
  final AlignToken? alignVertical;

  /// `null` means there is no offset on the axis (not named, or the axis is unreadable).
  final LayerAxisOffset? offsetX;
  final LayerAxisOffset? offsetY;

  /// Degrees clockwise in left-to-right writing; 0 means no rotation.
  final int rotate;

  @override
  String toString() => 'LayerPlacement($alignHorizontal $alignVertical $offsetX $offsetY rotate $rotate)';
}

AlignToken? _readAlign(Object? raw) {
  for (final token in AlignToken.values) {
    if (token.wire == raw) return token;
  }
  return null;
}

LayerAxisOffset? _readAxis(Object? raw, List<String> words) {
  if (raw is! Map) return null;
  final toward = raw['toward'];
  if (toward is! String || !words.contains(toward)) return null;
  final by = readSpacingRef(raw['by']);
  return by == null ? null : LayerAxisOffset(toward, by);
}

/// The value of the `layer` field as the READER sees it (`unreadableLayer`).
///
/// The document may not have been built by the builder, so each part is read separately: a non-object is
/// not an overlay at all (`null`, an ordinary layer, as for a 9.9 reader); an unknown alignment word
/// means the stack's word; an offset axis with an unknown direction or an unreadable magnitude means no
/// offset on that axis; an angle that is not an integer within range means no rotation. One half of an
/// offset does not lose the other, and an unknown key (a newer minor) is skipped.
LayerPlacement? readLayerValue(Object? raw) {
  if (raw is! Map) return null;
  final offset = raw['offset'] is Map ? raw['offset'] as Map : const {};
  final angle = raw['rotate'];
  final readable =
      angle is num &&
      angle.isFinite &&
      angle == angle.truncate() &&
      angle >= kMinLayerRotate &&
      angle <= kMaxLayerRotate;
  return LayerPlacement(
    alignHorizontal: _readAlign(raw['alignHorizontal']),
    alignVertical: _readAlign(raw['alignVertical']),
    offsetX: _readAxis(offset['x'], kLayerOffsetXToward),
    offsetY: _readAxis(offset['y'], kLayerOffsetYToward),
    rotate: readable ? angle.toInt() : 0,
  );
}

/// Input of the overlay geometry. Sizes and offsets are logical pixels; spacing references have
/// already been resolved by the theme.
@immutable
final class LayerGeometryInput {
  const LayerGeometryInput({
    required this.stack,
    required this.layer,
    required this.alignHorizontal,
    required this.alignVertical,
    this.offsetXToward,
    this.offsetX = 0,
    this.offsetYToward,
    this.offsetY = 0,
    this.rotate = 0,
    required this.rtl,
  });

  /// The box of the stack the layers stand in.
  final Size stack;

  /// The layer's own size.
  final Size layer;
  final AlignToken alignHorizontal;
  final AlignToken alignVertical;

  /// `start` / `end`; `null` means there is no horizontal offset.
  final String? offsetXToward;
  final double offsetX;

  /// `top` / `bottom`; `null` means there is no vertical offset.
  final String? offsetYToward;
  final double offsetY;
  final int rotate;
  final bool rtl;
}

/// Where an overlay stands: the UNrotated box in the stack's PHYSICAL coordinates, the angle the layer
/// is drawn with, and whether what is drawn goes beyond the stack's box.
@immutable
final class LayerGeometry {
  const LayerGeometry(this.rect, this.angle, this.protrudes);

  final Rect rect;

  /// Degrees clockwise; in right-to-left writing the sign is flipped.
  final double angle;
  final bool protrudes;
}

double _alongAxis(double room, double size, AlignToken align) => switch (align) {
  AlignToken.start => 0,
  AlignToken.end => room - size,
  AlignToken.center => (room - size) / 2,
};

/// WHERE AN OVERLAY STANDS: the reference implementation (`order`, `rtl`, `layoutBox`).
///
/// Three steps, and the order is a statement of the contract: alignment (horizontally, `start` is the
/// start of the LINE); offset in the stack's axes (`x` logical, `y` physical); rotation around the
/// center of the already shifted box (the sign of the angle flips in RTL). No step touches the size of
/// the stack.
LayerGeometry layerGeometry(LayerGeometryInput input) {
  final stack = input.stack;
  final layer = input.layer;
  var inlineStart = _alongAxis(stack.width, layer.width, input.alignHorizontal);
  if (input.offsetXToward != null) {
    inlineStart += input.offsetXToward == 'end' ? input.offsetX : -input.offsetX;
  }
  var y = _alongAxis(stack.height, layer.height, input.alignVertical);
  if (input.offsetYToward != null) {
    y += input.offsetYToward == 'bottom' ? input.offsetY : -input.offsetY;
  }
  final x = input.rtl ? stack.width - inlineStart - layer.width : inlineStart;
  // `+ 0.0`: in RTL a zero angle must not become "minus zero".
  final angle = (input.rtl ? -input.rotate : input.rotate).toDouble() + 0.0;
  final rect = Rect.fromLTWH(x, y, layer.width, layer.height);

  final radians = angle * math.pi / 180;
  final center = rect.center;
  const epsilon = 1e-9;
  var protrudes = false;
  for (final (sx, sy) in const [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]) {
    final dx = sx * layer.width / 2;
    final dy = sy * layer.height / 2;
    final px = center.dx + dx * math.cos(radians) - dy * math.sin(radians);
    final py = center.dy + dx * math.sin(radians) + dy * math.cos(radians);
    if (px < -epsilon || py < -epsilon || px > stack.width + epsilon || py > stack.height + epsilon) {
      protrudes = true;
    }
  }
  return LayerGeometry(rect, angle, protrudes);
}

/// Whether a point of the stack lies inside the drawn layer (with rotation).
bool layerContainsPoint(LayerGeometry geometry, Offset point) {
  final rect = geometry.rect;
  final center = rect.center;
  // Rotate the point BACK by the layer's angle, and ask about the unrotated box.
  final radians = -geometry.angle * math.pi / 180;
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  final localX = dx * math.cos(radians) - dy * math.sin(radians);
  final localY = dx * math.sin(radians) + dy * math.cos(radians);
  return localX.abs() <= rect.width / 2 && localY.abs() <= rect.height / 2;
}

/// A flow child for [pullFlow]: its size along the main axis (including its margins) and how far it is
/// pulled.
@immutable
final class PullFlowChild {
  const PullFlowChild(this.size, [this.pull = 0]);

  final double size;
  final double pull;
}

/// WHERE THE CHILDREN OF A FLOW WITH PULLING STAND: the reference implementation (`gap`, `followers`,
/// `parentSize`, `beyondOwnSize`).
///
/// A child's start is the end of the previous one plus the gap minus its `pull`; the first is zero minus
/// its `pull`. The arithmetic is one and has no exceptions: the gap REMAINS (overlap is `pull - gap`).
/// The parent's content length is the end of the last child, but not less than zero.
({List<double> starts, double size}) pullFlow(List<PullFlowChild> children, double gap) {
  final starts = <double>[];
  var cursor = 0.0;
  for (var index = 0; index < children.length; index++) {
    final child = children[index];
    final start = cursor + (index == 0 ? 0 : gap) - child.pull;
    starts.add(start);
    cursor = start + child.size;
  }
  return (starts: starts, size: math.max(0, cursor));
}

/// The ten policy rows of 9.10.0 (`x-compatibility.policy`, from `layerOutsideStack`). A mirror for
/// checking against the artifact.
const Map<String, String> kOffsetPolicy = {
  'layerOutsideStack': 'ignore',
  'layerOnFill': 'fill-wins',
  'noSizingLayer': 'ignore-layer',
  'unreadableLayer': 'ordinary-layer-unreadable-part-dropped',
  'layerClip': 'existing-clippers-only-stack-itself-does-not-clip',
  'layerTaps': 'where-drawn-inside-the-stack-box',
  'pullOutsideFlow': 'ignore',
  'pullWithWeight': 'weight-wins',
  'unreadablePull': 'no-pull',
  'pullPaintOrder': 'later-over-earlier',
};
