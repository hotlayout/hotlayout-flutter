import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/widgets.dart';

import '../model/press_feedback.dart';

/// Makes the node that performs a press sink a little under the finger (schema 9.25.0, `x-pressFeedback`).
///
/// The widget listens to raw pointer events, so it takes no part in the gesture arena: the press is decided as
/// before, by the control inside. Only the INNERMOST control under the finger answers: the events reach the widgets of
/// the hit path from the deepest one outward, so the first one claims the pointer and the cards around it stay still.
/// A control that gives no feedback (a disabled button, a node with `pressFeedback: 'none'`, a button that confirms by
/// a drag, a text field) claims the pointer too, with `kind: null`: a press that lands on it belongs to it.
///
/// Going down takes 80 ms and coming back 160 ms with a small overshoot; a press shorter than the way down still
/// reaches the pressed pose and then returns. The finger leaving the node, moving farther than the touch slop, a
/// lifted finger and a cancelled press all return the node. "Reduce motion" keeps only the fade to 0.7.
/// It changes the paint, never the layout.
class PressFeedback extends StatefulWidget {
  const PressFeedback({super.key, required this.kind, required this.child});

  /// How the node answers, or `null` when it gives no feedback and only claims the press.
  final PressFeedbackKind? kind;

  final Widget child;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

/// The pointers claimed by the innermost control, from the moment it went down until it was lifted or cancelled.
final Set<int> _claimed = <int>{};

const Cubic _downCurve = Cubic(0.2, 0, 0, 1);
const Cubic _upCurve = Cubic(0.34, 1.56, 0.64, 1);

class _PressFeedbackState extends State<PressFeedback> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)..addStatusListener(_onStatus);

  /// The way of the current phase: from [_from] to [_to], 0 at rest and 1 pressed (it may pass 0 on the way back).
  double _from = 0;
  double _to = 0;

  int? _pointer;
  Offset? _downAt;

  /// The finger was lifted before the way down was over; the node returns when it gets there.
  bool _releaseQueued = false;

  double get _amount => _from + (_to - _from) * (_to > _from ? _downCurve : _upCurve).transform(_controller.value);

  void _go(double to) {
    _from = _amount;
    _to = to;
    _controller
      ..duration = Duration(milliseconds: to > _from ? kPressDownMs : kPressUpMs)
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _releaseQueued && _to == 1) {
      _releaseQueued = false;
      _go(0);
    }
  }

  void _down(PointerDownEvent event) {
    // Someone deeper took this pointer: this node is not the one that performs the press.
    if (_claimed.contains(event.pointer) || _pointer != null) return;
    _claimed.add(event.pointer);
    if (widget.kind == null) {
      _pointer = event.pointer;
      return;
    }
    _pointer = event.pointer;
    _downAt = event.position;
    _releaseQueued = false;
    _go(1);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || widget.kind == null) return;
    final box = context.findRenderObject();
    final size = box is RenderBox && box.hasSize ? box.size : null;
    final outside = size != null && !(Offset.zero & size).inflate(kTouchSlop).contains(event.localPosition);
    final moved = _downAt != null && (event.position - _downAt!).distance > kTouchSlop;
    if (outside || moved) _release(event.pointer);
  }

  void _release(int pointer) {
    if (pointer != _pointer) return;
    _claimed.remove(pointer);
    _pointer = null;
    _downAt = null;
    if (widget.kind == null || _to != 1) return;
    if (_controller.isAnimating && _controller.status == AnimationStatus.forward) {
      _releaseQueued = true;
    } else {
      _go(0);
    }
  }

  @override
  void dispose() {
    final pointer = _pointer;
    if (pointer != null) _claimed.remove(pointer);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final pose = kind == null ? null : pressPoseOf(kind, reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    // The same widgets with and without a kind: a control that becomes enabled keeps the state of what is inside.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final amount = pose == null ? 0.0 : _amount;
          final scale = pose == null ? 1.0 : 1 + (pose.scale - 1) * amount;
          final opacity = pose == null ? 1.0 : (1 + (pose.opacity - 1) * amount).clamp(0.0, 1.0);
          // `FadeTransition`, not `Opacity`: the node's own `Opacity` (its `style.opacity`) stays the only one of its kind.
          return FadeTransition(
            opacity: AlwaysStoppedAnimation<double>(opacity),
            child: Transform.scale(scale: scale, child: child),
          );
        },
      ),
    );
  }
}
