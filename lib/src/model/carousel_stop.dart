import 'input_rules.dart' show readInputNumber;
import 'write_action.dart' show holdsWritten;

// The carousel tells the active stop (schema 9.32.0, `x-carouselStop`).
//
// Mirrors the reference implementation `carousel-stop.ts`. The optional `carousel.stopPath` names a NUMBER data
// path. A person's swipe, once the scroll has settled on a stop, writes the stop number there (the very write an
// input field makes: the session of the reader and the host at the same moment, under `writablePaths`); the carousel
// stands on the stop the value names when it is shown, and moves to it when the number changes. The rows of the
// `stop...` groups of `fixtures/carousel/carousel-cases.json` run these functions
// (`carousel_stop_cases_test.dart`); the gestures, the scrolling and the clock belong to `render/carousel.dart`.

/// The field inside the `carousel` object.
const String kCarouselStopKey = 'stopPath';

/// The longest path: the common bound of a data path.
const int kCarouselStopPathMax = 128;

/// The path as the reader reads it: the value of `carousel.stopPath` when it is a non-empty string within the bound.
/// Anything else (not a string, empty, too long) means there is no path: the carousel scrolls as without the field
/// and writes nothing. [raw] is the `carousel` object of a node that is a carousel host.
String? carouselStopPathOf(Object? raw) {
  if (raw is! Map) return null;
  final path = raw[kCarouselStopKey];
  return path is String &&
          path.isNotEmpty &&
          path.length <= kCarouselStopPathMax
      ? path
      : null;
}

/// The stop number a value names: a number with an integer value (`1` and `1.0` alike); otherwise none.
int? carouselStopNumberOf(Object? value) {
  final number = readInputNumber(value);
  if (number == null || !number.isFinite || number != number.truncateToDouble()) {
    return null;
  }
  return number.toInt();
}

/// The stop to show for a value: its number clamped to `[0, stopCount - 1]`; no number means the first.
int carouselShownStop(Object? value, int stopCount) {
  final last = stopCount < 1 ? 0 : stopCount - 1;
  final number = carouselStopNumberOf(value);
  return number == null ? 0 : number.clamp(0, last);
}

/// Where to go when the value changed, or `null` for nowhere. The event is a change of the NUMBER, not a comparison
/// of what is shown with the data at draw time: a write the host refused leaves the carousel where the person put it.
int? carouselStopFollow({
  required Object? previous,
  required Object? next,
  required int stopCount,
  required int active,
}) {
  if (carouselStopNumberOf(previous) == carouselStopNumberOf(next)) return null;
  final target = carouselShownStop(next, stopCount);
  return target == active ? null : target;
}

/// What to write when the scroll settled on [settled]: the stop number, only after a person's move and only if it is
/// not already there.
int? carouselStopWrite({
  required int settled,
  required bool byPerson,
  required Object? current,
}) {
  if (!byPerson || settled < 0) return null;
  return holdsWritten(current, settled) ? null : settled;
}

/// Mirror of the `x-carouselStop` block. Values are checked against the artifact by `carousel_stop_cases_test.dart`.
const Map<String, Object?> kCarouselStopRules = {
  'refines': ['x-style.layout.carousel.active'],
  'prop': 'carousel.stopPath',
  'path': {
    'is': 'a-literal-of-the-document-never-read-from-data',
    'maxLength': kCarouselStopPathMax,
    'type': 'number',
    'typeMatch':
        'exactly-number-checked-by-the-builder-against-the-data-contract',
    'unreadable':
        'no-path-the-carousel-writes-nothing-and-starts-at-the-first-stop',
    'misplaced': 'x-style.layout.carousel.misplaced',
  },
  'value': {
    'is': 'the-index-of-the-active-snap-stop-from-0',
    'counts': 'stops-of-x-style.layout.carousel.snap-not-cards',
    'written': 'an-integer-number',
  },
  'write': {
    'when':
        'a-person-moved-the-carousel-and-the-scroll-settled-on-a-stop-after-snapping',
    'notWhen': [
      'during-the-gesture',
      'the-reader-moved-it-the-show-or-following-the-value',
      'no-gesture-at-all',
    ],
    'sameValue': 'not-written-again-x-actions.write.sameValue.equality',
    'mechanism': 'the-write-of-an-input-x-style.layout.inputs.rules.write',
    'to': 'session-of-the-reader-and-the-host-at-the-same-moment',
    'gate': 'the-writable-paths-of-the-host-like-every-input',
    'host': {'onWrite': 'path-and-the-number', 'onAction': 'not-called'},
    'track': 'none',
  },
  'read': {
    'layers': 'x-dataScope.layers-with-the-data-scope-of-the-node',
    'number': 'a-number-with-an-integer-value-1-and-1.0-alike',
    'notANumber': 'the-first-stop',
    'fraction': 'the-first-stop',
    'outOfRange': 'clamped-to-the-first-or-the-last-stop',
    'atShow':
        'the-carousel-starts-at-the-stop-the-value-names-once-the-stops-are-laid-out-without-animation',
    'onChange': 'the-carousel-moves-to-the-stop-the-new-value-names',
    'change':
        'a-change-of-the-number-the-value-names-not-a-comparison-at-draw-time',
    'refusedWrite': 'the-carousel-stays-where-the-person-left-it',
    'duringGesture': 'the-gesture-wins-the-change-is-not-applied',
    'reducedMotion': 'x-style.layout.carousel.accessibility.reducedMotion',
    'fewerStops': 'x-style.layout.carousel.active.fewerStops',
  },
  'state':
      'x-style.layout.carousel.active.heldBy-unchanged-the-field-tells-the-data-where-the-state-is',
  'ownDots':
      'nodes-with-styleWhen-on-the-same-path-and-setValue-of-a-number-no-new-widget',
  'insideRepeater': 'not-published-every-row-would-write-the-same-path',
  'builder': 'the-preview-writes-and-follows-the-canvas-of-the-editor-neither',
  'olderReader':
      'skips-the-field-the-carousel-scrolls-nothing-is-written-and-it-starts-at-the-first-stop',
  'cases': 'contract/fixtures/carousel/carousel-cases.json',
};
