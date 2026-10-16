/// A COUNTDOWN THAT TICKS (schema 9.21.0, `countdownPart`): the screen redraws its countdown nodes every second
/// when one of them shows seconds, otherwise every minute, and only while it is shown.
///
/// The numbers themselves (the arithmetic, the written form, the plural word) are the rows of `countdownCases`
/// that `template_cases_test.dart` runs. Here: the mirror of the artifact block `x-countdown`, which parts the
/// reader finds in a document, how often it ticks, and a real screen that follows a clock (a replaceable one, as
/// the contract asks).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/countdown.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/countdown_clock.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _block = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json)['x-countdown']! as _Json;

_Json _part(String unit, {int? pad}) => {
  'kind': 'binding',
  'path': 'offer.endsAt',
  'fallback': '—',
  'format': 'countdownPart',
  'unit': unit,
  'pad': ?pad,
};

_Json _text(String id, Object content) => {
  'id': id,
  'type': 'Text',
  'props': {'content': content},
};

const _endsAt = '2026-10-10T09:01:00.000Z';

void main() {
  late DateTime clock;

  setUp(() {
    clock = DateTime.utc(2026, 10, 10, 9, 0, 0);
    readerClock = () => clock;
    addTearDown(() => readerClock = DateTime.now);
  });

  test('x-countdown: the mirror against the artifact', () {
    expect(_block['format'], kCountdownRules['format']);
    expect(_block['pathType'], kCountdownRules['pathType']);
    expect(_block['units'], CountdownUnit.values.map((unit) => unit.wire));
    expect(_block['props'], {'unit': 'unit', 'pad': 'pad'});
    expect(_block['withoutUnit'], isA<String>());
    expect(_block['fallback'], kCountdownRules['fallback']);
    final arithmetic = _block['arithmetic']! as _Json;
    expect(arithmetic['days'], 'floor(S / 86400)');
    expect(arithmetic['hours'], 'floor(S / 3600) mod 24');
    expect(arithmetic['minutes'], 'floor(S / 60) mod 60');
    expect(arithmetic['seconds'], 'S mod 60');
    expect(arithmetic['timeZone'], 'none');
    expect(CountdownUnit.days.secondsIn, 86400);
    expect(CountdownUnit.hours.wrap, 24);
    expect(CountdownUnit.minutes.wrap, 60);
    expect(CountdownUnit.seconds.wrap, 60);
    expect(CountdownUnit.days.wrap, isNull);
    final ticking = _block['ticking']! as _Json;
    expect(ticking['seconds'], contains('every second'));
    expect(ticking['otherwise'], 'every minute');
  });

  group('the rule', () {
    test('a part rounds DOWN and a past moment is zero', () {
      final now = DateTime.utc(2026, 10, 10, 9);
      expect(countdownPartOf(now.add(const Duration(milliseconds: 999)), now, CountdownUnit.seconds), 0);
      expect(countdownPartOf(now.add(const Duration(seconds: 3600 + 59)), now, CountdownUnit.hours), 1);
      expect(countdownPartOf(now.subtract(const Duration(days: 3)), now, CountdownUnit.days), 0);
      expect(countdownPartOf(now.add(const Duration(days: 400, hours: 5)), now, CountdownUnit.days), 400);
    });

    test('the parts of one duration add up to it', () {
      final now = DateTime.utc(2026, 10, 10, 9);
      final moment = now.add(const Duration(days: 2, hours: 14, minutes: 5, seconds: 9));
      final parts = [for (final unit in CountdownUnit.values) countdownPartOf(moment, now, unit)];
      expect(parts, [2, 14, 5, 9]);
    });

    test('the parts of a document are found anywhere, and only readable ones', () {
      expect(countdownUnitsIn({'a': [_part('hours'), {'b': _part('days')}]}), {CountdownUnit.hours, CountdownUnit.days});
      expect(countdownUnitsIn(_part('weeks')), isEmpty, reason: 'an unknown unit is no countdown');
      expect(countdownUnitsIn({'kind': 'binding', 'format': 'countdownPart'}), isEmpty, reason: 'without a unit');
      expect(countdownUnitsIn({'kind': 'binding', 'format': 'date', 'unit': 'hours'}), isEmpty);
      expect(countdownUnitsIn('text'), isEmpty);
    });

    test('a second ticks every second, anything else every minute, none not at all', () {
      expect(countdownTickOf({CountdownUnit.seconds}), const Duration(seconds: 1));
      expect(countdownTickOf({CountdownUnit.days, CountdownUnit.seconds}), const Duration(seconds: 1));
      expect(countdownTickOf({CountdownUnit.hours}), const Duration(minutes: 1));
      expect(countdownTickOf(<CountdownUnit>{}), isNull);
    });

    test('a very deep raw tree is walked without a deep stack', () {
      Object? deep = _part('hours');
      for (var i = 0; i < 20000; i += 1) {
        deep = {'child': deep};
      }
      expect(countdownUnitsIn(deep), {CountdownUnit.hours});
    });
  });

  UiDocument document(List<_Json> children) => docWith(children);

  group('a real screen follows the clock', () {
    String line(WidgetTester tester) => tester.widget<Text>(find.byType(Text).first).data!;

    testWidgets('seconds: a new number every second, never ahead of the clock', (tester) async {
      await pumpDocument(
        tester,
        document([_text('left', _part('seconds', pad: 2))]),
        data: {'offer.endsAt': _endsAt},
      );
      expect(line(tester), '00', reason: 'sixty seconds is a whole minute: the seconds part is 0');
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(line(tester), '59');
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(line(tester), '58');
      // Between two ticks nothing moves.
      clock = clock.add(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(line(tester), '58');
    });

    testWidgets('without a seconds part: a tick of a minute', (tester) async {
      await pumpDocument(
        tester,
        document([_text('left', _part('minutes'))]),
        data: {'offer.endsAt': _endsAt},
      );
      expect(line(tester), '1');
      clock = clock.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(line(tester), '1', reason: 'half a minute: the number waits for its tick');
      clock = clock.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(line(tester), '0');
    });

    testWidgets('only the nodes of the shown screen tick: a screen with no countdown reads no clock', (tester) async {
      var reads = 0;
      readerClock = () {
        reads += 1;
        return clock;
      };
      await pumpDocument(tester, document([_text('left', {'kind': 'literal', 'value': 'plain'})]));
      await tester.pump(const Duration(minutes: 3));
      expect(reads, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a host that pinned the moment drives the time itself: nothing ticks', (tester) async {
      var reads = 0;
      readerClock = () {
        reads += 1;
        return clock;
      };
      await pumpDocument(
        tester,
        document([_text('left', _part('seconds'))]),
        data: {'offer.endsAt': _endsAt},
        now: DateTime.utc(2026, 10, 10, 9),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(line(tester), '0');
      expect(reads, 0);
    });

    testWidgets('a screen the host hides stops ticking and reads the clock afresh when shown again', (tester) async {
      var shown = true;
      late StateSetter set;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return TickerMode(
                enabled: shown,
                child: Material(child: renderDocument(document([_text('left', _part('seconds', pad: 2))]), theme: RenderTheme.fallback(), data: const {'offer.endsAt': _endsAt})),
              );
            },
          ),
        ),
      );
      expect(line(tester), '00');
      set(() => shown = false);
      await tester.pump();
      clock = clock.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(line(tester), '00', reason: 'hidden: no tick');
      set(() => shown = true);
      await tester.pump();
      expect(line(tester), '50', reason: 'shown again: the clock, not the number it had');
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(line(tester), '49');
    });

    testWidgets('a screen left for another stops its timer (no pending timers at the end)', (tester) async {
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'two',
        'name': 'two',
        'initialScreenId': 'a',
        'screens': [
          screenEntry('a', [
            _text('left', _part('seconds')),
            buttonNode('Go', id: 'go', action: {'type': 'navigate', 'params': {'screenId': 'b'}}),
          ]),
          screenEntry('b', [
            _text('here', {'kind': 'literal', 'value': 'plain'}),
          ]),
        ],
      });
      await pumpDocument(tester, doc, data: {'offer.endsAt': _endsAt});
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('plain'), findsOneWidget);
      var reads = 0;
      readerClock = () {
        reads += 1;
        return clock;
      };
      await tester.pump(const Duration(seconds: 5));
      expect(reads, 0, reason: 'the first screen is gone, so is its clock');
    });
  });
}
