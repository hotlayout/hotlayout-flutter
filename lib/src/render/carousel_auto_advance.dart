/// The clock of a carousel that advances by time (schema 9.42.0, `carousel.autoAdvance`): when it ticks, what
/// pauses it and what it does at a step. The counting is the pure rule of `model/carousel_auto_advance.dart`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../model/carousel_auto_advance.dart';

/// Whether the screen above [context] is the one in front of the person: the top of the stack, not covered by a layer
/// and not moving away. The flow tells it; outside of a flow a screen is shown.
class ScreenShownScope extends InheritedWidget {
  const ScreenShownScope({super.key, required this.shown, required super.child});

  final bool shown;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScreenShownScope>()?.shown ?? true;

  @override
  bool updateShouldNotify(ScreenShownScope oldWidget) => oldWidget.shown != shown;
}

/// How often the clock ticks. A tick counts exactly this much time: a timer that is late (a busy frame) loses time
/// rather than catching up, and a step is never made twice for one gap.
const Duration kAutoAdvanceTick = Duration(milliseconds: 100);

/// What the clock asks the carousel.
typedef AutoAdvanceView = ({int active, int stopCount})?;

/// The clock of one carousel. It runs while a timer is configured, counts in [kAutoAdvanceTick] steps and asks the
/// carousel for the stop it stands on; the carousel tells it what holds the count (the pauses of
/// `x-carouselAutoAdvance.pauses.list`) and carries out the steps.
///
/// The count starts at the show: the first tick after the stops are laid out only notes the stop. A pause freezes the
/// count, and it resumes with what was left.
class CarouselAutoAdvanceDriver with WidgetsBindingObserver {
  CarouselAutoAdvanceDriver({required this.view, required this.onStep, required this.keyboardFocus});

  /// The stop the carousel stands on and the number of stops; `null` while the stops are not laid out.
  final AutoAdvanceView Function() view;

  /// Whether the keyboard focus is inside the carousel and it is the keyboard's: a focus that came from a click or a touch
  /// does not stop the timer for good.
  final bool Function() keyboardFocus;

  /// The timer takes the carousel to [step]: the carousel moves as its own move and writes the stop.
  final void Function(int step) onStep;

  CarouselAutoAdvance? _config;
  Timer? _timer;
  AutoAdvanceState? _state;

  final Set<int> _held = {};
  bool _moving = false;
  bool _screenNotShown = false;
  bool _screenReader = false;
  bool _background = false;

  /// A finger or a pointer button is down on the carousel.
  void pointerDown(int pointer) => _held.add(pointer);

  /// The pointer was let go, anywhere.
  void pointerUp(int pointer) => _held.remove(pointer);

  /// The scroll is moving: a gesture, momentum or the animation of a step.
  set moving(bool value) => _moving = value;

  /// What the surroundings say: the screen is not in front, or a screen reader is on.
  void surroundings({required bool screenNotShown, required bool screenReader}) {
    _screenNotShown = screenNotShown;
    _screenReader = screenReader;
  }

  /// Whether anything holds the count.
  bool get paused => _held.isNotEmpty || keyboardFocus() || _moving || _screenNotShown || _screenReader || _background;

  /// Sets the timer the carousel is configured with; `null` stops the clock. A new timer counts from the next show of
  /// the stops.
  void configure(CarouselAutoAdvance? config) {
    if (config == _config) return;
    final was = _config;
    _config = config;
    _state = null;
    if (config == null) {
      _timer?.cancel();
      _timer = null;
      if (was != null) WidgetsBinding.instance.removeObserver(this);
      return;
    }
    if (was == null) {
      WidgetsBinding.instance.addObserver(this);
      _background = _isBackground(WidgetsBinding.instance.lifecycleState);
    }
    _timer ??= Timer.periodic(kAutoAdvanceTick, (_) => _tick());
  }

  static bool _isBackground(AppLifecycleState? state) => state != null && state != AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _background = _isBackground(state);

  void _tick() {
    final config = _config;
    final seen = view();
    if (config == null || seen == null) return;
    final state = _state;
    if (state == null) {
      // The show: the count starts here.
      _state = AutoAdvanceState(active: seen.active, elapsed: 0);
      return;
    }
    final tick = carouselAutoAdvanceTick(
      state,
      dtMs: kAutoAdvanceTick.inMilliseconds.toDouble(),
      active: seen.active,
      stopCount: seen.stopCount,
      paused: paused,
      intervalMs: config.intervalMs,
      loop: config.loop,
    );
    _state = tick.state;
    final step = tick.step;
    if (step != null) onStep(step);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_config != null) WidgetsBinding.instance.removeObserver(this);
    _config = null;
  }
}
