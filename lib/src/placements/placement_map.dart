// The placement map: which published document each named place of an app shows.
//
// The app names a PLACE (`home.banner`); which document stands there is decided in the builder and
// published as one file, `placements/published.json`, next to the theme. This file is the reader
// of that file and the rules that turn a name into "a document", "empty", "unknown" or
// "unreadable". The rules are those of the `x-placementReading`, `x-placementSource` and
// `x-placementShowing` blocks of `assets/contract/placements.json`; the shared case table
// `assets/contract/fixtures/placements/placement-cases.json` runs every row of them.
//
// The map is untrusted input: it comes from the network and its `documentId` becomes a segment of
// an address. So the shape of every identifier is checked here, and a name is looked up among the
// OWN keys of the map only (`constructor` is not a place).
library;

import 'dart:convert' show jsonDecode, utf8;

import 'package:flutter/foundation.dart' show immutable;

/// The version of the placement contract this reader reads.
const String kPlacementsContractVersion = '1.0.0';

/// The longest placement name.
const int kPlacementNameMax = 64;

/// How many placements a project may publish. A limit of the publishing side: the reader does not
/// enforce it, it reads what it is given.
const int kMaxPlacements = 200;

/// The size limit of the map file. A limit of the publishing side, like [kMaxPlacements]; the
/// transport still stops reading a body several times this size (see `HttpPlacementTransport`).
const int kPlacementsMaxBytes = 65536;

/// The most bytes of a map body the reader reads; a longer body is a corrupt map. The byte order
/// mark counts.
const int kPlacementsReadMaxBytes = 262144;

/// The deepest nesting of arrays and objects the reader parses (the root counts as one); a deeper
/// body is a corrupt map, judged before it is parsed.
const int kPlacementsReadMaxDepth = 32;

/// How long one request of the placement code may take, from its start to the end of the body.
const Duration kPlacementFetchTimeout = Duration(seconds: 20);

final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9]*(\.[a-z0-9-]+)*$');
final RegExp _documentIdPattern = RegExp(r'^(?!\.+$)[A-Za-z0-9._-]{1,64}$');
final RegExp _entryPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');
const int _entryMax = 48;

final RegExp _versionPattern = RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$');
const String _readerMajor = '1';

/// Whether [name] has the form of a placement name: lowercase Latin letters and digits in
/// dot-separated segments, at most 64 characters.
bool isPlacementName(String name) => name.length <= kPlacementNameMax && _namePattern.hasMatch(name);

/// A map after tolerant reading.
@immutable
sealed class PlacementMapRead {
  const PlacementMapRead();
}

/// The file is a map of a major version this reader knows. Places are read lazily, by name.
final class PlacementMapOk extends PlacementMapRead {
  const PlacementMapOk({required this.version, required this.places});

  /// The `placementsVersion` the file declares.
  final String version;

  /// The raw `placements` object. A broken entry spoils only its own name.
  final Map<Object?, Object?> places;
}

/// The file is not a map: not an object, no version, or no `placements` object.
final class PlacementMapCorrupt extends PlacementMapRead {
  const PlacementMapCorrupt();
}

/// The file is a map of another major version of the contract: the reader does not know what is in it.
final class PlacementMapUnsupported extends PlacementMapRead {
  const PlacementMapUnsupported();
}

/// What stands in a placement.
enum PlacementStatus {
  /// A document (and maybe an entry point).
  document,

  /// The place is declared, but nothing is put into it.
  empty,

  /// The map has no such place (or the name cannot be a place).
  unknown,

  /// The map could not be read, or the entry of this place is broken.
  unreadable,
}

/// The answer to "what stands in this placement". One shape for every status.
@immutable
final class PlacementResolution {
  const PlacementResolution(this.status, {this.documentId, this.entry});

  final PlacementStatus status;

  /// The document of the place; set only for [PlacementStatus.document].
  final String? documentId;

  /// The entry point to start from; `null` means the initial screen of the document.
  final String? entry;

  @override
  bool operator ==(Object other) =>
      other is PlacementResolution && other.status == status && other.documentId == documentId && other.entry == entry;

  @override
  int get hashCode => Object.hash(status, documentId, entry);

  @override
  String toString() => 'PlacementResolution(${status.name}, $documentId, $entry)';
}

bool _isObject(Object? value) => value is Map;

