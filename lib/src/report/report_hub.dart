/// Where reports found deep in parsing and drawing go: to the log, to the document or theme being
/// parsed, or to the screens that are mounted.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'hotlayout_report.dart';

/// How many distinct reports one screen widget delivers over its life.
const int kMaxReportsPerWidget = 50;

/// The one way for code without a `BuildContext` to say that it ignored something.
///
/// A report is printed in debug builds, then goes to the innermost active collection
/// ([ReportHub.collect]: document and theme parsing keep what they found with the parsed object), or,
/// when nothing is collecting, to every mounted [ReportListener]. A listener delivers each distinct
/// report once.
abstract final class ReportHub {
  static final List<List<HotlayoutReport>> _collections = [];
  static final Set<_Receiver> _receivers = {};
  static final Set<HotlayoutReport> _printed = {};

  /// Reports one finding. The message is printed in debug builds.
  static void emit(HotlayoutReport report) {
    if (kDebugMode && (_printed.length < 200 && _printed.add(report))) debugPrint('[hotlayout] ${report.message}');
    if (_collections.isNotEmpty) {
      _collections.last.add(report);
      return;
    }
    for (final receiver in List.of(_receivers)) {
      receiver.add(report);
    }
  }

  /// Shorthand for an [IgnoredInputReport].
  static void ignored(String where, String reason) => emit(IgnoredInputReport(where: where, reason: reason));

  /// Runs [body] (synchronously) and returns its result with what it reported. Nothing reaches the
  /// listeners while [body] runs.
  static (T, List<HotlayoutReport>) collect<T>(T Function() body) {
    final list = <HotlayoutReport>[];
    _collections.add(list);
    try {
      return (body(), _merged(list));
    } finally {
      _collections.removeLast();
    }
  }

  /// Several `invalid-theme-values` become one, with the paths in order.
  static List<HotlayoutReport> _merged(List<HotlayoutReport> list) {
    final paths = <String>[];
    final rest = <HotlayoutReport>[];
    for (final report in list) {
      if (report is InvalidThemeValuesReport) {
        for (final path in report.paths) {
          if (!paths.contains(path)) paths.add(path);
        }
      } else {
        rest.add(report);
      }
    }
    return [if (paths.isNotEmpty) InvalidThemeValuesReport(paths: paths), ...rest];
  }
}

class _Receiver {
  _Receiver(this.callback);

  HotlayoutReportCallback? callback;
  final Set<HotlayoutReport> _seen = {};
  final List<HotlayoutReport> _pending = [];
  bool _scheduled = false;
  bool closed = false;

  void add(HotlayoutReport report) {
    if (closed || _seen.length >= kMaxReportsPerWidget || !_seen.add(report)) return;
    _pending.add(report);
    if (_scheduled) return;
    _scheduled = true;
    // Never in the middle of a build: the host's callback may set state.
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _scheduled = false;
    final batch = List.of(_pending);
    _pending.clear();
    final deliver = callback;
    if (closed || deliver == null) return;
    for (final report in batch) {
      deliver(report);
    }
  }
}

/// Hands the reports found while the child is drawn to [onReport], each once for the life of this
/// widget, together with the [initial] ones (found while the document or the theme was parsed).
class ReportListener extends StatefulWidget {
  /// Creates the listener.
  const ReportListener({
    required this.child,
    this.onReport,
    this.initial = const [],
    this.announced = const [],
    super.key,
  });

  /// The host's callback; `null` — reports are only printed in debug builds.
  final HotlayoutReportCallback? onReport;

  /// What was found before the widget existed.
  final List<HotlayoutReport> initial;

  /// What to print in the debug log when the widget appears (reports that were not printed when found).
  final List<HotlayoutReport> announced;

  /// The drawn screen.
  final Widget child;

  @override
  State<ReportListener> createState() => _ReportListenerState();
}

class _ReportListenerState extends State<ReportListener> {
  late final _Receiver _receiver = _Receiver(widget.onReport);

  @override
  void initState() {
    super.initState();
    ReportHub._receivers.add(_receiver);
    if (kDebugMode) {
      for (final report in widget.announced) {
        debugPrint('[hotlayout] ${report.message}');
      }
    }
    widget.initial.forEach(_receiver.add);
  }

  @override
  void didUpdateWidget(ReportListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _receiver.callback = widget.onReport;
    // A new document or theme brings its own findings; those already delivered are not repeated.
    if (!identical(oldWidget.initial, widget.initial)) widget.initial.forEach(_receiver.add);
  }

  @override
  void dispose() {
    _receiver.closed = true;
    ReportHub._receivers.remove(_receiver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
