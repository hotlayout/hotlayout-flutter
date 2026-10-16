import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../data/screen_data.dart';
import '../model/value_transition.dart';

/// Leads the numbers of ONE node from their old values to the new ones when the DATA change them (schema
/// 9.21.0, `animateChanges`). The formula, the steps and the decision are the model's
/// (`model/value_transition.dart`); this widget holds what the model cannot: which value is shown now.
///
/// A number leads only when the data under an already shown node change (`dataOnly`). The first frame of the
/// node, a node that appears, a new record of a list, a screen shown again, a changed language, a document
/// with other bindings, a system request to reduce motion, a value that is not a number on either side and a
/// value that did not change give the new value at once. A change DURING a transition starts from the value
/// shown at that moment and takes the full duration. Each number (the value and the max of a scale) has its
/// own transition.
///
/// The widget does not draw anything itself: [builder] gets the data with the shown numbers laid over every
/// layer ([ScreenData.withShown]), so the text is written by the same format, template and plural word as the
/// final one. [active] says that a number is between values now, for the screen reader to hear the final value
/// only (`semantics`).
class ValueTransition extends StatefulWidget {
  const ValueTransition({
    super.key,
    required this.targets,
    required this.data,
    required this.identity,
    required this.localeKey,
    required this.builder,
  });

  final List<TransitionTarget> targets;

  /// The data the node reads, WITHOUT the shown numbers.
  final ScreenData data;

  /// Who the node is: the chain of list instances and the identity of the record. A change of it is another
  /// node (a new record), and a new node is a first show.
  final Object? identity;

  /// What the language of the screen is; a change of it moves the numbers without a transition.
  final Object? localeKey;

  final Widget Function(BuildContext context, ScreenData shown, bool active) builder;

  @override
  State<ValueTransition> createState() => _ValueTransitionState();
}

/// The state of one number.
class _Run {
  _Run(this.settled);

  /// The last value of the data under the path, as the data had it.
  Object? settled;

  /// The transition in progress: from [from] to [to], begun at [startedAt] (the time of a frame).
  num? from;
  num? to;
  Duration? startedAt;
  int? digits;

  bool get leading => to != null;
}

class _ValueTransitionState extends State<ValueTransition> with SingleTickerProviderStateMixin {
  final Map<String, _Run> _runs = {};
  late final Ticker _ticker;

  /// The time of the frame that is being built. The ticker only asks for frames; the time is the engine's.
  Duration get _now => SchedulerBinding.instance.currentFrameTimeStamp;

  String get _signature => widget.targets.map((target) => target.signature).join(',');

  @override
  void initState() {
    super.initState();
    // Made here, not on first use: a ticker cannot be made while the element is being unmounted.
    _ticker = createTicker((_) => _onTick());
    for (final target in widget.targets) {
      _runs[target.path] = _Run(widget.data.lookup(target.path));
    }
  }

  @override
  void didUpdateWidget(ValueTransition old) {
    super.didUpdateWidget(old);
    final other = old.targets.map((target) => target.signature).join(',') != _signature ||
        old.identity != widget.identity ||
        old.localeKey != widget.localeKey;
    if (other) {
      // Another document, another record, another language: the values stand at once.
      _settleAll();
      return;
    }
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    for (final target in widget.targets) {
      final run = _runs[target.path] ??= _Run(widget.data.lookup(target.path));
      final next = widget.data.lookup(target.path);
      if (identical(next, run.settled) || next == run.settled) continue;
      final reason = noTransitionBecause(
        TransitionChange(animates: true, shownBefore: true, from: run.settled, to: next, reducedMotion: reduced),
      );
      if (reason != null) {
        run.settled = next;
        run.from = run.to = run.startedAt = run.digits = null;
        continue;
      }
      // From the number shown in this moment (an interrupted transition) to the new one, for the full duration.
      final from = _shownOf(run) ?? run.settled! as num;
      run.from = from;
      run.to = next! as num;
      run.startedAt = _now;
      run.digits = target.scale ? null : transitionDigitsOf(from, run.to!, target.format, target.currency);
      run.settled = next;
    }
    _syncTicker();
  }

  void _settleAll() {
    for (final target in widget.targets) {
      _runs[target.path] = _Run(widget.data.lookup(target.path));
    }
    _runs.removeWhere((path, _) => !widget.targets.any((target) => target.path == path));
    _ticker.stop();
  }

  /// The value shown for [run] at the time of the frame, or `null` when it is not leading.
  num? _shownOf(_Run run) {
    if (!run.leading) return null;
    final t = (_now - run.startedAt!).inMicroseconds / 1000;
    return transitionValueAt(from: run.from!, to: run.to!, t: t, digits: run.digits);
  }

  bool _finished(_Run run) => !run.leading || (_now - run.startedAt!).inMilliseconds >= kValueTransitionMs;

  void _syncTicker() {
    final any = _runs.values.any((run) => run.leading);
    if (any && !_ticker.isActive) {
      _ticker.start();
    } else if (!any && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick() {
    setState(() {
      for (final run in _runs.values) {
        // A finished transition is cleared: from now on the data's own value is drawn, which is exactly `to`.
        if (run.leading && _finished(run)) run.from = run.to = run.startedAt = run.digits = null;
      }
      _syncTicker();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = <String, Object?>{};
    final steps = <String, Object?>{};
    var active = false;
    for (final target in widget.targets) {
      final run = _runs[target.path];
      if (run == null || !run.leading || _finished(run)) continue;
      active = true;
      final t = (_now - run.startedAt!).inMicroseconds / 1000;
      if (target.scale) {
        // The fill grows without a step; the label of the scale writes it in steps.
        shown[target.path] = transitionValueAt(from: run.from!, to: run.to!, t: t);
        steps[target.path] = transitionValueAt(
          from: run.from!,
          to: run.to!,
          t: t,
          digits: transitionDigitsOf(run.from!, run.to!, null, null),
        );
      } else {
        shown[target.path] = transitionValueAt(from: run.from!, to: run.to!, t: t, digits: run.digits);
      }
    }
    final data = active ? widget.data.withShown(shown, labelShown: steps.isEmpty ? null : steps) : widget.data;
    return widget.builder(context, data, active);
  }
}