/// Parsed JSON → map. Unknown fields are skipped.
PlacementMapRead readPlacementMap(Object? raw) {
  if (raw is! Map) return const PlacementMapCorrupt();
  final version = raw.containsKey('placementsVersion') ? raw['placementsVersion'] : null;
  if (version is! String) return const PlacementMapCorrupt();
  // The major is compared as a string of digits: a number of any length is another major, never an overflow.
  final parsed = _versionPattern.firstMatch(version);
  if (parsed == null) return const PlacementMapCorrupt();
  if (parsed.group(1) != _readerMajor) return const PlacementMapUnsupported();
  final places = raw.containsKey('placements') ? raw['placements'] : null;
  if (!_isObject(places)) return const PlacementMapCorrupt();
  return PlacementMapOk(version: version, places: (places as Map).cast<Object?, Object?>());
}

/// Whether [text] holds more than [max] nested arrays and objects (the root is level one).
///
/// Counts brackets outside strings WITHOUT parsing, so a text that would overflow the stack of a
/// parser is judged before it is given to one.
bool jsonNestingExceeds(String text, int max) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
    } else if (code == 0x22) {
      inString = true;
    } else if (code == 0x7b || code == 0x5b) {
      depth++;
      if (depth > max) return true;
    } else if (code == 0x7d || code == 0x5d) {
      depth--;
    }
  }
  return false;
}

/// The text of the file → map. Text that is not JSON is [PlacementMapCorrupt], not an exception:
/// "the map is spoiled" travels the same way as any other unreadable map.
///
/// One leading U+FEFF is skipped. A text longer than [kPlacementsReadMaxBytes] bytes of UTF-8, or
/// nested deeper than [kPlacementsReadMaxDepth], is corrupt.
PlacementMapRead readPlacementMapText(String text) {
  // Every UTF-16 unit is at least one byte: a long text is judged without encoding it.
  if (text.length > kPlacementsReadMaxBytes || utf8.encode(text).length > kPlacementsReadMaxBytes) {
    return const PlacementMapCorrupt();
  }
  final body = text.isNotEmpty && text.codeUnitAt(0) == 0xfeff ? text.substring(1) : text;
  if (jsonNestingExceeds(body, kPlacementsReadMaxDepth)) return const PlacementMapCorrupt();
  final Object? raw;
  try {
    raw = jsonDecode(body);
  } on FormatException {
    return const PlacementMapCorrupt();
  }
  return readPlacementMap(raw);
}

/// The bytes of a body → text, or `null` when the body cannot be a map: longer than
/// [kPlacementsReadMaxBytes], or not UTF-8. Invalid bytes are never replaced with U+FFFD (`c0 af`
/// must not turn into a slash). A byte order mark stays in the text; [readPlacementMapText] skips one.
String? decodePlacementBody(List<int> bytes) {
  if (bytes.length > kPlacementsReadMaxBytes) return null;
  try {
    // A space in front keeps the decoder from dropping a leading byte order mark on its own: the
    // rule skips exactly one, and two are not JSON.
    return utf8.decode(<int>[0x20, ...bytes]).substring(1);
  } on FormatException {
    return null;
  }
}

/// The bytes of a map body → map: [decodePlacementBody], then [readPlacementMapText].
PlacementMapRead readPlacementMapBytes(List<int> bytes) {
  final text = decodePlacementBody(bytes);
  return text == null ? const PlacementMapCorrupt() : readPlacementMapText(text);
}

/// One entry of the map. `documentId: null` is an empty place (an entry point beside it is not read).
/// `entry: null` is the same as no entry: backends often write `null` for "nothing", and punishing
/// that helps nobody.
PlacementResolution readPlace(Object? value) {
  const unreadable = PlacementResolution(PlacementStatus.unreadable);
  if (value is! Map || !value.containsKey('documentId')) return unreadable;
  final documentId = value['documentId'];
  if (documentId == null) return const PlacementResolution(PlacementStatus.empty);
  if (documentId is! String || !_documentIdPattern.hasMatch(documentId)) return unreadable;
  final entry = value.containsKey('entry') ? value['entry'] : null;
  if (entry == null) return PlacementResolution(PlacementStatus.document, documentId: documentId);
  if (entry is! String || entry.length > _entryMax || !_entryPattern.hasMatch(entry)) return unreadable;
  return PlacementResolution(PlacementStatus.document, documentId: documentId, entry: entry);
}

/// What stands in the placement [name].
///
/// The order of the checks is part of the rule: a map that was not read answers `unreadable` to
/// every name (a malformed one too); a name of the wrong form is `unknown` (no map can have such
/// a place); then the own key.
PlacementResolution resolvePlacement(PlacementMapRead map, String name) {
  if (map is! PlacementMapOk) return const PlacementResolution(PlacementStatus.unreadable);
  if (!isPlacementName(name) || !map.places.containsKey(name)) {
    return const PlacementResolution(PlacementStatus.unknown);
  }
  return readPlace(map.places[name]);
}

// ---------------------------------------------------------------------------------------------
// Where the map comes from

