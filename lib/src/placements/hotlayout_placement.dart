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
import 'placement_source.dart';

/// Tells the host why a placement draws nothing, or not what was asked: once per cause, not on
/// every poll.
typedef PlacementReportCallback = void Function(String name, PlacementReport report);

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
/// The map is polled every [refreshInterval] and when the app returns to the foreground. A poll
/// that finds the network silent keeps what is on screen.
///
/// To control the source (your own transport, a store for the last known map, a bundled map) build a
/// [PlacementSource] and use [HotlayoutPlacement.fromSource].
class HotlayoutPlacement extends StatefulWidget {
  /// A placement read from the project at [projectBase] (see [placementFileUrl] for its form).
  HotlayoutPlacement({
    super.key,
    required String name,
    required Uri projectBase,
    String? bundledMap,
    required this.theme,
    required this.data,
    this.refreshInterval = const Duration(minutes: 5),
    this.onPlacement,
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
  }) : source = PlacementSource(projectBase: projectBase, name: name, bundledMap: bundledMap);

  /// A placement read through [source].
  const HotlayoutPlacement.fromSource({
    super.key,
    required this.source,
    required this.theme,
    required this.data,
    this.refreshInterval = const Duration(minutes: 5),
    this.onPlacement,
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
  });

  /// Where the map and the document come from.
  final PlacementSource source;

  final RenderTheme theme;
  final Map<String, Object?> data;

  /// How often the map is read again; `null` reads it once (and when the app returns to the foreground).
  final Duration? refreshInterval;

  /// Why the placement draws nothing, or not what was asked.
  final PlacementReportCallback? onPlacement;

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
  int _generation = 0;

  DocumentLoad? _document;
  String? _documentId;
  PlacementShowing? _showing;
  PlacementReport? _told;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(HotlayoutPlacement old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) {
      _generation++;
      _document = null;
      _documentId = null;
      _showing = null;
      _told = null;
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
    if (_busy) return;
    _busy = true;
    final generation = _generation;
    try {
      final load = await widget.source.refresh();
      DocumentLoad? document = _document;
      String? documentId = _documentId;
      PlacementDocumentOutcome? outcome;
      final source = load.documentSource;
      if (source != null) {
        try {
          final loaded = await source.load();
          document = document != null && document.signature == loaded.signature ? document : loaded;
          documentId = source.documentId;
          outcome = PlacementDocumentOk(document.document.entryPoints.keys);
        } on PlacementDocumentException catch (error) {
          if (error.missing) {
            document = null;
            documentId = null;
            outcome = const PlacementDocumentMissing();
          } else if (document != null && documentId == source.documentId) {
            // A poll that could not read the document keeps the one on screen.
            outcome = PlacementDocumentOk(document.document.entryPoints.keys);
          } else {
            document = null;
            documentId = null;
            outcome = const PlacementDocumentUnreadable();
          }
        }
      } else {
        document = null;
        documentId = null;
      }
      if (!mounted || generation != _generation) return;
      final showing = placementShowing(load.resolution, outcome);
      final changed = !identical(document, _document) || showing != _showing;
      _document = document;
      _documentId = documentId;
      _showing = showing;
      if (changed) setState(() {});
      final report = showing.report;
      if (report != _told) {
        _told = report;
        if (report != null) widget.onPlacement?.call(widget.source.name, report);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showing = _showing;
    final document = _document;
    if (showing == null || showing.show == PlacementShow.nothing || document == null) {
      return const SizedBox.shrink();
    }
    return renderDocument(
      document.document,
      theme: widget.theme,
      data: widget.data,
      entry: showing.entry,
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
