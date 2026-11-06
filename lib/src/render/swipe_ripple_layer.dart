/// The fill of a "swipe to confirm" button over the whole screen (schema 9.34.0, `confirmTransition: 'ripple'`).
///
/// The layer belongs to the screen flow, not to the button: the button leaves the tree when the screen changes, and the
/// fill must still be there to show the next screen from under it. It lies over everything the flow draws (the zones,
/// the navigation bar, the modal layers), is cut by the edges of the flow, and catches presses while it grows. The
/// circle grows linearly to cover the farthest corner, then the action runs (the screen changes under the fill, with
/// no motion of its own), then the fill fades away over the next screen.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../model/swipe_confirm.dart';
import '../model/swipe_motion.dart';

/// What the button hands over to start the fill.
class SwipeRippleSpec {
  const SwipeRippleSpec({
    required this.center,
    required this.halo,
    required this.core,
    required this.color,
    required this.indicatorSize,
    required this.onCovered,
    this.indicator,
  });

  /// The centre of the collapsed circle, in global coordinates.
  final Offset center;

  /// The diameter of the halo and of the core of the circle.
  final double halo;
  final double core;

  /// The colour of the thumb: the core is this colour, the halo the same at [kSwipeHaloOpacity].
  final Color color;

  final double indicatorSize;

  /// Draws the indicator of "busy" at the centre of the circle, or `null` for none.
  final Widget Function(Animation<double> turns)? indicator;

  /// Runs once, when the screen is covered. Not called when the fill is cancelled before.
  final VoidCallback onCovered;
}

/// One fill in flight: the button asks for it to be dropped when it leaves before the screen is covered.
class SwipeRippleHandle {
  SwipeRippleHandle._(this._drop, this._entry);

  final void Function(_Entry entry) _drop;
  final _Entry _entry;

  /// Removes the fill if the screen has not been covered yet; nothing runs.
  void cancel() {
    if (!_entry.acted) _drop(_entry);
  }
}

class _Entry {
  _Entry(this.spec, this.center, this.screen) : key = UniqueKey();

  final SwipeRippleSpec spec;

  /// The centre of the circle and the size of the flow, in the coordinates of the layer.
  final Offset center;
  final Size screen;
  final Key key;
  bool acted = false;

  /// The entry in the nearest `Overlay`, when the fill lies over the host's routes.
  OverlayEntry? overlayEntry;
}

/// The place a button asks for a fill: the nearest [SwipeRippleHost] above it.
class SwipeRippleScope extends InheritedWidget {
  const SwipeRippleScope({super.key, required this.start, required super.child});

  final SwipeRippleHandle Function(SwipeRippleSpec spec) start;

  /// The scope above [context], or `null` when the button is not inside a screen flow: it then has no fill.
  static SwipeRippleScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<SwipeRippleScope>();

  @override
  bool updateShouldNotify(SwipeRippleScope oldWidget) => false;
}

/// Holds the layers of the fills over [child]. The stack is always there, so the child keeps its place in the tree.
class SwipeRippleHost extends StatefulWidget {
  const SwipeRippleHost({super.key, required this.child, this.onCoverChanged});

  final Widget child;

  /// Told when a fill starts covering the screen and when the last one is gone: a screen that changes meanwhile does
  /// so with no motion of its own.
  final ValueChanged<bool>? onCoverChanged;

  @override
  State<SwipeRippleHost> createState() => _SwipeRippleHostState();
}

class _SwipeRippleHostState extends State<SwipeRippleHost> {
  final List<_Entry> _entries = [];

  SwipeRippleHandle _start(SwipeRippleSpec spec) {
    final box = context.findRenderObject() as RenderBox?;
    final size = box != null && box.hasSize ? box.size : MediaQuery.sizeOf(context);
    final entry = _Entry(spec, box != null && box.hasSize ? box.globalToLocal(spec.center) : spec.center, size);
    final wasCovering = _entries.isNotEmpty;
    setState(() => _entries.add(entry));
    if (!wasCovering) widget.onCoverChanged?.call(true);
    return SwipeRippleHandle._(_remove, entry);
  }

  /// Drops [entry]. A button that leaves the tree asks for this while the tree is locked, so the layer goes after the
  /// frame.
  void _remove(_Entry entry) {
    if (!_entries.remove(entry)) return;
    if (_entries.isEmpty) widget.onCoverChanged?.call(false);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => SwipeRippleScope(
    start: _start,
    child: Stack(
      fit: StackFit.passthrough,
      // Cut by the edges of the flow: the fill grows far past them.
      clipBehavior: Clip.hardEdge,
      children: [
        widget.child,
        for (final entry in _entries)
          Positioned.fill(
            key: entry.key,
            child: _RippleLayer(
              entry: entry,
              onCovered: () {
                entry.acted = true;
                entry.spec.onCovered();
              },
              onDone: () => _remove(entry),
            ),
          ),
      ],
    ),
  );
}

/// Provides [SwipeRippleScope] for a screen drawn by `renderScreen`, where the host keeps the stack of screens: the
/// fill lies in the nearest `Overlay`, above the routes of the host, so it outlives the route the button was on.
///
/// The layer is cut by the bounds of that overlay, and the farthest corner is a corner of it. A fill that has not
/// covered the screen yet goes with the provider (nothing runs); one that has acted goes on to its end. With no
/// `Overlay` above there is no place for a fill and no scope: the action runs at once.
class SwipeRippleOverlayHost extends StatefulWidget {
  const SwipeRippleOverlayHost({super.key, required this.child, this.onScreenCovered});

