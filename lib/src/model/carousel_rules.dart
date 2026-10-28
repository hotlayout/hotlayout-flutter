import 'dart:math' as math;

import 'carousel_stop.dart';
import 'progress_rules.dart';
import 'style_values.dart';

/// THE CAROUSEL: card width, snap stops and dots (schema 9.11.0,
/// `x-style.layout.carousel`).
///
/// Mirror of the builder's `carousel-rules.ts`, verbatim: only GEOMETRY and
/// selection, with no theme and no widgets. The gap, padding and peek arrive as
/// numbers already resolved by the caller. The functions cannot drift from the
/// reference implementation: `test/carousel_cases_test.dart` reads the case
/// table itself (`fixtures/carousel/carousel-cases.json`) and runs every row.
///
/// A carousel is not a widget but a `carousel` field on two hosts: a `Row` with
/// `scrollable: true` and a `Repeater` with `direction: 'row'` and NO
/// `columns`. Node parsing (`node.dart`) decides who the host is; this file
/// says what the field means.

/// Bounds of `perView` (`card.perViewMin` / `perViewMax`).
const int kCarouselPerViewMin = 1;
const int kCarouselPerViewMax = 6;

/// The peek of the next card when the field is absent or unreadable.
const String kDefaultCarouselPeek = 'lg';

/// The dots when the `indicator` field is absent or its word is unknown.
const String kDefaultCarouselIndicator = 'dots';

/// With more stops than this, no dots are drawn.
const int kCarouselMaxDots = 10;

/// Opacity of an inactive dot (the colour is the same as the active one's).
const double kCarouselInactiveDotOpacity = 0.3;

/// A card narrower than this is not a card: `perView` is not applied and the width is natural.
const double kCarouselMinCard = 1;

/// A card start closer to the scroll end than this is the same end.
const double kCarouselStopMerge = 0.5;

/// Dot tokens (`indicator.gap` / `dotSize` / `dotGap`, `dotRadius`,
/// `activeColor`).
const String kCarouselIndicatorGap = 'sm';
const String kCarouselDotSize = 'sm';
const String kCarouselDotGap = 'sm';
const String kCarouselDotRadius = 'pill';
const String kCarouselActiveColor = 'primary';

/// A carousel as the reader reads it (`readCarousel`).
final class ReaderCarousel {
  const ReaderCarousel({this.perView, this.peek, this.dots = true, this.stopPath});

  /// Number of whole cards in the visible area; `null` means natural width.
  final int? perView;

  /// Reference to the peek if readable; the default is [kDefaultCarouselPeek].
  final ScaleRef? peek;

  /// `false` — `indicator: 'none'`.
  final bool dots;

  /// The number data path the carousel writes its active stop to and follows (9.32.0, `carousel.stopPath`); `null`
  /// means there is no readable path, and the carousel neither writes nor follows anything.
  final String? stopPath;

  @override
  bool operator ==(Object other) =>
      other is ReaderCarousel &&
      other.perView == perView &&
      other.peek == peek &&
      other.dots == dots &&
      other.stopPath == stopPath;

  @override
  int get hashCode => Object.hash(perView, peek, dots, stopPath);
}

/// THE FIELD VALUE AS THE READER READS IT, whatever its shape:
///
///  * not an object: there is no carousel, and the row scrolls as it did before 9.11;
///  * `perView` not an integer 1..6: natural width;
///  * `peek` not a reference to a spacing: the default (read like a thickness:
///    a token or an integer 0..128);
///  * `indicator`: only `'none'` turns the dots off, anything else means dots;
///  * `stopPath` (9.32.0): a non-empty string up to 128 characters, otherwise there is no path;
///  * an unknown key is skipped.
ReaderCarousel? readCarousel(Object? raw) {
  if (raw is! Map) return null;
  final perView = raw['perView'];
  return ReaderCarousel(
    perView:
        perView is num &&
            perView.isFinite &&
            perView == perView.roundToDouble() &&
            perView >= kCarouselPerViewMin &&
            perView <= kCarouselPerViewMax
        ? perView.toInt()
        : null,
    peek: readProgressThickness(raw['peek']),
    dots: raw['indicator'] != 'none',
    stopPath: carouselStopPathOf(raw),
  );
}

/// CARD WIDTH for `perView`: `(viewport - paddingInlineStart - perView * gap -
/// peek) / perView`, WITHOUT rounding. `null` means no card came out (too
/// narrow, infinity): the width is natural, as without the field.
double? carouselCardWidth({
  required double viewport,
  required double paddingStart,
  required double gap,
  required double peek,
  required int perView,
}) {
  final width = (viewport - paddingStart - perView * gap - peek) / perView;
  return width.isFinite && width >= kCarouselMinCard ? width : null;
}

/// Snap stops (`carouselStops`).
final class CarouselStops {
  const CarouselStops({required this.stops, required this.maxScroll, required this.stopOfCard});

