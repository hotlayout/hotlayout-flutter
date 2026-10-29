// One pass of a placement: the map (or its fallbacks), the name resolved against it, the document
// read, what is drawn decided. No widget here, so a test can run it without one.
library;

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
/// The remembered document is keyed by the ADDRESS of the document, not by its id: the same id in
/// another project is another document. It keeps the placement on screen across a poll that cannot
/// read the document, and is dropped the moment the document answers 404.
final class PlacementReader {
  PlacementReader(this.source);

  final PlacementSource source;

  DocumentLoad? _document;
  String? _documentKey;

  PlacementResolution? _resolution;

  /// The instant the answer may change next, as of the last pass; `null` when it changes no more.
  int? nextBoundaryMs;

  /// Asks the network again and settles.
  Future<PlacementReading> read() async => _settle(await source.refresh());

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
      _documentKey = null;
    } else {
      final key = documentSource.url.toString();
      try {
        final loaded = await documentSource.load();
        final held = _document;
        _document = held != null && _documentKey == key && held.signature == loaded.signature ? held : loaded;
        _documentKey = key;
        outcome = PlacementDocumentOk(_document!.document.entryPoints.keys);
      } on PlacementDocumentException catch (error) {
        if (error.missing) {
          _document = null;
          _documentKey = null;
          outcome = const PlacementDocumentMissing();
        } else if (_document != null && _documentKey == key) {
          // A poll that could not read the document keeps the one on screen.
          outcome = PlacementDocumentOk(_document!.document.entryPoints.keys);
        } else {
          _document = null;
          _documentKey = null;
          outcome = const PlacementDocumentUnreadable();
        }
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
