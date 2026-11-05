/// What a "swipe to confirm" button draws besides its label (schema 9.22.0 to 9.34.0): the thumb and the fill behind
/// it, the circle it collapses into and the indicator of "busy".
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/swipe_confirm.dart';
import '../model/swipe_motion.dart';
import 'icon_glyph.dart';
import '../model/tokens.dart';

/// Keys the parts carry, for tests that look for them.
const Key kSwipeThumbKey = ValueKey<String>('hotlayout-swipe-thumb');
const Key kSwipeTrailKey = ValueKey<String>('hotlayout-swipe-trail');
const Key kSwipeCircleKey = ValueKey<String>('hotlayout-swipe-circle');

/// The thumb and the fill behind it, in the box of the track. The fill goes from the place of rest of the thumb to
/// the far edge of the thumb, with the height and the radius of the thumb, under it.
class SwipeThumbLayer extends StatelessWidget {
  const SwipeThumbLayer({
    super.key,
    required this.track,
    required this.progress,
    required this.radius,
    required this.color,
    required this.glyphColor,
    required this.glyph,
    required this.glyphSize,
    required this.busy,
    required this.spin,
  });

  final SwipeTrack track;
  final double progress;

  /// The radius of the track in points, or `null` when it was not measured.
  final double? radius;
  final Color color;
  final Color glyphColor;
  final IconToken glyph;
  final double glyphSize;

  /// The indicator of "busy" stands in the thumb instead of the glyph.
  final bool busy;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final geometry = swipeGeometryOf(track);
    final trail = swipeTrailOf(track, progress);
    final corner = BorderRadius.circular(swipeThumbRadiusOf(track, radius));
    final top = math.max(0.0, track.border) + math.max(0.0, track.inset);
    return Stack(
      children: [
        PositionedDirectional(
          start: trail.start,
          top: top,
          width: trail.width,
          height: geometry.diameter,
          child: DecoratedBox(
            key: kSwipeTrailKey,
            decoration: BoxDecoration(color: color, borderRadius: corner),
          ),
        ),
        PositionedDirectional(
          start: swipeThumbStartOf(track, progress),
          top: top,
          width: geometry.diameter,
          height: geometry.diameter,
          child: ExcludeSemantics(
            child: DecoratedBox(
              key: kSwipeThumbKey,
              decoration: BoxDecoration(color: color, borderRadius: corner),
              child: Center(
                child: busy
                    ? SwipeSpinner(turns: spin, size: glyphSize, color: glyphColor)
                    : IconGlyph(glyph, size: glyphSize, color: glyphColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The circle the button collapses into: the halo, the core with the ring of the border and the inset, and the
/// indicator at the centre. [elapsed] is the time of the collapse in milliseconds.
class SwipeCircleLayer extends StatelessWidget {
  const SwipeCircleLayer({
    super.key,
    required this.track,
    required this.elapsed,
    required this.color,
    required this.glyphColor,
    required this.glyphSize,
    required this.spin,
  });

  final SwipeTrack track;
  final double elapsed;
  final Color color;
  final Color glyphColor;
  final double glyphSize;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final frame = swipeCollapseAt(track, elapsed);
    final coreHeight = math.max(0.0, frame.height - 2 * frame.ring);
    final coreWidth = math.max(0.0, frame.width - 2 * frame.ring);
    return IgnorePointer(
      child: Stack(
        key: kSwipeCircleKey,
        children: [
          PositionedDirectional(
            start: frame.start,
            top: 0,
            width: frame.width,
            height: frame.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: color.a * frame.haloOpacity),
                borderRadius: BorderRadius.circular(frame.height / 2),
              ),
            ),
          ),
          PositionedDirectional(
            start: frame.start + frame.ring,
            top: frame.ring,
            width: coreWidth,
            height: coreHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(coreHeight / 2)),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: SwipeSpinner(turns: spin, size: glyphSize, color: glyphColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// The indicator of the busy state (`busy.indicator`): a ring of three quarters, the size of the glyph, in its colour,
/// with a stroke of an eighth of the size, turning once in 800 ms.
class SwipeSpinner extends StatelessWidget {
  const SwipeSpinner({super.key, required this.turns, required this.size, required this.color});

  final Animation<double> turns;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: turns,
    child: CustomPaint(size: Size.square(size), painter: _RingPainter(color, size / 8)),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.color, this.stroke);

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      (Offset.zero & size).deflate(stroke / 2),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.stroke != stroke;
}
