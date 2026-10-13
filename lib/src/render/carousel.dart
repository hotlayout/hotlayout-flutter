import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../model/carousel_rules.dart';

/// The carousel: scrolling that snaps to cards, with dots under it (schema 9.11.0,
/// `x-style.layout.carousel`).
///
/// Why not `PageView`: `viewportFraction` centres the page, does not know the start inset and
/// cannot make "the last card stops at the end of the scroll". So this is the same horizontal
/// `SingleChildScrollView` as a scrolling row, with its own [CarouselPhysics]: after the finger
/// is released it leads to the nearest STOP from the `carouselStops` list (toward the next one
/// in the direction of the velocity). Stops are computed from MEASURED card widths, so the same
/// `perView` and natural width are served by one code path; the card width formula
/// (`carouselCardWidth`) is applied by whoever builds the cards.

/// Snap physics: where the scroll ends up after release (`snap.stop`).
class CarouselPhysics extends ScrollPhysics {
  const CarouselPhysics({super.parent, required this.stops});

  /// Stops in logical pixels from the start; asked at the MOMENT of release, because card widths
  /// are known only after layout.
  final List<double> Function() stops;

  @override
  CarouselPhysics applyTo(ScrollPhysics? ancestor) =>
      CarouselPhysics(parent: buildParent(ancestor), stops: stops);

