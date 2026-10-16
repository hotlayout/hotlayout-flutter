/// The motion between screens of the flow: which scene moves beside the current one, and the
/// edge swipe back.
part of 'screen_flow.dart';

/// What moves beside the current scene.
enum _MoveKind {
  /// A page opened forward: the previous scene is beneath, the current one comes in over it.
  push,

  /// A page closed: the closed scene is on top and leaves, the current one is revealed beneath.
  pop,

  /// An edge swipe in progress: the scene below is revealed beneath the current one, which
  /// follows the finger. Nothing has changed in the stack yet.
  peek,

  /// A section switch: the new scene fades in over the old one.
  fade,
}

/// A scene that is drawn beside the current one while it moves.
///
/// [other] is a COPY of a stack (the one before the step, or the part below the current page),
/// used only to paint that scene; the flow's stack is never touched by motion. [controller] runs
/// from 0 to 1 when the page on top comes in and from 1 to 0 when it leaves.
final class _SceneMove {
  _SceneMove(this.kind, this.other, this.controller);

  _MoveKind kind;
  List<_Frame> other;
  final AnimationController controller;
}

extension _ScreenFlowMotion on _ScreenFlowState {
  /// Whether changes of screen move at all: the host did not turn transitions off and the system
  /// does not ask for no motion.
  bool get _moves =>
      widget.transitions != HotlayoutTransitions.none && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The index of the page a list of frames paints at the bottom: the last frame that is not a
  /// modal layer.
  int _baseOf(List<_Frame> frames) {
    var base = frames.length - 1;
    while (base > 0 && frames[base].screen.presentation == ScreenPresentationToken.modal) {
      base -= 1;
    }
    return base;
  }

  /// Drops every motion in flight: the next build draws the current stack at rest.
  void _settle() {
    final move = _move;
    _move = null;
    move?.controller.dispose();
    _leaving.clear();
    _enteringLayer = null;
    _swiping = false;
  }

  /// Chooses the motion of a step the stack has just taken from [before]. Called inside the
  /// `setState` of the step.
  void _moveOnStep(List<_Frame> before, ScreenShownCause cause) {
    _enteringLayer = null;
    if (!_moves) {
      _settle();
      return;
    }
    final oldBase = before[_baseOf(before)].memory;
    final samePage = identical(oldBase, _stack[_baseOf(_stack)].memory);
    switch (cause) {
      case ScreenShownCause.forward:
        // A modal layer over the same page: the layer slides in by itself.
        if (samePage) {
          _enteringLayer = _stack.last.memory;
          return;
        }
        _startMove(_MoveKind.push, before);
      case ScreenShownCause.back:
        // A modal layer closed: it sinks away over the page it lay on.
        if (samePage) {
          _leaving.add((frame: before.last, index: before.length - 1, base: oldBase));
          return;
        }
        final move = _move;
        if (move != null &&
            move.kind != _MoveKind.fade &&
            move.kind != _MoveKind.pop &&
            move.other.length == _stack.length &&
            identical(move.other.last.memory, _stack.last.memory)) {
          // The step back undoes the move in flight (a page that is still coming in, or the edge
          // swipe): the same motion plays back from where it is, instead of a jump to the end and
          // a second motion from there.
          // A page that was only covered is revealed anew, as after any step back; the page the
          // finger has already revealed is the one that stays.
          if (move.kind == _MoveKind.push) _revealAnew(_stack);
          move
            ..kind = _MoveKind.pop
            ..other = before;
          if (!_swiping) _runBack(move);
          return;
        }
        _revealAnew(_stack);
        _startMove(_MoveKind.pop, before);
      case ScreenShownCause.switchSection:
        _startMove(_MoveKind.fade, before);
      case ScreenShownCause.entry:
        _settle();
    }
  }

  /// The key of the scene whose page is the bottom of [frames]: global, because the scene moves
  /// between places in the tree as a step starts and ends (beneath, on top, alone) and must keep
  /// its state through every move.
  Key _sceneKey(List<_Frame> frames) {
    final page = frames[_baseOf(frames)].memory;
    return GlobalObjectKey(_sceneIdentity[page] ??= Object());
  }

  /// A page revealed by a step back is built anew, exactly as without motion: going back never
  /// brings back the scroll or the fields of a page that was left, even when the step comes
  /// while the page is still moving away.
  void _revealAnew(List<_Frame> frames) => _sceneIdentity[frames[_baseOf(frames)].memory] = Object();

