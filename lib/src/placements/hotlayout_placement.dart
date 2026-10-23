// The widget of one placement: a named place of the app that shows the document the builder put
// there. It draws nothing when the place is empty, unknown or unreadable, and says so to the host.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/document_source.dart';
import '../render/labels.dart';
import '../render/render_document.dart';
import '../report/hotlayout_report.dart';
import '../theme/render_theme.dart';
import 'placement_map.dart';
import 'placement_reader.dart';
import 'placement_source.dart';

/// Tells the host why a placement draws nothing, or not what was asked: once per cause, not on
/// every poll.
typedef PlacementReportCallback = void Function(String name, PlacementReport report);

/// Tells the host about every change of what a placement shows: its status, report, the state of the
/// map, the document and the entry point. The first settled state is told too, and so is the
/// return to a drawn document (`event.report` is `null`), so a host that folded the frame on
/// `documentMissing` learns when to unfold it.
typedef PlacementEventCallback = void Function(String name, PlacementEvent event);

/// A named place of the app that shows the document the builder put there.
///
/// ```dart
/// HotlayoutPlacement(
///   name: 'home.banner',
///   projectBase: Uri.parse(base),
///   theme: theme,
///   data: data,
///   onPlacement: (name, report) => log('$name: ${report.name}'),
/// )
/// ```
///
/// The widget reads the map of the project, finds the document of [name] and draws it with
/// [renderDocument]. An empty, unknown or unreadable place, and a document that is gone or cannot
/// be read, draw nothing at all (a zero-size box); [onPlacement] is told why. An entry point the
/// document no longer has is not an error on screen: the document is drawn from its first screen and
/// the host hears `entryMissing`.
///
/// [onPlacementEvent] hears every change, including the return of a document; [onPlacement] hears
/// only the reasons, once each.
///
/// The map is polled every [refreshInterval] and when the app returns to the foreground. A poll
/// that finds the network silent keeps what is on screen.
///
/// To control the source (your own transport, a store for the last known map, a bundled map) build a
/// [PlacementSource] and use [HotlayoutPlacement.fromSource].
class HotlayoutPlacement extends StatefulWidget {
  /// A placement read from the project at [projectBase] (see [placementFileUrl] for its form).
  const HotlayoutPlacement({
    super.key,
    required String name,
    required Uri projectBase,
    String? bundledMap,
    required this.theme,
    required this.data,
    this.refreshInterval = const Duration(minutes: 5),
    this.onPlacement,
    this.onPlacementEvent,
    this.locale,
    this.onAction,
    this.onRecordAction,
    this.onTrack,
    this.onHaptic,
    this.onScreenShown,
    this.onWrite,
    this.writablePaths,
    this.resolveImageUrl,
    this.labels = const RendererLabels(),
    this.onReport,
  }) : source = null,
       _name = name,
       _projectBase = projectBase,
       _bundledMap = bundledMap;

  /// A placement read through [source].
  const HotlayoutPlacement.fromSource({
    super.key,
    required PlacementSource this.source,
    required this.theme,
    required this.data,
    this.refreshInterval = const Duration(minutes: 5),
    this.onPlacement,
    this.onPlacementEvent,
    this.locale,
    this.onAction,
    this.onRecordAction,
    this.onTrack,
    this.onHaptic,
    this.onScreenShown,
    this.onWrite,
    this.writablePaths,
    this.resolveImageUrl,
    this.labels = const RendererLabels(),
    this.onReport,
  }) : _name = null,
       _projectBase = null,
       _bundledMap = null;

  /// The source given to [HotlayoutPlacement.fromSource]; `null` for the default constructor, which
  /// keeps its own source in its state and builds a new one only when [name], the project or the
  /// bundled map change.
  final PlacementSource? source;

  final String? _name;
  final Uri? _projectBase;
  final String? _bundledMap;

  final RenderTheme theme;
  final Map<String, Object?> data;

