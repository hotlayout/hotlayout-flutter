// Where the placement map comes from, and the document of a placement.
//
// The map is held the way a published document is: from the network (with an `ETag`, so a poll that
// finds nothing new costs a 304), then the last known text, then a copy bundled with the app. The
// status says WHY the map in use is the one in use, and three different stories stay apart:
// "the network is silent" is not "the map cannot be read", and neither is "no map was ever
// published".
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:http/http.dart' as http;

import '../data/document_source.dart';
import '../model/ui_document.dart';
import 'placement_map.dart';
import 'placement_schedule.dart';

/// What the placement code needs from an HTTP answer: the code, the body as RAW BYTES (the reader
/// decides whether they are UTF-8) and the `ETag`.
typedef PlacementResponse = ({int statusCode, Uint8List body, String? etag});

/// The network port of the placement map. Implement it to read the map through your own HTTP stack.
///
/// Throw when the request did not happen at all; the source applies the deadline, which runs to the
/// end of the body. Do not follow redirects: a `3xx` answer is returned as it is and counts as no answer.
abstract interface class PlacementTransport {
  /// One GET of [url]. When [ifNoneMatch] is given, send it as `If-None-Match`; a `304` answer
  /// has an empty body.
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch});
}

/// [PlacementTransport] over `package:http`.
///
/// `If-None-Match` is a custom request header: in a web build it makes the browser send a CORS
/// preflight (and the server must expose the `ETag`). On mobile there is no such cost. Redirects are
/// not followed. The body is read up to one byte more than a map may have (262 145 bytes); a longer
/// body is not a map.
final class HttpPlacementTransport implements PlacementTransport {
  HttpPlacementTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch}) async {
    final request = http.Request('GET', url)..followRedirects = false;
    if (ifNoneMatch != null) request.headers['If-None-Match'] = ifNoneMatch;
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      unawaited(response.stream.listen(null).cancel());
      return (statusCode: response.statusCode, body: Uint8List(0), etag: null);
    }
    final body = await _readCapped(response, kPlacementsReadMaxBytes + 1);
    return (statusCode: response.statusCode, body: body, etag: response.headers['etag']);
  }
}