  /// Where to go from [pixels] at [velocity]: toward the next stop in the direction of the
  /// velocity, to the nearest one when there is no velocity (a tie goes to the earlier).
  double target(double pixels, double velocity, double minExtent, double maxExtent, Tolerance tolerance) {
    final list = [for (final stop in stops()) stop.clamp(minExtent, maxExtent).toDouble()]..sort();
    if (list.isEmpty) return pixels.clamp(minExtent, maxExtent).toDouble();
    if (velocity > tolerance.velocity) {
      for (final stop in list) {
        if (stop > pixels + kCarouselStopMerge) return stop;
      }
      return list.last;
    }
    if (velocity < -tolerance.velocity) {
      for (final stop in list.reversed) {
        if (stop < pixels - kCarouselStopMerge) return stop;
      }
      return list.first;
    }
    return list[activeCarouselStop(list, pixels)];
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // Beyond the bounds (bounce) and at the edges with outward motion: as in the parent.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final goal = target(position.pixels, velocity, position.minScrollExtent, position.maxScrollExtent, tolerance);
    if ((goal - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, goal, velocity, tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// Memory of a stack frame's carousels (`carousel.active.heldBy: 'stack-frame'`): which stop is
/// open in each carousel of the screen.
///
/// State belongs to the FRAME, not to the widget: the screen under the top one in the stack is
/// not built at all, and state in the carousel's `State` vanished with it, so after "back" the
/// user saw the first card. A frame lives while it is in the stack, so the memory lives exactly
/// that long. The key is [carouselStateKey]; the value is the start of the open stop in
/// logical pixels.
class CarouselMemory {
  final Map<String, double> offsets = {};
}

/// The carousel: a row of cards in a horizontal scroll with snapping and dots.
///
/// [cards] are the already painted cards (with the right width); gaps, insets and dots are
/// added here. [cardWidths] are the outer widths if known in advance (`perView`): then the
/// number of dots is known from the first frame. Otherwise widths are measured after layout
/// and the dots appear on the next frame.
///
/// The state (which stop is open) is READER state, not the document's: it is held by a
/// [ScrollController], starts at the first stop and lives while the screen is in the stack.
class Carousel extends StatefulWidget {
  const Carousel({
    super.key,
    required this.cards,
    required this.rowBuilder,
    required this.viewport,
    required this.padding,
    required this.gap,
    required this.dots,
    required this.indicatorGap,
    required this.dotSize,
    required this.dotGap,
    required this.dotRadius,
    required this.activeColor,
    this.cardWidths,
    this.stateKey,
    this.memory,
  });

  /// The state key ([carouselStateKey]) and the stack frame's memory; without them the carousel
  /// starts at the first stop every time.
  final String? stateKey;
  final CarouselMemory? memory;

  final List<Widget> cards;

  /// Builds the row of cards together with the gaps already inserted.
  final Widget Function(List<Widget> children) rowBuilder;

  /// The visible area (the node's box without the border).
  final double viewport;
  final EdgeInsetsDirectional padding;
  final double gap;
  final List<double>? cardWidths;

  /// `false` — `indicator: 'none'`.
  final bool dots;
  final double indicatorGap;
  final double dotSize;
  final double dotGap;
  final double dotRadius;
  final Color activeColor;

  @override
  State<Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<Carousel> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final remembered = _remembered;
    _controller = ScrollController(initialScrollOffset: remembered ?? 0);
    if (remembered != null && remembered > 0) {
      // Fewer stops now (`fewerStops: clamp`): a remembered position beyond the scroll bounds
      // becomes the last stop rather than an empty place.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final position = _controller.position;
        if (position.hasContentDimensions && position.pixels > position.maxScrollExtent) {
          _controller.jumpTo(position.maxScrollExtent);
        }
      });
    }
  }

  double? get _remembered {
    final key = widget.stateKey;
    return key == null ? null : widget.memory?.offsets[key];
  }

  /// Remember the open stop when the scroll comes to rest.
  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollEndNotification || notification.depth != 0) return false;
    final key = widget.stateKey;
    final memory = widget.memory;
    if (key == null || memory == null || notification.metrics.axis != Axis.horizontal) return false;
    final stops = _liveStops();
    final pixels = notification.metrics.pixels;
    memory.offsets[key] = stops[activeCarouselStop(stops, pixels).clamp(0, stops.length - 1)];
    return false;
  }
  final List<GlobalKey> _keys = [];

  /// The scroll does not change its element when dots appear or disappear: otherwise the old and
  /// new `Scrollable` would share one controller for a moment.
  final GlobalKey _scrollKey = GlobalKey();
  List<double>? _measured;
  bool _scheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<double>? _widths() {
    if (widget.cardWidths != null) return widget.cardWidths;
    return _measured;
  }

  CarouselStops? _stopsFor(double viewport) {
    final widths = _widths();
    if (widths == null) return null;
    return carouselStops(
      viewport: viewport,
      paddingStart: widget.padding.start,
      paddingEnd: widget.padding.end,
      gap: widget.gap,
      cards: widths,
    );
  }

  /// Stops at the moment of the gesture: card widths come from layout, not from the numbers known
  /// in advance. They coincide, but layout does not lie.
  List<double> _liveStops() {
    // During layout (the initial offset from the carousel's memory: the scroll asks for a stop
    // when its area changes) card sizes must not be read, because `RenderBox.size` throws in the
    // middle of the parent's layout. Widths known in advance, or measured after the previous
    // frame, are used here.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      return _stopsFor(widget.viewport)?.stops ?? const [0];
    }
    final widths = <double>[];
    for (final key in _keys) {
      final box = key.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) widths.add(box.size.width);
    }
    if (widths.length != widget.cards.length) return _stopsFor(widget.viewport)?.stops ?? const [0];
    final viewport = _controller.positions.isEmpty ? widget.viewport : _controller.positions.first.viewportDimension;
    return carouselStops(
      viewport: viewport,
      paddingStart: widget.padding.start,
      paddingEnd: widget.padding.end,
      gap: widget.gap,
      cards: widths,
    ).stops;
  }

  /// After the frame the cards are measured (natural width) and, if the number of stops may have
  /// changed, repainted: whether there are dots depends on it.
  void _remeasure() {
    if (_scheduled || widget.cardWidths != null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final widths = <double>[];
      for (final key in _keys) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        widths.add(box.size.width);
      }
      final before = _measured;
      if (before != null && before.length == widths.length) {
        var same = true;
        for (var i = 0; i < widths.length; i += 1) {
          if ((before[i] - widths[i]).abs() > 1e-6) same = false;
        }
        if (same) return;
      }
      setState(() => _measured = widths);
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.cards.length;
    while (_keys.length < count) {
      _keys.add(GlobalKey());
    }
    if (_keys.length > count) _keys.removeRange(count, _keys.length);
    _remeasure();

    final children = <Widget>[];
    for (var i = 0; i < count; i += 1) {
      if (i > 0 && widget.gap > 0) children.add(SizedBox(width: widget.gap));
      children.add(
        KeyedSubtree(
          key: _keys[i],
          // The list announces the position ("3 of 5"); the dots are not in the accessibility tree.
          child: Semantics(container: true, role: SemanticsRole.listItem, child: widget.cards[i]),
        ),
      );
    }

    // The list goes BEFORE the cards (the item role needs a parent with the list role), so it
    // wraps the row inside the scroll, not the scroll itself.
    final scroll = NotificationListener<ScrollNotification>(
      key: _scrollKey,
      onNotification: _onScroll,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _controller,
        padding: widget.padding,
        physics: CarouselPhysics(stops: _liveStops),
        child: Semantics(container: true, role: SemanticsRole.list, child: widget.rowBuilder(children)),
      ),
    );

    final stops = _stopsFor(widget.viewport);
    final dotCount = carouselDotCount(
      dots: widget.dots,
      stopCount: stops?.stops.length ?? 1,
      viewport: widget.viewport,
      dotSize: widget.dotSize,
      dotGap: widget.dotGap,
    );
    if (dotCount == 0 || stops == null) return scroll;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        scroll,
        SizedBox(height: widget.indicatorGap),
        // The dots are decoration: not a control and not in the accessibility tree.
        ExcludeSemantics(
          child: Center(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final offset = _controller.positions.isEmpty ? 0.0 : _controller.positions.first.pixels;
                final active = activeCarouselStop(stops.stops, offset);
                return _Dots(
                  count: dotCount,
                  active: active,
                  size: widget.dotSize,
                  gap: widget.dotGap,
                  radius: widget.dotRadius,
                  color: widget.activeColor,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A row of dots in reading order (in right-to-left writing the first is on the right).
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.active,
    required this.size,
    required this.gap,
    required this.radius,
    required this.color,
  });

  final int count;
  final int active;
  final double size;
  final double gap;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final inactive = color.withValues(alpha: color.a * kCarouselInactiveDotOpacity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i += 1) ...[
          if (i > 0 && gap > 0) SizedBox(width: gap),
          Container(
            key: ValueKey<String>(i == active ? 'carousel-dot-active-$i' : 'carousel-dot-$i'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: i == active ? color : inactive,
              borderRadius: BorderRadius.circular(math.min(radius, size / 2)),
            ),
          ),
        ],
      ],
    );
  }
}
