import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart'
    show DocumentTooLargeException;
import 'package:hotlayout_flutter/src/placements/placement_map.dart'
    show kMaxPlacements, kPlacementNameMax, kPlacementsMaxBytes;

import 'support/fixtures.dart';
import 'support/network.dart';

/// The artifact copy, the source (the network, the ETag, the fallbacks) and the widget.

String _map(Map<String, Object?> places) =>
    jsonEncode({'placementsVersion': '1.0.0', 'placements': places});

final class _FakePlacementTransport implements PlacementTransport {
  _FakePlacementTransport(this.respond);

  Future<PlacementResponse> Function(Uri url, String? ifNoneMatch) respond;
  final List<({Uri url, String? ifNoneMatch})> requests = [];

  @override
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch}) {
    requests.add((url: url, ifNoneMatch: ifNoneMatch));
    return respond(url, ifNoneMatch);
  }
}

PlacementResponse _ok(String body, {String? etag}) =>
    (statusCode: 200, body: body, etag: etag);

final class _MemoryStore implements PlacementMapStore {
  _MemoryStore([this.text]);
  String? text;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String value) async => text = value;
}

void main() {
  final base = Uri.parse('https://example.test/orgs/o1/projects/p1');

  group('the artifact copy', () {
    final artifact =
        jsonDecode(File('assets/contract/placements.json').readAsStringSync())
            as Map<String, Object?>;

    test('the version and the limits mirror the artifact', () {
      expect(artifact['x-placementsVersion'], kPlacementsContractVersion);
      final limits = artifact['x-limits']! as Map<String, Object?>;
      expect(limits['maxPlacements'], kMaxPlacements);
      expect(limits['maxBytes'], kPlacementsMaxBytes);
      final name = limits['name']! as Map<String, Object?>;
      expect(name['maxLength'], kPlacementNameMax);
      // The name pattern of the artifact accepts and rejects what `isPlacementName` does.
      final pattern = RegExp(name['pattern']! as String);
      for (final candidate in [
        'home.banner',
        'promo.raffle-button',
        'a',
        'Home',
        'a..b',
        '',
        '__proto__',
        'a.b c',
      ]) {
        expect(
          isPlacementName(candidate),
          pattern.hasMatch(candidate) && candidate.length <= kPlacementNameMax,
          reason: candidate,
        );
      }
    });

    test('the reading policy is the one the reader implements', () {
      expect(
        artifact['x-placementReading'],
        containsPair('keyLookup', 'own-keys-only'),
      );
      expect(
        artifact['x-placementSource'],
        containsPair('rememberOnlyFreshNetwork', true),
      );
      expect(
        artifact['x-placementShowing'],
        containsPair('entryMissing', 'use-initial-and-tell-host'),
      );
    });
  });

  group('addresses', () {
    test('a plain folder', () {
      expect(
        placementFileUrl(base, 'placements/published.json').toString(),
        'https://example.test/orgs/o1/projects/p1/placements/published.json',
      );
      expect(
        placementFileUrl(
          Uri.parse('https://example.test/p/'),
          'documents/d1/published.json',
        ).toString(),
        'https://example.test/p/documents/d1/published.json',
      );
    });

    test('a storage object folder', () {
      final storage = Uri.parse(
        'https://storage.test/v0/b/bkt/o/orgs%2Fo1%2Fprojects%2Fp1',
      );
      expect(
        placementFileUrl(storage, 'documents/d1/published.json').toString(),
        'https://storage.test/v0/b/bkt/o/orgs%2Fo1%2Fprojects%2Fp1%2Fdocuments%2Fd1%2Fpublished.json?alt=media',
      );
    });
  });

  group('PlacementSource', () {
    PlacementSource source(
      _FakePlacementTransport transport, {
      String? bundled,
      PlacementMapStore? store,
    }) => PlacementSource(
      projectBase: base,
      name: 'home.banner',
      transport: transport,
      bundledMap: bundled,
      store: store,
    );

    final published = _map({
      'home.banner': {'documentId': 'd1', 'entry': 'raffle'},
    });

    test('a fresh map gives the document source and the entry', () async {
      final transport = _FakePlacementTransport(
        (_, _) async => _ok(published, etag: '"v1"'),
      );
      final load = await source(transport).refresh();
      expect(load.mapStatus, PlacementSourceStatus.fresh);
      expect(load.mapSource, PlacementMapSource.network);
      expect(load.resolution.status, PlacementStatus.document);
      expect(load.entry, 'raffle');
      expect(
        load.documentSource!.url.toString(),
        'https://example.test/orgs/o1/projects/p1/documents/d1/published.json',
      );
      expect(
        transport.requests.single.url.path,
        '/orgs/o1/projects/p1/placements/published.json',
      );
      expect(transport.requests.single.ifNoneMatch, isNull);
    });

    test('the second poll sends the ETag, and a 304 keeps the map', () async {
      final transport = _FakePlacementTransport(
        (_, etag) async => etag == '"v1"'
            ? (statusCode: 304, body: '', etag: null)
            : _ok(published, etag: '"v1"'),
      );
      final s = source(transport);
      await s.refresh();
      final again = await s.refresh();
      expect(transport.requests.last.ifNoneMatch, '"v1"');
      expect(again.mapStatus, PlacementSourceStatus.fresh);
      expect(again.mapSource, PlacementMapSource.lastKnown);
      expect(again.resolution.documentId, 'd1');
    });

    test(
      'a silent network keeps the last known map; it is "offline", not "corrupt"',
      () async {
        var fail = false;
        final transport = _FakePlacementTransport((_, _) async {
          if (fail) throw const SocketException('no route');
          return _ok(published);
        });
        final s = source(transport);
        await s.refresh();
        fail = true;
        final load = await s.refresh();
        expect(load.mapStatus, PlacementSourceStatus.offline);
        expect(load.mapSource, PlacementMapSource.lastKnown);
        expect(load.resolution.documentId, 'd1');
      },
    );

    test('a timeout is offline', () async {
      final transport = _FakePlacementTransport(
        (_, _) => Completer<PlacementResponse>().future,
      );
      final s = PlacementSource(
        projectBase: base,
        name: 'home.banner',
        transport: transport,
        timeout: const Duration(milliseconds: 20),
        bundledMap: published,
      );
      final load = await s.refresh();
      expect(load.mapStatus, PlacementSourceStatus.offline);
      expect(load.mapSource, PlacementMapSource.bundled);
    });

    test(
      'only a fresh map is remembered: garbage does not replace it',
      () async {
        var body = published;
        final transport = _FakePlacementTransport((_, _) async => _ok(body));
        final store = _MemoryStore();
        final s = source(transport, store: store);
        await s.refresh();
        expect(store.text, published);
        body = '<html>proxy error</html>';
        final load = await s.refresh();
        expect(load.mapStatus, PlacementSourceStatus.corrupt);
        expect(load.mapSource, PlacementMapSource.lastKnown);
        expect(store.text, published);
        expect(s.lastKnownMap, published);
      },
    );

    test('the stored map of the previous launch is the floor', () async {
      final transport = _FakePlacementTransport(
        (_, _) async => throw const SocketException('offline'),
      );
      final load = await source(
        transport,
        store: _MemoryStore(published),
      ).refresh();
      expect(load.mapSource, PlacementMapSource.lastKnown);
      expect(load.resolution.documentId, 'd1');
      expect(
        transport.requests.single.ifNoneMatch,
        isNull,
        reason: 'no ETag survives a restart',
      );
    });

    test('404 with nothing to fall back on: every place is unknown', () async {
      final transport = _FakePlacementTransport(
        (_, _) async => (statusCode: 404, body: '', etag: null),
      );
      final load = await source(transport).refresh();
      expect(load.mapStatus, PlacementSourceStatus.notPublished);
      expect(load.resolution.status, PlacementStatus.unknown);
      expect(load.documentSource, isNull);
    });

    test(
      'offline with nothing to fall back on: the place is unreadable',
      () async {
        final transport = _FakePlacementTransport(
          (_, _) async => (statusCode: 503, body: '', etag: null),
        );
        final load = await source(transport).refresh();
        expect(load.mapStatus, PlacementSourceStatus.offline);
        expect(load.resolution.status, PlacementStatus.unreadable);
      },
    );

    test('a body larger than any map is not a map', () async {
      final transport = _FakePlacementTransport(
        (_, _) async => throw const DocumentTooLargeException(1),
      );
      final load = await source(transport, bundled: published).refresh();
      expect(load.mapStatus, PlacementSourceStatus.corrupt);
      expect(load.mapSource, PlacementMapSource.bundled);
    });

    test('a hostile name asks nothing of the folder: unknown', () async {
      final transport = _FakePlacementTransport((_, _) async => _ok(published));
      final s = PlacementSource(
        projectBase: base,
        name: '__proto__',
        transport: transport,
      );
      final load = await s.refresh();
      expect(load.resolution.status, PlacementStatus.unknown);
      expect(load.documentSource, isNull);
    });
  });

  group('PlacementDocumentSource', () {
    PlacementDocumentSource documentSource(DocumentTransport transport) =>
        PlacementDocumentSource(
          url: Uri.parse('https://example.test/d.json'),
          documentId: 'd1',
          transport: transport,
        );

    test('reads a document', () async {
      final load = await documentSource(
        FakeDocumentTransport.replying(200, readFixture('minimal-screen')),
      ).load();
      expect(load.isFallback, isFalse);
    });

    test('404 is missing; everything else is unreadable', () async {
      Future<PlacementDocumentException> failure(DocumentTransport t) async {
        try {
          await documentSource(t).load();
        } on PlacementDocumentException catch (e) {
          return e;
        }
        fail('did not throw');
      }

      expect(
        (await failure(FakeDocumentTransport.replying(404, ''))).missing,
        isTrue,
      );
      expect(
        (await failure(FakeDocumentTransport.replying(500, ''))).missing,
        isFalse,
      );
      expect(
        (await failure(FakeDocumentTransport.replying(200, 'nope'))).missing,
        isFalse,
      );
      expect(
        (await failure(
          FakeDocumentTransport.failing(const SocketException('x')),
        )).missing,
        isFalse,
      );
    });
  });

  group('HotlayoutPlacement', () {
    final documentText = readFixture('rewards-showcase-screens');
    final documentId =
        (jsonDecode(documentText) as Map)['documentId'] as String;
    final entryPoints =
        ((jsonDecode(documentText) as Map)['entryPoints'] as Map).keys
            .cast<String>()
            .toList();

    Future<List<(String, PlacementReport)>> pump(
      WidgetTester tester, {
      required String mapText,
      required DocumentTransport documents,
    }) async {
      final told = <(String, PlacementReport)>[];
      final src = PlacementSource(
        projectBase: base,
        name: 'home.banner',
        transport: _FakePlacementTransport((_, _) async => _ok(mapText)),
        documentTransport: documents,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: HotlayoutPlacement.fromSource(
              source: src,
              theme: RenderTheme.fallback(),
              data: const {},
              refreshInterval: null,
              onPlacement: (name, report) => told.add((name, report)),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      return told;
    }

    testWidgets('draws the document of the place', (tester) async {
      final told = await pump(
        tester,
        mapText: _map({
          'home.banner': {'documentId': documentId, 'entry': entryPoints.first},
        }),
        documents: FakeDocumentTransport.replying(200, documentText),
      );
      expect(
        tester.getSize(find.byType(HotlayoutPlacement)).height,
        greaterThan(0),
      );
      expect(told, isEmpty);
    });

    testWidgets(
      'an entry the document lacks: drawn from the first screen, the host is told',
      (tester) async {
        final told = await pump(
          tester,
          mapText: _map({
            'home.banner': {'documentId': documentId, 'entry': 'gone'},
          }),
          documents: FakeDocumentTransport.replying(200, documentText),
        );
        expect(
          tester.getSize(find.byType(HotlayoutPlacement)).height,
          greaterThan(0),
        );
        expect(told, [('home.banner', PlacementReport.entryMissing)]);
      },
    );

    for (final (label, mapText, report) in [
      (
        'empty',
        _map({
          'home.banner': {'documentId': null},
        }),
        PlacementReport.empty,
      ),
      (
        'unknown',
        _map({
          'other.place': {'documentId': 'd1'},
        }),
        PlacementReport.unknown,
      ),
      (
        'unreadable',
        _map({
          'home.banner': {'documentId': '../x'},
        }),
        PlacementReport.unreadable,
      ),
    ]) {
      testWidgets('$label: draws nothing and tells the host once', (
        tester,
      ) async {
        final told = await pump(
          tester,
          mapText: mapText,
          documents: FakeDocumentTransport.replying(200, documentText),
        );
        expect(tester.getSize(find.byType(HotlayoutPlacement)), Size.zero);
        expect(told, [('home.banner', report)]);
      });
    }

    testWidgets('a document that is gone draws nothing and tells the host', (
      tester,
    ) async {
      final told = await pump(
        tester,
        mapText: _map({
          'home.banner': {'documentId': 'gone'},
        }),
        documents: FakeDocumentTransport.replying(404, ''),
      );
      expect(tester.getSize(find.byType(HotlayoutPlacement)), Size.zero);
      expect(told, [('home.banner', PlacementReport.documentMissing)]);
    });

    testWidgets(
      'a document that cannot be read draws nothing and tells the host',
      (tester) async {
        final told = await pump(
          tester,
          mapText: _map({
            'home.banner': {'documentId': 'd1'},
          }),
          documents: FakeDocumentTransport.replying(
            200,
            '{"not":"a document"}',
          ),
        );
        expect(tester.getSize(find.byType(HotlayoutPlacement)), Size.zero);
        expect(told, [('home.banner', PlacementReport.documentUnreadable)]);
      },
    );
  });
}
