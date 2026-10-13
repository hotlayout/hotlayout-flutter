/// ACTION CATALOG, ANALYTICS EVENT, SCREEN SHOW (schema 9.8.0).
///
/// The rule has four implementations: the contract reference, the builder preview,
/// the mirror in `@hotlayout/react` and this one. The examples are DATA
/// (`assets/contract/fixtures/actions/action-cases.json`), and here they
/// run row by row, the file ITSELF, without rewriting:
///
///  1. `formCases` (108) -- the address form as a pure function;
///  2. `handedCases` (55) -- what the host gets: parameters from data, `standard`,
///     `invalid`;
///  3. `schemaCases` (38) and `documentCases` (27) -- for the reader this means "does not crash":
///     the structure and the validator are checked by the builder;
///  4. `flowCases` (28) -- a REAL `ScreenFlow` and real taps:
///     after each step the stack, the analytics event, the handed action and
///     the show event are compared, and also the ORDER (event -> then either an action or a show);
///  5. the mirror of the `x-actions` blocks (with `params`) and `x-screenShown` and the fourteen
///     policy rows against the artifact.
///
/// Flow steps: `press` (with `repeat: true` -- auto-repeat of a held key,
/// a REAL keyboard on the button focus), `rerender`, `restart` and
/// `newVersion` (the host hands out a NEW version of the same document).
///
/// The model is the builder's `scripts/action-cases.test.tsx`. The only thing Flutter
/// cannot reproduce is `cancelled: true`: there is no host that cancels the reader's
/// navigation here (nor an `onNavigate` callback), so that
/// step checks only that the analytics event comes first.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _readJson(String path) => jsonDecode(File(path).readAsStringSync()) as _Json;

