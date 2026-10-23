// Where a document comes from.
//
// A document arrives over HTTP, and the bundled copy stays as the FLOOR: showing a screen must
// not break because of the network. Without this, every screen edit would need an app release,
// which is exactly what server-driven UI is meant to avoid.
//
// Three decisions recorded here, and why:
//
// 1. **Fall back instead of failing.** Any network failure (no connection, timeout, 404, garbage
//    instead of JSON, a foreign schema major) means the same thing: draw the bundled copy and
//    carry on. The same logic applies to the theme (`unreadableTheme: 'fallback-and-report'` in
//    the theme contract); for the document it is dictated not by the contract but by display: an
//    empty screen is the worst possible result.
// 2. **The fallback is not silent.** [DocumentLoad.status] and [DocumentLoad.detail] reach the
//    host as DATA, not only in a log. A silent fallback would mean that someone publishes, nothing
//    changes, and nobody knows why.
// 3. **The network is a port.** [DocumentTransport] exists so that a timeout, a 404 and garbage
//    can be checked by a test rather than by "bad Wi-Fi at a demo".
/// Where a document comes from: the app bundle or the network.
///
/// A published document is read over HTTP; a copy bundled with the app is the
/// floor. Any network failure — no connection, a timeout, a 404, a body that is
/// not a document, another major contract version — ends the same way: the
/// bundled copy is drawn and the reason is reported in [DocumentLoad.status].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:http/http.dart' as http;

import '../model/compatibility.dart';
import '../model/ui_document.dart';


/// What the renderer needs from an HTTP answer: the status code and the body
/// decoded as UTF-8.
///
/// No headers and no stream: everything that affects a decision is the code and the body.
typedef DocumentResponse = ({int statusCode, String body});

/// The network port. Implement it to read documents and themes through your
/// own HTTP stack (authentication, certificate pinning, a shared client).
///
/// Throw when the request did not happen at all. Do not apply a timeout: the
/// source does.
///
/// The port exists so the network can be replaced in a test: real bad Wi-Fi cannot be
/// reproduced, but a timeout and a 404 must be checked.
abstract interface class DocumentTransport {
  /// Performs one GET of [url].
  ///
  /// Throws if the request did not happen at all (no connection, DNS, TLS). The timeout is NOT
  /// applied by the transport but by [PublishedDocumentSource]: how long to wait is a display
  /// policy, not a property of the pipe.
  Future<DocumentResponse> fetch(Uri url);
}

/// [DocumentTransport] over `package:http`.
///
/// Sends no custom request headers, so a web build makes a "simple" request
/// without a CORS preflight.
/// The budget of a document body (`x-budget.maxDocumentBytes` of the schema artifact): 1 MiB. The producer
/// enforces it; the reader reads at most [kMaxBodyBytes] anyway.
const int kMaxDocumentBytes = 1 << 20;

/// The size the transport stops at: four times the budget. A body of that size or more is not a document,
/// and reading it to the end would only fill the memory of the app.
const int kMaxBodyBytes = 4 * kMaxDocumentBytes;

/// A response body larger than the transport reads ([kMaxBodyBytes]). [PublishedDocumentSource] and
/// `ThemeLoad.fromNetwork` report it as a malformed answer.
final class DocumentTooLargeException implements Exception {
  const DocumentTooLargeException(this.limit);

  /// The cap that was exceeded, in bytes.
  final int limit;

  @override
  String toString() => 'the body is larger than $limit bytes';
}

