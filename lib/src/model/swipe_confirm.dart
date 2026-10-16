/// "Swipe to confirm" (schema 9.22.0, `Button.confirm: 'swipe'`): mirror of the builder's `swipe-confirm.ts`.
///
/// The button is drawn as a TRACK with a thumb at the inline start. The action (and its `track` event) runs only when
/// the thumb is dragged to the inline end past the threshold and released; earlier it returns and nothing happens. The
/// gesture is for a finger or a mouse only: from the keyboard and for assistive technology it is an ordinary button
/// named by its label. The shared table is `assets/contract/fixtures/swipe-confirm/swipe-confirm-cases.json`.
library;

import 'dart:math' as math;

/// The only word of the contract; an ordinary press is the absence of the field.
const String kConfirmSwipe = 'swipe';

/// Whether the button asks to be confirmed by a swipe: the word `swipe` and nothing else (an unknown word of a
/// newer minor is an ordinary press).
bool confirmsBySwipe(Object? raw) => raw == kConfirmSwipe;

/// The share of the travel from which a release acts.
const double kSwipeThreshold = 0.9;

/// The glyph of the thumb when the button names no icon.
const String kSwipeThumbGlyph = 'chevron-right';

/// The track: the whole button box and the numbers the geometry needs.
typedef SwipeTrack = ({double height, double width, double border, double inset});

/// The geometry of a track in numbers from the logical START of the button.
typedef SwipeGeometry = ({double diameter, double thumbRoom, double travel, ({double start, double width}) label});

SwipeGeometry swipeGeometryOf(SwipeTrack track) {
  final border = math.max(0.0, track.border);
  final inset = math.max(0.0, track.inset);
  final diameter = math.max(0.0, track.height - 2 * border - 2 * inset);
  final thumbRoom = border + inset + diameter;
  final travel = math.max(0.0, track.width - 2 * border - 2 * inset - diameter);
  return (
    diameter: diameter,
    thumbRoom: thumbRoom,
    travel: travel,
    label: (start: thumbRoom, width: math.max(0.0, track.width - 2 * thumbRoom)),
  );
}

/// The natural width: the label and the room of the thumb on both sides. The inline padding of the size is not read.
double swipeNaturalWidthOf(double labelWidth, {required double height, required double border, required double inset}) =>
    math.max(0.0, labelWidth) + 2 * swipeGeometryOf((height: height, width: 0, border: border, inset: inset)).thumbRoom;

/// The share of the travel for a drag of [dx] on the screen (positive to the right): along the inline axis, so in
/// right-to-left writing moving left is progress; clamped to 0..1. No travel, no progress.
double swipeProgressOf(double dx, double travel, {bool rtl = false}) {
  if (!(travel > 0) || !dx.isFinite) return 0;
  final along = rtl ? -dx : dx;
  return math.min(1.0, math.max(0.0, along / travel));
}

/// What a release does. A disabled button neither moves nor acts.
enum SwipeRelease { act, back }

SwipeRelease swipeReleaseOf(double progress, {bool disabled = false}) =>
    !disabled && progress >= kSwipeThreshold ? SwipeRelease.act : SwipeRelease.back;

/// The distance of the thumb's circle from the logical start of the button.
double swipeThumbStartOf(SwipeTrack track, double progress) =>
    math.max(0.0, track.border) +
    math.max(0.0, track.inset) +
    math.min(1.0, math.max(0.0, progress)) * swipeGeometryOf(track).travel;

/// Whether the drag is captured by the button: more movement along the line than across. Until then the body scrolls.
bool swipeCapturedBy(double dx, double dy) => dx.abs() > dy.abs();
