// Where the placement map comes from, and the document of a placement.
//
// The map is held the way a published document is: from the network (with an `ETag`, so a poll that
// finds nothing new costs a 304), then the last known text, then a copy bundled with the app. The
// status says WHY the map in use is the one in use, and three different stories stay apart:
// "the network is silent" is not "the map cannot be read", and neither is "no map was ever
// published".
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:http/http.dart' as http;

import '../data/document_source.dart';
import '../model/ui_document.dart';
import 'placement_map.dart';

/// What the placement code needs from an HTTP answer: the code, the body as UTF-8 and the `ETag`.
typedef PlacementResponse = ({int statusCode, String body, String? etag});

/// The network port of the placement map. Implement it to read the map through your own HTTP stack.
///
/// Throw when the request did not happen at all; the source applies the timeout.
abstract interface class PlacementTransport {
  /// One GET of [url]. When [ifNoneMatch] is given, send it as `If-None-Match`; a `304` answer
  /// has an empty body.
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch});
}

/// [PlacementTransport] over `package:http`.
///
/// `If-None-Match` is a custom request header: in a web build it makes the browser send a CORS
/// preflight (and the server must expose the `ETag`). On mobile there is no such cost. The body is
/// read up to 256 KiB; a longer body is not a map.
final class HttpPlacementTransport implements PlacementTransport {
  HttpPlacementTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch}) async {
    final request = http.Request('GET', url);
    if (ifNoneMatch != null) request.headers['If-None-Match'] = ifNoneMatch;
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      unawaited(response.stream.listen(null).cancel());
      return (statusCode: response.statusCode, body: '', etag: null);
    }
    final body = await readCappedBody(response, limit: 4 * kPlacementsMaxBytes);
    return (statusCode: 200, body: body, etag: response.headers['etag']);
  }
}

/// Where the last known text of the map is kept between launches of the app.
///
/// The package stores nothing by itself; without a store the last known map lives in memory for
/// the life of the [PlacementSource].
abstract interface class PlacementMapStore {
  /// The text saved last, or `null`.
  Future<String?> read();

  /// Saves the text of a fresh map.
  Future<void> write(String text);
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
    this.timeout = kDocumentFetchTimeout,
    DateTime Function()? now,
  }) : transport = transport ?? HttpDocumentTransport(),
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
    if (response.statusCode != 200) {
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
    this.timeout = kDocumentFetchTimeout,
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
  bool _storeRead = false;
  int _sequence = 0;

  /// Where the map is read from.
  Uri get mapUrl => placementFileUrl(projectBase, 'placements/published.json');

  /// The last known text of the map, or `null`.
  String? get lastKnownMap => _lastKnown;

  /// Asks the network for the map and decides which map to use.
  Future<PlacementLoad> refresh() async {
    if (!_storeRead) {
      _storeRead = true;
      try {
        _lastKnown ??= await store?.read();
      } on Object catch (error) {
        debugPrint('[hotlayout] the stored placement map could not be read ($error)');
      }
    }
    final lastReadable = _lastKnown != null && readPlacementMapText(_lastKnown!) is PlacementMapOk;
    final conditional = lastReadable ? _etag : null;
    String? freshEtag;
    PlacementNetworkOutcome outcome;
    try {
      final target = withCacheBuster(mapUrl, _now(), ++_sequence);
      final response = await _transport.fetch(target, ifNoneMatch: conditional).timeout(timeout);
      outcome = switch (response.statusCode) {
        200 => PlacementNetworkMap(response.body),
        304 when conditional != null => const PlacementNetworkNotModified(),
        404 => const PlacementNetworkNotFound(),
        _ => const PlacementNetworkOffline(),
      };
      freshEtag = response.etag;
    } on DocumentTooLargeException {
      // A body longer than any map is not a map.
      outcome = const PlacementNetworkMap('');
    } on Object {
      outcome = const PlacementNetworkOffline();
    }
    final decision = pickPlacementMap(network: outcome, lastKnown: _lastKnown, bundled: bundledMap);
    if (decision.remember && outcome is PlacementNetworkMap) {
      _lastKnown = outcome.text;
      _etag = freshEtag;
      try {
        await store?.write(outcome.text);
      } on Object catch (error) {
        debugPrint('[hotlayout] the placement map could not be stored ($error)');
      }
    }
    if (decision.status != PlacementSourceStatus.fresh) {
      debugPrint('[hotlayout] placement map: ${decision.status.name}, using ${decision.source.name}');
    }
    final resolution = resolvePlacement(decision.map, name);
    return PlacementLoad(
      name: name,
      resolution: resolution,
      mapSource: decision.source,
      mapStatus: decision.status,
      documentSource: resolution.status == PlacementStatus.document
          ? PlacementDocumentSource(
              url: placementFileUrl(projectBase, 'documents/${resolution.documentId}/published.json'),
              documentId: resolution.documentId!,
              transport: _documentTransport,
              timeout: timeout,
              now: _now,
            )
          : null,
    );
  }
}