  void _startMove(_MoveKind kind, List<_Frame> other) {
    final previous = _move;
    _move = null;
    previous?.controller.dispose();
    // A layer still sinking away belongs to a scene that is leaving now as a whole.
    _leaving.clear();
    final controller = AnimationController(
      vsync: this,
      duration: kind == _MoveKind.fade ? Motion.sheet : Motion.page,
    );
    final move = _SceneMove(kind, other, controller);
    _move = move;
    controller.addStatusListener((status) => _onMoveStatus(move, status));
    switch (kind) {
      case _MoveKind.push || _MoveKind.fade:
        controller.forward();
      case _MoveKind.pop:
        controller.value = 1;
        controller.reverse();
      case _MoveKind.peek:
        controller.value = 1;
    }
  }

  void _runBack(_SceneMove move) {
    move.controller.reverse();
    _finishIfIdle(move);
  }

  void _onMoveStatus(_SceneMove move, AnimationStatus status) {
    if (!identical(_move, move) || _swiping) return;
    final done = switch (move.kind) {
      _MoveKind.push || _MoveKind.fade || _MoveKind.peek => status == AnimationStatus.completed,
      _MoveKind.pop => status == AnimationStatus.dismissed,
    };
    if (done) _endMove(move);
  }

  /// A command that had nothing left to animate does not report a new status: end it here.
  void _finishIfIdle(_SceneMove move) {
    if (!move.controller.isAnimating && identical(_move, move)) _endMove(move);
  }

  void _endMove(_SceneMove move) {
    if (!mounted) return;
    _update(() {
      if (identical(_move, move)) _move = null;
    });
    // Not from inside the controller's own status notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => move.controller.dispose());
  }

  /// The modal layer finished sinking away: stop drawing it.
  void _layerClosed(CarouselMemory memory) {
    if (!mounted) return;
    _update(() => _leaving.removeWhere((leaving) => identical(leaving.frame.memory, memory)));
  }

  // THE EDGE SWIPE BACK (iOS and macOS). The stack belongs to the flow, not to a `Navigator`, so
  // the host's route cannot offer its own swipe on a deeper screen (`PopScope` forbids it there).
  // The flow offers the same gesture itself: the page below is revealed while the finger moves,
  // and the stack takes the step back only when the finger lets go far or fast enough, through the
  // same `_goBack` as every other "back"; a swipe given up changes nothing and reports nothing.

  /// Whether a swipe from the leading edge would go back right now.
  bool get _canSwipeBack =>
      _moves &&
      widget.handleSystemBack &&
      cupertinoPagesOf(context) &&
      _canGoBack &&
      _baseOf(_stack) == _stack.length - 1 &&
      (_move == null || _swiping);

  /// The width of the strip along the leading edge a swipe back starts in, as on iOS.
  static const double _edgeWidth = 20;

  Widget _withEdgeSwipe(Widget flow) => Stack(
    fit: StackFit.passthrough,
    children: [
      flow,
      if (_canSwipeBack)
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: GestureDetector(
            key: kEdgeSwipeKey,
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _swipeStart(),
            onHorizontalDragUpdate: _swipeUpdate,
            onHorizontalDragEnd: (details) => _swipeEnd(details.velocity.pixelsPerSecond.dx),
            onHorizontalDragCancel: () => _swipeEnd(0, giveUp: true),
          ),
        ),
    ],
  );

  /// Distance along the line toward its end, as a share of the flow's width.
  double _alongLine(double dx) {
    final width = context.size?.width ?? 0;
    if (width <= 0) return 0;
    final share = dx / width;
    // The flow's own direction (the document's language), not the host's above it.
    return directionOfLocale(_resolution.directionLocale) == TextDirection.rtl ? -share : share;
  }

  void _swipeStart() {
    if (!_canSwipeBack || _swiping) return;
    _update(() {
      _swiping = true;
      _leaving.clear();
      final below = _stack.sublist(0, _baseOf(_stack));
      _revealAnew(below);
      _startMove(_MoveKind.peek, below);
    });
  }

  void _swipeUpdate(DragUpdateDetails details) {
    final move = _move;
    if (!_swiping || move == null) return;
    move.controller.value = (move.controller.value - _alongLine(details.primaryDelta ?? 0)).clamp(0.0, 1.0);
  }

  void _swipeEnd(double velocity, {bool giveUp = false}) {
    final move = _move;
    if (!_swiping || move == null) return;
    _update(() => _swiping = false);
    // As on iOS: a fling decides by its direction, a slow release by how far the page went.
    final speed = _alongLine(velocity);
    final back = !giveUp && (speed.abs() >= 1 ? speed > 0 : move.controller.value < 0.5);
    if (back && !(widget.onSystemBack?.call() ?? false) && _goBack()) return;
    move.controller.forward();
    _finishIfIdle(move);
  }
}

/// Key of the strip along the leading edge where the swipe back starts, for tests.
@visibleForTesting
const Key kEdgeSwipeKey = ValueKey<String>('hotlayout-edge-swipe');
