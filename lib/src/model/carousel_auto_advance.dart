import 'package:flutter/foundation.dart';

import 'write_action.dart' show holdsWritten;

// A carousel that advances by time (schema 9.42.0, `x-carouselAutoAdvance`).
//
// Mirrors the reference implementation `carousel-auto-advance.ts`. The optional `carousel.autoAdvance` is an object
// `{intervalMs, loop?}`: its presence turns the timer on. The timer counts the time the carousel stood on the current
// stop WITHOUT a pause; when the count reaches the interval it takes the carousel to the next stop (a stop of the snap
// list, not the next card), as the reader's own move, and writes the new stop number to `stopPath` when the carousel
// has one. The rows of the `autoAdvance...` groups of `fixtures/carousel/carousel-cases.json` run these functions
// (`carousel_auto_advance_cases_test.dart`); the clock, the pauses and the scrolling belong to
// `render/carousel_auto_advance.dart`.

/// The field inside the `carousel` object.
const String kCarouselAutoAdvanceKey = 'autoAdvance';

/// Bounds of the interval, ms (`x-carouselAutoAdvance.field.intervalMs`).
const double kCarouselAutoAdvanceMinMs = 2000;
const double kCarouselAutoAdvanceMaxMs = 15000;

/// What pauses the timer, in the order of `x-carouselAutoAdvance.pauses.list`.
enum AutoAdvancePause {
  /// A finger or a pointer button is down on the carousel.
  held,

  /// Keyboard focus is inside the carousel.
  keyboardFocus,

  /// The scroll is still moving: a gesture, momentum or the animation of a step.
  moving,

  /// The screen is not the top of the stack, a layer covers it, the app is in the background.
  notShown,

  /// A screen reader is on: no timer while it runs.
  screenReader,
}

/// The timer as the reader reads it.
@immutable
final class CarouselAutoAdvance {
  const CarouselAutoAdvance({required this.intervalMs, this.loop = false});

  /// The interval in ms, already clamped to its bounds.
  final double intervalMs;

  /// After the last stop, back to the first.
  final bool loop;

  @override
  bool operator ==(Object other) =>
      other is CarouselAutoAdvance && other.intervalMs == intervalMs && other.loop == loop;

  @override
  int get hashCode => Object.hash(intervalMs, loop);
}

/// The interval a value names: clamped to its bounds; not a number is the lower bound.
double carouselAutoAdvanceInterval(Object? value) {
  if (value is! num || !value.isFinite) return kCarouselAutoAdvanceMinMs;
  return value.toDouble().clamp(kCarouselAutoAdvanceMinMs, kCarouselAutoAdvanceMaxMs);
}

/// The timer a `carousel` object names, or `null` when it names none: the field must be an object. [raw] is the
/// `carousel` object of a node that is a carousel host (a row that does not scroll is no host, and its carousel is not
/// read at all).
CarouselAutoAdvance? carouselAutoAdvanceOf(Object? raw) {
  if (raw is! Map) return null;
  final field = raw[kCarouselAutoAdvanceKey];
  if (field is! Map) return null;
  return CarouselAutoAdvance(intervalMs: carouselAutoAdvanceInterval(field['intervalMs']), loop: field['loop'] == true);
}

/// The stop the timer leads to from [active]: the next one; from the last, nowhere or (with [loop]) the first. With
/// fewer than two stops there is no timer. An active stop out of range is clamped first.
int? carouselAutoAdvanceNext(int active, int stopCount, bool loop) {
  if (stopCount < 2) return null;
  final from = active.clamp(0, stopCount - 1);
  if (from + 1 < stopCount) return from + 1;
  return loop ? 0 : null;
}

/// The state of the timer: the stop the count runs from and the time the carousel has stood on it without a pause.
@immutable
final class AutoAdvanceState {
  const AutoAdvanceState({required this.active, required this.elapsed});

  final int active;
  final double elapsed;

  @override
  bool operator ==(Object other) => other is AutoAdvanceState && other.active == active && other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(active, elapsed);

  @override
  String toString() => 'AutoAdvanceState(active: $active, elapsed: $elapsed)';
}

/// What one tick of the clock does: the new state and where the timer leads the carousel (`null`: nowhere).
typedef AutoAdvanceTick = ({AutoAdvanceState state, int? step});

/// ONE TICK. A pause changes nothing (the count is frozen and resumes with what was left). Then the stop: when it is not
/// the one the count runs from, somebody else moved it (a person, the value of `stopPath`, fewer stops) and the count
/// restarts from 0 there, with no step. Otherwise the count grows by the time since the last tick (a negative one is
/// nothing) and is held at the interval; on the interval comes ONE step to the next stop (a long gap never catches up)
/// and the count restarts from 0; with nowhere to go the count stands at the interval.
AutoAdvanceTick carouselAutoAdvanceTick(
  AutoAdvanceState state, {
  required double dtMs,
  required int active,
  required int stopCount,
  required bool paused,
  required double intervalMs,
  required bool loop,
}) {
  if (paused) return (state: state, step: null);
  if (active != state.active) return (state: AutoAdvanceState(active: active, elapsed: 0), step: null);
  final dt = dtMs.isFinite && dtMs > 0 ? dtMs : 0.0;
  final elapsed = (state.elapsed + dt).clamp(0.0, intervalMs);
  if (elapsed < intervalMs) return (state: AutoAdvanceState(active: state.active, elapsed: elapsed), step: null);
  final next = carouselAutoAdvanceNext(state.active, stopCount, loop);
  if (next == null) return (state: AutoAdvanceState(active: state.active, elapsed: elapsed), step: null);
  return (state: AutoAdvanceState(active: next, elapsed: 0), step: next);
}

