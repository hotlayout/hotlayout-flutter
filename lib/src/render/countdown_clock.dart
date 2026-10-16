import 'dart:async';

import 'package:flutter/widgets.dart';

/// The clock the reader reads when the host did not pin the moment (`now: null`).
///
/// It is the device clock. It is a variable only so that a test of a countdown that ticks can put its own
/// clock in: a fake-async test does not move `DateTime.now`. A host that wants a fixed moment passes `now`.
DateTime Function() readerClock = DateTime.now;

/// Redraws a screen that shows a countdown (schema 9.21.0, `countdownPart`) while it is shown.
///
/// Every [every] it reads [readerClock] and builds again. A tick is a second when a node shows seconds, a
/// minute otherwise, so a shown number is never more than one tick behind the clock; the tick is NOT aligned to
/// the boundary of a minute. It runs only while the screen is shown: a screen the host hides (`TickerMode` off,
/// as a route under another route is) ticks no more, and reads the clock afresh when it is shown again.
class CountdownClock extends StatefulWidget {
  const CountdownClock({super.key, required this.every, required this.builder});

  final Duration every;
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<CountdownClock> createState() => _CountdownClockState();
}

class _CountdownClockState extends State<CountdownClock> {
  Timer? _timer;
  bool _shown = true;
  late DateTime _now = readerClock();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown == _shown && _timer != null) return;
    _shown = shown;
    _restart();
    // Shown again after a pause: the number must be the clock's, not the one it had when it was hidden.
    if (shown) _now = readerClock();
  }

  @override
  void didUpdateWidget(CountdownClock old) {
    super.didUpdateWidget(old);
    if (old.every != widget.every) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = _shown ? Timer.periodic(widget.every, (_) => setState(() => _now = readerClock())) : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
