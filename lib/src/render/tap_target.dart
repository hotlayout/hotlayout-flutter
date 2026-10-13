import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

/// Smallest side of the area a finger must be able to hit (the contract's touch-target rule).
const double kMinTapSide = 48;

/// Extends the touch area to 48 x 48 dp without affecting layout.
///
/// The button's look (40 dp tall) and the space it occupies stay as the document wrote them;
/// only the region that catches the finger grows. This is not
/// `MaterialTapTargetSize.padded`: that pushes neighbours apart with an invisible inset,
/// whereas here the child's box is exactly the same and no pixel is added.
///
/// A touch in the extended strip is handed to the child as if the finger had landed on the
/// nearest point of its box.
///
/// Why the extra machinery ([TapTargetScope]): Flutter's normal hit testing asks children only
/// inside each ancestor's box. The strip above an `AppBar` back arrow lies outside the bar's
/// own box, so no ancestor would let the touch through; and a column, which tests children
/// from the last one, would give the strip above a button to the sibling below it. So the
/// root of the flow decides: if the finger did not land in the OWN box of any [TapTarget], it
/// searches all registered targets for one whose strip covers the point, whose centre is
/// nearest, and which is actually "live" (its centre catches the touch itself, so neither a
/// modal scrim nor a layer on top covers it). The own box of another [TapTarget] always beats
/// someone else's strip.
///
/// Without a [TapTargetScope] above it, the target stays the child's box.
class TapTarget extends SingleChildRenderObjectWidget {
  const TapTarget({required Widget super.child, super.key});

  @override
  RenderTapTarget createRenderObject(BuildContext context) => RenderTapTarget();
}

/// Root of the flow for [TapTarget]: decides whose extended strip catches a touch.
class TapTargetScope extends SingleChildRenderObjectWidget {
  const TapTargetScope({required Widget super.child, super.key});

  @override
  RenderTapTargetScope createRenderObject(BuildContext context) => RenderTapTargetScope();
}

class RenderTapTargetScope extends RenderProxyBox {
  final Set<RenderTapTarget> _targets = {};

  /// Targets whose OWN box was hit by the current trial hit test.
  Set<RenderTapTarget>? _probe;

  Set<RenderTapTarget> _hitsAt(Offset position) {
    final hits = _probe = <RenderTapTarget>{};
    try {
      hitTestChildren(BoxHitTestResult(), position: position);
    } finally {
      _probe = null;
    }
    return hits;
  }

  RenderTapTarget? _bestFor(Offset position) {
    RenderTapTarget? best;
    var bestDistance = double.infinity;
    for (final target in _targets) {
      if (!target.attached || !target.hasSize || target.child == null) continue;
      final toScope = target.getTransformTo(this);
      final fromScope = Matrix4.tryInvert(toScope);
      if (fromScope == null) continue;
      final local = MatrixUtils.transformPoint(fromScope, position);
      if (target.size.contains(local) || !target.zone.contains(local)) continue;
      final center = target.size.center(Offset.zero);
      final distance = (local - center).distance;
      if (distance >= bestDistance) continue;
      // "Live": the target's centre catches the touch itself, i.e. no layer on top covers it.
      if (!_hitsAt(MatrixUtils.transformPoint(toScope, center)).contains(target)) continue;
      best = target;
      bestDistance = distance;
    }
    return best;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;

    var hit = false;
    // First, did the finger land in the own box of some target? That one is stronger.
    if (_targets.isNotEmpty && _hitsAt(position).isEmpty) {
      final best = _bestFor(position);
      if (best != null) hit = best.hitClamped(result, this, position);
    }
    // Then the normal hit test, run AFTER the strip, so that in gesture arenas the strip comes
    // first, ahead of the background and scrim lying under it.
    if (hitTestChildren(result, position: position) || hit) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

class RenderTapTarget extends RenderProxyBox {
  RenderTapTargetScope? _scope;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (RenderObject? p = parent; p != null; p = p.parent) {
      if (p is RenderTapTargetScope) {
        _scope = p;
        p._targets.add(this);
        break;
      }
    }
  }

  @override
  void detach() {
    _scope?._targets.remove(this);
    _scope = null;
    super.detach();
  }

  /// The strip around a box, in its coordinates: up to [kMinTapSide] on each axis.
  Rect get zone {
    final dx = math.max(0.0, (kMinTapSide - size.width) / 2);
    final dy = math.max(0.0, (kMinTapSide - size.height) / 2);
    return Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final hit = super.hitTest(result, position: position);
    if (hit) _scope?._probe?.add(this);
    return hit;
  }

  /// Hands the touch to the child as if the finger were at the point of its box nearest to it.
  /// [position] is in the coordinates of [scope].
  bool hitClamped(BoxHitTestResult result, RenderTapTargetScope scope, Offset position) {
    final inner = child;
    final fromScope = Matrix4.tryInvert(getTransformTo(scope));
    if (inner == null || fromScope == null) return false;
    final local = MatrixUtils.transformPoint(fromScope, position);
    final clamped = Offset(
      local.dx.clamp(0.0, math.max(0.0, size.width - 0.01)),
      local.dy.clamp(0.0, math.max(0.0, size.height - 0.01)),
    );
    final shift = Matrix4.translationValues(clamped.dx - local.dx, clamped.dy - local.dy, 0);
    return result.addWithRawTransform(
      transform: shift.multiplied(fromScope),
      position: position,
      hitTest: (r, p) => inner.hitTest(r, position: p),
    );
  }
}
