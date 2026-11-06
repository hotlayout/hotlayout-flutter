/// The fill of a "swipe to confirm" button when the host keeps the stack of screens (`renderScreen`): it lies in the
/// nearest `Overlay`, so it outlives the route the button was on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_paint.dart';
import 'package:hotlayout_flutter/src/render/swipe_ripple_layer.dart';

import 'support/fixtures.dart';

Finder _tracks() => find.byType(SwipeConfirmTrack);

Finder _fill() => find.byKey(kSwipeRippleLayerKey);

void _view(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.reset);
}

Future<void> _play(WidgetTester tester, int ms) async {
  for (var spent = 0; spent < ms; spent += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _swipe(WidgetTester tester, int index) async {
  final track = tester.getRect(_tracks().at(index));
  final thumb = tester.getRect(find.descendant(of: _tracks().at(index), matching: find.byKey(kSwipeThumbKey)));
  final travel = track.width - thumb.width - 2 * (thumb.left - track.left);
  final gesture = await tester.startGesture(Offset(thumb.center.dx, track.center.dy));
  for (var i = 0; i < 10; i += 1) {
    await gesture.moveBy(Offset(travel * 1.05 / 10, 0));
    await tester.pump();
  }
  await gesture.up();
}

Route<void> _plainRoute(Widget page) => PageRouteBuilder<void>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

class _Host {
  final navigator = GlobalKey<NavigatorState>();
  final actions = <String>[];
  final covered = <bool>[];

  Widget screen() {
    final doc = loadFixture('swipe-motion-screens');
    return renderScreen(
      doc.screens.first,
      theme: RenderTheme.fallback(),
      data: const {},
      onScreenCovered: covered.add,
      onAction: (action, nodeId) {
        actions.add(action.type);
        if (action.type == 'navigate' && navigator.currentState != null) {
          navigator.currentState!.push(_plainRoute(const Scaffold(body: Center(child: Text('Next route')))));
        }
      },
    );
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: screen()),
      ),
    );
    await tester.pump();
  }
}

void main() {
  group('the fill under renderScreen', () {
    testWidgets('grows over the screen first, and the action reaches the host once it is covered', (tester) async {
      _view(tester);
      final host = _Host();
      await host.pump(tester);
      await _swipe(tester, 0);
      await _play(tester, 1050);
      expect(_fill(), findsOneWidget, reason: 'the circle grows in the overlay');
      expect(host.actions, isEmpty, reason: 'the action waits for the cover');
      expect(host.covered, [true], reason: 'told before the action');

      await _play(tester, 800);
      expect(host.actions, ['navigate']);
      expect(find.text('Next route'), findsOneWidget);
      expect(_fill(), findsOneWidget, reason: 'the fill outlives the route it started on');
      expect(tester.widget<Opacity>(_fill()).opacity, lessThan(1));
      expect(host.covered, [true]);

      await _play(tester, 250);
      expect(_fill(), findsNothing);
      expect(host.actions, ['navigate'], reason: 'the action ran once');
      expect(host.covered, [true, false]);
    });

    testWidgets('a host callback that throws is reported and does not leave the fill on the screen', (tester) async {
      _view(tester);
      final covered = <bool>[];
      var taps = 0;
      final doc = loadFixture('swipe-motion-screens');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () => taps += 1, child: const Text('Host button')),
                Expanded(
                  child: renderScreen(
                    doc.screens.first,
                    theme: RenderTheme.fallback(),
                    data: const {},
                    onScreenCovered: covered.add,
                    onAction: (action, nodeId) => throw StateError('host failure'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await _swipe(tester, 0);
      await _play(tester, 1900);
      expect(tester.takeException(), isA<StateError>(), reason: 'the failure of the host reaches the error report');
      await _play(tester, 1000);
      expect(_fill(), findsNothing, reason: 'the fill fades away whatever the action did');
      expect(covered, [true, false]);
      await tester.tapAt(tester.getCenter(find.text('Host button')));
      await tester.pump();
      expect(taps, 1, reason: 'presses reach the host again');
    });

    testWidgets('a button that leaves before the cover takes the fill with it and nothing runs', (tester) async {
      _view(tester);
      final host = _Host();
      await host.pump(tester);
      await _swipe(tester, 0);
      await _play(tester, 1250);
      expect(_fill(), findsOneWidget);

      host.navigator.currentState!.pushReplacement(_plainRoute(const Scaffold(body: Text('Elsewhere'))));
      await _play(tester, 100);
      expect(find.text('Elsewhere'), findsOneWidget);
      expect(_fill(), findsNothing);
      expect(host.actions, isEmpty);
      await _play(tester, 1000);
      expect(host.actions, isEmpty);
      expect(host.covered, [true, false]);
    });

    testWidgets('the fill is clipped by the overlay and measured from it', (tester) async {
      _view(tester);
      final host = _Host();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: host.navigator,
          home: Scaffold(
            body: Padding(padding: const EdgeInsets.fromLTRB(0, 100, 0, 0), child: host.screen()),
          ),
        ),
      );
      await tester.pump();
      await _swipe(tester, 0);
      await _play(tester, 1000);
      expect(_fill(), findsOneWidget);
      expect(find.ancestor(of: _fill(), matching: find.byType(ClipRect)), findsWidgets);
      expect(tester.getSize(find.ancestor(of: _fill(), matching: find.byType(ClipRect)).first), const Size(393, 852));
    });

    testWidgets('with no Overlay above there is no fill and the action runs at once', (tester) async {
      _view(tester);
      final host = _Host();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(393, 852)),
            child: host.screen(),
          ),
        ),
      );
      await tester.pump();
      await _swipe(tester, 0);
      await _play(tester, 1000);
      expect(host.actions, ['navigate']);
      expect(_fill(), findsNothing);
      expect(host.covered, isEmpty);
    });
  });
}
