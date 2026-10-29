import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/placements/placement_map.dart' show readPlacementMap;
import 'package:hotlayout_flutter/src/placements/placement_schedule.dart' show kPlacementInstantPattern;

import 'support/fixtures.dart';
import 'support/network.dart';
import 'support/placement_bytes.dart';

/// The artifact mirror of the schedule, the pure rules beyond the shared table, the source that
/// decides again without the network, and the widget with a clock and a timer.

final class _Transport implements PlacementTransport {
  _Transport(this.body);

  final String body;
  int requests = 0;

  @override
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch}) async {
    requests++;
    return (statusCode: 200, body: bytesOf(body), etag: null);
  }
}

String _map(Map<String, Object?> places) => jsonEncode({'placementsVersion': '1.1.0', 'placements': places});

void main() {
  final base = Uri.parse('https://example.test/orgs/o1/projects/p1');

  test('the schedule block of the artifact is mirrored', () {
    final artifact = jsonDecode(File('assets/contract/placements.json').readAsStringSync()) as Map<String, Object?>;
    expect(artifact['x-placementsVersion'], kPlacementsContractVersion);
    final schedule = artifact['x-placementSchedule']! as Map<String, Object?>;
    expect(schedule['maxTimerMs'], kPlacementMaxTimerMs);
    expect((schedule['instant']! as Map)['pattern'], kPlacementInstantPattern);
    expect(schedule['clock'], 'device');
    expect(schedule['olderReaders'], 'permanent-only');
  });

  group('placementInstantMs', () {
    test('reads the contract form only', () {
      expect(placementInstantMs('2026-11-27T22:00:00Z'), DateTime.utc(2026, 11, 27, 22).millisecondsSinceEpoch);
      expect(placementInstantMs('2028-02-29T00:00:00Z'), isNotNull);
      for (final bad in [
        '2026-02-29T00:00:00Z',
        '2026-11-27T22:00:00+02:00',
        '2026-11-27T22:00:00.5Z',
        '2026-11-27t22:00:00z',
        '2026-11-27T24:00:00Z',
        '1999-12-31T23:59:59Z',
        '2026-11-27T22:00:00Z\n',
        '',
        null,
        42,
      ]) {
        expect(placementInstantMs(bad), isNull, reason: '$bad');
      }
    });
  });

  group('the rules', () {
    final map = readPlacementMap(jsonDecode(_map({
      'home.banner': {
        'documentId': 'everyday',
        'schedule': [
          {'documentId': 'sale', 'from': '2026-11-01T00:00:00Z', 'until': '2026-11-03T00:00:00Z'},
        ],
      },
    })));

    test('the boundary is the nearest edge after now', () {
      final from = placementInstantMs('2026-11-01T00:00:00Z')!;
      final until = placementInstantMs('2026-11-03T00:00:00Z')!;
      expect(nextPlacementBoundary(map, 'home.banner', from - 1), from);
      expect(nextPlacementBoundary(map, 'home.banner', from), until);
      expect(nextPlacementBoundary(map, 'home.banner', until), isNull);
      expect(nextPlacementBoundary(map, 'other.place', 0), isNull);
    });
  });

  group('PlacementSource', () {
    test('decides again at the clock of now without the network', () async {
      var now = DateTime.utc(2026, 10, 31);
      final transport = _Transport(_map({
        'home.banner': {
          'documentId': null,
          'schedule': [
            {'documentId': 'sale', 'entry': 'main', 'from': '2026-11-01T00:00:00Z', 'until': '2026-11-02T00:00:00Z'},
          ],
        },
      }));
      final source = PlacementSource(projectBase: base, name: 'home.banner', transport: transport, now: () => now);
      expect(source.recompute(), isNull, reason: 'nothing is held before the first read');
      final first = await source.refresh();
      expect(first.resolution.status, PlacementStatus.empty);
      expect(first.nextBoundaryMs, DateTime.utc(2026, 11, 1).millisecondsSinceEpoch);
      now = DateTime.utc(2026, 11, 1, 12);
      final second = source.recompute()!;
      expect(second.resolution, const PlacementResolution(PlacementStatus.document, documentId: 'sale', entry: 'main'));
      expect(second.documentSource?.documentId, 'sale');
      expect(transport.requests, 1);
    });
  });

  group('HotlayoutPlacement', () {
    final documentText = readFixture('rewards-showcase-screens');
    final documentId = (jsonDecode(documentText) as Map)['documentId'] as String;

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    Future<void> mount(WidgetTester tester, PlacementSource source, List<PlacementEvent> events) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: HotlayoutPlacement.fromSource(
              source: source,
              theme: RenderTheme.fallback(),
              data: const {},
              refreshInterval: null,
              onPlacementEvent: (name, event) => events.add(event),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    final scheduled = _map({
      'home.banner': {
        'documentId': null,
        'schedule': [
          {'documentId': documentId, 'from': '2026-11-01T00:00:00Z', 'until': '2026-11-02T00:00:00Z'},
        ],
      },
    });

    testWidgets('a timer at the boundary shows and removes the document, without reading the map again', (tester) async {
      var now = DateTime.utc(2026, 10, 31, 23);
      final transport = _Transport(scheduled);
      final events = <PlacementEvent>[];
      final source = PlacementSource(
        projectBase: base,
        name: 'home.banner',
        transport: transport,
        documentTransport: FakeDocumentTransport.replying(200, documentText),
        now: () => now,
      );
      await mount(tester, source, events);
      expect(tester.getSize(find.byType(HotlayoutPlacement)), Size.zero);
      expect(events.map((e) => e.show), [PlacementShow.nothing]);

      now = DateTime.utc(2026, 11, 1);
      await tester.pump(const Duration(hours: 1));
      await settle(tester);
      expect(tester.getSize(find.byType(HotlayoutPlacement)).height, greaterThan(0));
      expect(events.last.show, PlacementShow.document);
      expect(events.last.documentId, documentId);

      now = DateTime.utc(2026, 11, 2);
      await tester.pump(const Duration(days: 1));
      await settle(tester);
      expect(tester.getSize(find.byType(HotlayoutPlacement)), Size.zero);
      expect(events.map((e) => e.show), [PlacementShow.nothing, PlacementShow.document, PlacementShow.nothing]);
      expect(transport.requests, 1, reason: 'the map is not read again at a boundary');
    });

    testWidgets('returning to the foreground decides again at the clock of now', (tester) async {
      var now = DateTime.utc(2026, 10, 31, 23);
      final events = <PlacementEvent>[];
      final source = PlacementSource(
        projectBase: base,
        name: 'home.banner',
        transport: _Transport(scheduled),
        documentTransport: FakeDocumentTransport.replying(200, documentText),
        now: () => now,
      );
      await mount(tester, source, events);
      expect(tester.getSize(find.byType(HotlayoutPlacement)), Size.zero);

      // The clock jumped while the app was away; no timer elapsed.
      now = DateTime.utc(2026, 11, 1, 6);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await settle(tester);
      expect(tester.getSize(find.byType(HotlayoutPlacement)).height, greaterThan(0));
      expect(events.last.show, PlacementShow.document);
    });
  });
}
