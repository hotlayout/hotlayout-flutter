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
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/swipe_confirm.dart';
import '../model/tokens.dart';
import 'icon_glyph.dart';
import '../model/value_transition.dart' show valueTransitionEase;
import 'screen_form.dart';

/// What running the action of the button told: who ran it, and the host's promise when it returned one.
typedef SwipeActivation = ({SwipeRunner runner, Future<void>? promise});

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

  @override
  State<SwipeConfirmTrack> createState() => _SwipeConfirmTrackState();
}

enum _Phase { idle, gliding, busy, returning }

class _SwipeConfirmTrackState extends State<SwipeConfirmTrack> with TickerProviderStateMixin {
  double _dx = 0;
  double _progress = 0;
  bool _dragging = false;
  bool _focused = false;
  _Phase _phase = _Phase.idle;
  bool _hasPromise = false;
  bool _endAfterGlide = false;
  Timer? _limit;
  double _from = 0;
  double _to = 0;
  late final AnimationController _move;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    // Made here, not on first use: a ticker cannot be made while the element is being unmounted.
    _move = AnimationController(vsync: this)..addListener(_onMove);
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: kSwipeSpinnerTurnMs));
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;
  bool get _busy => _phase == _Phase.busy || _phase == _Phase.gliding;

  @override
  void dispose() {
    _limit?.cancel();
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
      setState(() => _phase = _Phase.busy);
      if (!MediaQuery.disableAnimationsOf(context)) _spin.repeat();
      if (_endAfterGlide) {
        _endAfterGlide = false;
        _giveBack();
      }
    } else if (_phase == _Phase.returning) {
      setState(() => _phase = _Phase.idle);
    }
  }

  /// "Busy" is over: the thumb returns to the start and the button acts again.
  void _giveBack() {
    _limit?.cancel();
    _spin
      ..stop()
      ..value = 0;
    setState(() => _phase = _Phase.returning);
    _glide(0, kSwipeReturnMs);
  }

  void _endBusy() {
    if (!mounted || _phase == _Phase.idle || _phase == _Phase.returning) return;
    if (_phase == _Phase.gliding) {
      _endAfterGlide = true;
    } else {
      _giveBack();
    }
  }

  /// Runs the action; the thumb then goes to the end and waits, or returns, by who ran it.
  void _run() {
    if (widget.disabled || (_phase != _Phase.idle && _phase != _Phase.returning)) return;
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
      _run();
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
      _run();
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
    final label = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(room, widget.verticalPadding / 2 + widget.border, room, widget.verticalPadding / 2 + widget.border),
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
    );

    final thumb = Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final track = _track(box.maxWidth, box.maxHeight);
          final geometry = swipeGeometryOf(track);
          return Stack(
            children: [
              PositionedDirectional(
                start: swipeThumbStartOf(track, _progress),
                top: widget.border + widget.inset,
                width: geometry.diameter,
                height: geometry.diameter,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: widget.thumbColor, shape: BoxShape.circle),
                    child: Center(
                      child: _busy
                          ? _Spinner(turns: _spin, size: fontSize, color: widget.glyphColor)
                          : IconGlyph(widget.glyph, size: fontSize, color: widget.glyphColor),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    Widget track = widget.decorate(Stack(children: [label, thumb]));
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
      onTap: widget.disabled || _busy ? null : _run,
      excludeSemantics: true,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: IntrinsicWidth(child: gesture),
      ),
    );
  }
}

/// The indicator of the busy state (`busy.indicator`): a ring of three quarters, the size of the glyph, in its colour,
/// with a stroke of an eighth of the size, turning once in 800 ms.
class _Spinner extends StatelessWidget {
  const _Spinner({required this.turns, required this.size, required this.color});

  final Animation<double> turns;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: turns,
    child: CustomPaint(size: Size.square(size), painter: _RingPainter(color, size / 8)),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.color, this.stroke);

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      (Offset.zero & size).deflate(stroke / 2),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.stroke != stroke;
}
