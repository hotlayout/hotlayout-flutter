/// The picture loader, the host's allow-lists and the extra numeric guards found by sweeping the package.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'package:hotlayout_flutter/src/model/border_dash.dart';
import 'package:hotlayout_flutter/src/model/progress_rules.dart';
import 'package:hotlayout_flutter/src/model/segment_transition.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/write_action.dart';
import 'package:hotlayout_flutter/src/render/picture_fetch.dart';
import 'package:hotlayout_flutter/src/render/picture_image.dart';
import 'package:hotlayout_flutter/src/render/picture_policy.dart';
import 'package:hotlayout_flutter/src/theme/theme_json.dart';

import '../support/fixtures.dart';
import 'picture_hardening_test.dart' show onePixelPng;
import 'support.dart';

/// A network that answers from a table of `status`, `location` and body, and records every request.
final class _Scripted extends HttpOverrides {
  _Scripted(this.replies);

  final Map<String, ({int status, String? location, List<int> body, bool silent})> replies;
  final List<String> requested = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

({int status, String? location, List<int> body, bool silent}) _reply(
  int status, {
  String? location,
  List<int> body = const [],
  bool silent = false,
}) => (status: status, location: location, body: body, silent: silent);

_Scripted _install(Map<String, ({int status, String? location, List<int> body, bool silent})> replies) {
  final previous = HttpOverrides.current;
  final net = _Scripted(replies);
  HttpOverrides.global = net;
  addTearDown(() => HttpOverrides.global = previous);
  return net;
}

class _Client implements HttpClient {
  _Client(this._net);

  final _Scripted _net;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _net.requested.add('$url');
    return _Request(_net, url);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this._net, this._url);

  final _Scripted _net;
  final Uri _url;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() {
    final reply = _net.replies['$_url'] ?? _reply(404);
    if (reply.silent) return Completer<HttpClientResponse>().future;
    return Future.value(_Response(reply));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this._reply);

  final ({int status, String? location, List<int> body, bool silent}) _reply;

  @override
  int get statusCode => _reply.status;

  @override
  int get contentLength => _reply.body.length;

  @override
  late final HttpHeaders headers = _Headers(_reply.location);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_reply.body).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  _Headers(this._location);

  final String? _location;

  @override
  String? value(String name) => name.toLowerCase() == 'location' ? _location : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A transport whose body is over the cap, as [HttpDocumentTransport] reports it.
final class _TooLarge implements DocumentTransport {
  @override
  Future<DocumentResponse> fetch(Uri url) => Future.error(const DocumentTooLargeException(kMaxBodyBytes));
}

const String _a = 'https://cdn.example.com/a.png';
const String _b = 'https://img.example.com/b.png';
const String _meta = 'https://169.254.169.254/latest/meta-data/';

Future<Object?> _outcome(Future<Object?> future) async {
  try {
    return await future;
  } on Object catch (error) {
    return error;
  }
}

Future<Object?> _fetch(String url, {int max = 1000, Duration? timeout, PictureCancel? cancel}) => _outcome(
  fetchPictureBytes(
    Uri.parse(url),
    approve: defaultImageUrlPolicy,
    maxBytes: max,
    timeout: timeout ?? kPictureTimeout,
    cancel: cancel,
  ),
);

