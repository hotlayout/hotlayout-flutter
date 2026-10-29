// One pass of a placement: the map (or its fallbacks), the name resolved against it, the document
// read, what is drawn decided. No widget here, so a test can run it without one.
library;

import 'dart:async';

import '../data/document_source.dart';
import 'placement_map.dart';
import 'placement_source.dart';

/// What one pass found: the state the host hears about, and the document to draw (if any).
final class PlacementReading {
  const PlacementReading({required this.event, required this.document});

  final PlacementEvent event;

  /// The document to draw; `null` when [PlacementEvent.show] is [PlacementShow.nothing].
  final DocumentLoad? document;
}

/// Reads a [PlacementSource] again and again and remembers the document it showed.
///
/// The documents read are kept by the ADDRESS of the document, not by its id: the same id in
/// another project is another document. After the map is read, the documents of every window of the
/// schedule are read in the background, so a window opens with no network. A read that cannot
/// complete (the network is silent, the answer is not a document) falls back on the last good copy
/// of that document; a 404 drops the copy.
final class PlacementReader {
  PlacementReader(this.source);

  final PlacementSource source;

  /// The most documents kept; the least recently read goes first.
  static const int kCacheMax = 64;

  final Map<String, DocumentLoad> _cache = {};
  DocumentLoad? _document;

  PlacementResolution? _resolution;

  /// The instant the answer may change next, as of the last pass; `null` when it changes no more.
  int? nextBoundaryMs;

  /// Asks the network again and settles.
  Future<PlacementReading> read() async {
    final reading = await _settle(await source.refresh());
    _prefetch();
    return reading;
  }

  /// Reads, in the background, the documents of the place that are not held yet.
  void _prefetch() {
    for (final documentSource in source.allDocumentSources()) {
      if (_cache.containsKey(documentSource.url.toString())) continue;
      unawaited(_remember(documentSource));
    }
  }

  Future<void> _remember(PlacementDocumentSource documentSource) async {
    try {
      _store(documentSource.url.toString(), await documentSource.load());
    } on Object {
      // A document that cannot be read ahead is read again when its window opens.
    }
  }

  DocumentLoad _store(String key, DocumentLoad loaded) {
    final held = _cache.remove(key);
    final kept = held != null && held.signature == loaded.signature ? held : loaded;
    _cache[key] = kept;
    if (_cache.length > kCacheMax) _cache.remove(_cache.keys.first);
    return kept;
  }

  /// Decides again, at the clock of now, on the map already held, and settles. Sends nothing for the
  /// map. `null` when there is nothing to settle: no map has been read yet, or the place stands as
  /// it stood (a boundary at which another window holds the place changes nothing for the host).
  Future<PlacementReading?> recompute() async {
    final load = source.recompute();
    if (load == null) return null;
    nextBoundaryMs = load.nextBoundaryMs;
    if (load.resolution == _resolution) return null;
    return _settle(load);
  }

  Future<PlacementReading> _settle(PlacementLoad load) async {
    _resolution = load.resolution;
    nextBoundaryMs = load.nextBoundaryMs;
    final documentSource = load.documentSource;
    PlacementDocumentOutcome? outcome;
    if (documentSource == null) {
      _document = null;
    } else {
      final key = documentSource.url.toString();
      try {
        _document = _store(key, await documentSource.load());
        outcome = PlacementDocumentOk(_document!.document.entryPoints.keys);
      } on PlacementDocumentException catch (error) {
        if (error.missing) _cache.remove(key);
        // A read that cannot complete keeps the last good copy of this document.
        final kept = error.missing ? null : _cache[key];
        _document = kept;
        outcome = kept != null
            ? PlacementDocumentOk(kept.document.entryPoints.keys)
            : error.missing
            ? const PlacementDocumentMissing()
            : const PlacementDocumentUnreadable();
      }
    }
    final showing = placementShowing(load.resolution, outcome);
    final drawn = showing.show == PlacementShow.document && _document != null;
    if (!drawn) {
      return PlacementReading(
        event: PlacementEvent(
          show: PlacementShow.nothing,
          report: showing.report ?? PlacementReport.documentUnreadable,
          mapStatus: load.mapStatus,
          documentId: null,
          entry: null,
        ),
        document: null,
      );
    }
    return PlacementReading(
      event: PlacementEvent(
        show: PlacementShow.document,
        report: showing.report,
        mapStatus: load.mapStatus,
        documentId: documentSource!.documentId,
        entry: showing.entry,
      ),
      document: _document,
    );
  }
}
