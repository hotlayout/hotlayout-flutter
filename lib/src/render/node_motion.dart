/// Endless motion of a node (schema 9.20.0, `motion`): a paint transform over the box the node has at rest.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../model/motion_rules.dart';

/// The rotation, in degrees clockwise, that the layers above a node have already painted it with.
///
/// A motion shifts along the axes of the SCREEN, after the node's own place (the offset and rotation of a stack
/// layer). A node inside a rotated layer lives in a rotated frame, so its shift is turned back by this angle
/// before it is applied there.
class PaintRotation extends InheritedWidget {
  const PaintRotation({super.key, required this.degrees, required super.child});

  final double degrees;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PaintRotation>()?.degrees ?? 0;

  @override
  bool updateShouldNotify(PaintRotation oldWidget) => oldWidget.degrees != degrees;
}

/// Draws [child] where [motion] puts it at the moment the node has been on the shown screen.
///
/// The clock starts when this widget is mounted: a node that appears again (back, a visibility condition) is a new
/// widget and counts from zero. The layout is untouched: [Transform] and [Opacity] only paint, so the box at rest
/// sizes the parent and the siblings stand still. Whoever clipped the node at rest clips it while it moves; this
/// widget adds no clip.
///
/// The system "reduce motion" (`MediaQuery.disableAnimations`) leaves the node at rest and stops the ticker.
///
/// Taps follow the painted node (the [Transform] default). The contract promises them only inside the box at rest
/// where the node is also painted; the ancestors reject a point outside their own box anyway.
class NodeMotionBox extends StatefulWidget {
  const NodeMotionBox({super.key, required this.motion, required this.child});

  final NodeMotion motion;
  final Widget child;

  @override
  State<NodeMotionBox> createState() => _NodeMotionBoxState();
}

class _NodeMotionBoxState extends State<NodeMotionBox> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _elapsedMs = ValueNotifier<double>(0);
  bool _reduced = false;

  void _onTick(Duration elapsed) => _elapsedMs.value = elapsed.inMicroseconds / 1000;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) {
      if (_ticker.isActive) _ticker.stop();
      _elapsedMs.value = 0;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsedMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final turned = PaintRotation.of(context) * math.pi / 180;
    final motion = widget.motion;
    final fades = motion is PulseMotion && motion.opacity != null;
    return ValueListenableBuilder<double>(
      valueListenable: _elapsedMs,
      child: widget.child,
      builder: (context, ms, child) {
        final pose = motionPoseAt(motion, ms, reducedMotion: _reduced, rtl: rtl);
        // The shift is in screen axes; undo the rotation the frame was painted with.
        final dx = pose.x * math.cos(turned) + pose.y * math.sin(turned);
        final dy = -pose.x * math.sin(turned) + pose.y * math.cos(turned);
        Widget moved = Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(dx, dy, 0).multiplied(Matrix4.diagonal3Values(pose.scale, pose.scale, 1)),
          child: child,
        );
        // Opacity multiplies the node's own `style.opacity` (which sits inside). Semantics stay while the node is
        // fully transparent at the peak: it is a node the person can still find.
        if (fades) moved = Opacity(opacity: pose.opacity, alwaysIncludeSemantics: true, child: moved);
        return moved;
      },
    );
  }
}