  /// How often the map is read again; `null` reads it once (and when the app returns to the foreground).
  final Duration? refreshInterval;

  /// Why the placement draws nothing, or not what was asked.
  final PlacementReportCallback? onPlacement;

  /// Every change of what the placement shows, see [PlacementEventCallback].
  final PlacementEventCallback? onPlacementEvent;

  /// The following are those of [renderDocument].
  final String? locale;
  final SduiActionCallback? onAction;
  final SduiRecordActionCallback? onRecordAction;
  final SduiTrackCallback? onTrack;
  final SduiHapticCallback? onHaptic;
  final SduiScreenShownCallback? onScreenShown;
  final SduiValueWrite? onWrite;
  final Object? writablePaths;
  final String? Function(String url)? resolveImageUrl;
  final RendererLabels labels;
  final HotlayoutReportCallback? onReport;

  @override
  State<HotlayoutPlacement> createState() => _HotlayoutPlacementState();
}

class _HotlayoutPlacementState extends State<HotlayoutPlacement> with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false;
  bool _again = false;
  int _generation = 0;

  late PlacementReader _reader;
  DocumentLoad? _document;
  PlacementEvent? _event;
  PlacementReport? _toldReport;

  static PlacementReader _readerFor(HotlayoutPlacement widget) => PlacementReader(
    widget.source ??
        PlacementSource(
          projectBase: widget._projectBase!,
          name: widget._name!,
          bundledMap: widget._bundledMap,
        ),
  );

  /// Whether the widget asks for another place than the reader reads.
  bool _sourceChanged(HotlayoutPlacement old) {
    final given = widget.source;
    if (given != null) return !identical(given, old.source);
    if (old.source != null) return true;
    return old._name != widget._name || old._projectBase != widget._projectBase || old._bundledMap != widget._bundledMap;
  }

  @override
  void initState() {
    super.initState();
    _reader = _readerFor(widget);
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(HotlayoutPlacement old) {
    super.didUpdateWidget(old);
    if (_sourceChanged(old)) {
      _generation++;
      _reader = _readerFor(widget);
      _document = null;
      _event = null;
      _toldReport = null;
      unawaited(_refresh());
    }
    if (old.refreshInterval != widget.refreshInterval) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final every = widget.refreshInterval;
    _timer = every == null ? null : Timer.periodic(every, (_) => unawaited(_refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) {
      // A refresh asked for while one is running (a new source, the app coming back) runs after it.
      _again = true;
      return;
    }
    _busy = true;
    final generation = _generation;
    try {
      final reader = _reader;
      final reading = await reader.read();
      if (!mounted || generation != _generation) return;
      final event = placementEventFor(_event, reading.event);
      final changed = !identical(reading.document, _document) || event != null;
      _document = reading.document;
      _event = reading.event;
      if (changed) setState(() {});
      if (event == null) return;
      final name = reader.source.name;
      widget.onPlacementEvent?.call(name, event);
      final report = event.report;
      if (report != _toldReport) {
        _toldReport = report;
        if (report != null) widget.onPlacement?.call(name, report);
      }
    } finally {
      _busy = false;
      if (_again && mounted) {
        _again = false;
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final document = _document;
    if (event == null || event.show == PlacementShow.nothing || document == null) {
      return const SizedBox.shrink();
    }
    return renderDocument(
      document.document,
      theme: widget.theme,
      data: widget.data,
      entry: event.entry,
      locale: widget.locale,
      onAction: widget.onAction,
      onRecordAction: widget.onRecordAction,
      onTrack: widget.onTrack,
      onHaptic: widget.onHaptic,
      onScreenShown: widget.onScreenShown,
      onWrite: widget.onWrite,
      writablePaths: widget.writablePaths,
      resolveImageUrl: widget.resolveImageUrl,
      labels: widget.labels,
      onReport: widget.onReport,
    );
  }
}
