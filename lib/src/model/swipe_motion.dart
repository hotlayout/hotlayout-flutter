/// "Swipe to confirm": the motion (schema 9.34.0, `Button.confirmTransition: 'ripple'`): mirror of the builder's
/// `swipe-motion.ts`.
///
/// While the thumb is dragged a fill of the thumb's colour follows it and the label fades with the travel. Released
/// past the threshold the button collapses into a circle with the busy indicator; with `ripple` that circle then grows
/// over the whole screen, the action runs under the fill and the next screen shows from under it. The shared table is
/// `assets/contract/fixtures/swipe-motion/swipe-motion-cases.json`.
library;

import 'dart:math' as math;

import 'swipe_confirm.dart';
import 'visibility_fade.dart' show cubicBezierAt;

/// The field of the button.
const String kConfirmTransitionKey = 'confirmTransition';

/// The only word of the field.
const String kConfirmTransitionRipple = 'ripple';

/// The field as the reader reads it: the word `ripple` and nothing else; any other value is no field.
bool confirmTransitionIsRipple(Object? raw) => raw == kConfirmTransitionRipple;

/// The actions whose screen change the reader performs itself: only they can be led by the fill.
const List<String> kRippleActionTypes = ['navigate', 'navigate.back'];

/// The collapse into a circle: how long, and the curve (`fastOutSlowIn`).
const double kSwipeCollapseMs = 600;
const List<double> kSwipeCollapseCurve = [0.4, 0, 0.2, 1];

/// The fill over the screen: how long (linear).
const double kSwipeRippleMs = 800;

/// The next screen from under the fill: how long (linear).
const double kSwipeRevealMs = 200;

/// The opacity of the halo of the circle.
const double kSwipeHaloOpacity = 0.4;

double _clamp01(double value) => value.isFinite ? math.min(1.0, math.max(0.0, value)) : 0.0;

/// The opacity of the label for a share of the travel: it fades with the travel.
double swipeLabelOpacityOf(double progress) => 1 - _clamp01(progress);

/// A strip from the logical start of the button.
typedef SwipeStrip = ({double start, double width});

/// The fill behind the thumb: from the place of rest of the thumb to its far edge. At rest it is exactly the thumb.
SwipeStrip swipeTrailOf(SwipeTrack track, double progress) {
  final geometry = swipeGeometryOf(track);
  return (
    start: math.max(0.0, track.border) + math.max(0.0, track.inset),
    width: _clamp01(progress) * geometry.travel + geometry.diameter,
  );
}

/// The radius of the thumb (and of the fill behind it), concentric with the track: the track radius minus the inset,
/// never below zero. [radius] is the real radius of the track in points (`style.radius`, or the radius of the theme
/// role of the button without a style); it is capped at half the height first, so a pill track keeps the thumb a
/// circle. A radius that was not measured gives the circle.
double swipeThumbRadiusOf(SwipeTrack track, double? radius) {
  final circle = swipeGeometryOf(track).diameter / 2;
  if (radius == null || radius.isNaN) return circle;
  final actual = math.min(math.max(0.0, radius), math.max(0.0, track.height) / 2);
  return math.min(circle, math.max(0.0, actual - math.max(0.0, track.inset)));
}

/// One frame of the collapse: the pill, its ring, and the opacity of the surface of the button and of the halo.
typedef SwipeCollapseFrame = ({
  double start,
  double width,
  double height,
  double ring,
  double surfaceOpacity,
  double haloOpacity,
});

/// The collapse [elapsed] milliseconds after its start. The pill narrows from the width of the button to a circle the
/// height of the button, towards the CENTRE of the box.
SwipeCollapseFrame swipeCollapseAt(SwipeTrack track, double elapsed) {
  final eased = cubicBezierAt(kSwipeCollapseCurve, _clamp01(elapsed / kSwipeCollapseMs));
  final height = math.max(0.0, track.height);
  final full = math.max(height, track.width);
  final width = full - (full - height) * eased;
  return (
    start: (track.width - width) / 2,
    width: width,
    height: height,
    ring: math.max(0.0, track.border) + math.max(0.0, track.inset),
    surfaceOpacity: 1 - eased,
    haloOpacity: kSwipeHaloOpacity * eased,
  );
}

/// The final scale of the circle: its core covers the farthest corner of the screen.
double swipeRippleScaleOf({
  required double centerX,
  required double centerY,
  required double screenWidth,
  required double screenHeight,
  required double core,
}) {
  final dx = math.max(centerX, screenWidth - centerX);
  final dy = math.max(centerY, screenHeight - centerY);
  final radius = core / 2;
  if (!(radius > 0)) return 1;
  return math.max(1.0, math.sqrt(dx * dx + dy * dy) / radius);
}

/// The scale of the circle [elapsed] milliseconds after the fill started: linear.
double swipeRippleAt(double scale, double elapsed) =>
    1 + (math.max(1.0, scale) - 1) * _clamp01(elapsed / kSwipeRippleMs);

/// The opacity of the fill [elapsed] milliseconds after the next screen began to show.
double swipeRevealAt(double elapsed) => 1 - _clamp01(elapsed / kSwipeRevealMs);

/// What happens, in order, after a release past the threshold (or a press from the keyboard).
enum SwipeStep { act, glide, collapse, busy, ripple, reveal, expand, giveBack }

/// How the button was activated: a finger or a mouse (`swipe`), or the keyboard and assistive technology.
enum SwipeWay { swipe, keyboard }