/// What the step writes to `stopPath`: the number of the new stop, unless the value already is it (typed equality).
int? carouselAutoAdvanceWrite(int step, Object? current) {
  if (step < 0) return null;
  return holdsWritten(current, step) ? null : step;
}

/// Mirror of the `x-carouselAutoAdvance` block. Checked against the artifact by
/// `carousel_auto_advance_cases_test.dart`.
const Map<String, Object?> kCarouselAutoAdvanceRules = {
  'refines': ['x-style.layout.carousel.active', 'x-carouselStop.write'],
  'prop': 'carousel.autoAdvance',
  'field': {
    'is': 'an-object-its-presence-turns-the-timer-on',
    'intervalMs': {
      'min': 2000,
      'max': 15000,
      'unit': 'ms',
      'outOfRange': 'clamped-literalOutOfRange',
      'notANumber': 'the-lower-bound-nonNumericLiteral',
    },
    'loop': {
      'is': 'the-literal-true',
      'absent': 'stay-on-the-last-stop-the-timer-stops',
      'otherValue': 'as-absent',
    },
    'notAnObject': 'no-auto-advance',
    'misplaced': 'x-style.layout.carousel.misplaced',
  },
  'timer': {
    'counts': 'the-time-the-carousel-stood-on-the-current-stop-without-a-pause',
    'step': 'to-the-next-stop-of-x-style.layout.carousel.snap-not-the-next-card',
    'at': 'the-count-reaches-intervalMs',
    'lastStop': {
      'withoutLoop': 'no-step-the-timer-stops-until-the-stop-changes-otherwise',
      'withLoop': 'to-the-first-stop',
    },
    'oneStop': 'no-timer',
    'stopChangedOtherwise': 'the-count-restarts-from-0-at-the-new-stop-once-nothing-pauses-the-timer',
    'otherwise': ['a-person-moved-it', 'the-stopPath-value-moved-it', 'fewer-stops-clamped-it'],
    'longGap': 'one-step-at-most-per-tick-the-count-restarts-from-0',
    'atShow': 'the-count-starts-from-0-once-the-screen-is-shown',
  },
  'pauses': {
    'list': ['held', 'keyboardFocus', 'moving', 'notShown', 'screenReader'],
    'effect': 'the-count-is-frozen-and-resumes-with-what-was-left',
    'held': 'a-finger-or-a-pointer-button-is-down-on-the-carousel',
    'keyboardFocus': 'keyboard-focus-is-inside-the-carousel-WCAG-2.2.2',
    'moving': 'the-scroll-is-still-moving-a-gesture-momentum-or-the-step-animation',
    'notShown': [
      'the-screen-is-not-the-top-of-the-stack',
      'a-modal-layer-covers-it',
      'the-app-is-in-the-background',
      'the-surface-is-a-still-picture',
    ],
    'screenReader': 'a-screen-reader-is-on-voiceover-talkback-no-timer-while-it-runs',
  },
  'motion': {
    'step': 'animated-like-following-the-value-x-carouselStop.read.onChange',
    'reducedMotion': 'the-step-is-instant-the-timer-still-runs',
    'personDuringStep': 'the-person-takes-over-the-gesture-wins',
  },
  'write': {
    'when': 'a-step-of-the-timer-with-carousel.stopPath',
    'value': 'the-index-of-the-new-stop-at-the-moment-of-the-step',
    'sameValue': 'not-written-again-x-actions.write.sameValue.equality',
    'mechanism': 'x-carouselStop.write.mechanism',
    'exception':
        'the-only-reader-move-that-writes-without-it-a-segmented-bar-on-the-same-path-would-not-follow',
    'noLoop':
        'the-timer-writes-the-stop-it-is-already-moving-to-following-the-value-finds-the-carousel-there-and-the-settle-of-a-reader-move-writes-nothing',
    'refusedWrite': 'the-carousel-stays-on-the-new-stop',
  },
  'insideRepeater': 'every-instance-of-the-template-has-its-own-timer',
  'notPublished': {'rowWithFewerThanTwoCards': 'carousel_auto_advance_not_read'},
  'ownProgress':
      'a-segmented-ProgressBar-bound-to-carousel.stopPath-follows-the-steps-the-fill-of-the-current-segment-over-time-is-not-in-the-contract',
  'builder': 'the-preview-runs-the-timer-the-canvas-of-the-editor-and-still-pictures-do-not',
  'olderReader': 'skips-the-field-only-a-person-moves-the-carousel',
  'cases': 'contract/fixtures/carousel/carousel-cases.json',
};
