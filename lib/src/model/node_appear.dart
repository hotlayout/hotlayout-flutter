import 'package:flutter/foundation.dart';

import 'motion_rules.dart' show kMotionDelayMax, kMotionDelayMin;
import 'visibility_fade.dart' show cubicBezierAt, kVisibilityFadeInCurve;

// The one-time appearance of a node when its screen is shown (schema 9.40.0, `appear`, rules in `x-appear`).
//
// Mirrors the reference implementation `node-appear.ts`. The field is `{kind: 'fade', duration, delay?}` or
// `{kind: 'rise', distance, duration, delay?}`; the pose at a moment after the show is [appearPoseAt]. The curve is the
// one a node uses when its condition makes it appear (`x-visibilityFade.in.curve`): the same act, one tempo. The rows
// of `fixtures/motion/motion-turn-cases.json` (`appearCases`, `momentCases`, `documentCases`) run these functions
// (`motion_turn_cases_test.dart`); the clock and the widget belong to `render/node_appear.dart`.

/// The field of a node.
const String kAppearKey = 'appear';

/// Bounds of the numbers (`x-appear.ranges`). The delay is the one of the motion: a zero delay is no field.
const int kAppearDurationMin = 100;
const int kAppearDurationMax = 2000;
const int kAppearDistanceMin = 1;
const int kAppearDistanceMax = 48;

enum AppearKind {
  /// Opacity from 0 to 1.
  fade,

  /// Opacity from 0 to 1 and a shift down from `distance` to 0.
  rise,
}

/// Where a node stands at a moment of its appearance: the shift down in logical pixels and the opacity factor.
@immutable
final class AppearPose {
  const AppearPose({this.y = 0, this.opacity = 1});

  /// Where a node stands without the field, and after the appearance.
  static const AppearPose rest = AppearPose();

  final double y;
  final double opacity;

  bool get isRest => y == 0 && opacity == 1;
}

/// The appearance of a node. Parsed strictly: an unknown kind, a missing or surplus field or a number out of bounds
/// means NO appearance, and the node stands at once.
@immutable
final class NodeAppear {
  const NodeAppear({required this.kind, this.distance = 0, required this.duration, this.delay = 0});

  final AppearKind kind;

  /// `rise` only: the shift down at the start, logical pixels.
  final int distance;

  /// Length of the appearance, ms.
  final int duration;

  /// Time the node waits, invisible and in its place, before it starts to appear, ms. Zero is no field.
  final int delay;

  /// The moment the appearance is over, ms after the show.
  int get endsAt => delay + duration;

  static const Set<String> _fadeKeys = {'kind', 'duration', 'delay'};
  static const Set<String> _riseKeys = {'kind', 'distance', 'duration', 'delay'};

  static int? _wholeNumber(Object? raw) {
    if (raw is! num || !raw.isFinite || raw != raw.truncateToDouble()) return null;
    return raw.toInt();
  }

  /// The appearance in `raw`, or `null` when it is not one this reader can draw.
  static NodeAppear? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = switch (raw['kind']) {
      'fade' => AppearKind.fade,
      'rise' => AppearKind.rise,
      _ => null,
    };
    if (kind == null) return null;
    if (!raw.keys.every((key) => (kind == AppearKind.rise ? _riseKeys : _fadeKeys).contains(key))) return null;
    final duration = _wholeNumber(raw['duration']);
    if (duration == null || duration < kAppearDurationMin || duration > kAppearDurationMax) return null;
    var delay = 0;
    if (raw.containsKey('delay')) {
      final parsed = _wholeNumber(raw['delay']);
      if (parsed == null || parsed < kMotionDelayMin || parsed > kMotionDelayMax) return null;
      delay = parsed;
    }
    var distance = 0;
    if (kind == AppearKind.rise) {
      final parsed = _wholeNumber(raw['distance']);
      if (parsed == null || parsed < kAppearDistanceMin || parsed > kAppearDistanceMax) return null;
      distance = parsed;
    }
    return NodeAppear(kind: kind, distance: distance, duration: duration, delay: delay);
  }
}

