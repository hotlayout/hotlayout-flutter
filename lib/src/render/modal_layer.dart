// The modal layer of the screen stack: scrim, sheet or centred window.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../model/media_chrome_rules.dart';
import '../model/sheet_dismiss.dart';
import '../model/wide_chrome_rules.dart';
import 'motion.dart';
import 'screen_transitions.dart';
import 'screen_zones.dart';
import 'sheet_drag.dart';

/// Key of the modal layer's box, for tests that measure its rectangle.
@visibleForTesting
const Key kModalLayerKey = ValueKey<String>('hotlayout-modal-layer');

/// The scale a centred window grows from while it fades in.
@visibleForTesting
const double kModalWindowStartScale = 0.96;

/// A sheet shown on a wide place as a WINDOW (schema 9.18.0): the screen in the layer cannot
/// tell this from its own width (that is 560, `compact`), so the layer tells it through this
/// scope. The root of such a layer takes its bottom corner radius from the top ones and has no
/// bottom safe area inset.
class SheetWindowScope extends InheritedWidget {
  const SheetWindowScope({super.key, required this.sheetWindow, required super.child});

  final bool sheetWindow;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetWindowScope>()?.sheetWindow ?? false;

  @override
  bool updateShouldNotify(SheetWindowScope oldWidget) => oldWidget.sheetWindow != sheetWindow;
}

/// The modal layer: a sheet sliding in from the bottom, or a window in the middle (schema
/// 9.9.0).
///
/// A stateful widget of our own, not `showModalBottomSheet`: the renderer has its own screen
/// stack (the document arrives whole and its screens are flow pages, not app routes), and
/// handing the host's `Navigator` over for the sake of an animation would change the
/// architecture for an effect.
///
/// The geometry is [modalBoxOf], checked against the `modalCases` table: a sheet spans the
/// area's full width and is pressed to the bottom; a window is the area minus an `xl` margin on
/// each side, at most 400 wide, centred on both axes. The height follows the content, at most
/// the available height; taller content scrolls INSIDE the layer (the screen root carries the
/// scroll). The layer has no built-in look: background, radius and shadow come from the screen
/// root's `style`. The scrim is black at 0.45 over the whole area; a touch outside the window
/// is `navigate.back`, like the system "back".
///
/// The sheet slides in from the bottom and the window grows from 96 % while it fades in (the
/// contract is silent about motion). Closing plays the same in reverse ([closing]): the screen
/// stack has already dropped the frame, and the flow keeps painting it here, untouchable, only
/// until [onClosed]; the stack itself never holds an "almost removed" screen.
class ModalLayer extends StatefulWidget {
  const ModalLayer({
    super.key,
    required this.onDismiss,
    required this.sheet,
    required this.placement,
    required this.windowMargin,
    this.backdropBlur,
    this.animateIn = true,
    this.closing = false,
    this.onClosed,
    this.dismissible = true,
  });

  /// Whether a person can close the layer: a tap on the scrim and a drag down (schema 9.26.0, `dismissible: false`
  /// turns both off; Esc is the flow's and checks the same word).
  final bool dismissible;

  final VoidCallback onDismiss;
  final Widget sheet;
  final ModalPlacement placement;

  /// Margin of the window (`center.margin`, step `xl`), dp.
  final double windowMargin;

  /// Blur of everything under the layer (schema 9.20.0, `ScreenEntry.backdropBlur`), in logical pixels: the
  /// standard deviation of a Gaussian blur. The scrim lies over it and the layer itself is never blurred.
  /// `null` means only the scrim, as before 9.20.0.
  final int? backdropBlur;

  /// Whether the layer slides in when it is first built. `false` for a layer that was already
  /// open and is only drawn again (the page above it went back), and when there is to be no motion.
  final bool animateIn;

  /// Whether the layer is on its way out: it plays its appearance in reverse, ignores touches, and
  /// calls [onClosed] when it is gone.
  final bool closing;