/// What the network answered to the request for the map.
@immutable
sealed class PlacementNetworkOutcome {
  const PlacementNetworkOutcome();
}

/// 200 with a body.
final class PlacementNetworkMap extends PlacementNetworkOutcome {
  const PlacementNetworkMap(this.text);
  final String text;
}

/// 304 to a request with an `ETag`: the file is the last known one.
final class PlacementNetworkNotModified extends PlacementNetworkOutcome {
  const PlacementNetworkNotModified();
}

/// 404: the project has not published placements.
final class PlacementNetworkNotFound extends PlacementNetworkOutcome {
  const PlacementNetworkNotFound();
}

/// 200 with a body that is not a map for a reason found before reading: not UTF-8, or over the size limit.
final class PlacementNetworkCorrupt extends PlacementNetworkOutcome {
  const PlacementNetworkCorrupt();
}

/// No answer: a connection error, the deadline, a redirect, 5xx, 403.
final class PlacementNetworkOffline extends PlacementNetworkOutcome {
  const PlacementNetworkOffline();
}

/// Why the map in use is the one in use.
enum PlacementSourceStatus {
  /// The network answered with a readable map (or 304 with a readable last known one).
  fresh,

  /// No answer: connection error, timeout, 5xx, 403, or 304 without a readable last known map.
  offline,

  /// The network answered with something that is not a map.
  corrupt,

  /// The network answered with a map of another major version.
  unsupported,

  /// The network answered 404: the project has not published placements.
  notPublished,
}

/// Whose map was taken.
enum PlacementMapSource { network, lastKnown, bundled, none }

/// The choice among the network, the last known text and the bundled copy.
@immutable
final class PlacementSourceDecision {
  const PlacementSourceDecision({
    required this.source,
    required this.status,
    required this.remember,
    required this.map,
  });

  final PlacementMapSource source;
  final PlacementSourceStatus status;

  /// Whether to keep the text of the network as the new "last known" one. Only a fresh map from
  /// the network is kept.
  final bool remember;

  /// The map to resolve places against.
  final PlacementMapRead map;
}

// Without any map the places say different things: when no map was ever published every place is
// `unknown` (the server's answer is the truth); when a map could not be read, `unreadable`.
const PlacementMapRead _noMapPublished = PlacementMapOk(version: kPlacementsContractVersion, places: <Object?, Object?>{});
const PlacementMapRead _noMapRead = PlacementMapCorrupt();

PlacementSourceDecision _fallbackFrom(String? lastKnown, String? bundled, PlacementSourceStatus status) {
  final last = lastKnown == null ? null : readPlacementMapText(lastKnown);
  if (last is PlacementMapOk) {
    return PlacementSourceDecision(source: PlacementMapSource.lastKnown, status: status, remember: false, map: last);
  }
  final copy = bundled == null ? null : readPlacementMapText(bundled);
  if (copy is PlacementMapOk) {
    return PlacementSourceDecision(source: PlacementMapSource.bundled, status: status, remember: false, map: copy);
  }
  return PlacementSourceDecision(
    source: PlacementMapSource.none,
    status: status,
    remember: false,
    map: status == PlacementSourceStatus.notPublished ? _noMapPublished : _noMapRead,
  );
}

/// Which map to use. The order of the fallbacks is the same for every reason: the last known text,
/// then the bundled copy.
PlacementSourceDecision pickPlacementMap({
  required PlacementNetworkOutcome network,
  String? lastKnown,
  String? bundled,
}) {
  switch (network) {
    case PlacementNetworkMap(:final text):
      final read = readPlacementMapText(text);
      if (read is PlacementMapOk) {
        return PlacementSourceDecision(
          source: PlacementMapSource.network,
          status: PlacementSourceStatus.fresh,
          remember: true,
          map: read,
        );
      }
      return _fallbackFrom(
        lastKnown,
        bundled,
        read is PlacementMapUnsupported ? PlacementSourceStatus.unsupported : PlacementSourceStatus.corrupt,
      );
    case PlacementNetworkCorrupt():
      return _fallbackFrom(lastKnown, bundled, PlacementSourceStatus.corrupt);
    case PlacementNetworkNotModified():
      final last = lastKnown == null ? null : readPlacementMapText(lastKnown);
      if (last is PlacementMapOk) {
        return PlacementSourceDecision(
          source: PlacementMapSource.lastKnown,
          status: PlacementSourceStatus.fresh,
          remember: false,
          map: last,
        );
      }
      // 304 without a readable last known map is the same as no answer.
      return _fallbackFrom(null, bundled, PlacementSourceStatus.offline);
    case PlacementNetworkNotFound():
      return _fallbackFrom(lastKnown, bundled, PlacementSourceStatus.notPublished);
    case PlacementNetworkOffline():
      return _fallbackFrom(lastKnown, bundled, PlacementSourceStatus.offline);
  }
}

