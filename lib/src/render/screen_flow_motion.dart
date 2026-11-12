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

  /// A cross-dissolve (a section switch, or a page of `transition: 'fade'`): the old scene lies over the new one,
  /// which stands still, and fades out.
  crossfade,
}

/// A scene that is drawn beside the current one while it moves.
///
/// [other] is a COPY of a stack (the one before the step, or the part below the current page),
/// used only to paint that scene; the flow's stack is never touched by motion. [controller] runs
/// from 0 to 1 when the page on top comes in and from 1 to 0 when it leaves; [plan] is the motion it plays.
final class _SceneMove {
  _SceneMove(this.kind, this.other, this.controller, this.plan, {this.fingered = false});

  _MoveKind kind;
  List<_Frame> other;
  final AnimationController controller;
  final ScreenTransitionPlan plan;

  /// A finger drives the motion (an edge swipe, and what follows its release): constant speed, so the page stays under it.
  final bool fingered;
}

extension _ScreenFlowMotion on _ScreenFlowState {
  /// Whether changes of screen move at all: the host did not turn transitions off, the system
  /// does not ask for no motion, and no fill of a swipe button covers the screen (it is already the motion).
  bool get _moves =>
      !_rippleCovers &&
      widget.transitions != HotlayoutTransitions.none &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// The index of the page a list of frames paints at the bottom: the last frame that is not a
  /// modal layer.
  int _baseOf(List<_Frame> frames) {
    var base = frames.length - 1;
    while (base > 0 && frames[base].screen.presentation == ScreenPresentationToken.modal) {
      base -= 1;
    }
    return base;
  }

  /// Drops every motion in flight: the next build draws the current stack at rest. A new step does this to the
  /// motion before it: the old one is finished at once, and the new one starts from the end state.
  void _settle() {
    final move = _move;
    _move = null;
    move?.controller.dispose();
    _leaving.clear();
    _enteringLayer = null;
    _enteringPlan = null;
    _swiping = false;
  }

  /// The width of the area the host gave the flow: the shape of a layer follows it.
  double get _areaWidth => context.size?.width ?? MediaQuery.sizeOf(context).width;

  /// A screen as the transition sees it: the effective presentation (the first screen of a stack is a page).
  TransitionScreen _transitionScreen(List<_Frame> frames, int index) {
    final screen = frames[index].screen;
    return TransitionScreen(
      modal: index > 0 && screen.presentation == ScreenPresentationToken.modal,
      placement: screen.modalPlacement?.wire,
      transition: screen.transition,
    );
  }

  /// The motion of a step the stack has just taken from [before]; [dragged]: the sheet that left was already taken
  /// down by the finger.
  ScreenTransitionPlan _planOf(StackStep step, List<_Frame> before, {bool dragged = false}) => screenTransitionPlan(
    step: step,
    from: _transitionScreen(before, before.length - 1),
    to: _transitionScreen(_stack, _stack.length - 1),
    areaWidth: _areaWidth,
    reducedMotion: widget.transitions == HotlayoutTransitions.none || (MediaQuery.maybeDisableAnimationsOf(context) ?? false),
    covered: _rippleCovers,
    dragged: dragged,
  );

  /// Chooses the motion of a step the stack has just taken from [before]. Called inside the
  /// `setState` of the step.
  void _moveOnStep(List<_Frame> before, ScreenShownCause cause) {
    final dragged = identical(_draggedLayer, before.last.memory);
    _draggedLayer = null;
    // A step back that is the end of an edge swipe goes on from where the finger left the page; every other
    // step finishes the motion before it at once.
    final move = _move;
    final swipe =
        cause == ScreenShownCause.back &&
        move != null &&
        move.kind == _MoveKind.peek &&
        move.other.length == _stack.length &&
        identical(move.other.last.memory, _stack.last.memory);
    if (swipe) {
      // The page the finger has already revealed is the one that stays.
      move
        ..kind = _MoveKind.pop
        ..other = before;
      if (!_swiping) _runBack(move);
      return;
    }
    _settle();
    final step = switch (cause) {
      ScreenShownCause.forward => StackStep.push,
      ScreenShownCause.back => StackStep.pop,
      ScreenShownCause.switchSection => StackStep.switchSection,
      ScreenShownCause.entry => StackStep.start,
    };
    if (step == StackStep.start) return;
    final plan = _planOf(step, before, dragged: dragged);
    final oldBase = before[_baseOf(before)].memory;
    final samePage = identical(oldBase, _stack[_baseOf(_stack)].memory);
    if (plan.motion.isLayer && samePage) {
      if (plan.motion.isLayerIn) {
        // A layer over the same page: it comes in by itself.
        _enteringLayer = _stack.last.memory;
        _enteringPlan = plan;
      } else {
        // A layer closed: it goes away over the page it lay on.
        _leaving.add((frame: before.last, index: before.length - 1, base: oldBase, plan: plan));
      }
      return;
    }
    if (!plan.moves) {
      // At once; a page revealed by a step back is still built anew, as after any step back.
      if (step == StackStep.pop && !samePage) _revealAnew(_stack);
      return;
    }
    if (step == StackStep.pop && !samePage) _revealAnew(_stack);
    final kind = switch (plan.motion) {
      TransitionMotion.crossfade => _MoveKind.crossfade,
      TransitionMotion.pop => _MoveKind.pop,
      _ => _MoveKind.push,
    };
    _startMove(kind, before, plan);
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

  void _startMove(_MoveKind kind, List<_Frame> other, ScreenTransitionPlan plan, {bool fingered = false}) {
    final previous = _move;
    _move = null;
    previous?.controller.dispose();
    // A layer still sinking away belongs to a scene that is leaving now as a whole.
    _leaving.clear();
    final controller = AnimationController(vsync: this, duration: plan.duration);
    final move = _SceneMove(kind, other, controller, plan, fingered: fingered);
    _move = move;
    controller.addStatusListener((status) => _onMoveStatus(move, status));
    switch (kind) {
      case _MoveKind.push || _MoveKind.crossfade:
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
      _MoveKind.push || _MoveKind.crossfade || _MoveKind.peek => status == AnimationStatus.completed,
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
      // The motion of a step back, at the speed of the finger.
      final plan = screenTransitionPlan(
        step: StackStep.pop,
        from: const TransitionScreen(),
        to: const TransitionScreen(),
        areaWidth: _areaWidth,
      ).linear;
      _startMove(_MoveKind.peek, below, plan, fingered: true);
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