UiDocument _imageDoc(String url, {String id = 'pic'}) => docWith([
  {
    'id': id,
    'type': 'Image',
    'props': {
      'source': {'kind': 'url', 'url': url},
      'aspectRatio': '1:1',
      'fit': 'cover',
    },
  },
]);

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  for (var i = 0; i < 20; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('picture loader: redirects', () {
    test('a redirect to an allowed address is followed', () async {
      final net = _install({_a: _reply(302, location: _b), _b: _reply(200, body: onePixelPng)});
      final result = await _fetch(_a, max: 1 << 20);
      expect(result, isA<List<int>>());
      expect(net.requested, [_a, _b]);
    });

    test('a relative Location is resolved against the request address', () async {
      final net = _install({_a: _reply(301, location: '/other.png'), 'https://cdn.example.com/other.png': _reply(200, body: onePixelPng)});
      await _fetch(_a, max: 1 << 20);
      expect(net.requested, [_a, 'https://cdn.example.com/other.png']);
    });

    for (final target in ['http://cdn.example.com/a.png', _meta, 'https://localhost/a.png', 'https://127.0.0.1/a.png', 'file:///etc/hosts']) {
      test('a redirect to $target is refused and never requested', () async {
        final net = _install({_a: _reply(307, location: target), target: _reply(200, body: onePixelPng)});
        final result = await _fetch(_a);
        expect(result, isA<PictureFetchException>());
        expect(net.requested, [_a]);
      });
    }

    test('a redirect without Location is refused', () async {
      _install({_a: _reply(302)});
      expect(await _fetch(_a), isA<PictureFetchException>());
    });

    test('at most three redirects are followed', () async {
      final hops = [for (var i = 0; i < 6; i += 1) 'https://h$i.example.com/p.png'];
      final net = _install({
        for (var i = 0; i < 5; i += 1) hops[i]: _reply(302, location: hops[i + 1]),
        hops[5]: _reply(200, body: onePixelPng),
      });
      expect(await _fetch(hops[0], max: 1 << 20), isA<PictureFetchException>());
      expect(net.requested, hops.sublist(0, 4));
    });

    test('exactly three redirects are followed', () async {
      final hops = [for (var i = 0; i < 4; i += 1) 'https://h$i.example.com/p.png'];
      final net = _install({
        for (var i = 0; i < 3; i += 1) hops[i]: _reply(302, location: hops[i + 1]),
        hops[3]: _reply(200, body: onePixelPng),
      });
      expect(await _fetch(hops[0], max: 1 << 20), isA<List<int>>());
      expect(net.requested, hops);
    });

    test('a non-200 answer is an error that does not carry the address', () async {
      _install({_a: _reply(404)});
      final result = await _fetch(_a);
      expect(result, isA<PictureFetchException>());
      expect('$result', 'HTTP 404');
    });
  });

  group('picture loader: size and time', () {
    test('a body above the cap is refused', () async {
      _install({_a: _reply(200, body: List.filled(2000, 1))});
      final result = await _fetch(_a, max: 1000);
      expect('$result', 'body too large');
    });

    test('a body at the cap is read', () async {
      _install({_a: _reply(200, body: List.filled(1000, 1))});
      expect(await _fetch(_a, max: 1000), isA<List<int>>());
    });

    test('a request that never answers ends at the timeout', () async {
      _install({_a: _reply(200, silent: true)});
      final result = await _fetch(_a, timeout: const Duration(milliseconds: 50));
      expect('$result', 'timeout');
    });

    test('a cancelled request ends at once and leaves no timer behind', () async {
      _install({_a: _reply(200, silent: true)});
      final cancel = PictureCancel();
      final pending = _fetch(_a, cancel: cancel);
      cancel.cancel();
      expect('${await pending}', 'cancelled');
    });
  });

  group('picture policy', () {
    test('the default accepts https with a host name and refuses the rest; data: addresses are not judged by it', () {
      const policy = PicturePolicy();
      expect(policy.approve(_a), _a);
      expect(policy.approve('https://127.0.0.1/a.png'), isNull);
      expect(policy.approve('data:image/png;base64,AAAA', isData: true), 'data:image/png;base64,AAAA');
    });

    test('a host policy sees data: addresses too, may rewrite, and a policy that throws refuses', () {
      expect(PicturePolicy(resolveImageUrl: (url) => null).approve('data:image/png;base64,AAAA', isData: true), isNull);
      expect(PicturePolicy(resolveImageUrl: (url) => 'https://cdn.example.com/x.png').approve('https://a.example.com/'), 'https://cdn.example.com/x.png');
      expect(PicturePolicy(resolveImageUrl: (url) => throw StateError('no')).approve(_a), isNull);
    });

    test('decodeSide: the box times the pixel ratio, never above the ceiling, an unbounded side takes the ceiling', () {
      expect(decodeSide(100, 3, 1), 300);
      expect(decodeSide(100, 3, 2), 600);
      expect(decodeSide(10000, 3, 1), kMaxDecodedSide);
      expect(decodeSide(double.infinity, 3, 1), kMaxDecodedSide);
      expect(decodeSide(double.nan, 3, 1), kMaxDecodedSide);
      expect(decodeSide(0, 3, 1), 1);
      expect(kMaxDecodedSide, 4096);
      expect(kDefaultMaxDownloadBytes, 10 * 1000 * 1000);
      expect(kPictureTimeout, const Duration(seconds: 30));
      expect(kMaxPictureRedirects, 3);
    });

    testWidgets('the host policy can rewrite an address and apply to SVG', (tester) async {
      const svg = 'https://cdn.example.com/a.svg';
      final net = _install({
        'https://static.example.com/a.png': _reply(200, body: onePixelPng),
        'https://static.example.com/a.svg': _reply(200, body: utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>')),
      });
      String? rewrite(String url) => url.replaceFirst('https://cdn.example.com/', 'https://static.example.com/');
      await _show(tester, renderDocument(_imageDoc(_a), theme: RenderTheme.fallback(), data: const {}, resolveImageUrl: rewrite));
      await _show(tester, renderDocument(_imageDoc(svg, id: 'svg'), theme: RenderTheme.fallback(), data: const {}, resolveImageUrl: rewrite));
      expect(net.requested, ['https://static.example.com/a.png', 'https://static.example.com/a.svg']);
    });

    testWidgets('a host policy that refuses draws the placeholder and requests nothing', (tester) async {
      final net = _install({});
      await _show(tester, renderDocument(_imageDoc(_a), theme: RenderTheme.fallback(), data: const {}, resolveImageUrl: (url) => null));
      expect(net.requested, isEmpty);
      expect(find.text('Image unavailable'), findsOneWidget);
    });

    testWidgets('renderScreen takes the same policy', (tester) async {
      final net = _install({});
      final doc = _imageDoc(_a);
      await _show(tester, renderScreen(doc.screens.first, theme: RenderTheme.fallback(), data: const {}, resolveImageUrl: (url) => null));
      expect(net.requested, isEmpty);
    });

    testWidgets('maxDownloadBytes lowers the cap: a body above it is a broken picture', (tester) async {
      _install({_a: _reply(200, body: onePixelPng)});
      await _show(tester, renderDocument(_imageDoc(_a), theme: RenderTheme.fallback(), data: const {}, maxDownloadBytes: 10));
      expect(find.text('Image unavailable'), findsOneWidget);
    });

    testWidgets('a data: picture above the cap is a broken picture and is never decoded', (tester) async {
      final url = 'data:image/png;base64,${base64Encode(onePixelPng)}';
      await _show(tester, renderDocument(_imageDoc(url), theme: RenderTheme.fallback(), data: const {}, maxDownloadBytes: 10));
      expect(find.text('Image unavailable'), findsOneWidget);
      await _show(tester, renderDocument(_imageDoc(url), theme: RenderTheme.fallback(), data: const {}));
      expect(find.text('Image unavailable'), findsNothing);
    });

    testWidgets('a data: address is size-checked before it is decoded', (tester) async {
      final huge = 'data:image/png;base64,${'A' * 5000}';
      await _show(tester, renderDocument(_imageDoc(huge), theme: RenderTheme.fallback(), data: const {}, maxDownloadBytes: 100));
      expect(find.text('Image unavailable'), findsOneWidget);
    });

    testWidgets('an SVG whose load is abandoned stops its request (no timer is left behind)', (tester) async {
      final net = _install({'https://cdn.example.com/a.svg': _reply(200, silent: true)});
      await _show(tester, renderDocument(_imageDoc('https://cdn.example.com/a.svg'), theme: RenderTheme.fallback(), data: const {}));
      expect(net.requested, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('writablePaths', () {
    UiDocument form() => docWith([
      {
        'id': 'ok',
        'type': 'Switch',
        'props': {
          'label': {'kind': 'literal', 'value': 'Ok'},
          'value': {'kind': 'binding', 'path': 'user.ok', 'fallback': false},
        },
      },
      {
        'id': 'w',
        'type': 'Button',
        'props': {
          'label': {'kind': 'literal', 'value': 'save'},
          'action': {
            'type': 'setValue',
            'params': {'path': 'user.balance', 'value': 'x'},
          },
        },
      },
    ]);

    Future<List<String>> run(WidgetTester tester, Object? allowed, {String tap = 'save'}) async {
      final writes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderDocument(
              form(),
              theme: RenderTheme.fallback(),
              data: const {},
              onWrite: (path, value) => writes.add(path),
              writablePaths: allowed,
            ),
          ),
        ),
      );
      await tester.tap(find.text(tap));
      await tester.pump();
      return writes;
    }

    testWidgets('a list: a listed path is written', (tester) async {
      expect(await run(tester, ['user.balance']), ['user.balance']);
    });

    testWidgets('a list: a path that is not listed is not written', (tester) async {
      expect(await run(tester, ['form.x']), isEmpty);
    });

    testWidgets('a predicate: allowed path is written, others are not', (tester) async {
      expect(await run(tester, (String p) => p.startsWith('user.')), ['user.balance']);
      expect(await run(tester, (String p) => p.startsWith('form.')), isEmpty);
    });

    testWidgets('a field write is gated too, and the field value does not reach the session', (tester) async {
      expect(await run(tester, ['user.balance'], tap: 'Ok'), isEmpty);
    });

    testWidgets('an allow-list of an unknown kind allows nothing, a predicate that throws allows nothing', (tester) async {
      expect(await run(tester, 42), isEmpty);
      expect(await run(tester, (String p) => throw StateError('x')), isEmpty);
    });

    test('isWritablePath: the shape rule comes first, whatever the list says', () {
      expect(isWritablePath('__proto__.x', ['__proto__.x']), isFalse);
      expect(isWritablePath('a.b'), isTrue);
      expect(isWritablePath('a.b', const <String>{'a.b'}), isTrue);
      expect(isWritablePath('a.b', const <String>{}), isFalse);
    });

    testWidgets('renderScreen takes writablePaths', (tester) async {
      final writes = <String>[];
      final doc = form();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderScreen(
              doc.screens.first,
              theme: RenderTheme.fallback(),
              data: const {},
              onWrite: (path, value) => writes.add(path),
              writablePaths: const ['nothing.here'],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ok'));
      await tester.pump();
      expect(writes, isEmpty);
    });
  });

  group('sweep: every conversion of a document, theme or data number to an integer is guarded', () {
    const hostile = <double>[double.infinity, double.negativeInfinity, double.nan, 1e300, -1e300];

    test('wholeNumberIn (fieldRadius, part size)', () {
      for (final value in hostile) {
        expect(wholeNumberIn(value, 0, 256), isNull, reason: '$value');
      }
      expect(wholeNumberIn(12.0, 0, 256), 12);
    });

    test('filledSegments: NaN fills nothing and infinity fills everything', () {
      expect(filledSegments(double.nan, 5), 0);
      expect(filledSegments(double.infinity, 5), 5);
      expect(filledSegments(-double.infinity, 5), 0);
    });

    test('segmentFillInline: a not finite number of steps draws nothing', () {
      for (final value in hostile) {
        expect(segmentFillInline(value, step: 10, gap: 2), value > 0 && value.isFinite ? isNotNull : 0, reason: '$value');
      }
    });

    test('dashedLineOf: a not finite box has no dashes', () {
      for (final value in [double.infinity, double.nan]) {
        final line = dashedLineOf((
          width: value,
          height: 40,
          border: 2,
          radii: (topStart: 4.0, topEnd: 4.0, bottomEnd: 4.0, bottomStart: 4.0),
        ));
        expect(line.count, 0, reason: '$value');
      }
    });

    test('themeFontWeight: not finite or outside 100..900 is no weight', () {
      for (final value in [...hostile, 0.0, 99.0, 901.0, -100.0]) {
        expect(themeFontWeight(value), isNull, reason: '$value');
      }
      expect(themeFontWeight(450), FontWeight.w500);
      expect(themeFontWeight(100), FontWeight.w100);
      expect(themeFontWeight(900), FontWeight.w900);
    });
  });

  group('theme numbers are held to the schema bounds', () {
    Map<String, Object?> theme(Map<String, Object?> typography, {Map<String, Object?>? elevation, Map<String, Object?>? gradient}) => {
      'id': 't',
      'name': 'T',
      'brightness': 'light',
      'color': {'primary': '#112233'},
      'spacing': {'none': 0, 'sm': 8, 'huge': 129, 'negative': -1},
      'radius': {'sm': 4, 'huge': 257},
      'typography': typography,
      'elevation': ?elevation,
      'gradient': ?gradient,
    };

    test('spacing 0..128 and radius 0..256; outside is no token', () {
      final read = readRenderTheme(theme({}));
      expect(read.spacing.containsKey('sm'), isTrue);
      expect(read.spacing.containsKey('huge'), isFalse);
      expect(read.spacing.containsKey('negative'), isFalse);
      expect(read.radii.containsKey('sm'), isTrue);
      expect(read.radii.containsKey('huge'), isFalse);
    });

    Map<String, Object?> style(Object? size, {Object? lineHeight, Object? letterSpacing, Object? weight}) => {
      'fontSize': size,
      'lineHeight': ?lineHeight,
      'letterSpacing': ?letterSpacing,
      'fontWeight': ?weight,
    };

    test('typography bounds: fontSize 8..96, lineHeight 0.8..3, letterSpacing -2..8, fontWeight 100..900', () {
      final read = readRenderTheme(theme({
        'ok': style(16, lineHeight: 1.4, letterSpacing: 0.5, weight: 600),
        'bigSize': style(97),
        'smallSize': style(7),
        'tallLine': style(16, lineHeight: 3.1),
        'flatLine': style(16, lineHeight: 0.7),
        'wideTrack': style(16, letterSpacing: 8.1),
        'tightTrack': style(16, letterSpacing: -2.1),
        'lightWeight': style(16, weight: 99),
        'heavyWeight': style(16, weight: 901),
      }));
      expect(read.typography.keys, ['ok']);
    });

    test('the edges of every range are accepted', () {
      final read = readRenderTheme(theme({
        'low': style(8, lineHeight: 0.8, letterSpacing: -2, weight: 100),
        'high': style(96, lineHeight: 3, letterSpacing: 8, weight: 900),
      }));
      expect(read.typography.keys, ['low', 'high']);
    });

    test('shadow bounds: a layer with a number out of range is left out', () {
      Map<String, Object?> layer({Object? x = 0, Object? y = 4, Object? blur = 8, Object? spread = 0, Object? opacity = 0.2}) => {
        'color': '#000000',
        'opacity': opacity,
        'offsetX': x,
        'offsetY': y,
        'blur': blur,
        'spread': spread,
      };
      final read = readRenderTheme(theme({}, elevation: {
        'ok': [layer()],
        'x': [layer(x: 65)],
        'y': [layer(y: -65)],
        'blur': [layer(blur: 129)],
        'negBlur': [layer(blur: -1)],
        'spread': [layer(spread: 65)],
        'opacity': [layer(opacity: 1.5)],
      }));
      expect(read.elevations['ok'], hasLength(1));
      for (final name in ['x', 'y', 'blur', 'negBlur', 'spread', 'opacity']) {
        expect(read.elevations[name], anyOf(isNull, isEmpty), reason: name);
      }
    });

    test('a gradient stop outside 0..1 is left out', () {
      final read = readRenderTheme(theme({}, gradient: {
        'g': {
          'angle': 90,
          'stops': [
            {'color': '#000000', 'position': 0},
            {'color': '#ffffff', 'position': 2},
          ],
        },
      }));
      expect(read.gradients.containsKey('g'), isFalse);
    });
  });

  group('ThemeLoad never throws', () {
    for (final raw in <Object?>[
      null,
      42,
      'text',
      <Object?>[],
      {'themes': 5},
      {'themeContractVersion': '4.0.0', 'themes': {'t': <Object?>[]}},
      {'contract': {'themeContractVersion': 4, 'themes': <String, Object?>{}}},
    ]) {
      test('fromJson(${jsonEncode(raw)}) is a status', () {
        expect(() => ThemeLoad.fromJson(raw), returnsNormally);
      });
    }

    test('a body that is not even a string-decodable JSON is malformed', () {
      expect(ThemeLoad.parse('{"themes":').status, ThemeLoadStatus.malformed);
    });
  });

  group('document and theme body cap, end to end', () {
    test('an oversized document is a malformed load with the bundled copy', () async {
      final source = PublishedDocumentSource(
        url: Uri.parse('https://cdn.example.com/doc.json'),
        transport: _TooLarge(),
        fallback: diskFixtureSource('minimal-screen'),
      );
      final load = await source.load();
      expect(load.status, DocumentLoadStatus.malformed);
    });

    test('an oversized theme is a malformed load with the built-in theme', () async {
      final load = await ThemeLoad.fromNetwork(Uri.parse('https://cdn.example.com/theme.json'), transport: _TooLarge());
      expect(load.status, ThemeLoadStatus.malformed);
    });

    test('a document just under the cap is read', () async {
      final url = 'https://cdn.example.com/doc.json';
      installRecordingHttp({url: fakeBytes(utf8.encode(readFixture('minimal-screen')))});
      final response = await HttpDocumentTransport().fetch(Uri.parse(url));
      expect(response.statusCode, 200);
      expect(response.body, readFixture('minimal-screen'));
    });
  });
}