// ---------------------------------------------------------------------------------------------
// What a placement draws

/// What the host is told when a placement does not simply draw its document.
enum PlacementReport {
  /// The place is declared but empty.
  empty,

  /// The map has no such place.
  unknown,

  /// The map or the entry of the place could not be read.
  unreadable,

  /// The document of the place is gone (404).
  documentMissing,

  /// The document of the place could not be read.
  documentUnreadable,

  /// The entry point of the place is not in the document: the document is drawn from its first
  /// screen. A mistake of configuration that someone has to fix.
  entryMissing,
}

/// What came of reading the document of a place, after the reader's own fallbacks.
@immutable
sealed class PlacementDocumentOutcome {
  const PlacementDocumentOutcome();
}

final class PlacementDocumentOk extends PlacementDocumentOutcome {
  const PlacementDocumentOk(this.entryPoints);

  /// The names of the entry points the document has.
  final Iterable<String> entryPoints;
}

final class PlacementDocumentMissing extends PlacementDocumentOutcome {
  const PlacementDocumentMissing();
}

final class PlacementDocumentUnreadable extends PlacementDocumentOutcome {
  const PlacementDocumentUnreadable();
}

/// Draw the document or nothing.
enum PlacementShow { document, nothing }

@immutable
final class PlacementShowing {
  const PlacementShowing({required this.show, required this.entry, required this.report});

  final PlacementShow show;

  /// The entry point to start from; `null` is the initial screen of the document.
  final String? entry;

  /// What to tell the host; `null` for nothing.
  final PlacementReport? report;

  @override
  bool operator ==(Object other) =>
      other is PlacementShowing && other.show == show && other.entry == entry && other.report == report;

  @override
  int get hashCode => Object.hash(show, entry, report);
}

/// What the place draws. An entry point the document does not have is the initial screen
/// (`unknownEntryPoint: 'use-initial'` of the document contract), and the host hears about it.
PlacementShowing placementShowing(PlacementResolution resolution, [PlacementDocumentOutcome? document]) {
  if (resolution.status != PlacementStatus.document) {
    return PlacementShowing(
      show: PlacementShow.nothing,
      entry: null,
      report: PlacementReport.values.byName(resolution.status.name),
    );
  }
  if (document == null || document is PlacementDocumentUnreadable) {
    return const PlacementShowing(show: PlacementShow.nothing, entry: null, report: PlacementReport.documentUnreadable);
  }
  if (document is PlacementDocumentMissing) {
    return const PlacementShowing(show: PlacementShow.nothing, entry: null, report: PlacementReport.documentMissing);
  }
  final entry = resolution.entry;
  if (entry == null) return const PlacementShowing(show: PlacementShow.document, entry: null, report: null);
  if ((document as PlacementDocumentOk).entryPoints.contains(entry)) {
    return PlacementShowing(show: PlacementShow.document, entry: entry, report: null);
  }
  return const PlacementShowing(show: PlacementShow.document, entry: null, report: PlacementReport.entryMissing);
}

// ---------------------------------------------------------------------------------------------
// What the host hears

/// The settled state of a placement, as the host is told about it. One shape for both outcomes:
/// when [show] is [PlacementShow.nothing] there is no document and no entry.
@immutable
final class PlacementEvent {
  const PlacementEvent({
    required this.show,
    required this.report,
    required this.mapStatus,
    required this.documentId,
    required this.entry,
  });

  /// Whether a document is drawn.
  final PlacementShow show;

  /// Why nothing is drawn, or not what was asked; `null` when the document is drawn as asked.
  final PlacementReport? report;

  /// Why the map in use is the one in use.
  final PlacementSourceStatus mapStatus;

  /// The document drawn; `null` when nothing is.
  final String? documentId;

  /// The entry point the document starts from; `null` is its initial screen.
  final String? entry;

  @override
  bool operator ==(Object other) =>
      other is PlacementEvent &&
      other.show == show &&
      other.report == report &&
      other.mapStatus == mapStatus &&
      other.documentId == documentId &&
      other.entry == entry;

  @override
  int get hashCode => Object.hash(show, report, mapStatus, documentId, entry);

  @override
  String toString() => 'PlacementEvent(${show.name}, ${report?.name}, ${mapStatus.name}, $documentId, $entry)';
}

/// The event the host hears when a placement settles in [next] after [previous] (`null`: the first
/// settled state), or `null` when nothing the host can see has changed. A change of any of the five
/// fields is an event, the return to a drawn document (`report` null) included.
PlacementEvent? placementEventFor(PlacementEvent? previous, PlacementEvent next) =>
    previous == next ? null : next;
