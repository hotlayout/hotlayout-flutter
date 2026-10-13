import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake network reply: status code and body.
typedef FakeHttpReply = ({int statusCode, List<int> body});

FakeHttpReply httpOk(String body) => (statusCode: 200, body: utf8.encode(body));

FakeHttpReply httpBytes(List<int> body) => (statusCode: 200, body: body);

FakeHttpReply httpStatus(int statusCode, [String body = '']) =>
    (statusCode: statusCode, body: utf8.encode(body));

/// A network faked at the `dart:io` level that records EVERY request.
///
/// Why this low, rather than through a port like [FakeDocumentTransport]: the
/// code under test here is a third-party library. The claim "an SVG file pulls
/// in no foreign request" only means something if the fake sits below
/// everything the library could use to reach the network. A port in our own
/// loader would see exactly one request by construction and prove nothing.
///
/// An address missing from [replies] yields 404: "unknown" is a refusal, not an
/// empty successful reply.
final class FakeHttp extends HttpOverrides {
  FakeHttp(this.replies);

  final Map<String, FakeHttpReply> replies;

  /// All addresses requested, in request order.
  final List<Uri> requests = [];

  /// Requests that never answer: the "still loading" state.
  final Set<String> silent = {};

  /// Requests that fail outright: no connectivity, DNS, TLS.
  final Set<String> unreachable = {};

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(this);
}

/// Installs [FakeHttp] for the duration of one test and restores the old one after.
///
/// Must be called INSIDE `testWidgets`: the binding installs its own fake
/// ("everything 400") before each test and would overwrite one set earlier.
FakeHttp installFakeHttp(Map<String, FakeHttpReply> replies) {
  final previous = HttpOverrides.current;
  final fake = FakeHttp(replies);
  HttpOverrides.global = fake;
  addTearDown(() => HttpOverrides.global = previous);
  return fake;
}

class _FakeClient implements HttpClient {
  _FakeClient(this._net);

  final FakeHttp _net;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    _net.requests.add(url);
    return _FakeRequest(_net, url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) {}

  // The rest of `HttpClient` is connection configuration the fake does not need.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._net, this._url);

  final FakeHttp _net;
  final Uri _url;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() {
    if (_net.silent.contains(_url.toString())) {
      return Completer<HttpClientResponse>().future;
    }
    if (_net.unreachable.contains(_url.toString())) {
      return Future.error(const SocketException('No connection'));
    }
    final reply = _net.replies[_url.toString()] ?? httpStatus(404, 'Not Found');
    return Future.value(_FakeResponse(reply));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._reply);

  final FakeHttpReply _reply;

  @override
  int get statusCode => _reply.statusCode;

  @override
  String get reasonPhrase => '';

  @override
  int get contentLength => _reply.body.length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(Uint8List.fromList(_reply.body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
