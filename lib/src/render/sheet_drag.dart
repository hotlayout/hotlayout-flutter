/// The drag that closes a sheet (schema 9.26.0, `x-sheetDismiss`): one finger, tracked from the first touch.
library;

import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:flutter/gestures.dart';

import '../model/long_press.dart' show kLongPressSlop;
import '../model/sheet_dismiss.dart';

/// Follows one finger over a sheet and tells whether it drags the sheet down instead of scrolling its body.
///
/// *Start.* The finger moves down past the touch slop and more down than sideways, and the body of the sheet is at its
/// top ([scrolled] is zero) — the reference rule [sheetDragStarts]. It is judged on every move until it starts.
///
/// *Arena.* The recognizer joins the gesture arena only to take the finger from what is under it: the moment the drag
/// starts it accepts, so a tap recognizer under the finger is rejected and the lifted finger presses nothing. If the
/// body's scroll view wins first (a fast flick), the recognizer goes on following the finger all the same: the body
/// of a sheet does not stretch past its top, so the two do not move at once. It never needs to win to drag.
///
/// *Velocity* is that of the last [kSheetVelocityWindowMs] of the movement, logical pixels per second, down positive.
class SheetDragRecognizer extends OneSequenceGestureRecognizer {
  SheetDragRecognizer({super.debugOwner});

  /// How far the body of the sheet is scrolled from its top now; zero when it is at the top or does not scroll.
  double Function() scrolled = () => 0;

  /// The finger started to drag the sheet.
  VoidCallback? onStart;

  /// The finger moved: how far down it is from the point of touch (never negative).
  ValueChanged<double>? onUpdate;

  /// The finger was lifted: how far down it was, and how fast it was going.
  void Function(double dragged, double velocity)? onEnd;

  /// The touch was cancelled by the system.
  VoidCallback? onCancel;

  int? _pointer;
  Offset? _start;
  bool _dragging = false;
  final List<({Duration time, double y})> _samples = [];

  @override
  String get debugDescription => 'sheet drag';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // One finger: a second one is somebody else's.
    if (_pointer != null) return;
    _pointer = event.pointer;
    _start = event.position;
    _dragging = false;
    _samples
      ..clear()
      ..add((time: event.timeStamp, y: event.position.dy));
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _move(event);
    } else if (event is PointerUpEvent) {
      _finish(event);
    } else if (event is PointerCancelEvent) {
      _forget(cancelled: true);
    }
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    if (start == null) return;
    final dy = event.position.dy - start.dy;
    final dx = event.position.dx - start.dx;
    if (!_dragging) {
      final starts = sheetDragStarts(
        sheet: true,
        dismissible: true,
        scrolled: scrolled(),
        dy: dy,
        dx: dx,
        onHandle: false,
      );
      if (!starts) {
        // The finger went past the slop the wrong way (up, sideways, or the body is scrolled): it scrolls or does
        // something else, and this recognizer steps out of the arena so that it does not stand in its way.
        if (dx * dx + dy * dy > kLongPressSlop * kLongPressSlop) _giveUp();
        return;
      }
      _dragging = true;
      // Take the finger from whatever is under it: its tap is not a press any more.
      resolve(GestureDisposition.accepted);
      onStart?.call();
    }
    _samples
      ..removeWhere((sample) => event.timeStamp - sample.time > const Duration(milliseconds: kSheetVelocityWindowMs))
      ..add((time: event.timeStamp, y: event.position.dy));
    onUpdate?.call(dy < 0 ? 0 : dy);
  }

  void _giveUp() {
    resolve(GestureDisposition.rejected);
    _forget(cancelled: false);
  }

  /// Logical pixels per second over the last window of the movement; down is positive.
  double _velocity() {
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final last = _samples.last;
    final span = (last.time - first.time).inMicroseconds / Duration.microsecondsPerSecond;
    return span <= 0 ? 0 : (last.y - first.y) / span;
  }

  void _finish(PointerUpEvent event) {
    final start = _start;
    final wasDragging = _dragging;
    final velocity = _velocity();
    _forget(cancelled: false);
    if (!wasDragging || start == null) return;
    final dragged = event.position.dy - start.dy;
    onEnd?.call(dragged < 0 ? 0 : dragged, velocity);
  }

  void _forget({required bool cancelled}) {
    final wasDragging = _dragging;
    final pointer = _pointer;
    _pointer = null;
    _start = null;
    _dragging = false;
    _samples.clear();
    if (pointer != null) stopTrackingPointer(pointer);
    if (cancelled && wasDragging) onCancel?.call();
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    // Lost the arena (the body's scroll view took the finger first): keep following it, the sheet can still move.
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _samples.clear();
    super.dispose();
  }
}
