/// The track of a "swipe to confirm" button (schema 9.22.0, `Button.confirm: 'swipe'`).
///
/// The button is a TRACK with a circular thumb at the inline start. A finger or a mouse drags the thumb along the
/// line; released at or past the threshold it runs the action (once, `track` first, as an ordinary press does), earlier
/// it returns and nothing happens. A press without a drag does nothing. For the keyboard and assistive technology it is
/// an ordinary button named by its label: Enter and Space (not their auto-repeat) and the "activate" semantics action
/// run it at once. A disabled button does not move. The numbers are `model/swipe_confirm.dart`.
///
/// AFTER THE ACTION (schema 9.24.0, `x-swipeConfirmBusy`) the action has run at once and the thumb glides to the end
/// (200 ms) and STAYS there, busy: a ring of three quarters instead of the glyph, turning once in 800 ms; presses,
/// gestures and keys do nothing and the name is still the label. An action of the reader or of the host keeps it busy;
/// `none` and an invalid action send the thumb back at once. The host's answer ends it: a `Future` that completes (or
/// fails) returns the thumb over 250 ms; with no `Future` the thumb returns after eight seconds, unless the screen
/// changed first and the button went with it. "Reduce motion": the thumb jumps, the ring stands still.
///
/// THE MOTION (schema 9.34.0, `x-swipeConfirmMotion`): a fill of the thumb's colour follows the thumb and the label
/// fades with the travel; "busy" is the button collapsed into a circle (600 ms) holding the indicator, and its end
/// expands the circle back before the thumb returns. With `confirmTransition: 'ripple'`, after a swipe on a `navigate`
/// or `navigate.back` action, the circle grows over the whole screen (the layer of the screen flow,
/// `swipe_ripple_layer.dart`) and only then does the action run, under the fill. The keyboard, assistive technology
/// and "reduce motion" skip the circle and the fill.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/swipe_confirm.dart';
import '../model/swipe_motion.dart';
import '../model/tokens.dart';
import '../model/value_transition.dart' show valueTransitionEase;
import 'screen_form.dart';
import 'swipe_confirm_paint.dart';
import 'swipe_ripple_layer.dart';

/// What running the action of the button told: who ran it, and the host's promise when it returned one.
typedef SwipeActivation = ({SwipeRunner runner, Future<void>? promise});

/// What the button is about to do, asked BEFORE it runs: who runs the action and its type.
typedef SwipeIntent = ({SwipeRunner runner, String actionType});

class SwipeConfirmTrack extends StatefulWidget {
  const SwipeConfirmTrack({
    super.key,
    required this.decorate,
    required this.label,
    required this.typography,
    required this.labelColor,
    required this.verticalPadding,
    required this.border,
    required this.inset,
    required this.thumbColor,
    required this.glyphColor,
    required this.glyph,
    required this.disabled,
    required this.onActivate,
    required this.focusColor,
    this.radius,
    this.intent,
    this.ripple = false,
  });

  /// Draws the surface of the track (role, own style) around the content; the content is laid out in the full box.
  final Widget Function(Widget content) decorate;

  final String label;
  final TextStyle typography;
  final Color labelColor;

  /// The vertical padding of the size (both sides together); the inline padding is not read.
  final double verticalPadding;

  /// The border on one side, zero without one.
  final double border;

  /// The room between the border and the thumb (the `xs` step).
  final double inset;

  final Color thumbColor;
  final Color glyphColor;
  final IconToken glyph;
  final bool disabled;
  final SwipeActivation Function() onActivate;
  final Color focusColor;
  final BorderRadiusGeometry? radius;

  /// Who runs the action and of what type, asked before it runs. Without it the fill never plays.
  final SwipeIntent Function()? intent;

  /// `confirmTransition: 'ripple'` (9.34.0): whether the document asks for the fill; it plays only on an action of the
  /// reader that changes the screen, after a swipe.
  final bool ripple;

  @override
  State<SwipeConfirmTrack> createState() => _SwipeConfirmTrackState();
}