/// Whether the fill plays: after a swipe, on an action the reader performs itself, without "reduce motion".
bool swipeRipplePlays({
  required SwipeRunner runner,
  required String actionType,
  required bool ripple,
  required SwipeWay way,
  required bool reducedMotion,
}) =>
    ripple &&
    way == SwipeWay.swipe &&
    !reducedMotion &&
    runner == SwipeRunner.reader &&
    kRippleActionTypes.contains(actionType);

/// The steps after a release. With the fill the action goes AFTER it, so the next screen stands under the fill; the
/// circle of "busy" and the end of "busy" are the same as without it.
List<SwipeStep> swipeSequenceOf({
  required SwipeRunner runner,
  required String actionType,
  required bool ripple,
  required SwipeWay way,
  required bool reducedMotion,
}) {
  if (runner == SwipeRunner.none || runner == SwipeRunner.invalid) return const [SwipeStep.act, SwipeStep.giveBack];
  if (swipeRipplePlays(
    runner: runner,
    actionType: actionType,
    ripple: ripple,
    way: way,
    reducedMotion: reducedMotion,
  )) {
    return const [SwipeStep.glide, SwipeStep.collapse, SwipeStep.ripple, SwipeStep.act, SwipeStep.reveal];
  }
  if (reducedMotion) return const [SwipeStep.act, SwipeStep.busy];
  return const [SwipeStep.act, SwipeStep.glide, SwipeStep.collapse, SwipeStep.busy];
}

/// How "busy" ends: the circle expands back, then the thumb returns; under "reduce motion" the thumb only returns.
List<SwipeStep> swipeBusyReturnOf(bool reducedMotion) =>
    reducedMotion ? const [SwipeStep.giveBack] : const [SwipeStep.expand, SwipeStep.giveBack];

/// The block `x-swipeConfirmMotion` of the artifact, whole: the rules in words and the numbers of the motion.
const Map<String, Object?> kSwipeMotionRules = {
  'on': ['Button'],
  'when': 'confirm-is-swipe',
  'refines': ['x-swipeConfirm.label', 'x-swipeConfirmBusy.busy.thumb', 'x-swipeConfirmBusy.release.atOrPastThreshold'],
  'drag': {
    'trail': 'from-the-rest-place-of-the-thumb-to-its-far-edge-the-height-radius-and-fill-of-the-thumb-under-the-thumb',
    'labelOpacity': 'one-minus-the-progress',
  },
  'thumbShape': {
    'radius': 'the-track-radius-minus-the-inset-never-below-zero-concentric-with-the-track',
    'trackRadius':
        'the-actual-radius-of-the-button-its-style-radius-or-else-the-radius-of-its-theme-role-capped-at-half-the-height',
    'inset': 'x-swipeConfirm.thumb.inset',
    'pill': 'a-track-radius-of-half-the-height-or-more-keeps-the-thumb-a-circle',
    'trail': 'the-radius-of-the-thumb-on-every-corner-no-corner-sticks-out',
    'unchanged': 'the-collapse-circle-the-halo-and-the-ripple-stay-round',
  },
  'collapse': {
    'durationMs': 600,
    'curve': [0.4, 0, 0.2, 1],
    'after': 'the-glide-to-the-end',
    'shape': 'a-pill-the-height-of-the-button-narrowing-to-a-circle-at-the-centre-of-the-box',
    'core': 'the-fill-of-the-thumb-inset-by-the-border-plus-the-inset-on-every-side',
    'halo': 'the-fill-of-the-thumb-at-halo-opacity-between-the-core-and-the-edge',
    'haloOpacity': 0.4,
    'surface': 'the-background-border-and-shadow-of-the-button-fade-out',
    'label': 'hidden',
    'indicator': 'the-busy-indicator-of-x-swipeConfirmBusy-at-the-centre',
    'layout': 'unchanged-the-box-keeps-its-size',
  },
  'busyLook': 'the-collapsed-circle',
  'expand': 'the-collapse-played-backwards-then-the-thumb-returns',
  'field': 'confirmTransition',
  'words': ['ripple'],
  'noField': 'the-screen-changes-as-usual',
  'ripple': {
    'durationMs': 800,
    'curve': 'linear',
    'plays': 'after-a-swipe-on-a-navigate-or-navigate-back-action-without-reduced-motion',
    'actions': ['navigate', 'navigate.back'],
    'after': 'the-collapse',
    'centre': 'the-centre-of-the-collapsed-circle',
    'scaleTo': 'until-the-core-covers-the-farthest-corner-of-the-screen',
    'layer': 'above-everything-on-the-screen-including-the-zones-and-the-status-bar-area',
    'then': 'the-action-and-its-track-run-once-the-next-screen-is-under-the-fill',
  },
  'reveal': {'durationMs': 200, 'curve': 'linear', 'what': 'the-fill-fades-out-over-the-next-screen'},
  'rippleNotPlayed': {
    'keyboardAndAssistive': 'the-action-at-once-no-ripple',
    'reducedMotion': 'the-action-at-once-no-collapse-no-ripple',
    'otherActions': 'not-published-confirm-transition-not-read',
  },
  'leavesBeforeAct': 'nothing-runs-the-fill-goes-with-the-button',
  'reducedMotion': 'the-trail-follows-the-finger-no-collapse-no-ripple-the-busy-thumb-jumps-to-the-end-as-in-9-24',
  'editorCanvas': 'the-thumb-at-the-start-nothing-plays',
  'olderReader': 'the-look-of-9-24-and-the-screen-changes-as-usual',
  'cases': 'contract/fixtures/swipe-motion/swipe-motion-cases.json',
};
