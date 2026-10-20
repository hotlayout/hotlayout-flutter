/// A shadow that is painted only OUTSIDE the box it belongs to, as CSS `box-shadow` is.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Whether a background lets what lies under it show through: a colour or a gradient with a stop that is not
/// fully opaque. An opaque background hides the part of the shadow under the box, so it needs no clipping.
bool backgroundIsTranslucent({Color? color, Gradient? gradient}) {
  if (color != null && color.a < 1) return true;
  return gradient != null && gradient.colors.any((stop) => stop.a < 1);
}

/// Paints [shadow] behind [child] and clips it to the outside of the box (the child's size with [radius]).
///
/// Flutter's `BoxDecoration.boxShadow` paints the whole blurred shape, also under the box, so a translucent
/// background shows the shadow through it. A CSS shadow never paints inside the border box; this widget keeps
/// that rule for a background that is not opaque.
class OutsideShadow extends StatelessWidget {
  const OutsideShadow({
    required this.shadow,
    required this.radius,
    required this.child,
    super.key,
  });

  final List<BoxShadow> shadow;
  final BorderRadiusGeometry? radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _OutsideShadowPainter(
      shadow,
      radius?.resolve(Directionality.of(context)) ?? BorderRadius.zero,
    ),
    child: child,
  );
}

class _OutsideShadowPainter extends CustomPainter {
  const _OutsideShadowPainter(this.shadow, this.radius);

  final List<BoxShadow> shadow;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = radius.toRRect(Offset.zero & size);
    var reach = 0.0;
    for (final layer in shadow) {
      final extent =
          layer.blurRadius * 2 +
          layer.spreadRadius.abs() +
          layer.offset.distance;
      if (extent > reach) reach = extent;
    }
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(reach + 1)),
      Path()..addRRect(box),
    );
    canvas
      ..save()
      ..clipPath(outside);
    for (final layer in shadow) {
      canvas.drawRRect(
        box.shift(layer.offset).inflate(layer.spreadRadius),
        layer.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OutsideShadowPainter old) =>
      old.radius != radius || !listEquals(old.shadow, shadow);
}