/// The pose of [appear] [elapsedMs] after the screen was shown: `p = clamp((t - delay) / duration, 0, 1)`,
/// `e = cubic-bezier(0, 0, 0.2, 1)(p)`, opacity `e`, a `rise` shifts down by `distance * (1 - e)`. While the delay runs the
/// node stands in the START pose (invisible, fully shifted) so a cascade does not flash. With [reducedMotion] it is at rest.
AppearPose appearPoseAt(NodeAppear appear, double elapsedMs, {bool reducedMotion = false}) {
  if (reducedMotion) return AppearPose.rest;
  final elapsed = elapsedMs - appear.delay;
  final share = elapsed.isFinite ? (elapsed / appear.duration).clamp(0.0, 1.0) : 0.0;
  final eased = cubicBezierAt(kVisibilityFadeInCurve, share);
  final y = appear.kind == AppearKind.rise ? appear.distance * (1 - eased) : 0.0;
  return AppearPose(y: y + 0.0, opacity: eased);
}

/// The moments of a flow `momentCases` name.
enum AppearShowMoment { firstShow, forward, back, switchSection, modalClosed, conditionMet, widthClassChanged, newRecord }

/// Whether the appearance plays at a moment: a show of the screen does; closing a layer above is not a show, and a node
/// that appears on a screen already shown (its condition, the width class, a new record) follows `visibilityTransition`
/// or stands at once.
bool appearPlaysOn(AppearShowMoment moment) => switch (moment) {
  AppearShowMoment.firstShow ||
  AppearShowMoment.forward ||
  AppearShowMoment.back ||
  AppearShowMoment.switchSection => true,
  _ => false,
};

/// Mirror of the `x-appear` block. Checked against the artifact by `motion_turn_cases_test.dart`.
final Map<String, Object?> kAppearRules = {
  'prop': kAppearKey,
  'on': 'every node except the root «Screen»; on a zone of the screen it is not published',
  'kinds': ['fade', 'rise'],
  'fade': {'opacity': 'e'},
  'rise': {'opacity': 'e', 'y': 'distance * (1 - e), down'},
  'progress': 'p = clamp((t - delay) / duration, 0, 1); e = the curve at p',
  'curve': {'is': 'x-visibilityFade.in.curve', 'bezier': kVisibilityFadeInCurve},
  'beforeDelay':
      'the start pose: opacity 0 and, for «rise», the full shift — the node is invisible, its box is in the layout',
  'rest': {'y': 0, 'opacity': 1},
  'shown':
      'x-valueAppear.shown — the same moments as «animateIn»: the first show, a screen pushed on top, a screen shown again by «back» or a section switch; closing a layer above is not a show',
  'notOnShownScreen':
      'a node that appears on a screen already shown (its condition starts to hold, a width class, a new record of a list) does not play the appearance: it follows «visibilityTransition» or appears at once',
  'hiddenAtShow': 'a node not visible when the screen is shown does not play the appearance later',
  'withVisibilityTransition':
      'both fields may stand on one node: the appearance plays at the show, «visibilityTransition» on every later change of the condition',
  'withMotion':
      'both start at the show: the endless motion runs from t = 0 under the appearance; the appearance shift and opacity are applied over the motion pose',
  'stagger': 'none — every node starts at the show; a cascade is the own «delay» of each node',
  'reducedMotion': 'rest — the node is there at once',
  'notPlayed': ['the editor canvas', 'thumbnails and still images of a screen', 'reduce motion'],
  'layout': 'unchanged: the box stands at its place from the first frame',
  'order': 'after the node own place («layer» offset and rotation): the shift goes along the screen vertical',
  'opacity': 'multiplies the node own opacity («style.opacity») and the opacity of «pulse»',
  'taps': 'the node catches presses from the first frame, at its place at rest',
  'zones':
      'not read on a zone of the screen — the first child of the screen root that is an AppBar, a pinned node, a NavBar and a NavItem: zones are the frame of the screen and come with it at once',
  'ranges': {
    'duration': {'min': kAppearDurationMin, 'max': kAppearDurationMax},
    'delay': {'min': kMotionDelayMin, 'max': kMotionDelayMax},
    'distance': {'min': kAppearDistanceMin, 'max': kAppearDistanceMax},
  },
  'olderReader': 'skips the field — the node is there at once',
  'cases': 'contract/fixtures/motion/motion-turn-cases.json',
};