/// [collapsing] and [expanding] are the circle forming and unforming; [rippling] is the fill over the screen.
enum _Phase { idle, gliding, collapsing, busy, expanding, returning, rippling }

class _SwipeConfirmTrackState extends State<SwipeConfirmTrack> with TickerProviderStateMixin {
  double _dx = 0;
  double _progress = 0;
  bool _dragging = false;
  bool _focused = false;
  _Phase _phase = _Phase.idle;
  bool _hasPromise = false;
  bool _endAfterGlide = false;
  bool _ripplePending = false;
  SwipeRippleHandle? _ripple;
  Timer? _limit;
  double _from = 0;
  double _to = 0;
  late final AnimationController _move;
  late final AnimationController _spin;
  late final AnimationController _collapse;

  @override
  void initState() {
    super.initState();
    // Made here, not on first use: a ticker cannot be made while the element is being unmounted.
    _move = AnimationController(vsync: this)..addListener(_onMove);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kSwipeSpinnerTurnMs),
    );
    _collapse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..addListener(() => setState(() {}))
      ..addStatusListener(_onCollapse);
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;
  bool get _busy => _phase != _Phase.idle && _phase != _Phase.returning;

  /// The circle stands where the thumb was (under "reduce motion" there is no circle: the thumb waits at the end).
  bool _circle = false;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    _limit?.cancel();
    // A fill that has not covered the screen yet goes with the button and the action never runs.
    _ripple?.cancel();
    _collapse.dispose();
    _move.dispose();
    _spin.dispose();
    super.dispose();
  }

  SwipeTrack _track(double width, double height) =>
      (height: height, width: width, border: widget.border, inset: widget.inset);

  double _height(BuildContext context) {
    final fontSize = widget.typography.fontSize ?? 14;
    final line = MediaQuery.textScalerOf(context).scale(fontSize) * (widget.typography.height ?? 1);
    return widget.verticalPadding + 2 * widget.border + line;
  }

  void _onMove() {
    final eased = valueTransitionEase(_move.value);
    setState(() => _progress = _from + (_to - _from) * eased);
    if (_move.isCompleted) _arrived();
  }

  /// Moves the thumb to [target] over [ms]; "reduce motion" jumps.
  void _glide(double target, int ms) {
    _from = _progress;
    _to = target;
    if (MediaQuery.disableAnimationsOf(context) || _from == _to) {
      _move.stop();
      setState(() => _progress = target);
      _arrived();
      return;
    }
    _move.duration = Duration(milliseconds: ms);
    _move.forward(from: 0);
  }

  void _arrived() {
    if (_phase == _Phase.gliding) {
      if (_reduced) {
        setState(() => _phase = _Phase.busy);
        _settledBusy();
        return;
      }
      // The thumb is at the end: the button collapses into a circle with the indicator.
      setState(() {
        _phase = _Phase.collapsing;
        _circle = true;
      });
      _spin.repeat();
      _collapse.forward(from: 0);
    } else if (_phase == _Phase.returning) {
      setState(() => _phase = _Phase.idle);
    }
  }

  void _onCollapse(AnimationStatus status) {
    if (status == AnimationStatus.completed && _phase == _Phase.collapsing) {
      if (_ripplePending) {
        _ripplePending = false;
        _launchRipple();
      } else {
        setState(() => _phase = _Phase.busy);
        _settledBusy();
      }
    } else if (status == AnimationStatus.dismissed && _phase == _Phase.expanding) {
      _stopSpin();
      setState(() {
        _phase = _Phase.returning;
        _circle = false;
      });
      _glide(0, kSwipeReturnMs);
    }
  }

  /// The button now waits as "busy": an answer that came earlier ends it at once.
  void _settledBusy() {
    if (!_endAfterGlide) return;
    _endAfterGlide = false;
    _giveBack();
  }

  void _stopSpin() => _spin
    ..stop()
    ..value = 0;

  /// "Busy" is over: the circle expands back (a thumb that never collapsed has nothing to expand), then the thumb
  /// returns to the start and the button acts again.
  void _giveBack() {
    _limit?.cancel();
    if (_circle && !_reduced) {
      setState(() => _phase = _Phase.expanding);
      _collapse.reverse();
      return;
    }
    _stopSpin();
    _collapse.value = 0;
    setState(() {
      _phase = _Phase.returning;
      _circle = false;
    });
    _glide(0, kSwipeReturnMs);
  }

  void _endBusy() {
    if (!mounted || _phase == _Phase.idle || _phase == _Phase.returning || _phase == _Phase.expanding) return;
    if (_phase == _Phase.gliding || _phase == _Phase.collapsing) {
      _endAfterGlide = true;
    } else {
      _giveBack();
    }
  }

  /// Runs the action; the thumb then goes to the end and waits, or returns, by who ran it. After a swipe that asks for
  /// the fill the action waits for it instead (`swipeSequenceOf`).
  void _run(SwipeWay way) {
    if (widget.disabled || (_phase != _Phase.idle && _phase != _Phase.returning)) return;
    if (_playsRipple(way)) {
      _beginRipple();
      return;
    }
    final activation = widget.onActivate();
    if (!mounted) return;
    if (swipeAfterReleaseOf(activation.runner) == SwipeAfterRelease.back) {
      setState(() => _phase = _Phase.returning);
      _glide(0, kSwipeReturnMs);
      return;
    }
    final promise = activation.promise;
    _hasPromise = promise != null;
    _limit?.cancel();
    setState(() => _phase = _Phase.gliding);
    _glide(1, kSwipeCompleteMs);
    if (promise != null) {
      promise.then<void>((_) => _endBusy(), onError: (Object _) => _endBusy());
    } else {
      _limit = Timer(const Duration(milliseconds: kSwipeBusyMaxMs), () {
        if (swipeBusyOutcomeOf(SwipeBusyEvent.timeout, promise: _hasPromise) == SwipeBusyOutcome.back) _endBusy();
      });
    }
  }

  bool _playsRipple(SwipeWay way) {
    final intent = widget.intent;
    if (!widget.ripple || intent == null || SwipeRippleScope.maybeOf(context) == null) return false;
    final about = intent();
    return swipeSequenceOf(
      runner: about.runner,
      actionType: about.actionType,
      ripple: true,
      way: way,
      reducedMotion: _reduced,
    ).contains(SwipeStep.ripple);
  }

  /// The thumb goes to the end, the button collapses into a circle, and the circle grows over the screen.
  void _beginRipple() {
    _limit?.cancel();
    _endAfterGlide = false;
    _ripplePending = true;
    setState(() => _phase = _Phase.gliding);
    _glide(1, kSwipeCompleteMs);
  }

  void _launchRipple() {
    final scope = SwipeRippleScope.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (scope == null || box == null || !box.hasSize) {
      _covered();
      return;
    }
    final ring = swipeCollapseAt(_track(box.size.width, box.size.height), 0).ring;
    final glyph = widget.typography.fontSize ?? 14;
    setState(() => _phase = _Phase.rippling);
    _ripple = scope.start(
      SwipeRippleSpec(
        center: box.localToGlobal(box.size.center(Offset.zero)),
        halo: box.size.height,
        core: math.max(0.0, box.size.height - 2 * ring),
        color: widget.thumbColor,
        indicatorColor: widget.glyphColor,
        indicatorSize: glyph,
        indicator: (turns) => SwipeSpinner(turns: turns, size: glyph, color: widget.glyphColor),
        onCovered: _covered,
      ),
    );
  }

  /// The screen is covered: the action runs now, with its `track`, once. The button usually leaves with the screen;
  /// one that stays (a screen that did not change) is at rest again under the fading fill.
  void _covered() {
    if (!mounted) return;
    widget.onActivate();
    if (!mounted) return;
    _stopSpin();
    _collapse.value = 0;
    _move.stop();
    setState(() {
      _progress = 0;
      _circle = false;
      _phase = _Phase.idle;
    });
  }

  void _start(DragStartDetails details) {
    if (widget.disabled || _busy) return;
    _move.stop();
    setState(() {
      _dx = 0;
      _dragging = true;
      _phase = _Phase.idle;
    });
  }

  void _update(DragUpdateDetails details) {
    if (widget.disabled || !_dragging) return;
    final box = context.findRenderObject()! as RenderBox;
    final travel = swipeGeometryOf(_track(box.size.width, box.size.height)).travel;
    _dx += details.delta.dx;
    setState(() => _progress = swipeProgressOf(_dx, travel, rtl: _rtl));
  }

  void _endDrag(DragEndDetails details) {
    if (!_dragging) return;
    final release = swipeReleaseOf(_progress, disabled: widget.disabled);
    setState(() => _dragging = false);
    if (release == SwipeRelease.act) {
      _run(SwipeWay.swipe);
    } else {
      _glide(0, kSwipeReturnMs);
    }
  }

  void _cancel() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    _glide(0, kSwipeReturnMs);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final activation =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select;
    if (!activation) return KeyEventResult.ignored;
    // A held key is not a series of presses.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyDownEvent) {
      _run(SwipeWay.keyboard);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final height = _height(context);
    final room = swipeGeometryOf(_track(0, height)).thumbRoom;
    final fontSize = widget.typography.fontSize ?? 14;

    // The label is centred in the strip between the two places of the thumb, so the circle never covers it; the
    // padding of the strip is also what gives the track its natural width (label plus the room on both sides).
    // The label fades with the travel (it is gone at the end, so the circle never lies over it).
    final label = Opacity(
      opacity: swipeLabelOpacityOf(_progress),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          room,
          widget.verticalPadding / 2 + widget.border,
          room,
          widget.verticalPadding / 2 + widget.border,
        ),
        child: Center(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontFamily: widget.typography.fontFamily,
              fontSize: widget.typography.fontSize,
              height: widget.typography.height,
              forceStrutHeight: true,
            ),
            style: widget.typography.copyWith(color: widget.labelColor),
          ),
        ),
      ),
    );

    final radius = widget.radius?.resolve(Directionality.of(context)).topLeft.x;
    final thumb = Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) => _circle
            ? const SizedBox.shrink()
            : SwipeThumbLayer(
                track: _track(box.maxWidth, box.maxHeight),
                progress: _progress,
                radius: radius,
                color: widget.thumbColor,
                glyphColor: widget.glyphColor,
                glyph: widget.glyph,
                glyphSize: fontSize,
                busy: _busy,
                spin: _spin,
              ),
      ),
    );

    // The surface (background, border, shadow) fades while the button collapses; the circle lies over it.
    final surfaceOpacity = _circle
        ? swipeCollapseAt(_track(0, height), _collapse.value * kSwipeCollapseMs).surfaceOpacity
        : 1.0;
    final circle = Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) => _circle
            ? SwipeCircleLayer(
                track: _track(box.maxWidth, box.maxHeight),
                elapsed: _collapse.value * kSwipeCollapseMs,
                color: widget.thumbColor,
                glyphColor: widget.glyphColor,
                glyphSize: fontSize,
                spin: _spin,
              )
            : const SizedBox.shrink(),
      ),
    );

    Widget track = Stack(
      children: [
        Opacity(
          opacity: surfaceOpacity,
          child: widget.decorate(Stack(children: [label, thumb])),
        ),
        circle,
      ],
    );
    if (_focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      track = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: widget.focusColor, width: 2),
          borderRadius: widget.radius,
        ),
        child: track,
      );
    }

    final gesture = widget.disabled
        ? DisabledPress(child: track)
        : _busy
        ? AbsorbPointer(child: track)
        : GestureDetector(
            // The drag counts from the moment the finger came down, not from where the recognizer won.
            dragStartBehavior: DragStartBehavior.down,
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _update,
            onHorizontalDragEnd: _endDrag,
            onHorizontalDragCancel: _cancel,
            child: track,
          );

    return Semantics(
      container: true,
      button: true,
      enabled: !widget.disabled && !_busy,
      label: widget.label.isEmpty ? null : widget.label,
      onTap: widget.disabled || _busy ? null : () => _run(SwipeWay.keyboard),
      excludeSemantics: true,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: IntrinsicWidth(child: gesture),
      ),
    );
  }
}
