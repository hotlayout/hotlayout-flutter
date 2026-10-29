import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/placements/placement_map.dart';
import 'package:hotlayout_flutter/src/placements/placement_reader.dart';
import 'package:hotlayout_flutter/src/placements/placement_schedule.dart';
import 'package:hotlayout_flutter/src/placements/placement_source.dart';

import 'support/network.dart';
import 'support/placement_bytes.dart';

/// The shared placement table (`assets/contract/fixtures/placements/placement-cases.json`): EVERY row
/// of `readCases`, `sourceCases` and `showingCases` runs here, as in every other reader.
///
/// The table is read with a plain JSON decode, so `__proto__` stays an own key of its rows.
void main() {
  final table =
      jsonDecode(
            File(
              'assets/contract/fixtures/placements/placement-cases.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final readCases = (table['readCases']! as List).cast<Map<String, Object?>>();
  final sourceCases = (table['sourceCases']! as List)
      .cast<Map<String, Object?>>();
  final showingCases = (table['showingCases']! as List)
      .cast<Map<String, Object?>>();
  final bodyCases = (table['bodyCases']! as List).cast<Map<String, Object?>>();
  final transportCases = (table['transportCases']! as List)
      .cast<Map<String, Object?>>();
  final eventCases = (table['eventCases']! as List)
      .cast<Map<String, Object?>>();
  final cacheCases = (table['cacheCases']! as List)
      .cast<Map<String, Object?>>();

  final scheduleCases = (table['scheduleCases']! as List)
      .cast<Map<String, Object?>>();

  Map<String, Object?> row(Object? value) =>
      (value! as Map).cast<String, Object?>();

  /// The parts of a body joined in order: `text` as UTF-8, `hex` as raw bytes, each `times` times.
  Uint8List bodyOf(Object? parts) {
    final out = BytesBuilder(copy: false);
    for (final item in (parts! as List)) {
      final part = row(item);
      final times = (part['times'] as int?) ?? 1;
      final Uint8List one;
      if (part.containsKey('hex')) {
        final hex = part['hex']! as String;
        one = Uint8List.fromList([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]);
      } else {
        one = bytesOf(part['text']! as String);
      }
      for (var i = 0; i < times; i++) {
        out.add(one);
      }
    }
    return out.takeBytes();
  }

  void expectResolution(PlacementMapRead map, List<Object?> expected) {
    for (final item in expected) {
      final e = row(item);
      final got = resolvePlacement(map, e['name']! as String);
      expect(
        (got.status.name, got.documentId, got.entry),
        (e['status'], e['documentId'], e['entry']),
        reason: 'name ${jsonEncode(e['name'])}',
      );
    }
  }

  String kindOf(PlacementMapRead read) => switch (read) {
    PlacementMapOk() => 'map',
    PlacementMapCorrupt() => 'corrupt',
    PlacementMapUnsupported() => 'unsupported',
  };

  test('the table has the rows the contract promises', () {
    expect(table['placementsVersion'], kPlacementsContractVersion);
    expect(readCases.length, 36);
    expect(sourceCases.length, 21);
    expect(showingCases.length, 10);
    expect(bodyCases.length, 26);
    expect(transportCases.length, 26);
    expect(eventCases.length, 8);
    expect(cacheCases.length, 3);
    expect(scheduleCases.length, 37);
    expect(
      scheduleCases.fold<int>(0, (n, r) => n + (r['checks']! as List).length),
      89,
    );
    expect(
      readCases.fold<int>(0, (n, r) => n + (r['resolve']! as List).length),
      80,
    );
    expect(
      sourceCases.fold<int>(0, (n, r) => n + (r['resolve']! as List).length),
      22,
    );
  });

  group('readCases', () {
    for (final c in readCases) {
      test(c['name']! as String, () {
        final read = c.containsKey('text')
            ? readPlacementMapText(c['text']! as String)
            : readPlacementMap(c['json']);
        expect(kindOf(read), c['read']);
        expectResolution(read, (c['resolve']! as List).cast<Object?>());
        // The tolerant reader reads the same map from its serialised text.
        if (c.containsKey('json')) {
          expect(
            kindOf(readPlacementMapText(jsonEncode(c['json']))),
            c['read'],
          );
        }
      });
    }
  });

  group('sourceCases', () {
    PlacementNetworkOutcome outcomeOf(Map<String, Object?> network) =>
        switch (network['kind']) {
          'map' => PlacementNetworkMap(network['text']! as String),
          'notModified' => const PlacementNetworkNotModified(),
          'notFound' => const PlacementNetworkNotFound(),
          'offline' => const PlacementNetworkOffline(),
          final other => fail('unknown network kind $other'),
        };

    for (final c in sourceCases) {
      test(c['name']! as String, () {
        final decision = pickPlacementMap(
          network: outcomeOf(row(c['network'])),
          lastKnown: c['lastKnown'] as String?,
          bundled: c['bundled'] as String?,
        );
        final expected = row(c['expected']);
        expect(decision.source.name, expected['source']);
        expect(decision.status.name, expected['status']);
        expect(decision.remember, expected['remember']);
        expectResolution(decision.map, (c['resolve']! as List).cast<Object?>());
      });
    }
  });

  group('showingCases', () {
    for (final c in showingCases) {
      test(c['name']! as String, () {
        final r = row(c['resolution']);
        final resolution = PlacementResolution(
          PlacementStatus.values.byName(r['status']! as String),
          documentId: r['documentId'] as String?,
          entry: r['entry'] as String?,
        );
        final document = c['document'] == null ? null : row(c['document']);
        final outcome = switch (document?['kind']) {
          null => null,
          'ok' => PlacementDocumentOk(
            (document!['entryPoints']! as List).cast<String>(),
          ),
          'missing' => const PlacementDocumentMissing(),
          'unreadable' => const PlacementDocumentUnreadable(),
          final other => fail('unknown document kind $other'),
        };
        final got = placementShowing(resolution, outcome);
        final expected = row(c['expected']);
        expect(
          (got.show.name, got.entry, got.report?.name),
          (expected['show'], expected['entry'], expected['report']),
        );
      });
    }
  });

  group('bodyCases', () {
    for (final c in bodyCases) {
      test(c['name']! as String, () {
        final read = readPlacementMapBytes(bodyOf(c['body']));
        expect(kindOf(read), c['read']);
        expectResolution(read, (c['resolve']! as List).cast<Object?>());
      });
    }
  });

  group('transportCases', () {
    final documentText = publishedDocumentJson(documentId: 'd1');
    final mapUrl = Uri.parse('https://example.test/placements/published.json');
    final documentUrl = Uri.parse(
      'https://example.test/documents/d1/published.json',
    );

    for (final c in transportCases) {
      testWidgets(c['name']! as String, (tester) async {
        final answer = row(c['answer']);
        final status = answer['status']! as int;
        final completedAt = answer['completedAtMs'] as int?;
        final isMap = c['request'] == 'map';
        // The answer arrives at completedAtMs (never when null): the deadline counts to the end of the body.
        Future<void> arrives() => completedAt == null
            ? Completer<void>().future
            : Future<void>.delayed(Duration(milliseconds: completedAt));
        {
          Object? result;
          if (isMap) {
            final body = answer.containsKey('body')
                ? bodyOf(answer['body'])
                : noBytes;
            final transport = _OneAnswer(() async {
              await arrives();
              return (statusCode: status, body: body, etag: null);
            });
            fetchPlacementMap(transport, mapUrl).then(
              (fetched) => result = switch (fetched.outcome) {
                PlacementNetworkMap() => 'map',
                PlacementNetworkCorrupt() => 'corrupt',
                PlacementNetworkNotModified() => 'notModified',
                PlacementNetworkNotFound() => 'notFound',
                PlacementNetworkOffline() => 'offline',
              },
            );
          } else {
            final source = PlacementDocumentSource(
              url: documentUrl,
              documentId: 'd1',
              transport: FakeDocumentTransport((_) async {
                await arrives();
                return (statusCode: status, body: documentText);
              }),
            );
            source.load().then<void>((_) => result = 'read').catchError((
              Object error,
            ) {
              result = (error as PlacementDocumentException).missing
                  ? 'missing'
                  : 'unreadable';
            });
          }
          await tester.pump(const Duration(seconds: 60));
          await tester.pump();
          expect(result, c['expected']);
        }
      });
    }
  });

  group('eventCases', () {
    PlacementEvent eventOf(Map<String, Object?> e) => PlacementEvent(
      show: PlacementShow.values.byName(e['status']! as String),
      report: e['report'] == null
          ? null
          : PlacementReport.values.byName(e['report']! as String),
      mapStatus: PlacementSourceStatus.values.byName(e['mapStatus']! as String),
      documentId: e['documentId'] as String?,
      entry: e['entry'] as String?,
    );

    for (final c in eventCases) {
      test(c['name']! as String, () {
        final told = <PlacementEvent>[];
        PlacementEvent? previous;
        for (final state in (c['states']! as List)) {
          final next = eventOf(row(state));
          final event = placementEventFor(previous, next);
          if (event != null) told.add(event);
          previous = next;
        }
        expect(told, [for (final e in (c['events']! as List)) eventOf(row(e))]);
      });
    }
  });

  group('cacheCases', () {
    for (final c in cacheCases) {
      test(c['name']! as String, () async {
        final store = _KeyedStore();
        final readers = <String, PlacementReader>{};
        final answers =
            <String, ({Map<String, Object?> map, String? document})>{};
        PlacementReader readerOf(String project) =>
            readers.putIfAbsent(project, () {
              final base = Uri.parse(
                'https://example.test/orgs/o1/projects/$project',
              );
              return PlacementReader(
                PlacementSource(
                  projectBase: base,
                  name: 'home.banner',
                  store: store,
                  transport: _OneAnswer(() async {
                    final map = answers[project]!.map;
                    if (map['kind'] != 'map') {
                      throw const SocketException('offline');
                    }
                    return (
                      statusCode: 200,
                      body: bytesOf(map['text']! as String),
                      etag: null,
                    );
                  }),
                  documentTransport: FakeDocumentTransport((_) async {
                    return switch (answers[project]!.document) {
                      'ok' => (
                        statusCode: 200,
                        body: publishedDocumentJson(documentId: 'd1'),
                      ),
                      'notFound' => (statusCode: 404, body: ''),
                      _ => throw const SocketException('offline'),
                    };
                  }),
                ),
              );
            });

        for (final raw in (c['steps']! as List)) {
          final step = row(raw);
          final project = step['project']! as String;
          answers[project] = (
            map: row(step['map']),
            document: step['document'] as String?,
          );
          final reading = await readerOf(project).read();
          final expected = row(step['expected']);
          expect(
            (
              reading.event.show.name,
              reading.event.report?.name,
              reading.event.mapStatus.name,
            ),
            (expected['status'], expected['report'], expected['mapStatus']),
            reason: 'project $project',
          );
        }
      });
    }
  });

  group('scheduleCases', () {
    for (final c in scheduleCases) {
      test(c['name']! as String, () {
        final read = c.containsKey('text')
            ? readPlacementMapText(c['text']! as String)
            : readPlacementMap(c['json']);
        // The tolerant reader reads the same map from its serialised text.
        final again = c.containsKey('json')
            ? readPlacementMapText(jsonEncode(c['json']))
            : read;
        for (final map in [read, again]) {
          for (final item in (c['checks']! as List)) {
            final check = row(item);
            final nowMs = placementInstantMs(check['now'])!;
            final place = check['place']! as String;
            final got = resolvePlacementAt(map, place, nowMs);
            final reason = 'place $place at ${check['now']}';
            expect(
              (got.status.name, got.documentId, got.entry),
              (check['status'], check['documentId'], check['entry']),
              reason: reason,
            );
            final next = check['next'];
            expect(
              nextPlacementBoundary(map, place, nowMs),
              next == null ? isNull : placementInstantMs(next),
              reason: 'next boundary, $reason',
            );
          }
        }
      });
    }
  });

  group('hostile input', () {
    test(
      'names that cannot be placements are unknown, whatever the map holds',
      () {
        final map = readPlacementMapText(
          jsonEncode({
            'placementsVersion': '1.0.0',
            'placements': {
              'home.banner': {'documentId': 'd1'},
            },
          }),
        );
        for (final name in [
          '__proto__',
          'constructor',
          'toString',
          '',
          'a' * 65,
          'Home.banner',
          'home..banner',
          'home.banner\n',
          '../x',
        ]) {
          expect(
            resolvePlacement(map, name).status,
            PlacementStatus.unknown,
            reason: jsonEncode(name),
          );
        }
        expect(isPlacementName('a' * 64), isTrue);
        expect(isPlacementName('a' * 65), isFalse);
      },
    );

    test('a document id that could walk out of the folder is unreadable', () {
      for (final id in [
        '..',
        '.',
        'a/b',
        r'a\b',
        '',
        'a' * 65,
        'a b',
        '%2e%2e',
        'd1\n',
      ]) {
        final map = readPlacementMapText(
          jsonEncode({
            'placementsVersion': '1.0.0',
            'placements': {
              'home.banner': {'documentId': id},
            },
          }),
        );
        expect(
          resolvePlacement(map, 'home.banner').status,
          PlacementStatus.unreadable,
          reason: jsonEncode(id),
        );
      }
    });

    test(
      'a map is read whatever its size: the limits are the publisher\'s',
      () {
        final places = {
          for (var i = 0; i < 300; i++) 'p$i': {'documentId': 'd$i'},
        };
        final map = readPlacementMapText(
          jsonEncode({'placementsVersion': '1.0.0', 'placements': places}),
        );
        expect(map, isA<PlacementMapOk>());
        expect(resolvePlacement(map, 'p299').documentId, 'd299');
        expect(kMaxPlacements, 200);
        expect(kPlacementsMaxBytes, 65536);
      },
    );

    test('a version that is not a plain semver is not a map', () {
      for (final version in [
        '1.0',
        '1.0.0-beta',
        'v1.0.0',
        '01.0.0',
        1,
        null,
      ]) {
        expect(
          readPlacementMap({
            'placementsVersion': version,
            'placements': <String, Object?>{},
          }),
          isA<PlacementMapCorrupt>(),
          reason: '$version',
        );
      }
    });
  });
}

final class _OneAnswer implements PlacementTransport {
  _OneAnswer(this.respond);

  final Future<PlacementResponse> Function() respond;

  @override
  Future<PlacementResponse> fetch(Uri url, {String? ifNoneMatch}) => respond();
}

final class _KeyedStore implements PlacementMapStore {
  final Map<String, String> texts = {};

  @override
  Future<String?> read(String key) async => texts[key];

  @override
  Future<void> write(String key, String text) async => texts[key] = text;
}
