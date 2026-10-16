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

/// Where a moving node is painted: a shift in logical pixels (x to the right, y down), a scale and an opacity
/// factor.
@immutable
final class MotionPose {
  const MotionPose({this.x = 0, this.y = 0, this.scale = 1, this.opacity = 1});

  /// Where a node stands without the field.
  static const MotionPose rest = MotionPose();

  final double x;
  final double y;
  final double scale;
  final double opacity;

  bool get isRest => x == 0 && y == 0 && scale == 1 && opacity == 1;
}

/// The pose of [motion] at [elapsedMs] since the node appeared on the shown screen.
///
/// One formula for every reader: `theta = 2 * pi * ((t - delay) mod duration) / duration`, rest before the delay
/// ends; `float` shifts along the axes (toward the END of the line horizontally, so mirrored when [rtl]; the
/// vertical drift goes up first, and `both` draws a figure eight), `pulse` breathes with
/// `p = (1 - cos(theta)) / 2`. With [reducedMotion] the node stands at rest.
MotionPose motionPoseAt(NodeMotion motion, double elapsedMs, {bool reducedMotion = false, bool rtl = false}) {
  if (reducedMotion) return MotionPose.rest;
  final elapsed = elapsedMs - motion.delay;
  if (!elapsed.isFinite || elapsed < 0) return MotionPose.rest;
  final theta = 2 * math.pi * (elapsed % motion.duration) / motion.duration;
  return switch (motion) {
    FloatMotion() => _floatPose(motion, theta, rtl ? -1 : 1),
    PulseMotion() => _pulsePose(motion, theta),
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
