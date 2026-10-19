/// Shared helpers of the hardening tests: hostile values and tree walks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Numbers a JSON document can carry (`jsonDecode` turns `1e400` into infinity) plus
/// those only a host `Map` can carry (NaN).
const Map<String, double> jsonHostileNumbers = {
  '1e300': 1e300,
  '-1e300': -1e300,
  'Infinity (1e400 in JSON)': double.infinity,
  '-Infinity (-1e400 in JSON)': double.negativeInfinity,
  '1e-300': 1e-300,
};

const Map<String, double> dataHostileNumbers = {
  ...jsonHostileNumbers,
  'NaN': double.nan,
};

/// [tree] with every number replaced by [value] — or only the numbers under a key in [keys].
Object? replaceNumbers(Object? tree, double value, {Set<String>? keys, String? key}) {
  if (tree is Map) {
    return {
      for (final e in tree.entries) e.key: replaceNumbers(e.value, value, keys: keys, key: e.key as String),
    };
  }
  if (tree is List) return [for (final item in tree) replaceNumbers(item, value, keys: keys, key: key)];
  if (tree is num && (keys == null || keys.contains(key))) return value;
  return tree;
}

/// Every map key that holds a number somewhere in [tree].
Set<String> numericKeys(Object? tree, [String? key, Set<String>? into]) {
  final keys = into ?? <String>{};
  if (tree is Map) {
    for (final e in tree.entries) {
      numericKeys(e.value, e.key as String, keys);
    }
  } else if (tree is List) {
    for (final item in tree) {
      numericKeys(item, key, keys);
    }
  } else if (tree is num && key != null) {
    keys.add(key);
  }
  return keys;
}

Map<String, Object?> decodeObject(String source) => (jsonDecode(source) as Map).cast<String, Object?>();

/// Collects every `debugPrint` line while [body] runs.
Future<List<String>> captureDebugPrint(Future<void> Function() body) async {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

/// Fails the test with every exception the framework caught, not only the first one.
void expectNoException(WidgetTester tester, String reason) {
  final errors = <Object>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    errors.add(e);
  }
  expect(errors, isEmpty, reason: reason);
}

/// One request as the network saw it.
final class SeenRequest {
  SeenRequest(this.method, this.url);

  final String method;
  final Uri url;
  final Map<String, List<String>> headers = {};
  final List<Cookie> cookies = [];
  bool followRedirects = true;
  int maxRedirects = 5;

  /// Bytes of the response body the client pulled.
  int bytesPulled = 0;
}

/// What the fake network answers: status and a body of [length] bytes, made on demand
/// (so a "huge" body costs nothing until somebody reads it), with an honest or a lying
/// `Content-Length`.
typedef FakeBody = ({int status, int length, int? declaredLength, List<int> Function()? bytes});

FakeBody fakeBytes(List<int> bytes, {int status = 200}) =>
    (status: status, length: bytes.length, declaredLength: bytes.length, bytes: () => bytes);

FakeBody fakeHuge(int length, {int? declaredLength}) =>
    (status: 200, length: length, declaredLength: declaredLength, bytes: null);

/// A network faked at the `dart:io` level that records method, headers, cookies, the redirect
/// setting and how much of each body was read. Everything not in [replies] is a 404.
final class RecordingHttp extends HttpOverrides {
  RecordingHttp(this.replies);

  final Map<String, FakeBody> replies;
  final List<SeenRequest> requests = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _RecClient(this);
}

RecordingHttp installRecordingHttp(Map<String, FakeBody> replies) {
  final previous = HttpOverrides.current;
  final fake = RecordingHttp(replies);
  HttpOverrides.global = fake;
  addTearDown(() => HttpOverrides.global = previous);
  return fake;
}

class _RecClient implements HttpClient {
  _RecClient(this._net);

  final RecordingHttp _net;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final seen = SeenRequest(method, url);
    _net.requests.add(seen);
    return _RecRequest(_net, seen);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecRequest implements HttpClientRequest {
  _RecRequest(this._net, this._seen) : headers = _RecHeaders(_seen.headers);

  final RecordingHttp _net;
  final SeenRequest _seen;

  @override
  final HttpHeaders headers;

  @override
  List<Cookie> get cookies => _seen.cookies;

  @override
  bool get followRedirects => _seen.followRedirects;

  @override
  set followRedirects(bool value) => _seen.followRedirects = value;

  @override
  int get maxRedirects => _seen.maxRedirects;

  @override
  set maxRedirects(int value) => _seen.maxRedirects = value;

  @override
  Uri get uri => _seen.url;

  @override
  String get method => _seen.method;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    final reply = _net.replies[_seen.url.toString()] ?? fakeBytes(utf8.encode('Not Found'), status: 404);
    return _RecResponse(reply, _seen);
  }

  @override
  Future<HttpClientResponse> get done => Completer<HttpClientResponse>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecResponse extends Stream<List<int>> implements HttpClientResponse {
  _RecResponse(this._reply, this._seen);

  final FakeBody _reply;
  final SeenRequest _seen;

  @override
  int get statusCode => _reply.status;

  @override
  String get reasonPhrase => '';

  @override
  int get contentLength => _reply.declaredLength ?? -1;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _RecHeaders({});

  Stream<List<int>> _body() async* {
    final whole = _reply.bytes;
    if (whole != null) {
      final bytes = whole();
      _seen.bytesPulled += bytes.length;
      yield bytes;
      return;
    }
    const chunk = 1 << 16;
    final zeros = Uint8List(chunk);
    for (var sent = 0; sent < _reply.length; sent += chunk) {
      final n = math.min(chunk, _reply.length - sent);
      _seen.bytesPulled += n;
      yield n == chunk ? zeros : Uint8List(n);
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body().listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  Future<Socket> detachSocket() => throw UnsupportedError('fake');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecHeaders implements HttpHeaders {
  _RecHeaders(this._into);

  final Map<String, List<String>> _into;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) => _into[name.toLowerCase()] = ['$value'];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_into[name.toLowerCase()] ??= []).add('$value');

  @override
  List<String>? operator [](String name) => _into[name.toLowerCase()];

  @override
  String? value(String name) => _into[name.toLowerCase()]?.join(',');

  @override
  void forEach(void Function(String name, List<String> values) action) => _into.forEach(action);

  @override
  ContentType? get contentType => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