  /// Called once the closing motion is over (after the frame, never during a build).
  final VoidCallback? onClosed;

  @override
  State<ModalLayer> createState() => _ModalLayerState();
}

class _ModalLayerState extends State<ModalLayer> with TickerProviderStateMixin {
  // The layer moves between sheet and window when the area changes its width class (rotation,
  // split screen): the key keeps the same subtree, so typed text and focus are not lost.
  final GlobalKey _layerSlot = GlobalKey(debugLabel: 'hotlayout-modal-layer');
  late final AnimationController _controller = AnimationController(vsync: this, duration: Motion.sheet);

  // THE DRAG DOWN (schema 9.26.0). [_offset] is how far the sheet is pulled from its place, logical pixels. The way
  // back or out is [_settle], which moves [_offset] from [_settleFrom] to [_settleTo] along [_settleCurve].
  // [_bodyScrolled] is how far the body of the sheet is scrolled from its top (the drag starts only at the top).
  // [_exiting]: the sheet is on its way out by a drag, and only then does the stack go back; [_exited]: it has left.
  late final AnimationController _settle = AnimationController(vsync: this)..addListener(_onSettle);
  double _offset = 0;
  double _settleFrom = 0;
  double _settleTo = 0;
  Curve _settleCurve = Curves.linear;
  double _bodyScrolled = 0;
  double _sheetHeight = 0;
  bool _exiting = false;
  bool _exited = false;
  VoidCallback? _settled;


  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    if (!widget.animateIn) {
      _controller.value = 1;
      if (widget.closing) _close();
      return;
    }
    /*
     * The duration is taken in the first frame, not in the constructor: `MediaQuery` cannot be
     * read during `initState`. Zero here means "the system asks for no motion": the controller
     * then jumps to the end and the layer simply appears.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.closing) return;
      _controller.duration = transitionDurationOf(context, Motion.sheet);
      _controller.forward();
    });
  }

  @override
  void didUpdateWidget(ModalLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.closing && !oldWidget.closing) _close();
  }

  void _close() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The sheet already left by a drag: there is nothing to play, it only has to be taken off.
      if (_exited) {
        _controller.value = 0;
        return;
      }
      // Closing from where the appearance is now: a sheet closed half-way sinks from there.
      _controller.duration = transitionDurationOf(context, Motion.sheet);
      _controller.reverse();
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || !widget.closing) return;
    // Never from the build: the flow answers with `setState`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onClosed?.call();
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onSettle() {
    final eased = _settleCurve.transform(_settle.value);
    setState(() => _offset = _settleFrom + (_settleTo - _settleFrom) * eased);
  }

  /// Moves the sheet to [to] over [duration] (instantly under "reduce motion" or without transitions), then runs
  /// [then].
  void _moveSheet(double to, SheetMotion motion, VoidCallback? then) {
    final duration = transitionDurationOf(context, Duration(milliseconds: motion.durationMs));
    _settle.stop();
    _settled = null;
    if (duration == Duration.zero || _offset == to) {
      setState(() => _offset = to);
      then?.call();
      return;
    }
    _settleFrom = _offset;
    _settleTo = to;
    _settleCurve = Cubic(motion.curve[0], motion.curve[1], motion.curve[2], motion.curve[3]);
    _settled = then;
    _settle.duration = duration;
    _settle.forward(from: 0).whenComplete(() {
      if (!mounted || !_settle.isCompleted) return;
      final done = _settled;
      _settled = null;
      done?.call();
    });
  }

  double _measuredHeight() {
    final box = _layerSlot.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : _sheetHeight;
  }

  void _dragStarted() {
    _settle.stop();
    _settled = null;
    _sheetHeight = _measuredHeight();
  }

  void _dragged(double dy) => setState(() => _offset = dy);

  /// The finger was lifted (`sheetDragOutcome`): the sheet returns, or goes out and then the stack goes back.
  void _released(double dragged, double velocity) {
    final outcome = sheetDragOutcome(sheetHeight: _sheetHeight, dragged: dragged, velocity: velocity);
    if (outcome == SheetDragOutcome.returns) {
      _moveSheet(0, kSheetReturn, null);
      return;
    }
    setState(() => _exiting = true);
    _moveSheet(_sheetHeight + MediaQuery.viewInsetsOf(context).bottom, kSheetExit, () {
      if (!mounted) return;
      setState(() => _exited = true);
      widget.onDismiss();
    });
  }

  /// A sheet that was cancelled by the system returns without a word.
  void _dragCancelled() => _moveSheet(0, kSheetReturn, null);

  /// The sheet with the drag over it: the recognizer that follows the finger, a note of how far the body is scrolled,
  /// and a body that does not stretch past its top (the drag takes over there).
  Widget _dragZone(Widget slot) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: {
      SheetDragRecognizer: GestureRecognizerFactoryWithHandlers<SheetDragRecognizer>(
        SheetDragRecognizer.new,
        (recognizer) => recognizer
          ..scrolled = (() => _bodyScrolled)
          ..onStart = _dragStarted
          ..onUpdate = _dragged
          ..onEnd = _released
          ..onCancel = _dragCancelled,
      ),
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // The body of the sheet is the scroll view nearest to it; the rows and carousels inside are deeper.
        if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
          _bodyScrolled = (notification.metrics.pixels - notification.metrics.minScrollExtent).clamp(0.0, double.infinity);
        }
        return false;
      },
      child: slot,
    ),
  );

  /// The blur under the scrim (schema 9.20.0): exactly the area of the scrim, the blur first and the scrim over it.
  /// It grows with the layer's appearance, like the scrim, and is the named radius once the layer is in place.
  Widget _blurUnder(Widget scrim, double progress) {
    final radius = widget.backdropBlur;
    if (radius == null || progress <= 0) return scrim;
    final sigma = radius * progress;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: scrim,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = CurvedAnimation(parent: _controller, curve: Motion.enter, reverseCurve: Motion.exit);
    // The on-screen keyboard (`rules.focus.modal`): the layer rises above it instead of staying
    // under it. The keyboard height comes from the reader's own `MediaQuery` context; a host that
    // has already shrunk the screen gives zero.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // The top safe inset (schema 9.19.0, `safeTop.modal`): none INSIDE the layer; the sheet is no taller
    // than the area below the inset, the window is centred in it, and the scrim covers the whole area,
    // the status bar strip included.
    final safeTop = topInsetOf(context);
    // The bottom safe inset: a window in the middle stands above it as well (the area between the inset
    // strips). A sheet is anchored to the bottom edge and its own bottom zone adds the inset, so it is
    // left alone. The keyboard already covers the inset, hence the larger of the two.
    final shape0 = modalShapeOf(widget.placement.wire, MediaQuery.sizeOf(context).width);
    final safeBottom = shape0 == ModalShape.sheet ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    final lower = math.max(keyboard, safeBottom);

    return LayoutBuilder(
      builder: (context, area) {
        // The area the host gave the screen. If infinite, neither scrim nor placement would be
        // visible; then the layer takes what its content has.
        final viewportWidth = area.hasBoundedWidth ? area.maxWidth : 0.0;
        final viewportHeight = area.hasBoundedHeight ? area.maxHeight : double.infinity;
        // HOW THE LAYER IS SHOWN (`modalShapeOf`): decided by the width class of the AREA the host
        // gave the screen, not of the layer. A sheet without the word `center` is a window in the
        // middle on `medium` / `expanded`; an infinite width is "unknown", i.e. `compact`.
        final shape = modalShapeOf(widget.placement.wire, viewportWidth);
        final window = shape != ModalShape.sheet;
        final sheetWindow = shape == ModalShape.sheetWindow;
        // The content is measured at the LAYER's width, not the area's: the rule says the window width,
        // and the screen root has no sizes of its own (`x-style.screenExcluded`). The content's width
        // class comes from this box: 560 < 600, so it is `compact`.
        final layerWidth = area.hasBoundedWidth
            ? modalLayerWidthOf(widget.placement.wire, viewportWidth, widget.windowMargin)
            : null;
        final raisedHeight = viewportHeight.isFinite
            ? math.max(0.0, viewportHeight - lower - safeTop)
            : viewportHeight;
        final availableHeight = !viewportHeight.isFinite
            ? double.infinity
            : sheetWindow
            ? math.max(0.0, math.min(raisedHeight * kWideModalMaxHeightShare, raisedHeight - 2 * widget.windowMargin))
            : window
            ? math.max(0.0, raisedHeight - 2 * widget.windowMargin)
            : raisedHeight;

        // The scrim does not see a touch INSIDE the layer: the layer is a box, not just its opaque
        // places (a root with no background is a transparent layer).
        final layer = Listener(
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            key: kModalLayerKey,
            constraints: BoxConstraints(
              minWidth: window ? (layerWidth ?? 0) : 0,
              maxWidth: window ? (layerWidth ?? double.infinity) : double.infinity,
              maxHeight: availableHeight,
            ),
            // The layer above the keyboard has already accounted for it: the screen inside does not
            // subtract it a second time nor add a safe area inset where the keyboard covers it.
            child: keyboard > 0 || safeTop > 0 || safeBottom > 0
                ? MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      viewInsets: MediaQuery.viewInsetsOf(context).copyWith(bottom: 0),
                      viewPadding: MediaQuery.viewPaddingOf(context).copyWith(top: 0, bottom: safeBottom > 0 || keyboard > 0 ? 0 : null),
                      padding: MediaQuery.paddingOf(context).copyWith(top: 0, bottom: safeBottom > 0 || keyboard > 0 ? 0 : null),
                    ),
                    child: SheetWindowScope(sheetWindow: sheetWindow, child: widget.sheet),
                  )
                : SheetWindowScope(sheetWindow: sheetWindow, child: widget.sheet),
          ),
        );
        final slot = KeyedSubtree(key: _layerSlot, child: layer);
        // Only a sheet from the bottom, that a person may close, is dragged (a window in the middle is not).
        final draggable = shape == ModalShape.sheet && widget.dismissible && !widget.closing;
        // The scrim fades with the share of the sheet that is still visible.
        final visible = _offset <= 0 || _sheetHeight <= 0 ? 1.0 : (1 - _offset / _sheetHeight).clamp(0.0, 1.0);

        return AnimatedBuilder(
          animation: progress,
          builder: (context, _) => IgnorePointer(
            ignoring: widget.closing || _exiting,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // `dismissible: false`: the scrim still takes the touch, so it does not fall to the page, but does nothing.
                    onTap: widget.dismissible ? widget.onDismiss : null,
                    // The scrim thickens along with the layer's appearance: otherwise the screen under it would
                    // darken before it becomes clear why.
                    child: _blurUnder(
                      ColoredBox(color: Colors.black.withValues(alpha: kModalScrimOpacity * progress.value * visible)),
                      progress.value,
                    ),
                  ),
                ),
                if (window)
                  Padding(
                    padding: EdgeInsets.only(top: safeTop, bottom: lower),
                    child: Center(
                      child: Opacity(
                        opacity: progress.value,
                        child: Transform.scale(
                          scale: kModalWindowStartScale + (1 - kModalWindowStartScale) * progress.value,
                          child: slot,
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: EdgeInsets.only(top: safeTop, bottom: keyboard),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      /*
                     * The offset is in FRACTIONS OF THE LAYER'S OWN HEIGHT, not pixels: a sheet may be three
                     * rows or half the screen, and both must slide in the same way, from behind their own
                     * bottom edge. Pixels would give short sheets a long path from nowhere.
                     */
                      child: Transform.translate(
                        offset: Offset(0, _offset),
                        child: FractionalTranslation(
                          translation: Offset(0, 1 - progress.value),
                          child: draggable ? _dragZone(slot) : slot,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
