import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Motion of a node and blur under a layer (schema 9.20.0).
///
/// Mirror of the contract's `x-motion` and `x-backdropBlur` blocks; `test/motion_cases_test.dart`
/// compares every number here with the artifact and runs the shared table
/// (`assets/contract/fixtures/motion/motion-cases.json`).
///
/// Motion changes no layout: it is a paint transform (shift, scale, opacity) over the box the node
/// has at rest. The curve is a sine and is not a field.

/// Bounds of the motion numbers (`x-motion.ranges`).
const int kMotionDurationMin = 400;
const int kMotionDurationMax = 60000;
const int kMotionDelayMin = 1;
const int kMotionDelayMax = 60000;
const int kFloatAmplitudeMin = 1;
const int kFloatAmplitudeMax = 48;
const double kPulseScaleMin = 0.5;
const double kPulseScaleMax = 1.5;
const double kPulseOpacityMin = 0;
const double kPulseOpacityMax = 1;

/// Bounds of the sway angle, whole degrees (`x-motionTurn.ranges.angle`).
const int kSwayAngleMin = 1;
const int kSwayAngleMax = 45;

/// Bounds of a blur radius in logical pixels (`x-backdropBlur.radius`): one rule for the blur under a modal
/// layer and for the glass of a node.
const int kBackdropBlurMin = 1;
const int kBackdropBlurMax = 40;

/// The radius of a blur from the document, or `null` when there is no field or it is not a whole number in
/// bounds. A value the schema would reject is not clamped: a blur nobody asked for in that size is worse than
/// none.
int? backdropBlurOf(Object? raw) {
  final value = _wholeNumber(raw);
  if (value == null || value < kBackdropBlurMin || value > kBackdropBlurMax) return null;
  return value;
}

int? _wholeNumber(Object? raw) {
  if (raw is! num || !raw.isFinite || raw != raw.truncateToDouble()) return null;
  return raw.toInt();
}

/// Which way a floating node drifts (`x-motion.float.axes`).
enum FloatAxis {
  vertical,
  horizontal,
  both;

  static FloatAxis? tryParse(Object? raw) {
    for (final axis in values) {
      if (axis.name == raw) return axis;
    }
    return null;
  }
}

/// Which way a spinning node turns (`x-motionTurn.spin.directions`).
enum SpinDirection {
  clockwise,
  counterclockwise;

  static SpinDirection? tryParse(Object? raw) {
    for (final direction in values) {
      if (direction.name == raw) return direction;
    }
    return null;
  }
}

/// The point of the box a swaying node turns about (`x-motionTurn.sway.pivots`).
enum TurnPivot {
  center,

  /// The middle of the top edge.
  top,

  /// The middle of the bottom edge.
  bottom;

  static TurnPivot? tryParse(Object? raw) {
    for (final pivot in values) {
      if (pivot.name == raw) return pivot;
    }
    return null;
  }
}

/// An endless motion of a node. Parsed strictly: a form this reader does not know, a missing field, a number out
/// of bounds or an extra field means NO motion, and the node stands where it stands without the field.
@immutable
sealed class NodeMotion {
  const NodeMotion({required this.duration, this.delay = 0});

  /// Length of one cycle, ms.
  final int duration;

  /// Time the node stands at rest before its first cycle, ms. Zero is no field.
  final int delay;

  static const Set<String> _commonKeys = {'kind', 'duration', 'delay'};