  final Widget child;

  /// `true` when a fill starts covering the screen (before the action), `false` when the last one is gone.
  final ValueChanged<bool>? onScreenCovered;

  @override
  State<SwipeRippleOverlayHost> createState() => _SwipeRippleOverlayHostState();
}

class _SwipeRippleOverlayHostState extends State<SwipeRippleOverlayHost> {
  final List<_Entry> _entries = [];

  // Kept apart from `widget`: a fill that has acted outlives this state and still reports its end.
  ValueChanged<bool>? _report;

  SwipeRippleHandle _start(SwipeRippleSpec spec) {
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject() as RenderBox?;
    final sized = box != null && box.hasSize;
    final entry = _Entry(
      spec,
      sized ? box.globalToLocal(spec.center) : spec.center,
      sized ? box.size : MediaQuery.sizeOf(context),
    );
    _report = widget.onScreenCovered;
    final wasCovering = _entries.isNotEmpty;
    _entries.add(entry);
    entry.overlayEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: ClipRect(
          child: _RippleLayer(
            entry: entry,
            onCovered: () {
              entry.acted = true;
              entry.spec.onCovered();
            },
            onDone: () => _remove(entry),
          ),
        ),
      ),
    );
    overlay.insert(entry.overlayEntry!);
    if (!wasCovering) _report?.call(true);
    return SwipeRippleHandle._(_remove, entry);
  }

  void _remove(_Entry entry) {
    if (!_entries.remove(entry)) return;
    entry.overlayEntry?.remove();
    entry.overlayEntry?.dispose();
    entry.overlayEntry = null;
    if (_entries.isNotEmpty) return;
    // A button that leaves the tree asks for this while the tree is locked, and the host may rebuild on the answer.
    final report = _report;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_entries.isEmpty) report?.call(false);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    for (final entry in List.of(_entries)) {
      if (!entry.acted) _remove(entry);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) return widget.child;
    return SwipeRippleScope(start: _start, child: widget.child);
  }
}

/// The key of the fill while it is on the screen, for tests that look for it.
const Key kSwipeRippleLayerKey = ValueKey<String>('hotlayout-swipe-ripple');

enum _Stage { grow, reveal }

class _RippleLayer extends StatefulWidget {
  const _RippleLayer({required this.entry, required this.onCovered, required this.onDone});

  final _Entry entry;
  final VoidCallback onCovered;
  final VoidCallback onDone;

  @override
  State<_RippleLayer> createState() => _RippleLayerState();
}

class _RippleLayerState extends State<_RippleLayer> with TickerProviderStateMixin {
  late final AnimationController _clock;
  late final AnimationController _spin;
  _Stage _stage = _Stage.grow;
  late final double _scale;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: kSwipeRippleMs.round()),
    )..addStatusListener(_onStatus);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kSwipeSpinnerTurnMs),
    )..repeat();
    // The geometry is fixed when the fill starts: the layer lies over the whole flow, so it is measured once.
    final entry = widget.entry;
    _scale = swipeRippleScaleOf(
      centerX: entry.center.dx,
      centerY: entry.center.dy,
      screenWidth: entry.screen.width,
      screenHeight: entry.screen.height,
      core: entry.spec.core,
    );
    _clock.forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_stage == _Stage.grow) {
      // The fade is set going before the host hears anything: whatever the action does, the fill ends on its own.
      setState(() => _stage = _Stage.reveal);
      _clock
        ..duration = Duration(milliseconds: kSwipeRevealMs.round())
        ..forward(from: 0);
      try {
        widget.onCovered();
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'hotlayout_flutter',
            context: ErrorDescription('while running the action of a swipe button after its fill covered the screen'),
          ),
        );
      }
    } else {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.entry.spec;
    final center = widget.entry.center;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final elapsed = _clock.value * _clock.duration!.inMilliseconds;
        final growing = _stage == _Stage.grow;
        final scale = growing ? swipeRippleAt(_scale, elapsed) : _scale;
        final opacity = growing ? 1.0 : swipeRevealAt(elapsed);
        return IgnorePointer(
          ignoring: !growing,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Opacity(
                key: kSwipeRippleLayerKey,
                opacity: opacity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _CirclePainter(
                        center: center,
                        halo: spec.halo / 2 * scale,
                        core: spec.core / 2 * scale,
                        color: spec.color,
                      ),
                    ),
                    if (spec.indicator != null)
                      Positioned(
                        left: center.dx - spec.indicatorSize / 2,
                        top: center.dy - spec.indicatorSize / 2,
                        width: spec.indicatorSize,
                        height: spec.indicatorSize,
                        child: spec.indicator!(_spin),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CirclePainter extends CustomPainter {
  const _CirclePainter({required this.center, required this.halo, required this.core, required this.color});

  final Offset center;
  final double halo;
  final double core;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(center, halo, Paint()..color = color.withValues(alpha: color.a * kSwipeHaloOpacity));
    canvas.drawCircle(center, core, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CirclePainter old) =>
      old.center != center || old.halo != halo || old.core != core || old.color != color;
}