/// The first [limit] bytes of the body; the rest is not read.
Future<Uint8List> _readCapped(http.StreamedResponse response, int limit) async {
  final bytes = BytesBuilder(copy: false);
  final done = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = response.stream.listen(
    (chunk) {
      bytes.add(chunk);
      if (bytes.length >= limit && !done.isCompleted) {
        unawaited(subscription.cancel());
        done.complete();
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );
  await done.future;
  final all = bytes.takeBytes();
  return all.length > limit ? Uint8List.sublistView(all, 0, limit) : all;
}

/// How an answer that came in time is sorted. `304` is `notModified` here; whether it is believed
/// depends on having asked with an `ETag`.
PlacementNetworkOutcome placementMapAnswer(PlacementResponse response) {
  final status = response.statusCode;
  if (status >= 300 && status <= 399 && status != 304) return const PlacementNetworkOffline();
  if (status == 304) return const PlacementNetworkNotModified();
  if (status == 404) return const PlacementNetworkNotFound();
  if (status < 200 || status > 299) return const PlacementNetworkOffline();
  final text = decodePlacementBody(response.body);
  return text == null ? const PlacementNetworkCorrupt() : PlacementNetworkMap(text);
}

/// One request for the map, judged by the rules of the network: the whole request, to the end of
/// the body, must fit in [timeout]; a request that did not happen is no answer.
Future<({PlacementNetworkOutcome outcome, String? etag})> fetchPlacementMap(
  PlacementTransport transport,
  Uri url, {
  String? ifNoneMatch,
  Duration timeout = kPlacementFetchTimeout,
}) async {
  try {
    final response = await transport.fetch(url, ifNoneMatch: ifNoneMatch).timeout(timeout);
    return (outcome: placementMapAnswer(response), etag: response.etag);
  } on Object {
    return (outcome: const PlacementNetworkOffline(), etag: null);
  }
}

/// Where the last known text of the map is kept between launches of the app.
///
/// The package stores nothing by itself; without a store the last known map lives in memory for
/// the life of the [PlacementSource].
///
/// Every call names the address of the map as [key]: keep the texts of different addresses apart, or
/// the map of one project would be served for another.
abstract interface class PlacementMapStore {
  /// The text saved last under [key], or `null`.
  Future<String?> read(String key);

  /// Saves the text of a fresh map under [key].
  Future<void> write(String key, String text);
}

/// The address of [relativePath] inside [projectBase].
///
/// [projectBase] is the folder of the project in the storage. Two forms are understood: a plain
/// folder (`https://host/orgs/o1/projects/p1`, files are appended with `/`) and the address of a
/// Firebase Storage object folder (`…/v0/b/<bucket>/o/orgs%2Fo1%2Fprojects%2Fp1`, files are
/// appended with an encoded slash and `?alt=media`).
Uri placementFileUrl(Uri projectBase, String relativePath) {
  var base = projectBase.removeFragment().toString().split('?').first;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  while (base.toLowerCase().endsWith('%2f')) {
    base = base.substring(0, base.length - 3);
  }
  final objectForm = projectBase.path.contains('/o/') && projectBase.path.toLowerCase().contains('%2f');
  if (objectForm) {
    return Uri.parse('$base%2F${relativePath.replaceAll('/', '%2F')}?alt=media');
  }
  return Uri.parse('$base/$relativePath');
}

/// The document of a placement could not be loaded. Thrown by [PlacementDocumentSource.load].
final class PlacementDocumentException implements Exception {
  const PlacementDocumentException({required this.missing, required this.detail});

  /// `true` when the document is gone (404); `false` when it could not be read for any other reason.
  final bool missing;

  /// The reason in English, for logs.
  final String detail;

  @override
  String toString() => 'PlacementDocumentException(${missing ? 'missing' : 'unreadable'}: $detail)';
}

/// The published document of one placement.
///
/// Unlike [PublishedDocumentSource] it has NO bundled fallback: a placement whose document is not
/// there draws nothing and says so. So [load] throws [PlacementDocumentException] when there is no
/// readable document of a supported version.
final class PlacementDocumentSource implements DocumentSource {
  PlacementDocumentSource({
    required this.url,
    required this.documentId,
    DocumentTransport? transport,
    this.timeout = kPlacementFetchTimeout,
    DateTime Function()? now,
  }) : transport = transport ?? HttpDocumentTransport(followRedirects: false),
       _now = now ?? DateTime.now;

  /// The address of `published.json` of the document, without the cache buster.
  final Uri url;

  /// The document id from the map.
  final String documentId;

  final DocumentTransport transport;
  final Duration timeout;
  final DateTime Function() _now;
  int _sequence = 0;

  @override
  String get title => 'Placement document $documentId';

  @override
  bool get isRefreshable => true;

  @override
  DocumentSource? get seed => null;

  @override
  Future<DocumentLoad> load() async {
    final target = withCacheBuster(url, _now(), ++_sequence);
    final DocumentResponse response;
    try {
      response = await transport.fetch(target).timeout(timeout);
    } on TimeoutException {
      throw const PlacementDocumentException(missing: false, detail: 'no answer in time');
    } on Object catch (error) {
      throw PlacementDocumentException(missing: false, detail: 'the request did not happen: $error');
    }
    if (response.statusCode == 404) {
      throw const PlacementDocumentException(missing: true, detail: 'nothing is published at this address (404)');
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw PlacementDocumentException(missing: false, detail: 'the server answered ${response.statusCode}');
    }
    final UiDocument document;
    try {
      document = UiDocument.fromJsonString(response.body);
    } on Object catch (error) {
      throw PlacementDocumentException(missing: false, detail: 'the answer is not a document: $error');
    }
    if (!document.isSupportedVersion) {
      throw PlacementDocumentException(
        missing: false,
        detail: 'document schema "${document.schemaVersion}" is not readable by this renderer',
      );
    }
    return DocumentLoad(
      document: document,
      signature: documentSignature(response.body),
      status: DocumentLoadStatus.network,
      detail: '${document.name} (${document.documentId}), schema ${document.schemaVersion}',
      receivedAt: _now(),
    );
  }
}

/// What a placement stands for right now.
@immutable
final class PlacementLoad {
  const PlacementLoad({
    required this.name,
    required this.resolution,
    required this.mapSource,
    required this.mapStatus,
    required this.documentSource,
    this.nextBoundaryMs,
  });

  /// The placement name.
  final String name;

  /// What the map says stands there.
  final PlacementResolution resolution;

  /// Whose map answered: the network, the last known text, the bundled copy, or none.
  final PlacementMapSource mapSource;

  /// Why that map is in use. Log it: it is the difference between "offline" and "spoiled".
  final PlacementSourceStatus mapStatus;

  /// The source of the placed document; `null` unless [resolution] is a document.
  final PlacementDocumentSource? documentSource;

  /// The instant (milliseconds since the epoch) at which the answer may change next, by the
  /// schedule of the place; `null` when the schedule changes nothing any more.
  final int? nextBoundaryMs;

  /// The entry point to start from; `null` is the initial screen of the document.
  String? get entry => resolution.entry;
}

/// One placement of an app: reads the map of the project, keeps the last known one, and yields the
/// document that stands in the place.
///
/// ```dart
/// final source = PlacementSource(projectBase: base, name: 'home.banner');
/// final load = await source.refresh();
/// final document = load.documentSource; // null: nothing to draw, see load.resolution
/// ```
///
/// What stands in the place is decided at the instant of the clock of the device (the `now` given to
/// the constructor, [DateTime.now] by default), because the map may schedule documents for a window
/// of time (see [resolvePlacementAt]). [recompute] decides again on the map already held, without the
/// network: call it when [PlacementLoad.nextBoundaryMs] comes, and when the app returns to the
/// foreground.
///
/// Call [refresh] again to poll: it sends `If-None-Match` with the `ETag` of the last fresh answer,
/// so a map that did not change costs a 304. A refresh that finds the network silent keeps the last
/// known map.
final class PlacementSource {
  PlacementSource({
    required this.projectBase,
    required this.name,
    PlacementTransport? transport,
    DocumentTransport? documentTransport,
    this.bundledMap,
    this.store,
    this.timeout = kPlacementFetchTimeout,
    DateTime Function()? now,
  }) : _transport = transport ?? HttpPlacementTransport(),
       _documentTransport = documentTransport,
       _now = now ?? DateTime.now;

  /// The folder of the project in the storage, see [placementFileUrl].
  final Uri projectBase;

  /// The placement name, for example `home.banner`.
  final String name;

  /// The text of a map bundled with the app: the floor under the last known map.
  final String? bundledMap;

  /// Where the last known text survives a restart; in memory only when `null`.
  final PlacementMapStore? store;

  final Duration timeout;
  final PlacementTransport _transport;
  final DocumentTransport? _documentTransport;
  final DateTime Function() _now;

  String? _lastKnown;
  String? _etag;
  PlacementSourceDecision? _decision;
  bool _storeRead = false;
  int _sequence = 0;

  String get _mapKey => mapUrl.toString();

  /// Where the map is read from.
  Uri get mapUrl => placementFileUrl(projectBase, 'placements/published.json');

  /// The last known text of the map, or `null`.
  String? get lastKnownMap => _lastKnown;

  /// The clock of this source: milliseconds since the epoch.
  int get clockMs => _now().toUtc().millisecondsSinceEpoch;

  /// Decides again, at the clock of now, on the map the last [refresh] chose; `null` before the
  /// first [refresh]. Sends nothing.
  PlacementLoad? recompute() {
    final decision = _decision;
    return decision == null ? null : _loadFrom(decision);
  }

  /// Asks the network for the map and decides which map to use.
  Future<PlacementLoad> refresh() async {
    if (!_storeRead) {
      _storeRead = true;
      try {
        _lastKnown ??= await store?.read(_mapKey);
      } on Object catch (error) {
        debugPrint('[hotlayout] the stored placement map could not be read ($error)');
      }
    }
    final lastReadable = _lastKnown != null && readPlacementMapText(_lastKnown!) is PlacementMapOk;
    final conditional = lastReadable ? _etag : null;
    final target = withCacheBuster(mapUrl, _now(), ++_sequence);
    final fetched = await fetchPlacementMap(_transport, target, ifNoneMatch: conditional, timeout: timeout);
    // A 304 to a request that did not ask for one is not believed.
    final outcome = fetched.outcome is PlacementNetworkNotModified && conditional == null
        ? const PlacementNetworkOffline()
        : fetched.outcome;
    final decision = pickPlacementMap(network: outcome, lastKnown: _lastKnown, bundled: bundledMap);
    if (decision.remember && outcome is PlacementNetworkMap) {
      _lastKnown = outcome.text;
      _etag = fetched.etag;
      try {
        await store?.write(_mapKey, outcome.text);
      } on Object catch (error) {
        debugPrint('[hotlayout] the placement map could not be stored ($error)');
      }
    }
    if (decision.status != PlacementSourceStatus.fresh) {
      debugPrint('[hotlayout] placement map: ${decision.status.name}, using ${decision.source.name}');
    }
    _decision = decision;
    return _loadFrom(decision);
  }

  /// The sources of every document the place can show on the map held: its permanent content and
  /// each window of the schedule. Empty before the first [refresh].
  List<PlacementDocumentSource> allDocumentSources() {
    final map = _decision?.map;
    if (map == null) return const [];
    return [for (final id in placementDocumentIds(map, name)) _documentSourceFor(id)];
  }

  PlacementDocumentSource _documentSourceFor(String documentId) => PlacementDocumentSource(
    url: placementFileUrl(projectBase, 'documents/$documentId/published.json'),
    documentId: documentId,
    transport: _documentTransport,
    timeout: timeout,
    now: _now,
  );

  PlacementLoad _loadFrom(PlacementSourceDecision decision) {
    final nowMs = clockMs;
    final resolution = resolvePlacementAt(decision.map, name, nowMs);
    return PlacementLoad(
      name: name,
      resolution: resolution,
      mapSource: decision.source,
      mapStatus: decision.status,
      nextBoundaryMs: nextPlacementBoundary(decision.map, name, nowMs),
      documentSource: resolution.status == PlacementStatus.document ? _documentSourceFor(resolution.documentId!) : null,
    );
  }
}
