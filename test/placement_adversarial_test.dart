// Adversarial pass over placements: the placement map and the documents it names come from the
// network, so they are untrusted input.
//
// The `findings` group states what once did not hold and now does; the `guards` group holds paths
// around the claims that were tried and did not work.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/placements/placement_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fixtures.dart';
import 'support/network.dart';
import 'support/placement_bytes.dart';

String _map(Map<String, Object?> places) => jsonEncode({'placementsVersion': '1.0.0', 'placements': places});

final class _Transport implements PlacementTransport {
  _Transport(this.respond);

  Future<PlacementResponse> Function(Uri url) respond;
  final List<Uri> requests = [];

  @override
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch}) {
    requests.add(url);
    return respond(url);
  }
}

final class _Store implements PlacementMapStore {
  _Store([this.text]);
  String? text;

  @override
  Future<String?> read(String key) async => text;

  @override
  Future<void> write(String key, String value) async => text = value;
}

PlacementResponse _ok(String body) => (statusCode: 200, body: bytesOf(body), etag: null);

void main() {
  final base = Uri.parse('https://example.test/orgs/o1/projects/p1');
  const hugeMajor = '{"placementsVersion":"99999999999999999999.0.0","placements":{}}';

  group('findings', () {
    test(
      'a major too big for an int is "unsupported", as in the reference, not a thrown FormatException',
      () {
        expect(readPlacementMapText(hugeMajor), isA<PlacementMapUnsupported>());
      },
    );

    test(
      'a hostile version on the network still falls back to the last known map instead of throwing out of refresh()',
      () async {
        final source = PlacementSource(
          projectBase: base,
          name: 'home.banner',
          transport: _Transport((_) async => _ok(hugeMajor)),
          store: _Store(
            _map({
              'home.banner': {'documentId': null},
            }),
          ),
        );
        final load = await source.refresh();
        expect(load.mapStatus, PlacementSourceStatus.unsupported);
        expect(load.mapSource, PlacementMapSource.lastKnown);
        expect(load.resolution.status, PlacementStatus.empty);
      },
    );

    test(
      'the same hostile version in the BUNDLED copy does not throw either',
      () {
        expect(() => pickPlacementMap(network: const PlacementNetworkOffline(), bundled: hugeMajor), returnsNormally);
      },
    );

    testWidgets('the default constructor keeps its source across parent rebuilds', (tester) async {
      // The test binding answers every request with 400, so the placement settles on "unreadable".
      // A rebuild with the same name and project must not start over: the host hears that once.
      final events = <PlacementEvent>[];
      Widget host(String name) => Directionality(
        textDirection: TextDirection.ltr,
        child: HotlayoutPlacement(
          name: name,
          projectBase: base,
          theme: RenderTheme.fallback(),
          data: const {},
          refreshInterval: null,
          onPlacementEvent: (_, event) => events.add(event),
        ),
      );
      await tester.pumpWidget(host('home.banner'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpWidget(host('home.banner'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpWidget(host('home.banner'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(events.length, 1);
      // Another name is another place: it is read again and told again.
      await tester.pumpWidget(host('profile.top'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(events.length, 2);
    });

    testWidgets(
      'a source swapped while a refresh is in flight still ends with the document on screen',
      (tester) async {
        final documentText = readFixture('rewards-showcase-screens');
        final documentId = (jsonDecode(documentText) as Map)['documentId'] as String;
        final gate = Completer<void>();
        final transport = _Transport((_) async {
          await gate.future;
          return _ok(
            _map({
              'home.banner': {'documentId': documentId},
            }),
          );
        });
        PlacementSource make() => PlacementSource(
          projectBase: base,
          name: 'home.banner',
          transport: transport,
          documentTransport: FakeDocumentTransport.replying(200, documentText),
        );
        Widget host(PlacementSource source) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: HotlayoutPlacement.fromSource(
              source: source,
              theme: RenderTheme.fallback(),
              data: const {},
              refreshInterval: null,
            ),
          ),
        );
        await tester.pumpWidget(host(make()));
        // The parent rebuilds (as the default constructor always does) before the first answer.
        await tester.pumpWidget(host(make()));
        gate.complete();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        expect(tester.getSize(find.byType(HotlayoutPlacement)).height, greaterThan(0));
      },
    );
  });

  group('guards', () {
    const escapes = [
      '..',
      '.',
      '...',
      '%2e%2e',
      '%2F',
      'a/b',
      r'a\b',
      '//evil.test',
      'https://evil.test/x',
      'd?x=1',
      'd#x',
      '．．',
      'ｄ1',
      'd\n',
      '\nd',
      ' d',
      'd ',
      'd\u0000',
      'd​',
      '',
    ];
    for (final id in escapes) {
      test('documentId ${jsonEncode(id)} never becomes a request', () async {
        final transport = _Transport(
          (_) async => _ok(
            _map({
              'home.banner': {'documentId': id},
            }),
          ),
        );
        final load = await PlacementSource(projectBase: base, name: 'home.banner', transport: transport).refresh();
        expect(load.resolution.status, PlacementStatus.unreadable);
        expect(load.documentSource, isNull);
      });
    }

    test('a document address built from a legal id stays under the project base', () async {
      for (final id in ['..a', 'a..', '.a', 'a.b', '_', '-', 'A' * 64]) {
        final transport = _Transport(
          (_) async => _ok(
            _map({
              'home.banner': {'documentId': id},
            }),
          ),
        );
        final load = await PlacementSource(projectBase: base, name: 'home.banner', transport: transport).refresh();
        final url = load.documentSource!.url;
        expect(url.host, 'example.test');
        expect(url.path, '/orgs/o1/projects/p1/documents/$id/published.json');
        expect(url.pathSegments, isNot(contains('..')));
      }
    });

    test('__proto__ and constructor are only what the map says', () {
      final map = readPlacementMapText(
        '{"placementsVersion":"1.0.0","placements":{"__proto__":{"documentId":"x"},"constructor":{"documentId":"c"}}}',
      );
      expect(resolvePlacement(map, '__proto__').status, PlacementStatus.unknown);
      expect(resolvePlacement(map, 'constructor').documentId, 'c');
      expect(resolvePlacement(readPlacementMapText(_map({})), 'constructor').status, PlacementStatus.unknown);
    });

    test('version strings that are not MAJOR.MINOR.PATCH are corrupt', () {
      for (final version in [
        '01.0.0',
        '1.0.0-x',
        '1.0.0+b',
        '1.0',
        ' 1.0.0',
        '1.0.0 ',
        '1.0.0\n',
        'v1.0.0',
        '١.0.0',
        '',
      ]) {
        expect(
          readPlacementMapText(jsonEncode({'placementsVersion': version, 'placements': {}})),
          isA<PlacementMapCorrupt>(),
          reason: version,
        );
      }
    });

    test('duplicate keys: the last one wins', () {
      final map = readPlacementMapText(
        '{"placementsVersion":"1.0.0","placements":{"home.banner":{"documentId":"a"},"home.banner":{"documentId":null}}}',
      );
      expect(resolvePlacement(map, 'home.banner').status, PlacementStatus.empty);
    });

    test('deep JSON inside the size cap is corrupt and never reaches the parser', () {
      const depth = 100000;
      final text = '{"placementsVersion":"1.0.0","placements":{},"x":${'[' * depth}${']' * depth}}';
      expect(readPlacementMapText(text), isA<PlacementMapCorrupt>());
    });

    test('a corrupt, another-major or 404 answer never overwrites the last known map', () async {
      final good = _map({
        'home.banner': {'documentId': null},
      });
      for (final response in <PlacementResponse>[
        _ok('<html>'),
        _ok('{"placementsVersion":"2.0.0","placements":{}}'),
        (statusCode: 404, body: noBytes, etag: null),
        (statusCode: 304, body: noBytes, etag: null),
      ]) {
        final store = _Store(good);
        final load = await PlacementSource(
          projectBase: base,
          name: 'home.banner',
          transport: _Transport((_) async => response),
          store: store,
        ).refresh();
        expect(store.text, good);
        expect(load.resolution.status, PlacementStatus.empty);
      }
    });

    test('a body larger than any map is cut and read as corrupt, not held in memory', () async {
      final transport = HttpPlacementTransport(
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(Stream.value(List.filled(300000, 0x20)), 200),
        ),
      );
      final load = await PlacementSource(projectBase: base, name: 'home.banner', transport: transport).refresh();
      expect(load.mapStatus, PlacementSourceStatus.corrupt);
    });

    test('a body with one UTF-8 byte order mark is a map', () async {
      final bytes = [
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(
          _map({
            'home.banner': {'documentId': null},
          }),
        ),
      ];
      final transport = HttpPlacementTransport(client: MockClient((_) async => http.Response.bytes(bytes, 200)));
      final load = await PlacementSource(projectBase: base, name: 'home.banner', transport: transport).refresh();
      expect(load.mapStatus, PlacementSourceStatus.fresh);
    });

    test('a body that is not UTF-8 is a corrupt map, not "no answer"', () async {
      final bytes = [...utf8.encode('{"placementsVersion":"1.0.0","x":"'), 0xff, ...utf8.encode('","placements":{}}')];
      final transport = HttpPlacementTransport(client: MockClient((_) async => http.Response.bytes(bytes, 200)));
      final load = await PlacementSource(projectBase: base, name: 'home.banner', transport: transport).refresh();
      expect(load.mapStatus, PlacementSourceStatus.corrupt);
    });
  });
}
