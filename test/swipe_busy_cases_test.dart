/// "SWIPE TO CONFIRM": THE END (schema 9.24.0, `x-swipeConfirmBusy`).
///
/// After the thumb is released past the threshold (or the key is pressed) the action runs at once, the thumb glides
/// to the end and STAYS there, busy, until the answer of the host. The `busy…` groups of
/// `fixtures/swipe-confirm/swipe-confirm-cases.json` run row by row by the rule, and the mechanism through a REAL
/// button and a real frame clock: who runs the action, what ends the waiting, what the busy button does not do.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/model/swipe_confirm.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table = jsonDecode(File('assets/contract/fixtures/swipe-confirm/swipe-confirm-cases.json').readAsStringSync()) as _Row;
final _Row _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();

Map<String, Object?> _button(Map<String, Object?> action) => {
  'id': 'btn',
  'type': 'Button',
  'props': <String, Object?>{
    'label': {'kind': 'literal', 'value': 'Pay'},
    'variant': 'primary',
    'action': action,
    'fullWidth': true,
    'confirm': 'swipe',
    'size': 'lg',
  },
};

const _hostAction = {'type': 'redeem', 'params': <String, String>{}};

Finder _thumb() => find.descendant(
  of: find.byType(SwipeConfirmTrack),
  matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle),
);

Finder _ring() => find.descendant(of: find.byType(SwipeConfirmTrack), matching: find.byType(RotationTransition));

void _view(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(345, 600);
  addTearDown(tester.view.reset);
}

/// Drags the thumb all the way and releases it.
Future<void> _swipe(WidgetTester tester) async {
  final track = tester.getRect(find.byType(SwipeConfirmTrack));
  final thumb = tester.getRect(_thumb());
  final gesture = await tester.startGesture(Offset(thumb.center.dx, track.center.dy));
  for (var i = 0; i < 10; i += 1) {
    await gesture.moveBy(Offset((track.width - thumb.width) / 10 * 1.05, 0));
    await tester.pump();
  }
  await gesture.up();
}

Future<void> _enter(WidgetTester tester) async {
  Focus.of(tester.element(find.descendant(of: find.byType(SwipeConfirmTrack), matching: find.byType(IntrinsicWidth))), scopeOk: false).requestFocus();
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
}