  /// The motion in `raw`, or `null` when the value is not a motion this reader can draw.
  static NodeMotion? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final duration = _wholeNumber(raw['duration']);
    if (duration == null || duration < kMotionDurationMin || duration > kMotionDurationMax) return null;
    var delay = 0;
    if (raw.containsKey('delay')) {
      final parsed = _wholeNumber(raw['delay']);
      if (parsed == null || parsed < kMotionDelayMin || parsed > kMotionDelayMax) return null;
      delay = parsed;
    }
    return switch (raw['kind']) {
      'float' => _parseFloat(raw, duration, delay),
      'pulse' => _parsePulse(raw, duration, delay),
      'spin' => _parseSpin(raw, duration, delay),
      'sway' => _parseSway(raw, duration, delay),
      _ => null,
    };
  }

  static bool _onlyKeys(Map raw, Set<String> own) => raw.keys.every((key) => _commonKeys.contains(key) || own.contains(key));

  static FloatMotion? _parseFloat(Map raw, int duration, int delay) {
    if (!_onlyKeys(raw, const {'axis', 'amplitude'})) return null;
    final axis = FloatAxis.tryParse(raw['axis']);
    final amplitude = _wholeNumber(raw['amplitude']);
    if (axis == null || amplitude == null || amplitude < kFloatAmplitudeMin || amplitude > kFloatAmplitudeMax) {
      return null;
    }
    return FloatMotion(axis: axis, amplitude: amplitude, duration: duration, delay: delay);
  }

  static SpinMotion? _parseSpin(Map raw, int duration, int delay) {
    if (!_onlyKeys(raw, const {'direction'})) return null;
    final direction = SpinDirection.tryParse(raw['direction']);
    if (direction == null) return null;
    return SpinMotion(direction: direction, duration: duration, delay: delay);
  }

  static SwayMotion? _parseSway(Map raw, int duration, int delay) {
    if (!_onlyKeys(raw, const {'angle', 'pivot'})) return null;
    final angle = _wholeNumber(raw['angle']);
    final pivot = TurnPivot.tryParse(raw['pivot']);
    if (angle == null || pivot == null || angle < kSwayAngleMin || angle > kSwayAngleMax) return null;
    return SwayMotion(angle: angle, pivot: pivot, duration: duration, delay: delay);
  }

  static PulseMotion? _parsePulse(Map raw, int duration, int delay) {
    if (!_onlyKeys(raw, const {'scale', 'opacity'})) return null;
    final scale = raw['scale'];
    if (scale is! num || !scale.isFinite || scale < kPulseScaleMin || scale > kPulseScaleMax) return null;
    double? opacity;
    if (raw.containsKey('opacity')) {
      final value = raw['opacity'];
      if (value is! num || !value.isFinite || value < kPulseOpacityMin || value > kPulseOpacityMax) return null;
      opacity = value.toDouble();
    }
    return PulseMotion(scale: scale.toDouble(), opacity: opacity, duration: duration, delay: delay);
  }
}

/// The node drifts along [axis] by up to [amplitude] logical pixels.
final class FloatMotion extends NodeMotion {
  const FloatMotion({required this.axis, required this.amplitude, required super.duration, super.delay});

  final FloatAxis axis;
  final int amplitude;
}

/// The node breathes: [scale] and, optionally, [opacity] at the peak of the cycle.
final class PulseMotion extends NodeMotion {
  const PulseMotion({required this.scale, this.opacity, required super.duration, super.delay});

  /// Scale at the peak, about the centre of the box; 1 changes nothing.
  final double scale;

  /// Opacity factor at the peak; `null` leaves opacity alone.
  final double? opacity;
}

/// The node turns round the centre of its box at a constant speed, [direction] round, one turn per [duration]. Not
/// mirrored in a right-to-left language: a turn has no direction of the line.
final class SpinMotion extends NodeMotion {
  const SpinMotion({required this.direction, required super.duration, super.delay});

  final SpinDirection direction;
}

/// The node swings by up to [angle] degrees either way about [pivot], by the sine of the cycle.
final class SwayMotion extends NodeMotion {
  const SwayMotion({required this.angle, required this.pivot, required super.duration, super.delay});

  /// The largest angle, whole degrees.
  final int angle;

  final TurnPivot pivot;
}

/// Where a moving node is painted: a shift in logical pixels (x to the right, y down), a scale, an opacity factor and a
/// turn in degrees clockwise about [pivot].
@immutable
final class MotionPose {
  const MotionPose({
    this.x = 0,
    this.y = 0,
    this.scale = 1,
    this.opacity = 1,
    this.rotate = 0,
    this.pivot = TurnPivot.center,
  });

  /// Where a node stands without the field.
  static const MotionPose rest = MotionPose();

  final double x;
  final double y;
  final double scale;
  final double opacity;

  /// Degrees clockwise.
  final double rotate;

  /// The point of the box the turn is about; the centre at rest.
  final TurnPivot pivot;

  bool get isRest => x == 0 && y == 0 && scale == 1 && opacity == 1 && rotate == 0;
}