  /// Offsets where scrolling stops, ascending; there is always at least one.
  final List<double> stops;
  final double maxScroll;

  /// Which stop shows each card at the start (or the scroll end).
  final List<int> stopOfCard;
}

/// STOPS: card starts measured from the first card's start, no further than
/// `maxScroll = paddingStart + cards with gaps + paddingEnd - viewport`; a stop
/// beyond `maxScroll - 0.5` is `maxScroll`; the scroll end is always a stop.
/// [cards] are the outer widths (box plus `margin`) in document order.
CarouselStops carouselStops({
  required double viewport,
  required double paddingStart,
  required double paddingEnd,
  required double gap,
  required List<double> cards,
}) {
  final starts = <double>[];
  var cursor = 0.0;
  for (var index = 0; index < cards.length; index += 1) {
    starts.add(cursor);
    cursor += cards[index] + (index < cards.length - 1 ? gap : 0);
  }
  final content = paddingStart + cursor + paddingEnd;
  final maxScroll = math.max(0.0, content - viewport);
  final stops = <double>[];
  final stopOfCard = <int>[];
  for (final start in starts) {
    if (maxScroll > 0 && start < maxScroll - kCarouselStopMerge) {
      stops.add(start);
      stopOfCard.add(stops.length - 1);
    } else {
      // All cards whose start cannot be reached share the "end" stop.
      if (stops.isEmpty || stops.last != maxScroll) stops.add(maxScroll);
      stopOfCard.add(stops.length - 1);
    }
  }
  if (stops.isEmpty) stops.add(0);
  // The last card is wider than the area: the scroll end is always a stop.
  if (maxScroll > 0 && stops.last < maxScroll - kCarouselStopMerge) stops.add(maxScroll);
  return CarouselStops(stops: stops, maxScroll: maxScroll, stopOfCard: stopOfCard);
}

/// THE ACTIVE STOP: the one nearest to the offset; on a tie, the earlier. The
/// offset is from the logical start; outside the range (overscroll) it is the
/// extreme stop.
int activeCarouselStop(List<double> stops, double offset) {
  final at = offset.isFinite ? math.max(0.0, offset) : 0.0;
  var best = 0;
  var distance = double.infinity;
  for (var index = 0; index < stops.length; index += 1) {
    final away = (stops[index] - at).abs();
    if (away < distance) {
      best = index;
      distance = away;
    }
  }
  return best;
}

/// Width of the row of dots (`indicator.dotsRowWidth`):
/// `count * dotSize + (count - 1) * dotGap`.
double carouselDotsRowWidth(int count, double dotSize, double dotGap) => count * dotSize + (count - 1) * dotGap;

/// How many dots to draw: 0 means there is no indicator and it takes no room.
///
/// ONE function holds the rule: nothing is drawn when dots are off, there is a
/// single stop, there are more than 10 stops, OR the row `dotsRowWidth` does
/// not fit the viewport width [viewport] (the row fits when its width is
/// `<= viewport`; `dotsRowWiderThanViewport: 'not-drawn'`). The widget asks
/// this function and computes nothing itself.
int carouselDotCount({
  required bool dots,
  required int stopCount,
  required double viewport,
  required double dotSize,
  required double dotGap,
}) {
  if (!dots || stopCount <= 1 || stopCount > kCarouselMaxDots) return 0;
  if (carouselDotsRowWidth(stopCount, dotSize, dotGap) > viewport) return 0;
  return stopCount;
}

/// Height of the indicator under the area: gap plus dot; 0 when there are no dots.
double carouselIndicatorBlock(int dotCount, double gap, double dotSize) => dotCount > 0 ? gap + dotSize : 0;

/// The eight carousel policy rows of 9.11.0 plus two for segments, ten in all
/// (`x-compatibility.policy`, starting at `carouselOutsideHost`).
const Map<String, String> kCarouselPolicy = {
  'carouselOutsideHost': 'ignore',
  'unreadableCarousel': 'plain-scroll-unreadable-part-default',
  'carouselCardWidth': 'carousel-wins-over-own-width',
  'carouselNested': 'inner-takes-the-gesture',
  'carouselState': 'reader-state-starts-at-first-stop',
  'carouselGestures': 'along-row-carousel-across-screen',
  'carouselIndicator': 'decorative-position-told-by-the-list',
  'carouselReducedMotion': 'no-animated-programmatic-scroll-snap-stays',
  ...kSegmentsPolicy,
};

/// The key of a carousel's state (`carousel.active.keyedBy:
/// 'node-and-template-instance-path'`): the node TOGETHER WITH the chain of
/// template-instance indexes from the root. A carousel in a data-driven list
/// row has its own state per record; a list in a list uses the whole chain, not
/// the last index. Only the equality of keys is compared, not their shape
/// (`stateCases`).
String carouselStateKey(String nodeId, List<int> instance) => '${nodeId.length}:$nodeId/${instance.join('.')}';