final class HttpDocumentTransport implements DocumentTransport {
  /// Uses [client], or a new `http.Client` when omitted. With [followRedirects] `false` a redirect is
  /// not followed: its `3xx` answer is returned as it is.
  HttpDocumentTransport({http.Client? client, this.followRedirects = true}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Whether a redirect is followed.
  final bool followRedirects;

  @override
  Future<DocumentResponse> fetch(Uri url) async {
    /*
     * NO CUSTOM HEADERS: this is a requirement on the WEB, not a simplification.
     *
     * A header such as `Cache-Control: no-cache` costs nothing in a mobile app, but in a browser
     * it turns the request into a "non-simple" one: the browser sends an `OPTIONS` preflight and
     * the server must separately allow that header in the bucket's CORS configuration. If it
     * does not, the request never happens and looks like `Failed to fetch`, i.e. "no network";
     * every fallback would then work flawlessly and hide the problem.
     *
     * Cache bypass does not need the header: `withCacheBuster` adds a unique query parameter to
     * the address.
     */
    final request = http.Request('GET', url)..followRedirects = followRedirects;
    final response = await _client.send(request);
    return (statusCode: response.statusCode, body: await readCappedBody(response));
  }
}

/// Reads a response body as UTF-8 and never more than [limit] bytes.
///
/// A declared length above the cap is refused before a byte of the body is read; an undeclared or
/// understated one is counted as the stream arrives and cut at the cap. Either throws
/// [DocumentTooLargeException].
Future<String> readCappedBody(http.StreamedResponse response, {int limit = kMaxBodyBytes}) async {
  final declared = response.contentLength;
  if (declared != null && declared >= limit) {
    unawaited(response.stream.listen(null).cancel());
    throw DocumentTooLargeException(limit);
  }
  final bytes = BytesBuilder(copy: false);
  final done = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = response.stream.listen(
    (chunk) {
      bytes.add(chunk);
      if (bytes.length >= limit && !done.isCompleted) {
        unawaited(subscription.cancel());
        done.completeError(DocumentTooLargeException(limit));
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
  // `utf8`, not `response.body`: without a charset in `Content-Type`, `http` decodes the body as latin1 and
  // non-ASCII text turns to garbage. A document is always UTF-8, as
  // `x-budget.measure: 'utf8-bytes-of-serialized-json'` states.
  return utf8.decode(bytes.takeBytes());
}

/// Why the document that is on screen is the one on screen.
///
/// Finer than "ok / not ok" on purpose: "not published yet" and "server down" are different news
/// and must not be confused.
enum DocumentLoadStatus {
  /// Read from the network. The published document is shown.
  network,

  /// A bundled source was read; the network was not asked.
  bundled,

  /// HTTP 404: nothing is published at the address yet. The bundled copy is shown.
  ///
  /// This is not an error: it is what storage looks like before the first publication.
  notPublished,

  /// Any other status code that is not 200. The bundled copy is shown.
  serverError,

  /// No answer within the timeout. The bundled copy is shown.
  ///
  /// Separate from [unreachable] because the remedy differs: a timeout means "the network exists
  /// but is slow".
  timedOut,

  /// The request did not happen: no connection, DNS, TLS, or — on a sandboxed
  /// platform — a missing network permission. The bundled copy is shown.
  unreachable,

  /// The answer is not a document: not JSON, or no usable screen. The bundled
  /// copy is shown.
  malformed,

  /// The document's major contract version differs from the renderer's, in
  /// either direction, or is unreadable. The bundled copy is shown;
  /// [DocumentLoad.detail] says which: a newer document needs a newer package,
  /// an older one has to be republished from the builder.
  ///
  /// The reader falls back rather than showing a "different version" notice: the bundled copy is
  /// deliberately compatible, and showing it beats a version message.
  incompatible;

  /// Whether the bundled copy is shown *instead of* the published document.
  bool get isFallback => this != network && this != bundled;
}

/// A document together with the answer to "where did it come from".
@immutable
final class DocumentLoad {
  /// Creates a load result. Sources create these; a host rarely needs to.
  const DocumentLoad({
    required this.document,
    required this.status,
    required this.receivedAt,
    required this.signature,
    this.detail,
  });

  /// The document to draw.
  final UiDocument document;
  /// Why this document is the one to draw.
  final DocumentLoadStatus status;

  /// Fingerprint of the JSON text this document was parsed from.
  ///
  /// Two loads with equal signatures carry the same document: a refresh that
  /// brings the same signature has nothing new to draw.
  ///
  /// It answers exactly one question: "is this the same document that is already on screen?".
  /// The parsed documents themselves cannot be compared: after parsing they are new objects, equal
  /// only in content.
  final String signature;

  /// The reason in words, for logs. English, not localized: do not show it to
  /// users.
  final String? detail;

  /// When this result was produced. It answers "did the refresh actually go to the network?".
  final DateTime receivedAt;

  /// Whether the bundled copy is shown instead of the published document.
  bool get isFallback => status.isFallback;

  /// The same document with another [status] and [detail].
  DocumentLoad withStatus(DocumentLoadStatus status, String detail) => DocumentLoad(
    document: document,
    status: status,
    detail: detail,
    receivedAt: receivedAt,
    signature: signature,
  );

  /// This result with [document] in place of its own.
  ///
  /// Used when [signature] matched: nothing needs to change, but the result should still say
  /// that the network was asked, and when.
  ///
  /// A new [UiDocument] object with the same `documentId` does not reset the
  /// screen stack of `renderDocument`, so this is an economy, not a necessity:
  /// when a refresh brings the same [signature], `next.reusing(previous.document)`
  /// spares a rebuild of the screen.
  DocumentLoad reusing(UiDocument document) => DocumentLoad(
    document: document,
    status: status,
    detail: detail,
    receivedAt: receivedAt,
    signature: signature,
  );
}

/// A place a document can be loaded from.
///
/// There are two kinds, and both are needed: the network is the point of the whole design, and
/// bundled documents are what keeps a display alive when the network fails.
abstract interface class DocumentSource {
  /// A name for this source, for logs and debug menus.
  String get title;

  /// Whether calling [load] again can bring a different document.
  ///
  /// An asset does not change between reads, so refreshing it is wasted work.
  bool get isRefreshable;

  /// A source that answers at once, to draw before [load] completes; `null`
  /// when this source already is one.
  ///
  /// Thanks to it the app has no loading state at all: no empty screen, and no indicator that
  /// nothing could stop if the network never answers.
  DocumentSource? get seed;

  /// Loads the document.
  ///
  /// Never throws because of the network. Throws only when the bundled copy
  /// itself cannot be read — a build error (a missing asset), not a runtime
  /// condition and must not be hidden.
  Future<DocumentLoad> load();
}

/// A document from the app's assets.
final class BundledDocumentSource implements DocumentSource {
  /// Reads the asset at [assetPath] from [bundle], or from `rootBundle`.
  ///
  /// Declare the file under `flutter: assets:` in the pubspec of **your** app.
  const BundledDocumentSource({
    required this.title,
    required this.assetPath,
    this.bundle,
  });

  /// A name for this source, for logs and debug menus.
  @override
  final String title;

  /// The asset key of the document, as declared in the app's pubspec.
  final String assetPath;
  /// The bundle to read from; `rootBundle` when `null`.
  final AssetBundle? bundle;

  @override
  bool get isRefreshable => false;

  @override
  DocumentSource? get seed => null;

  @override
  Future<DocumentLoad> load() async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    return DocumentLoad(
      document: UiDocument.fromJsonString(source),
      status: DocumentLoadStatus.bundled,
      detail: assetPath,
      receivedAt: DateTime.now(),
      signature: documentSignature(source),
    );
  }
}

/// A published document read over HTTP, with a bundled copy as the fallback.
///
/// [load] asks [url] and returns the published document, or — on any failure —
/// the [fallback] document with the reason in [DocumentLoad.status]. Every
/// request gets an extra query parameter `_req`, so that a cache in between
/// cannot serve an old publication.
final class PublishedDocumentSource implements DocumentSource {
  /// Reads [url] through [transport]; gives up after [timeout].
  PublishedDocumentSource({
    required this.url,
    required this.fallback,
    required this.transport,
    this.title = 'Published (network)',
    this.timeout = kDocumentFetchTimeout,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The request number within this source: the second half of the mark in [withCacheBuster].
  int _sequence = 0;

  /// The address of the published document, WITHOUT the cache buster: [load] adds that.
  final Uri url;

  /// The bundled copy shown first and whenever the network gives no document.
  ///
  /// It is certain to be compatible with THIS renderer code.
  final BundledDocumentSource fallback;

  /// The network port.
  final DocumentTransport transport;

  /// A name for this source, for logs and debug menus.
  @override
  final String title;

  /// How long to wait for the network. [kDocumentFetchTimeout] by default.
  ///
  /// The upper bound is a display requirement, not an optimisation: without it a refresh on bad
  /// Wi-Fi would mean an indicator that never ends.
  final Duration timeout;

  final DateTime Function() _now;

  @override
  bool get isRefreshable => true;

  /// While the network thinks, the bundled copy is on screen rather than nothing.
  @override
  DocumentSource? get seed => fallback;

  @override
  Future<DocumentLoad> load() async {
    final target = withCacheBuster(url, _now(), ++_sequence);
    DocumentResponse response;
    try {
      response = await transport.fetch(target).timeout(timeout);
    } on TimeoutException {
      return _fallback(DocumentLoadStatus.timedOut, 'no answer within ${_human(timeout)}');
    } on DocumentTooLargeException catch (error) {
      return _fallback(DocumentLoadStatus.malformed, 'the answer is not a document: $error');
    } on Object catch (error) {
      return _fallback(DocumentLoadStatus.unreachable, 'the request did not happen: $error');
    }

    if (response.statusCode == 404) {
      return _fallback(
        DocumentLoadStatus.notPublished,
        'nothing is published at this address yet (404)',
      );
    }
    if (response.statusCode != 200) {
      return _fallback(DocumentLoadStatus.serverError, 'the server answered ${response.statusCode}');
    }

    UiDocument document;
    try {
      document = UiDocument.fromJsonString(response.body);
    } on Object catch (error) {
      return _fallback(DocumentLoadStatus.malformed, 'the answer is not a document: $error');
    }

    // A foreign major is a fallback too, not a version notice. `renderDocument` shows the notice
    // when there is nothing left to choose from; here there is a choice, and the bundled copy is
    // deliberately compatible with this code.
    if (!document.isSupportedVersion) {
      // One status for both directions (the fallback is the same), but the REASON differs: whoever
      // reads the log must know whether to update the package or republish the document.
      const reader = UiDocument.supportedSchemaVersion;
      return _fallback(
        DocumentLoadStatus.incompatible,
        switch (document.versionVerdict) {
          VersionVerdict.newerMajor =>
            'document schema ${document.schemaVersion} is a newer major than this renderer '
                'reads ($reader): update the hotlayout_flutter package',
          VersionVerdict.olderMajor =>
            'document schema ${document.schemaVersion} is an older major than this renderer '
                'reads ($reader): republish the document from the builder',
          _ => 'document schema "${document.schemaVersion}" is not a version; this renderer reads $reader',
        },
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

  Future<DocumentLoad> _fallback(DocumentLoadStatus status, String reason) async {
    // Deliberately not guarded by `kDebugMode`: this is exactly the event someone opens the
    // console for. "Showing the bundled copy because ..." must be visible.
    debugPrint('[hotlayout] document not taken from the network ($reason) → bundled copy');
    final bundled = await fallback.load();
    return bundled.withStatus(status, reason);
  }
}

/// A duration for people: "5 s", and milliseconds when under a second (not "0 s" for 20 ms).
String _human(Duration duration) => duration.inMilliseconds >= 1000
    ? '${duration.inSeconds} s'
    : '${duration.inMilliseconds} ms';

/// Fingerprint of a document's JSON text. See [DocumentLoad.signature].
///
/// Length plus a string hash. Cryptographic strength is not needed (this is a display
/// optimisation, not security), but cheapness is: it is computed on every refresh.
String documentSignature(String source) => '${source.length}:${source.hashCode}';

/// Default timeout of [PublishedDocumentSource]: five seconds.
///
/// A compromise between a slow network and the patience of someone who just pressed refresh.
/// Shorter and a publication may not arrive on a slow network; longer and it is unclear whether
/// the refresh happened at all.
const Duration kDocumentFetchTimeout = Duration(seconds: 5);

/// Cache bypass: a request mark is added to the address.
///
/// Firebase Storage serves an object with the `Cache-Control` header from its metadata, which
/// the app cannot influence. If that header ever holds `max-age`, a refresh would show the old
/// copy, the very failure the network is supposed to remove. A different address per request
/// cannot be served from a cache by construction; `alt=media` accepts extra parameters.
///
/// The mark is the time PLUS a sequence number, not the time alone: two refreshes in a row fit
/// into one millisecond, and the "different address" would stop being different exactly when it
/// matters most.
Uri withCacheBuster(Uri url, DateTime now, int sequence) => url.replace(
  queryParameters: {
    ...url.queryParameters,
    '_req': '${now.millisecondsSinceEpoch}-$sequence',
  },
);