void main() {
  test('the groups have the promised rows', () {
    expect(_rows('busyReleaseCases'), hasLength(4));
    expect(_rows('busyEndCases'), hasLength(7));
    expect(_rows('busyRuleCases'), hasLength(10));
    expect(_table['afterAction'], isNull);
  });

  group('busyReleaseCases: what the thumb does after the action', () {
    ButtonAction action(String runner) => switch (runner) {
      'reader' => ButtonAction.parse({'type': 'navigate', 'params': {'screenId': 'next'}}),
      'host' => ButtonAction.parse({'type': 'redeem'}),
      'none' => ButtonAction.parse({'type': 'none'}),
      'invalid' => ButtonAction.parse({'type': 'openUrl', 'params': {'url': 'http://not-https.example/'}}),
      _ => fail('unknown runner $runner'),
    };
    for (final row in _rows('busyReleaseCases')) {
      test(row['name']! as String, () {
        final runner = swipeRunnerOf(action(row['runner']! as String).handOver((_) => null));
        expect(runner.name, row['runner']);
        expect(swipeAfterReleaseOf(runner) == SwipeAfterRelease.busy ? 'busy' : 'return', row['expect']);
      });
    }
  });

  group('busyEndCases: how the busy state ends', () {
    for (final row in _rows('busyEndCases')) {
      test(row['name']! as String, () {
        final outcome = swipeBusyOutcomeOf(SwipeBusyEvent.values.byName(row['event']! as String), promise: row['answer'] == 'promise');
        expect(outcome.name == 'back' ? 'return' : outcome.name, row['expect']);
      });
    }
  });

  group('busyRuleCases: the artifact and the code mirror', () {
    final block = _schema['x-swipeConfirmBusy']! as _Row;
    Object? at(String path) {
      Object? current = block;
      for (final part in path.split('.')) {
        current = (current! as Map)[part];
      }
      return current;
    }

    for (final row in _rows('busyRuleCases')) {
      test(row['name']! as String, () {
        final rule = row['rule']! as String;
        // `reducedMotion` and `shownAgain` carry the same text as the row, spelled the same way.
        expect(at(rule), row['expect']);
      });
    }
    test('the numbers', () {
      expect(block['completeMs'], kSwipeCompleteMs);
      expect(block['returnMs'], kSwipeReturnMs);
      expect((block['busy']! as _Row)['turnMs'], kSwipeSpinnerTurnMs);
      expect((block['ends']! as _Row)['noPromiseTimeoutMs'], kSwipeBusyMaxMs);
      expect(block['refines'], contains('x-swipeConfirm.afterAction'));
    });
  });

  group('on a real button', () {
    testWidgets('an action of the host without a promise: busy to the end, back after eight seconds', (tester) async {
      _view(tester);
      final calls = <String>[];
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) => calls.add(a.type));
      final start = tester.getRect(_thumb());
      final track = tester.getRect(find.byType(SwipeConfirmTrack));
      await _swipe(tester);
      expect(calls, ['redeem'], reason: 'the action runs at once, before the thumb arrives');
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getRect(_thumb()).left;
      expect(middle, greaterThan(start.left));
      await tester.pump(const Duration(milliseconds: 200));
      final end = tester.getRect(_thumb());
      expect(end.right, closeTo(track.right - 4, 1.5), reason: 'the thumb stands at the end');
      expect(_ring(), findsOneWidget, reason: 'the indicator instead of the glyph');
      expect(find.text('Pay'), findsOneWidget, reason: 'the label stays');

      // Nothing acts while busy: a second swipe, a tap, Enter.
      await tester.tapAt(track.center);
      await _enter(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(calls, ['redeem']);
      expect(tester.getRect(_thumb()), end);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 125));
      expect(tester.getRect(_thumb()).left, inExclusiveRange(start.left, end.left), reason: 'returning');
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(_thumb()), start);
      expect(_ring(), findsNothing);
      await _swipe(tester);
      expect(calls, ['redeem', 'redeem'], reason: 'the button acts again');
      await tester.pump(const Duration(seconds: 9));
    });

    testWidgets('a Future of the host is held past the time limit; completing it returns the thumb in 250 ms', (tester) async {
      _view(tester);
      final answer = Completer<void>();
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) => answer.future);
      final start = tester.getRect(_thumb());
      await _swipe(tester);
      await tester.pump(const Duration(seconds: 20));
      expect(_ring(), findsOneWidget, reason: 'a promise is held');
      answer.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(tester.getRect(_thumb()).left, greaterThan(start.left));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(_thumb()), start);
      expect(_ring(), findsNothing);
    });

    testWidgets('a rejected Future returns the thumb as well', (tester) async {
      _view(tester);
      final answer = Completer<void>();
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) => answer.future);
      final start = tester.getRect(_thumb());
      await _swipe(tester);
      await tester.pump(const Duration(seconds: 1));
      answer.completeError(StateError('refused'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(_thumb()), start);
    });

    testWidgets('a Future that is already done does not cut the glide short', (tester) async {
      _view(tester);
      final start = Rect.zero;
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) => Future<void>.value());
      final begin = tester.getRect(_thumb());
      await _swipe(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(_thumb()).left, greaterThan(begin.left), reason: 'still gliding to the end');
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getRect(_thumb()), begin);
      expect(start, Rect.zero);
    });

    testWidgets('HostActions.handle answers with the Future of its handler', (tester) async {
      _view(tester);
      final answer = Completer<void>();
      final actions = HostActions(handlers: {'redeem': (call) => answer.future});
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onRecordAction: actions.handle);
      final begin = tester.getRect(_thumb());
      await _swipe(tester);
      await tester.pump(const Duration(seconds: 12));
      expect(_ring(), findsOneWidget);
      answer.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(_thumb()), begin);
    });

    for (final (name, action) in <(String, Map<String, Object?>)>[
      ('none', {'type': 'none'}),
      ('an invalid standard action', {'type': 'openUrl', 'params': {'url': 'http://not-https.example/'}}),
    ]) {
      testWidgets('$name: the thumb returns at once and is never busy', (tester) async {
        _view(tester);
        await pumpDocument(tester, UiDocumentBuilder.bare([_button(action)]));
        final start = tester.getRect(_thumb());
        await _swipe(tester);
        await tester.pump(const Duration(milliseconds: 100));
        expect(_ring(), findsNothing);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getRect(_thumb()), start);
      });
    }

    testWidgets('the keyboard acts at once and then the same as after a swipe', (tester) async {
      _view(tester);
      final calls = <String>[];
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) => calls.add(a.type));
      final start = tester.getRect(_thumb());
      await _enter(tester);
      expect(calls, ['redeem']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getRect(_thumb()).left, greaterThan(start.left));
      expect(_ring(), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
    });

    testWidgets('reduced motion: the thumb jumps, the indicator stands still', (tester) async {
      _view(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), disableAnimations: true, onAction: (a, id) {});
      final start = tester.getRect(_thumb());
      final track = tester.getRect(find.byType(SwipeConfirmTrack));
      await _swipe(tester);
      await tester.pump();
      expect(tester.getRect(_thumb()).right, closeTo(track.right - 4, 1.5));
      final before = tester.widget<RotationTransition>(_ring()).turns.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<RotationTransition>(_ring()).turns.value, before, reason: 'no rotation');
      await tester.pump(const Duration(seconds: 9));
      expect(tester.getRect(_thumb()), start, reason: 'and back by the limit, at once');
    });

    testWidgets('the indicator turns once in 800 ms', (tester) async {
      _view(tester);
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) {});
      await _swipe(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final turns = tester.widget<RotationTransition>(_ring()).turns;
      final first = turns.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(turns.value, closeTo((first + 0.5) % 1, 0.02));
      await tester.pump(const Duration(seconds: 9));
    });

    testWidgets('the name is the label and the busy button is not an enabled control', (tester) async {
      _view(tester);
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, UiDocumentBuilder.bare([_button(_hostAction)]), onAction: (a, id) {});
      await _swipe(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final node = tester.getSemantics(find.byType(SwipeConfirmTrack));
      // ignore: deprecated_member_use
      expect(node.label, 'Pay');
      expect(node.flagsCollection.isEnabled.name, 'isFalse');
      handle.dispose();
      await tester.pump(const Duration(seconds: 9));
    });

    testWidgets('an action of the reader: the button goes with its screen, and a screen shown again has the thumb at the start', (tester) async {
      _view(tester);
      final doc = docWithScreens([
        screenEntry('first', [
          _button({'type': 'navigate', 'params': {'screenId': 'second'}}),
        ]),
        screenEntry('second', [
          textNode('Done', id: 'done'),
          buttonNode('Back', action: const {'type': 'navigate.back'}, id: 'back'),
        ]),
      ], initialScreenId: 'first');
      await pumpDocument(tester, doc);
      final start = tester.getRect(_thumb());
      await _swipe(tester);
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Done'), findsOneWidget);
      expect(find.byType(SwipeConfirmTrack), findsNothing);
      await tester.tap(find.text('Back'));
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SwipeConfirmTrack), findsOneWidget);
      expect(tester.getRect(_thumb()), start);
      expect(_ring(), findsNothing);
    });
  });
}