/// The pose of [motion] at [elapsedMs] since the node appeared on the shown screen.
///
/// One formula for every reader: `theta = 2 * pi * ((t - delay) mod duration) / duration`, rest before the delay
/// ends; `float` shifts along the axes (toward the END of the line horizontally, so mirrored when [rtl]; the
/// vertical drift goes up first, and `both` draws a figure eight), `pulse` breathes with
/// `p = (1 - cos(theta)) / 2`, `spin` turns by `s * 360 * ((t - delay) mod duration) / duration` degrees (`s` is +1 clockwise,
/// not mirrored) and `sway` by `mirror * angle * sin(theta)` about its pivot. With [reducedMotion] the node stands at rest.
MotionPose motionPoseAt(NodeMotion motion, double elapsedMs, {bool reducedMotion = false, bool rtl = false}) {
  if (reducedMotion) return MotionPose.rest;
  final elapsed = elapsedMs - motion.delay;
  if (!elapsed.isFinite || elapsed < 0) return MotionPose.rest;
  final theta = 2 * math.pi * (elapsed % motion.duration) / motion.duration;
  return switch (motion) {
    FloatMotion() => _floatPose(motion, theta, rtl ? -1 : 1),
    PulseMotion() => _pulsePose(motion, theta),
    SpinMotion() => MotionPose(
      rotate: (motion.direction == SpinDirection.clockwise ? 1 : -1) * 360 * (elapsed % motion.duration) / motion.duration + 0.0,
    ),
    SwayMotion() => MotionPose(rotate: (rtl ? -1 : 1) * motion.angle * math.sin(theta) + 0.0, pivot: motion.pivot),
  };
}

MotionPose _floatPose(FloatMotion motion, double theta, int mirror) {
  final amplitude = motion.amplitude.toDouble();
  final x = motion.axis == FloatAxis.vertical ? 0.0 : mirror * amplitude * math.sin(theta);
  final y = switch (motion.axis) {
    FloatAxis.horizontal => 0.0,
    FloatAxis.vertical => -amplitude * math.sin(theta),
    FloatAxis.both => -amplitude * math.sin(2 * theta),
  };
  // Negative zero is not a pose anybody asked for.
  return MotionPose(x: x + 0.0, y: y + 0.0);
}

MotionPose _pulsePose(PulseMotion motion, double theta) {
  final progress = (1 - math.cos(theta)) / 2;
  return MotionPose(
    scale: 1 + (motion.scale - 1) * progress,
    opacity: 1 + ((motion.opacity ?? 1) - 1) * progress,
  );
}

/// Mirror of the `x-motionTurn` block (schema 9.40.0): the two kinds that turn a node. Checked against the artifact by
/// `test/motion_turn_cases_test.dart`.
const Map<String, Object?> kMotionTurnRules = {
  'prop': 'motion',
  'kinds': ['spin', 'sway'],
  'shares':
      'x-motion: «on», «clock», «phase», «reducedMotion», «layout», «opacity», «clip» and the bounds of duration and delay are those of x-motion',
  'spin': {
    'directions': ['clockwise', 'counterclockwise'],
    'rotate':
        'r = s * 360deg * ((t - delay) mod duration) / duration; s = +1 clockwise, -1 counterclockwise; while t < delay r = 0',
    'curve': 'none — a constant speed: an even turn is the point of spinning; a sine would jerk at every turn',
    'pivot': 'the centre of the box',
    'rightToLeft': 'not mirrored: a turn has no direction of the line',
  },
  'sway': {
    'pivots': ['center', 'top', 'bottom'],
    'rotate': 'r = angle * sin(theta), degrees, positive — clockwise; theta of x-motion.phase',
    'curve': 'sine — not a field, as in x-motion',
    'pivot': {
      'center': 'the centre of the box',
      'top': 'the middle of the top edge of the box',
      'bottom': 'the middle of the bottom edge of the box',
    },
    'rightToLeft': 'mirrored: r = -angle * sin(theta)',
  },
  'order':
      'after the node own place («layer» offset and rotation): the turn is about the pivot of the box as the layer placed it, so it adds to the layer rotation about that pivot',
  'rest': {'rotate': 0},
  'taps':
      'the rule of x-motion.taps holds as written: promised inside the box at rest where the turned node is also drawn — not the bounding rectangle of the turned node, not the whole box at rest',
  'ranges': {
    'duration': {'min': kMotionDurationMin, 'max': kMotionDurationMax},
    'delay': {'min': kMotionDelayMin, 'max': kMotionDelayMax},
    'angle': {'min': kSwayAngleMin, 'max': kSwayAngleMax},
  },
  'olderReader': 'a value of an unknown kind — the node stands at rest (x-motion.olderReader)',
  'cases': 'contract/fixtures/motion/motion-turn-cases.json',
};
