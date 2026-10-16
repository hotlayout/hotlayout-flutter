/// `HostActions`: the host's own actions routed by type, the standard actions
/// through their check, and everything that was not performed in one place.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import 'support/fixtures.dart';

ButtonAction _action(String type, [Map<String, String> params = const {}]) =>
    ButtonAction.parse({'type': type, 'params': params}).handOver((_) => null);

void main() {
  test('a handler gets the call by type, with the node and the record', () {
    final calls = <HostActionCall>[];
    final actions = HostActions(handlers: {'redeem': calls.add});
    actions.handle(_action('redeem', {'rewardId': 'r1'}), 'btn', {'reward.id': 'r2'});
    expect(calls.single.type, 'redeem');
    expect(calls.single.nodeId, 'btn');
    expect(calls.single.params, {'rewardId': 'r1'});
    expect(calls.single.record, {'reward.id': 'r2'});
  });

  test('valueOf reads the parameter first, then the record, as text', () {
    final call = HostActionCall(
      action: _action('redeem', {'id': 'param'}),
      nodeId: 'n',
      record: {'id': 'record', 'reward.price': 300, 'reward.new': true, 'reward.tags': ['a']},
    );
    expect(call.valueOf('id'), 'param');
    expect(call.valueOf('reward.price'), '300');
    expect(call.valueOf('reward.new'), 'true');
    expect(call.valueOf('reward.tags'), isNull, reason: 'a list is not a value of one field');
    expect(call.valueOf('missing'), isNull);
  });

  test('an action without a handler is a miss, with the reason', () {
    final misses = <(String, HostActionMiss)>[];
    final actions = HostActions(onMiss: (call, reason) => misses.add((call.type, reason)));
    actions.handle(_action('share'), 'n', null);
    expect(misses, [('share', HostActionMiss.noHandler)]);
  });

  group('standard actions', () {
    test('openUrl runs only through its check and never reaches a handler', () {
      final opened = <String>[];
      final misses = <HostActionMiss>[];
      final actions = HostActions(openUrl: opened.add, onMiss: (_, reason) => misses.add(reason));
      actions.handle(_action('openUrl', {'url': 'https://example.com/terms'}), 'n', null);
      actions.handle(_action('openUrl', {'url': 'javascript:alert(1)'}), 'n', null);
      expect(opened, ['https://example.com/terms']);
      expect(misses, [HostActionMiss.invalid]);
    });

    test('a deeplink of a scheme the app does not own is not performed', () {
      final opened = <String>[];
      final misses = <HostActionMiss>[];
      final actions = HostActions(
        deeplinkSchemes: const ['myapp'],
        openDeeplink: opened.add,
        onMiss: (_, reason) => misses.add(reason),
      );
      actions.handle(_action('deeplink', {'url': 'myapp://wallet/add'}), 'n', null);
      actions.handle(_action('deeplink', {'url': 'otherapp://x'}), 'n', null);
      expect(opened, ['myapp://wallet/add']);
      expect(misses, [HostActionMiss.noExecutor]);
    });

    test('close without an executor is a miss', () {
      final misses = <HostActionMiss>[];
      HostActions(onMiss: (_, reason) => misses.add(reason)).handle(_action('close'), 'n', null);
      expect(misses, [HostActionMiss.noExecutor]);
    });

    test('a handler for a standard type is refused when the router is created', () {
      for (final type in ['openUrl', 'deeplink', 'close']) {
        expect(() => HostActions(handlers: {type: (_) {}}), throwsArgumentError, reason: type);
      }
    });
  });

  group('asynchronous handlers', () {
    test('a running handler blocks the same type; another type goes on', () async {
      final started = <String>[];
      final misses = <HostActionMiss>[];
      final gate = Completer<void>();
      final actions = HostActions(
        handlers: {
          'redeem': (call) async {
            started.add('redeem');
            await gate.future;
          },
          'copy': (call) => started.add('copy'),
        },
        onMiss: (_, reason) => misses.add(reason),
      );
      actions.handle(_action('redeem'), 'n', null);
      actions.handle(_action('redeem'), 'n', null);
      actions.handle(_action('copy'), 'n', null);
      expect(started, ['redeem', 'copy']);
      expect(misses, [HostActionMiss.busy]);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(actions.running, isEmpty);
      actions.handle(_action('redeem'), 'n', null);
      expect(started, ['redeem', 'copy', 'redeem']);
    });

    test('exclusive: false runs every press', () async {
      var runs = 0;
      final gate = Completer<void>();
      final actions = HostActions(
        exclusive: false,
        handlers: {
          'redeem': (call) async {
            runs += 1;
            await gate.future;
          },
        },
      );
      actions.handle(_action('redeem'), 'n', null);
      actions.handle(_action('redeem'), 'n', null);
      expect(runs, 2);
      gate.complete();
    });

    test('an error, thrown or from the Future, goes to onError and unblocks the type', () async {
      final errors = <Object>[];
      final actions = HostActions(
        handlers: {
          'sync': (call) => throw StateError('sync'),
          'async': (call) async => throw StateError('async'),
        },
        onError: (call, error, stack) => errors.add(error),
      );
      actions.handle(_action('sync'), 'n', null);
      actions.handle(_action('async'), 'n', null);
      await Future<void>.delayed(Duration.zero);
      expect(errors.map((e) => (e as StateError).message), ['sync', 'async']);
      expect(actions.running, isEmpty);
    });

    test('without onError an error is reported to Flutter, not thrown at the renderer', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      HostActions(handlers: {'boom': (call) => throw StateError('boom')}).handle(_action('boom'), 'n', null);
      expect(reported.single.library, 'hotlayout_flutter');
    });
  });

  testWidgets('wired into a flow: a press in a list row reaches its handler with the row record', (tester) async {
    final calls = <HostActionCall>[];
    final actions = HostActions(handlers: {'redeem': calls.add});
    final doc = docWithScreens([
      screenEntry('home', [
        {
          'id': 'rewards',
          'type': 'Repeater',
          'props': {'source': 'items', 'item': 'item', 'gap': 'none', 'direction': 'column'},
          'children': [
            {
              'id': 'redeem',
              'type': 'Button',
              'props': {
                'label': {'kind': 'binding', 'path': 'item.name', 'fallback': '—'},
                'variant': 'primary',
                'action': {'type': 'redeem'},
              },
            },
          ],
        },
      ]),
    ], initialScreenId: 'home');
    await pumpDocument(
      tester,
      doc,
      data: {
        'items': [
          {'id': 'a', 'name': 'Mug'},
          {'id': 'b', 'name': 'Bottle'},
        ],
      },
      onRecordAction: actions.handle,
    );
    await tester.tap(find.text('Bottle'));
    await tester.pump();
    expect(calls.single.valueOf('item.id'), 'b');
  });
}