final _table = _readJson('assets/contract/fixtures/actions/action-cases.json');
final _schema = _readJson('assets/contract/screen-schema.json');

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json _obj(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();

/// `{ "repeat": { prefix, char, length } }` in place of a string -- a string of the required
/// length; works at any JSON depth.
Object? _materialize(Object? value) {
  if (value is Map) {
    if (value.length == 1 && value.containsKey('repeat')) {
      final repeat = _obj(value['repeat']);
      final prefix = repeat['prefix']! as String;
      final char = repeat['char']! as String;
      final length = repeat['length']! as int;
      return prefix + char * (length - prefix.length);
    }
    return {for (final entry in value.entries) entry.key: _materialize(entry.value)};
  }
  if (value is List) return [for (final item in value) _materialize(item)];
  return value;
}

ActionParamForm _formOf(String wire) =>
    ActionParamForm.values.firstWhere((form) => form.name == wire, orElse: () => throw StateError('form $wire'));

/// What the host got, in the shape it is written in the table.
_Json _handedJson(ButtonAction action) {
  final standard = action.standard;
  return {
    'type': action.type,
    if (action.params.isNotEmpty) 'params': action.params,
    if (standard != null)
      'standard': switch (standard) {
        OpenUrlAction() => {'type': 'openUrl', 'url': standard.url},
        DeeplinkAction() => {'type': 'deeplink', 'url': standard.url, 'scheme': standard.scheme},
        CloseAction() => {'type': 'close'},
      },
    if (action.invalid != null) 'invalid': {'param': action.invalid!.param, 'problem': action.invalid!.problem.wire},
  };
}

_Json _trackJson(TrackEvent event) => {'event': event.event, if (event.params.isNotEmpty) 'params': event.params};

_Json _shownJson(ScreenShown shown) => {
  'documentId': shown.documentId,
  'screenId': shown.screenId,
  'entry': shown.entry,
  'presentation': shown.presentation,
  'cause': shown.cause.wire,
  'depth': shown.depth,
  'record': shown.record,
  // 9.9.0: optional keys -- only when the screen named them (there is no extra key).
  if (shown.modalPlacement != null) 'modalPlacement': shown.modalPlacement,
  if (shown.statusBarIcons != null) 'statusBarIcons': shown.statusBarIcons,
};

/// Everything the host sees for one action, IN ORDER of arrival.
typedef _Seen = ({List<String> order, List<TrackEvent> tracks, List<ButtonAction> handed, List<ScreenShown> shown});

void main() {
  group('table: structure', () {
    test('five tables, names within a table are unique, the address limit is from the artifact', () {
      expect(_rows('formCases'), hasLength(108));
      expect(_rows('schemaCases'), hasLength(38));
      expect(_rows('documentCases'), hasLength(27));
      expect(_rows('handedCases'), hasLength(55));
      expect(_rows('flowCases'), hasLength(39));
      for (final key in ['formCases', 'schemaCases', 'documentCases', 'handedCases', 'flowCases']) {
        final names = _rows(key).map((row) => row['name']).toList();
        expect(names.toSet(), hasLength(names.length), reason: key);
      }
      expect(_table['urlMaxLength'], kActionUrlMaxLength);
    });
  });

  group('parameter form (formCases)', () {
    for (final row in _rows('formCases')) {
      test(row['name']! as String, () {
        final value = row.containsKey('repeat') ? _materialize({'repeat': row['repeat']}) as String : row['value'] as String?;
        final problem = paramFormProblem(_formOf(row['form']! as String), value);
        expect(problem?.wire, row['problem']);
      });
    }

    test('order of checks: absent -> too long -> form', () {
      final long = 'javascript:${'a' * 2100}';
      expect(paramFormProblem(ActionParamForm.httpsUrl, null), ActionParamProblem.missing);
      expect(paramFormProblem(ActionParamForm.httpsUrl, ''), ActionParamProblem.missing);
      expect(paramFormProblem(ActionParamForm.httpsUrl, long), ActionParamProblem.tooLong);
      expect(paramFormProblem(ActionParamForm.httpsUrl, ' https://a.example'), ActionParamProblem.notHttps);
      expect(paramFormProblem(ActionParamForm.appLink, long), ActionParamProblem.tooLong);
    });

    test('Uri.parse is not a check: what the platform parser lets through, the form rejects', () {
      for (final hostile in [r'https:\\bank.example', 'https://bank.example@evil.example', 'https://a\tb.example']) {
        expect(paramFormProblem(ActionParamForm.httpsUrl, hostile), isNotNull, reason: hostile);
      }
    });
  });

  group('what the host gets (handedCases)', () {
    for (final row in _rows('handedCases')) {
      test(row['name']! as String, () {
        final action = ButtonAction.parse(_materialize(row['action']));
        final data = _obj(_materialize(row['data']));
        final handed = action.handOver((path) => data[path]);

        expect(_handedJson(handed), _materialize(row['handed']));
        // `standard` and `invalid` never occur together, and the document fields do not go to the host.
        expect(handed.standard == null || handed.invalid == null, isTrue);
        expect(handed.track, isNull);
        expect(handed.paramBindings, isEmpty);
        expect(handed.carryRecord, isFalse);
      });
    }
  });

  group('action from the document (schemaCases, documentCases): the reader does not crash', () {
    for (final row in [..._rows('schemaCases'), ..._rows('documentCases')]) {
      test(row['name']! as String, () {
        final action = ButtonAction.parse(_materialize(row['action']));
        // A field of the wrong shape is ignored, the rest of the action works.
        final handed = action.handOver((_) => null);
        expect(handed.type, action.type);
      });
    }

    test('9.8.0 fields are read one by one: a corrupted one does not cancel the rest', () {
      final action = ButtonAction.parse({
        'type': 'openUrl',
        'params': {'url': 'https://example.com'},
        'paramBindings': {'url': 'offer.url', '__proto__': 'x', 'broken': 7, 'empty': ''},
        'track': {'event': 'bad event name'},
        'carryRecord': 'true',
      });
      expect(action.paramBindings, {'url': 'offer.url'});
      expect(action.track, isNull);
      expect(action.carryRecord, isFalse);
      expect(action.handOver((_) => null).standard, isA<OpenUrlAction>());
    });

    test('a non-map in place of paramBindings and track: the action works', () {
      for (final junk in <Object?>[null, 3, 'x', [1], true]) {
        final action = ButtonAction.parse({
          'type': 'close',
          'paramBindings': junk,
          'track': junk,
          'carryRecord': junk,
        });
        expect(action.type, 'close');
        expect(action.paramBindings, isEmpty);
        expect(action.track, isNull);
        // Exactly `true` is the only spelling of the word.
        expect(action.carryRecord, junk == true);
        expect(action.handOver((_) => null).standard, isA<CloseAction>());
      }
    });

    test('carryRecord — exactly `true`', () {
      expect(ButtonAction.parse({'type': 'navigate', 'carryRecord': true}).carryRecord, isTrue);
      for (final other in <Object?>['true', 1, false, 'yes', const <Object?>[]]) {
        expect(ButtonAction.parse({'type': 'navigate', 'carryRecord': other}).carryRecord, isFalse, reason: '$other');
      }
    });

    test('analytics event: exactly the limits in the artifact', () {
      final good = TrackEvent.parse({
        'event': 'offer_open',
        'params': {'placement': 'banner'},
      });
      expect(good?.event, 'offer_open');
      expect(good?.params, {'placement': 'banner'});
      expect(TrackEvent.parse({'event': 'a' * 41}), isNull);
      expect(TrackEvent.parse({'event': 'a' * 40}), isNotNull);
      expect(TrackEvent.parse({'event': 'offer_open', 'params': {'note': 'a' * 101}}), isNull);
      expect(TrackEvent.parse({'event': 'offer_open', 'params': {'position': 3}}), isNull);
      expect(TrackEvent.parse({'event': 'offer_open', 'params': {'item-id': '1'}}), isNull);
      expect(
        TrackEvent.parse({'event': 'e', 'params': {for (var i = 0; i < 26; i += 1) 'k$i': 'v'}}),
        isNull,
      );
    });
  });

  group('flows (flowCases) -- a real ScreenFlow, real taps', () {
    for (final row in _rows('flowCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final data = {..._obj(_materialize(row['data']))};
        var built = _flowDocument(row, data);
        final controller = ScreenFlowController();
        addTearDown(controller.dispose);

        final order = <String>[];
        final tracks = <TrackEvent>[];
        final handed = <ButtonAction>[];
        final shown = <ScreenShown>[];

        Future<void> pump({String? entry, UiDocument? document, Map<String, Object?>? withData, String? locale}) =>
            pumpDocument(
              tester,
              document ?? built.document,
              data: withData ?? data,
              entry: entry,
              locale: locale,
              controller: controller,
              onTrack: (event, nodeId, record) {
                order.add('track');
                tracks.add(event);
              },
              onRecordAction: (action, nodeId, record) {
                order.add('handed');
                handed.add(action);
              },
              onScreenShown: (event) {
                order.add('shown');
                shown.add(event);
              },
            );

        _Seen take() {
          final seen = (order: [...order], tracks: [...tracks], handed: [...handed], shown: [...shown]);
          order.clear();
          tracks.clear();
          handed.clear();
          shown.clear();
          return seen;
        }

        void expectStack(List<String> stack, String where) {
          expect(controller.currentScreenId, stack.last, reason: '$where: top screen');
          expect(controller.canGoBack, stack.length > 1, reason: '$where: stack depth');
        }

        void expectSeen(_Seen seen, _Json expected, String where) {
          // Analytics event.
          final expectedTrack = expected['track'];
          if (expectedTrack == null) {
            expect(seen.tracks, isEmpty, reason: '$where: no analytics event');
          } else {
            expect(seen.tracks, hasLength(1), reason: '$where: exactly one analytics event');
            expect(_trackJson(seen.tracks.single), expectedTrack, reason: '$where: analytics event');
          }
          // Handed action.
          final expectedHanded = expected['handed'];
          if (expectedHanded == null) {
            expect(seen.handed, isEmpty, reason: '$where: the host got no action');
          } else {
            expect(seen.handed, hasLength(1), reason: '$where: the host got exactly one action');
            expect(_handedJson(seen.handed.single), _materialize(expectedHanded), reason: '$where: handed action');
          }
          // Show event.
          final expectedShown = expected['shown'];
          if (expectedShown == null) {
            expect(seen.shown, isEmpty, reason: '$where: no show');
          } else {
            expect(seen.shown, hasLength(1), reason: '$where: exactly one show');
            expect(_shownJson(seen.shown.single), expectedShown, reason: '$where: show event');
          }
          // Order: analytics event -> then either a handed action or a show.
          expect(seen.order, [
            if (expectedTrack != null) 'track',
            if (expectedHanded != null) 'handed',
            if (expectedShown != null) 'shown',
          ], reason: '$where: order');
        }

        // Start: the first show is exactly one.
        await pump(entry: row['entry'] as String?);
        await tester.pumpAndSettle();
        final start = _obj(row['start']);
        expectStack((start['stack']! as List<Object?>).cast<String>(), 'start');
        final startSeen = take();
        expect(startSeen.shown, hasLength(1), reason: 'start: exactly one show');
        expect(_shownJson(startSeen.shown.single), start['shown'], reason: 'start: show event');
        expect(startSeen.tracks, isEmpty);
        expect(startSeen.handed, isEmpty);

        var currentEntry = row['entry'] as String?;
        final steps = (row['steps']! as List<Object?>).cast<_Json>();
        for (var index = 0; index < steps.length; index += 1) {
          final step = steps[index];
          final expected = _obj(step['expect']);
          final where = 'step $index (${step['do']})';
          switch (step['do']) {
            case 'press' when step['repeat'] == true:
              // Auto-repeat of a held activation key: no action,
              // no analytics event, no show. Focus is on the step button; the repeat
              // is sent by the REAL keyboard of the test engine.
              await _focusButton(tester, _label(index));
              await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              // The first key press is a PRESS: it acts once and its
              // description is the previous table step; here we look only at the repeat.
              take();
              await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
              await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              final repeated = take();
              await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              take();
              expectSeen(repeated, expected, where);
            case 'press':
              await tester.tap(find.text(_label(index)).last);
              await tester.pumpAndSettle();
              final seen = take();
              if (step['cancelled'] == true) {
                // A host that cancels the reader's navigation does not exist in Flutter: we check
                // what cannot depend on it -- the analytics event has already
                // arrived, exactly once and first.
                expect(seen.tracks, hasLength(1), reason: where);
                expect(_trackJson(seen.tracks.single), expected['track'], reason: where);
                expect(seen.order.first, 'track', reason: where);
              } else {
                expectSeen(seen, expected, where);
                expectStack((expected['stack']! as List<Object?>).cast<String>(), where);
              }
            case 'newVersion':
              // The host hands out a NEW version of the same document (the same
              // `documentId` and entry): `screens` are the screens of the new version, `initial`
              // and `entryPoints` are optional replacements.
              built = _flowDocument(row, data, newVersion: step);
              await pump(entry: currentEntry, document: built.document, withData: data);
              await tester.pumpAndSettle();
              expectSeen(take(), expected, where);
              expectStack((expected['stack']! as List<Object?>).cast<String>(), where);
            case 'rerender':
              // New data, another language, a new object of the SAME document.
              await pump(
                entry: currentEntry,
                document: UiDocument.fromJson(built.json),
                withData: {...data, 'rerender.marker': 'new data'},
                locale: 'uk',
              );
              await tester.pumpAndSettle();
              expectSeen(take(), expected, where);
              expectStack((expected['stack']! as List<Object?>).cast<String>(), where);
            case 'restart':
              currentEntry = step['entry'] as String?;
              await pump(entry: currentEntry);
              await tester.pumpAndSettle();
              expectSeen(take(), expected, where);
              expectStack((expected['stack']! as List<Object?>).cast<String>(), where);
            default:
              fail('unknown step ${step['do']}');
          }
        }
      });
    }
  });

  group('fixture actions-screens: each button -> what the host got', () {
    const items = [
      {'id': 'bottle', 'name': 'Bottle'},
      {'id': 'backpack', 'name': 'Backpack'},
    ];

    Future<
      ({
        List<ButtonAction> handed,
        List<TrackEvent> tracks,
        List<Map<String, Object?>?> records,
        List<ScreenShown> shown,
        List<String> order,
      })
    >
    open(WidgetTester tester, {Map<String, Object?> data = const {}, String? entry}) async {
      final handed = <ButtonAction>[];
      final tracks = <TrackEvent>[];
      final records = <Map<String, Object?>?>[];
      final shown = <ScreenShown>[];
      final order = <String>[];
      await pumpDocument(
        tester,
        loadFixture('actions-screens'),
        data: {'items': items, ...data},
        entry: entry,
        onTrack: (event, nodeId, record) {
          order.add('track');
          tracks.add(event);
        },
        onRecordAction: (action, nodeId, record) {
          order.add('handed');
          handed.add(action);
          records.add(record);
        },
        onScreenShown: (event) {
          order.add('shown');
          shown.add(event);
        },
      );
      await tester.pumpAndSettle();
      return (handed: handed, tracks: tracks, records: records, shown: shown, order: order);
    }

    Future<void> tap(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label).last);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('openUrl: the host gets a verified action, the analytics event comes first, nothing is opened', (tester) async {
      final seen = await open(tester);
      await tap(tester, 'Open the terms');
      expect(seen.order, ['shown', 'track', 'handed']);
      expect(seen.tracks.single.event, 'terms_open');
      expect(seen.tracks.single.params, {'placement': 'offer'});
      final action = seen.handed.single;
      expect(action.type, 'openUrl');
      expect(action.standard, isA<OpenUrlAction>());
      expect((action.standard! as OpenUrlAction).url, 'https://example.com/terms?utm_source=app');
      expect(action.track, isNull);
    });

    testWidgets('deeplink and close', (tester) async {
      final seen = await open(tester);
      await tap(tester, 'Open in the app');
      final link = seen.handed.last.standard! as DeeplinkAction;
      expect(link.scheme, 'myapp');
      expect(link.url, 'myapp://offers/weekend');

      await tap(tester, 'Close');
      expect(seen.handed.last.standard, isA<CloseAction>());
      // `close` does not touch the stack: the same screen, no show.
      expect(seen.shown, hasLength(1));
    });

    testWidgets('parameter from data: share takes the code from data, openUrl with a non-address is invalid', (tester) async {
      final seen = await open(tester, data: {'offer.code': 'WEEKEND20'});
      await tap(tester, 'Share the code');
      expect(seen.handed.last.type, 'share');
      expect(seen.handed.last.params, {'text': 'WEEKEND20'});
      expect(seen.handed.last.standard, isNull);
      expect(seen.handed.last.invalid, isNull);

      await tap(tester, 'Partner page');
      final partner = seen.handed.last;
      expect(partner.standard, isNull, reason: 'an invalid action is not standard');
      expect(partner.invalid?.param, 'url');
      expect(partner.invalid?.problem, ActionParamProblem.notHttps);
      // An invalid action still goes to the host, and the literal is NOT substituted in its place.
      expect(partner.params['url'], 'WEEKEND20');
    });

    testWidgets('no data: the literal stays', (tester) async {
      final seen = await open(tester);
      await tap(tester, 'Share the code');
      expect(seen.handed.last.params, {'text': 'Promo'});
      await tap(tester, 'Partner page');
      expect(seen.handed.last.standard, isA<OpenUrlAction>());
    });

    testWidgets('none with track: the host gets only the event', (tester) async {
      final seen = await open(tester);
      await tap(tester, 'Only an event');
      expect(seen.tracks.single.event, 'banner_tap');
      expect(seen.handed, isEmpty);
      expect(seen.shown, hasLength(1));
    });

    testWidgets('list row -> details -> "Choose delivery" (the same record) versus "Delivery, no record"', (tester) async {
      final seen = await open(tester);
      await tap(tester, 'Backpack');
      expect(seen.tracks.single.event, 'reward_open');
      expect(seen.shown.last.screenId, 'details');
      expect(seen.shown.last.cause, ScreenShownCause.forward);
      expect(seen.shown.last.record, {'item.id': 'backpack', 'item.name': 'Backpack'});

      await tap(tester, 'Choose delivery');
      expect(seen.shown.last.screenId, 'delivery');
      expect(seen.shown.last.depth, 3);
      expect(seen.shown.last.record, {'item.id': 'backpack', 'item.name': 'Backpack'});

      await tap(tester, 'Back');
      expect(seen.shown.last.screenId, 'details');
      expect(seen.shown.last.cause, ScreenShownCause.back);

      await tap(tester, 'Delivery, no record');
      expect(seen.shown.last.screenId, 'delivery');
      expect(seen.shown.last.record, isNull);
    });

    testWidgets('«Confirm» -> layer -> "Done" (close from the layer) does not touch the stack', (tester) async {
      final seen = await open(tester);
      await tap(tester, 'Backpack');
      await tap(tester, 'Confirm');
      expect(seen.shown.last.screenId, 'confirm');
      expect(seen.shown.last.presentation, 'modal');
      final shownCount = seen.shown.length;

      await tap(tester, 'Done');
      expect(seen.handed.last.standard, isA<CloseAction>());
      expect(seen.handed.last.params, {'result': 'done'});
      expect(seen.shown, hasLength(shownCount), reason: 'close is for the host, no show');

      await tap(tester, 'Not now');
      expect(seen.shown.last.screenId, 'details');
      expect(seen.shown.last.cause, ScreenShownCause.back);
    });

    testWidgets('entry promo: the show event carries the entry name', (tester) async {
      final seen = await open(tester, entry: 'promo');
      expect(seen.shown.single.entry, 'promo');
      expect(seen.shown.single.cause, ScreenShownCause.entry);
      expect(seen.shown.single.depth, 1);
    });
  });

  group('system "back" is also a show', () {
    testWidgets('removing a screen with system "back" gives exactly one event with cause back', (tester) async {
      final shown = <ScreenShown>[];
      final doc = docWithScreens([
        screenEntry('first', [
          buttonNode('Next', id: 'next', action: {
            'type': 'navigate',
            'params': {'screenId': 'second'},
          }),
        ]),
        screenEntry('second', [textNode('Second', id: 't2')]),
      ], initialScreenId: 'first');
      await pumpDocument(tester, doc, onScreenShown: shown.add);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(shown.map((event) => event.cause), [ScreenShownCause.entry, ScreenShownCause.forward]);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(shown.map((event) => event.cause), [
        ScreenShownCause.entry,
        ScreenShownCause.forward,
        ScreenShownCause.back,
      ]);
      expect(shown.last.screenId, 'first');
    });
  });

  group('compatibility: onScreenChanged and renderScreen', () {
    testWidgets('the deprecated onScreenChanged is called at the same moment as onScreenShown', (tester) async {
      final order = <String>[];
      final doc = docWithScreens([
        screenEntry('first', [
          buttonNode('Next', id: 'next', action: {
            'type': 'navigate',
            'params': {'screenId': 'second'},
          }),
        ]),
        screenEntry('second', [textNode('Second', id: 't2')]),
      ], initialScreenId: 'first');
      await pumpDocument(
        tester,
        doc,
        // ignore: deprecated_member_use_from_same_package
        onScreenChanged: (screen) => order.add('changed:${screen.screenId}'),
        onScreenShown: (shown) => order.add('shown:${shown.screenId}'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(order, ['changed:first', 'shown:first', 'changed:second', 'shown:second']);
    });

    testWidgets('renderScreen: the analytics event goes first, none does not reach the host', (tester) async {
      final order = <String>[];
      final doc = docWithScreens([
        screenEntry('only', [
          buttonNode('Measure', id: 'measure', action: {
            'type': 'none',
            'track': {'event': 'banner_tap'},
          }),
          buttonNode('Open', id: 'open', action: {
            'type': 'openUrl',
            'params': {'url': 'https://example.com'},
            'track': {'event': 'open_tap'},
          }),
        ]),
      ], initialScreenId: 'only');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderScreen(
              doc.initialScreen,
              theme: RenderTheme.fallback(),
              data: const {},
              onTrack: (event, nodeId, record) => order.add('track:${event.event}'),
              onAction: (action, nodeId) => order.add('action:${action.type}:${action.standard}'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Measure'));
      await tester.tap(find.text('Open'));
      expect(order, ['track:banner_tap', 'track:open_tap', 'action:openUrl:openUrl(https://example.com)']);
    });
  });

  group('the reader opens nothing itself', () {
    test('lib/ has no address executors except the host helper', () {
      final offenders = <String>[];
      final hostile = RegExp(r'url_launcher|launchUrl|launchUri|canLaunch|SystemNavigator|Navigator\.of|Navigator\.pop');
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        for (final match in hostile.allMatches(text)) {
          // A comment line is not a call.
          final lineStart = text.lastIndexOf('\n', match.start) + 1;
          final prefix = text.substring(lineStart, match.start).trimLeft();
          if (prefix.startsWith('//') || prefix.startsWith('///') || prefix.startsWith('*')) continue;
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
      expect(offenders, isEmpty);
    });

    test('the package pubspec.yaml has no url_launcher', () {
      final text = File('pubspec.yaml').readAsStringSync();
      final dependencies = text.substring(text.indexOf('\ndependencies:'), text.indexOf('\ndev_dependencies:'));
      expect(dependencies, isNot(contains('url_launcher')));
    });

    test('runStandardAction: runs only a verified standard action', () {
      final opened = <String>[];
      final links = <String>[];
      var closed = 0;
      bool run(Object? raw, {Iterable<String>? schemes, bool withExecutors = true}) {
        final action = ButtonAction.parse(raw).handOver((_) => null);
        return runStandardAction(
          action,
          openUrl: withExecutors ? opened.add : null,
          deeplinkSchemes: schemes,
          openDeeplink: withExecutors ? links.add : null,
          close: withExecutors ? () => closed += 1 : null,
        );
      }

      expect(run({'type': 'openUrl', 'params': {'url': 'https://example.com/a'}}), isTrue);
      expect(opened.single, 'https://example.com/a');
      // An invalid and an own action are `false`, executors are not called.
      expect(run({'type': 'openUrl', 'params': {'url': 'javascript:alert(1)'}}), isFalse);
      expect(run({'type': 'share', 'params': {'text': 'x'}}), isFalse);
      expect(opened, hasLength(1));
      // Without an executor the action is not run.
      expect(run({'type': 'openUrl', 'params': {'url': 'https://example.com'}}, withExecutors: false), isFalse);
      // deeplink: without the host scheme list -- never; with a scheme not in the list -- no.
      expect(run({'type': 'deeplink', 'params': {'url': 'myapp://offers'}}), isFalse);
      expect(run({'type': 'deeplink', 'params': {'url': 'myapp://offers'}}, schemes: const ['other']), isFalse);
      expect(links, isEmpty);
      expect(run({'type': 'deeplink', 'params': {'url': 'myapp://offers'}}, schemes: const ['myapp']), isTrue);
      expect(links.single, 'myapp://offers');
      // A scheme forbidden by the contract does not become a link, even if the host named it.
      expect(run({'type': 'deeplink', 'params': {'url': 'javascript:alert(1)'}}, schemes: const ['javascript']), isFalse);
      expect(links, hasLength(1));
      // close.
      expect(run({'type': 'close'}), isTrue);
      expect(closed, 1);
    });

    test('runStandardAction: the scheme list holds only strings; the executor gets the verified string', () {
      final links = <String>[];
      final action = ButtonAction.parse({
        'type': 'deeplink',
        'params': {'url': 'myapp://offers?x=%zz'},
      }).handOver((_) => null);
      // The list is read ONCE: a lazily computed one could give
      // a different result the second time. Dart rejects non-strings in the list already by type.
      var passes = 0;
      Iterable<String> lazy() sync* {
        passes += 1;
        yield 'myapp';
      }

      expect(runStandardAction(action, deeplinkSchemes: lazy(), openDeeplink: links.add), isTrue);
      expect(passes, 1);
      links.clear();
      // A "set" list: works just like a list.
      expect(runStandardAction(action, deeplinkSchemes: {'myapp'}, openDeeplink: links.add), isTrue);
      // The executor gets the same string, byte for byte, even if `Uri` cannot parse it.
      expect(links.single, 'myapp://offers?x=%zz');
    });

    test('uri is a convenience, not a verdict: null for an address the platform could not parse', () {
      final handed = ButtonAction.parse({
        'type': 'deeplink',
        'params': {'url': 'myapp://h:99999999999999999999/'},
      }).handOver((_) => null);
      final link = handed.standard! as DeeplinkAction;
      expect(link.url, 'myapp://h:99999999999999999999/');
      expect(link.uri, isNull);
      expect(() => link.uri?.port, returnsNormally);
      expect((ButtonAction.parse({'type': 'openUrl', 'params': {'url': 'https://example.com/a'}}).handOver((_) => null).standard! as OpenUrlAction).uri?.host, 'example.com');
    });
  });

  group('artifact mirror', () {
    final actions = _obj(_schema['x-actions']);
    final forms = _obj(actions['forms']);
    final httpsUrl = _obj(forms['httpsUrl']);
    final appLink = _obj(forms['appLink']);
    final compatibility = _obj(_schema['x-compatibility']);
    final policy = _obj(compatibility['policy']);

    test('the reader version is the same as in the artifact (not lower than 9.9.0)', () {
      expect(SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 9, 0)), greaterThanOrEqualTo(0));
      expect(_schema['x-schemaVersion'], kSupportedSchemaVersion);
    });

    test('x-actions: executors, catalog, forms, order of problems', () {
      expect(actions['executors'], ActionExecutor.values.map((e) => e.name));
      expect(actions['problems'], ActionParamProblem.values.map((p) => p.wire));
      expect(actions['problemOrder'], kActionProblemOrder);
      final catalog = (actions['catalog']! as List<Object?>).cast<_Json>();
      expect(catalog.map((entry) => entry['type']), kActionCatalog.map((entry) => entry.type));
      expect(catalog.map((entry) => entry['type']).skip(7), ['setValue', 'toggleValue'], reason: 'the two write actions come last');
      for (var index = 0; index < kActionCatalog.length; index += 1) {
        final artifact = catalog[index];
        final mine = kActionCatalog[index];
        expect(artifact['executor'], mine.executor.name, reason: mine.type);
        final params = (artifact['params']! as List<Object?>).cast<_Json>();
        expect(params, hasLength(mine.params.length), reason: mine.type);
        for (var p = 0; p < params.length; p += 1) {
          expect(params[p]['name'], mine.params[p].name);
          expect(params[p]['form'], mine.params[p].form.name);
          expect(params[p]['required'], mine.params[p].required);
          expect(params[p]['bindable'], mine.params[p].bindable);
        }
      }
    });

    test('form expressions and forbidden schemes -- verbatim from the artifact', () {
      expect(kHttpsUrlPatternSource, httpsUrl['pattern']);
      expect(httpsUrl['maxLength'], kActionUrlMaxLength);
      expect(kAppLinkPatternSource, appLink['pattern']);
      expect(kAppLinkSchemePatternSource, appLink['schemePattern']);
      expect(appLink['maxLength'], kActionUrlMaxLength);
      expect(appLink['forbiddenSchemes'], kForbiddenLinkSchemes);
    });

    test('x-actions.params: key, limits, reserved names -- verbatim from the artifact', () {
      final params = _obj(actions['params']);
      expect(params['keyPattern'], kParamKeyPatternSource);
      expect(params['keyMaxLength'], kParamKeyMaxLength);
      expect(params['valueMaxLength'], kParamValueMaxLength);
      expect(params['valueType'], 'string');
      expect(params['reservedNames'], ['__proto__', 'constructor', 'prototype']);
      expect(params['invalidEntry'], 'skip');
      // Both places of the schema where the record key lives say the same thing.
      final buttonAction = _obj(_obj(_schema[r'$defs'])['ButtonAction']);
      final props = _obj(buttonAction['properties']);
      expect(_obj(_obj(props['params'])['propertyNames'])['pattern'], params['keyPattern']);
      expect(_obj(_obj(props['paramBindings'])['propertyNames'])['pattern'], params['keyPattern']);
    });

    test('paramBinding, track, carryRecord', () {
      final binding = _obj(actions['paramBinding']);
      expect(binding['field'], 'paramBindings');
      expect(binding['accepts'], 'non-empty-string');
      expect(binding['maxLength'], kActionUrlMaxLength);
      expect(binding['otherwise'], 'literal-from-params');
      expect(binding['readWith'], 'data-scope-of-the-node');

      final track = _obj(actions['track']);
      expect(track['namePattern'], kTrackNamePatternSource);
      expect(track['eventMaxLength'], kTrackEventMaxLength);
      expect(track['paramKeyMaxLength'], kTrackParamKeyMaxLength);
      expect(track['paramValueMaxLength'], kTrackParamValueMaxLength);
      expect(track['maxParams'], kTrackMaxParams);
      expect(track['delivery'], 'before-the-action');

      expect(_obj(actions['carryRecord']), {'field': 'carryRecord', 'on': 'navigate'});
      expect(_obj(actions['handed'])['standardTypes'], [kOpenUrlActionType, kDeeplinkActionType, kCloseActionType]);
      expect(_obj(actions['handed'])['fields'], ['type', 'params', 'standard', 'invalid']);
      expect(actions['cases'], 'contract/fixtures/actions/action-cases.json');
    });

    test('x-screenShown: reasons, transitions, fields', () {
      final block = _obj(_schema['x-screenShown']);
      expect(block['causes'], ScreenShownCause.values.map((c) => c.wire));
      expect(block['transitions'], {'start': 'entry', 'push': 'forward', 'pop': 'back', 'switch': 'switch'});
      expect(block['fields'], ['documentId', 'screenId', 'entry', 'presentation', 'cause', 'depth', 'record']);
      expect(block['entry'], 'requested-name-known-to-document-else-null');
      expect(block['depth'], 'stack-length-after-change-first-is-1');
      expect(block['record'], 'record-the-screen-was-opened-with-else-null');
    });

    test('fourteen policy rows and five capabilities', () {
      expect(kActionPolicy, hasLength(14));
      for (final entry in kActionPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // They come before the thirteen 9.9.0 rows (`kMediaChromePolicy`) and the ten 9.10.0 rows (`kOffsetPolicy`), after the 9.7.0 and earlier rows.
      expect(
        policy.keys.toList().sublist(policy.length - 14 - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - kMediaChromePolicy.length - kOffsetPolicy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length)),
        kActionPolicy.keys.toList(),
      );

      final features = _obj(compatibility['features']);
      for (final feature in ['actionCatalog', 'actionParamBinding', 'actionTrack', 'screenShownEvent', 'carryRecord']) {
        expect(features[feature], '9.8.0', reason: feature);
        expect(kFeatureCatalog[feature], '9.8.0', reason: feature);
        expect(supportsFeature(feature, readerVersion: '9.7.0'), isFalse, reason: feature);
        expect(supportsFeature(feature), isTrue, reason: feature);
      }
    });

    test('the action params limit is 2048 characters (was 128)', () {
      final defs = _obj(_schema[r'$defs']);
      final buttonAction = _obj(defs['ButtonAction']);
      final params = _obj(_obj(buttonAction['properties'])['params']);
      expect(_obj(params['additionalProperties'])['maxLength'], kActionUrlMaxLength);
    });
  });
}

/// Focus is on the button labelled [label]: the closest `Focus` above its label --
/// the button's own Material focus.
Future<void> _focusButton(WidgetTester tester, String label) async {
  final text = find.text(label).last;
  await tester.ensureVisible(text);
  Focus.of(tester.element(text), scopeOk: false).requestFocus();
  await tester.pump();
}

/// The label of the button of step `index` in the case document.
String _label(int index) => 'step $index';

({UiDocument document, _Json json}) _flowDocument(_Json row, Map<String, Object?> data, {_Json? newVersion}) {
  // A new version (step `newVersion`) changes the screens, and if needed the start and entries;
  // step buttons land on the same screens as in the first version, and
  // are skipped where the screen no longer exists.
  final screens = _obj(newVersion?['screens'] ?? row['screens']).cast<String, String>();
  final initial = (newVersion?['initial'] ?? row['initial']) as String;
  final entryPoints = newVersion?['entryPoints'] ?? row['entryPoints'];
  final children = <String, List<_Json>>{
    for (final id in screens.keys)
      id: [
        // A screen without content is not needed by the test, but is not empty either.
        {
          'id': 'title-$id',
          'type': 'Text',
          'props': {
            'content': {'kind': 'literal', 'value': 'screen $id'},
            'align': 'start',
            'overflow': 'visible',
          },
        },
      ],
  };

  var top = ((_obj(row['start'])['stack']! as List<Object?>).cast<String>()).last;
  final steps = (row['steps']! as List<Object?>).cast<_Json>();
  for (var index = 0; index < steps.length; index += 1) {
    final step = steps[index];
    if (step['do'] == 'press') {
      _Json button = {
        'id': 'step-$index',
        'type': 'Button',
        'props': {
          'label': {'kind': 'literal', 'value': _label(index)},
          'variant': 'primary',
          'fullWidth': true,
          'action': _materialize(step['action']),
        },
      };
      final instances = (step['instances']! as List<Object?>).cast<_Json>();
      for (var depth = instances.length - 1; depth >= 0; depth -= 1) {
        final source = 'c${index}x$depth';
        data[source] = [instances[depth]['fields']];
        button = {
          'id': 'list-$index-$depth',
          'type': 'Repeater',
          'props': {'source': source, 'item': instances[depth]['item'], 'direction': 'column', 'gap': 'none'},
          'children': [button],
        };
      }
      children[top]?.add(button);
    }
    top = ((_obj(step['expect'])['stack']! as List<Object?>).cast<String>()).last;
  }

  final json = {
    'schemaVersion': kSupportedSchemaVersion,
    'documentId': row['documentId'],
    'name': 'case',
    'initialScreenId': initial,
    'entryPoints': entryPoints,
    'screens': [
      for (final entry in screens.entries)
        screenEntry(entry.key, children[entry.key]!, presentation: entry.value == 'modal' ? 'modal' : null),
    ],
  };
  return (document: UiDocument.fromJson(json), json: json);
}
