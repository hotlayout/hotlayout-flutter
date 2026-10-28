import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/semantics.dart';

import '../model/carousel_rules.dart';
import '../model/carousel_stop.dart';

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
    this.stopPath,
    this.stopValue,
    this.onStopWrite,
  });

  /// The number data path of the active stop (9.32.0, `carousel.stopPath`); `null` means the carousel neither
  /// writes nor follows anything.
  final String? stopPath;

  /// The value under [stopPath] now, read through the data layers of the node.
  final Object? stopValue;

  /// Writes the stop number a person settled on to [stopPath]: the very write an input field makes (session and
  /// host at the same moment). `null` when nothing can be written.
  final ValueChanged<int>? onStopWrite;

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

  /// The value under the stop path when the carousel looked last: a change of the NUMBER it names moves the carousel.
  Object? _lastValue;

  /// A person moved the scroll since it was last at rest: a drag, or the wheel. The reader's own moves (the show, the
  /// following of the value) clear it, so they never write.
  bool _person = false;

  /// The finger holds the row: a change of the value is not applied then.
  bool _dragging = false;

  /// The carousel stands on the stop its value names (set once the stops are laid out).
  bool _placed = true;

  @override
  void initState() {
    super.initState();
    _lastValue = widget.stopValue;
    final shown = _shownOffset();
    final remembered = shown == null ? _remembered : null;
    _controller = ScrollController(initialScrollOffset: shown ?? remembered ?? 0);
    if (widget.stopPath != null) {
      // With a path the value tells where to stand, whatever the frame remembered; the stops are known now (`perView`)
      // or after the first measuring.
      _placed = shown != null;
      if (!_placed) WidgetsBinding.instance.addPostFrameCallback((_) => _placeShown());
    } else if (remembered != null && remembered > 0) {
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

  /// The offset of the stop the value names, when the stops are known; `null` otherwise.
  double? _shownOffset() {
    if (widget.stopPath == null) return null;
    final stops = _stopsFor(widget.viewport)?.stops;
    if (stops == null) return null;
    return stops[carouselShownStop(widget.stopValue, stops.length)];
  }

  /// Stand on the stop the value names, without animation, once the stops are laid out (natural card widths).
  void _placeShown() {
    if (!mounted || _placed || widget.stopPath == null || !_controller.hasClients) return;
    final stops = _liveStops();
    _placed = true;
    _moveByReader(stops[carouselShownStop(widget.stopValue, stops.length)], animate: false);
  }

  /// A move the reader makes (the show, the following of the value): never written back.
  void _moveByReader(double offset, {required bool animate}) {
    if (!_controller.hasClients) return;
    _person = false;
    final position = _controller.position;
    final goal = offset.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if ((position.pixels - goal).abs() < 0.01) return;
    if (animate) {
      _controller.animateTo(goal, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    } else {
      _controller.jumpTo(goal);
    }
  }

  @override
  void didUpdateWidget(Carousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stopPath != oldWidget.stopPath) {
      _lastValue = widget.stopValue;
      _placed = widget.stopPath == null;
      if (!_placed) WidgetsBinding.instance.addPostFrameCallback((_) => _placeShown());
      return;
    }
    if (widget.stopPath == null) return;
    final previous = _lastValue;
    _lastValue = widget.stopValue;
    // The gesture wins: a change under the finger is not applied. A stop not laid out yet is placed from the latest value.
    if (_dragging || !_placed) return;
    final value = widget.stopValue;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final stops = _liveStops();
      final target = carouselStopFollow(
        previous: previous,
        next: value,
        stopCount: stops.length,
        active: activeCarouselStop(stops, _controller.position.pixels),
      );
      if (target != null) _moveByReader(stops[target], animate: !MediaQuery.disableAnimationsOf(context));
    });
  }

  /// A scroll came to rest: remember the open stop, and tell a person's stop to the data.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.horizontal) return false;
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      _dragging = true;
      _person = true;
    }
    if (notification is! ScrollEndNotification) return false;
    _dragging = false;
    final stops = _liveStops();
    final active = activeCarouselStop(stops, notification.metrics.pixels).clamp(0, stops.length - 1);
    final key = widget.stateKey;
    final memory = widget.memory;
    if (key != null && memory != null) memory.offsets[key] = stops[active];
    final byPerson = _person;
    _person = false;
    final write = widget.onStopWrite;
    // Not in the middle of a layout (a rest caused by new dimensions is never a person's): a write sets state.
    if (widget.stopPath != null &&
        write != null &&
        SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      final value = carouselStopWrite(settled: active, byPerson: byPerson, current: widget.stopValue);
      if (value != null) write(value);
    }
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
      if (!_placed) WidgetsBinding.instance.addPostFrameCallback((_) => _placeShown());
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
    final scroll = Listener(
      // The wheel is a person's move too; a drag is told by its scroll notification.
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _person = true;
      },
      child: NotificationListener<ScrollNotification>(
        key: _scrollKey,
        onNotification: _onScroll,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _controller,
          padding: widget.padding,
          physics: CarouselPhysics(stops: _liveStops),
          child: Semantics(container: true, role: SemanticsRole.list, child: widget.rowBuilder(children)),
        ),
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
