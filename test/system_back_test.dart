import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// SYSTEM BACK AND THE DOCUMENT STACK.
///
/// The system back event and the document stack used to be unrelated: on the
/// third screen of a flow, Android back left the whole flow (or the app). These
/// tests check that the event steps back INSIDE the document while it can, and
/// reaches the host route only on the first screen.
///
/// The system button is simulated with `tester.binding.handlePopRoute()` - the
/// same entry point the platform uses (Android, browser back button).
Map<String, Object?> _navigate(String screenId) => {
  'type': ButtonAction.navigate,
  'params': {ButtonAction.screenIdParam: screenId},
};

UiDocument _threeScreens({String? thirdPresentation, String documentId = 'flow'}) => docWithScreens([
  screenEntry('first', [
    textNode('Перший екран', id: 't1'),
    buttonNode('До другого', action: _navigate('second'), id: 'to-second'),
  ]),
  screenEntry('second', [
    textNode('Другий екран', id: 't2'),
    buttonNode('До третього', action: _navigate('third'), id: 'to-third'),
  ]),
  screenEntry('third', [textNode('Третій екран', id: 't3')], presentation: thirdPresentation),
], initialScreenId: 'first', documentId: documentId);

/// Host app: a home page from which the flow is opened as a SEPARATE route, so
/// "the host route was popped" shows up as a return to the home page.
Future<void> _pumpHost(
  WidgetTester tester,
  UiDocument doc, {
  ScreenFlowController? controller,
  ScreenFlowBackCallback? onSystemBack,
  bool handleSystemBack = true,
  SduiActionCallback? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: renderDocument(
                      doc,
                      theme: RenderTheme.fallback(),
                      data: const {},
                      controller: controller,
                      onSystemBack: onSystemBack,
                      handleSystemBack: handleSystemBack,
                      onAction: onAction,
                    ),
                  ),
                ),
              ),
              child: const Text('Відкрити потік'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Відкрити потік'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// System back. Returns whether anyone handled the event: `false` on Android
/// means "the app goes to background".
Future<bool> _systemBack(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

/// What the flow route tells the system in advance - this is what the predictive back gesture reads.
RoutePopDisposition _disposition(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.byType(ScreenFlow)))!.popDisposition;

void main() {
  group('system back in a flow', () {
    testWidgets('on the second screen goes back to the first and does NOT pop the host route', (tester) async {
      final host = <String>[];
      await _pumpHost(tester, _threeScreens(), onAction: (a, id) => host.add(a.type));
      await _tap(tester, 'До другого');
      expect(find.text('Другий екран'), findsOneWidget);

      expect(await _systemBack(tester), isTrue);

      expect(find.text('Перший екран'), findsOneWidget);
      expect(find.text('Другий екран'), findsNothing);
      expect(find.text('Відкрити потік'), findsNothing, reason: 'the flow route must stay');
      // The step happened inside the document - the host was not asked.
      expect(host, isEmpty);
    });

    testWidgets('from the third screen goes one step at a time, not straight out', (tester) async {
      await _pumpHost(tester, _threeScreens());
      await _tap(tester, 'До другого');
      await _tap(tester, 'До третього');

      await _systemBack(tester);
      expect(find.text('Другий екран'), findsOneWidget);
      await _systemBack(tester);
      expect(find.text('Перший екран'), findsOneWidget);
      await _systemBack(tester);
      expect(find.text('Відкрити потік'), findsOneWidget);
      expect(find.byType(ScreenFlow), findsNothing);
    });

    testWidgets('on the first screen the host route gets the event', (tester) async {
      await _pumpHost(tester, _threeScreens());

      expect(await _systemBack(tester), isTrue);

      expect(find.text('Відкрити потік'), findsOneWidget);
      expect(find.byType(ScreenFlow), findsNothing);
    });

    testWidgets('a modal screen closes, the screen under it stays', (tester) async {
      await _pumpHost(tester, _threeScreens(thirdPresentation: 'modal'));
      await _tap(tester, 'До другого');
      await _tap(tester, 'До третього');
      // The sheet lies OVER the second screen: both are on the glass.
      expect(find.text('Третій екран'), findsOneWidget);
      expect(find.text('Другий екран'), findsOneWidget);

      await _systemBack(tester);

      expect(find.text('Третій екран'), findsNothing);
      expect(find.text('Другий екран'), findsOneWidget);
    });

    /*
     * `canPop` is not an implementation detail: the Android 14 predictive gesture
     * picks the animation BEFORE the gesture completes, and asks exactly this.
     * "Always false with a manual pop" would break the animation on the first
     * screen; "always true" would pop the route in the middle of the flow.
     */
    testWidgets('`canPop` of the route changes along with the stack', (tester) async {
      await _pumpHost(tester, _threeScreens());
      expect(_disposition(tester), RoutePopDisposition.pop);

      await _tap(tester, 'До другого');
      expect(_disposition(tester), RoutePopDisposition.doNotPop);

      await _tap(tester, 'До третього');
      expect(_disposition(tester), RoutePopDisposition.doNotPop);

      await _systemBack(tester);
      expect(_disposition(tester), RoutePopDisposition.doNotPop);

      await _systemBack(tester);
      expect(_disposition(tester), RoutePopDisposition.pop);
    });

    testWidgets('flow on the ROOT route: a step back is handled, from the first screen it is not', (
      tester,
    ) async {
      await pumpDocument(tester, _threeScreens());
      await _tap(tester, 'До другого');

      expect(await _systemBack(tester), isTrue);
      expect(find.text('Перший екран'), findsOneWidget);

      // Nothing more to pop: the "not handled" answer is what means "send the
      // app to background" on Android.
      expect(await _systemBack(tester), isFalse);
      expect(find.text('Перший екран'), findsOneWidget);
    });
  });

  group('host intercepts', () {
    testWidgets('`handleSystemBack: false` — the event goes to the host even mid-flow', (
      tester,
    ) async {
      await _pumpHost(tester, _threeScreens(), handleSystemBack: false);
      await _tap(tester, 'До другого');
      expect(_disposition(tester), RoutePopDisposition.pop);

      await _systemBack(tester);

      expect(find.text('Відкрити потік'), findsOneWidget);
      expect(find.byType(ScreenFlow), findsNothing);
    });

    testWidgets('`onSystemBack` returned true - the stack does not move and the route stays', (
      tester,
    ) async {
      var asked = 0;
      var handled = true;
      await _pumpHost(
        tester,
        _threeScreens(),
        onSystemBack: () {
          asked += 1;
          return handled;
        },
      );

      // The host is not asked on the first screen: the event is theirs anyway.
      await _tap(tester, 'До другого');
      await _systemBack(tester);
      expect(asked, 1);
      expect(find.text('Другий екран'), findsOneWidget);
      expect(find.text('Відкрити потік'), findsNothing);

      // "Not mine" - the flow steps back by itself.
      handled = false;
      await _systemBack(tester);
      expect(asked, 2);
      expect(find.text('Перший екран'), findsOneWidget);

      // First screen: the call stays silent, the route is popped.
      await _systemBack(tester);
      expect(asked, 2);
      expect(find.text('Відкрити потік'), findsOneWidget);
    });
  });

  group('stack controller', () {
    testWidgets('reports whether there is somewhere to go back to, and which screen is shown', (tester) async {
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified += 1);

      // Before the flow: "nowhere to go and unknown where".
      expect(controller.canGoBack, isFalse);
      expect(controller.currentScreenId, isNull);

      await _pumpHost(tester, _threeScreens(), controller: controller);
      expect(controller.canGoBack, isFalse);
      expect(controller.currentScreenId, 'first');
      expect(notified, 1, reason: 'the flow appearing changes the answer');

      await _tap(tester, 'До другого');
      expect(controller.canGoBack, isTrue);
      expect(controller.currentScreenId, 'second');
      expect(notified, 2);
    });

    testWidgets('`goBack` takes the same step as `navigate.back`', (tester) async {
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      final host = <String>[];
      await _pumpHost(tester, _threeScreens(), controller: controller, onAction: (a, _) => host.add(a.type));
      await _tap(tester, 'До другого');
      await _tap(tester, 'До третього');

      expect(controller.goBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Другий екран'), findsOneWidget);
      expect(controller.currentScreenId, 'second');

      expect(controller.goBack(), isTrue);
      await tester.pumpAndSettle();
      expect(controller.canGoBack, isFalse);

      // The controller does not leave the first screen and does not call the host:
      // leaving the flow is up to whoever called `goBack`.
      expect(controller.goBack(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Перший екран'), findsOneWidget);
      expect(host, isEmpty);
    });

    testWidgets('works even when system back interception is off', (tester) async {
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await _pumpHost(tester, _threeScreens(), controller: controller, handleSystemBack: false);
      await _tap(tester, 'До другого');

      expect(controller.goBack(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Перший екран'), findsOneWidget);
    });

    testWidgets('after the flow is removed answers "nowhere to go" and tells the listeners', (
      tester,
    ) async {
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await _pumpHost(tester, _threeScreens(), controller: controller, handleSystemBack: false);
      await _tap(tester, 'До другого');
      var notified = 0;
      controller.addListener(() => notified += 1);

      await _systemBack(tester); // the host popped the route together with the flow

      expect(controller.canGoBack, isFalse);
      expect(controller.currentScreenId, isNull);
      expect(controller.goBack(), isFalse);
      expect(notified, 1);
    });

    testWidgets('a different document resets the stack - the controller sees it', (tester) async {
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      Widget app(UiDocument doc) => MaterialApp(
        home: Scaffold(
          body: renderDocument(doc, theme: RenderTheme.fallback(), data: const {}, controller: controller),
        ),
      );
      await tester.pumpWidget(app(_threeScreens()));
      await _tap(tester, 'До другого');
      expect(controller.canGoBack, isTrue);
      var notified = 0;
      controller.addListener(() => notified += 1);

      // A different `documentId` is a different document, not a new copy of the same one.
      await tester.pumpWidget(app(_threeScreens(documentId: 'another')));
      await tester.pumpAndSettle();

      expect(controller.canGoBack, isFalse);
      expect(controller.currentScreenId, 'first');
      expect(notified, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new copy of the SAME document does not reset the stack (9.8.0, rerender)', (tester) async {
      // A host that parses JSON in `build` passes a new object every time. Resetting
      // the stack on that would return the person to the first screen and emit a
      // "screen shown" event that never happened; the `flowCases` table says: not a show.
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      Widget app(UiDocument doc) => MaterialApp(
        home: Scaffold(
          body: renderDocument(doc, theme: RenderTheme.fallback(), data: const {}, controller: controller),
        ),
      );
      await tester.pumpWidget(app(_threeScreens()));
      await _tap(tester, 'До другого');

      await tester.pumpWidget(app(_threeScreens()));
      await tester.pumpAndSettle();

      expect(controller.canGoBack, isTrue);
      expect(controller.currentScreenId, 'second');
      expect(find.text('Другий екран'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('flow inside host navigation', () {
    /*
     * A host dialog is a separate route OVER the flow route. System back asks the
     * top route, so it closes; the flow `PopScope` is not touched at all. A
     * `didPopRoute` listener in the flow would step back in the document UNDER
     * the open dialog.
     */
    testWidgets('an open host dialog closes first, the document stack stays intact', (tester) async {
      await _pumpHost(tester, _threeScreens());
      await _tap(tester, 'До другого');
      showDialog<void>(
        context: tester.element(find.byType(ScreenFlow)),
        builder: (_) => const AlertDialog(title: Text('Діалог хоста')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Діалог хоста'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('Діалог хоста'), findsNothing);
      expect(find.text('Другий екран'), findsOneWidget);

      await _systemBack(tester);
      expect(find.text('Перший екран'), findsOneWidget);
    });

    /// Host tabs with their own `Navigator` per tab - a typical app.
    Widget nested(UiDocument doc, {required bool forwardBack, ScreenFlowController? controller}) {
      final nestedKey = GlobalKey<NavigatorState>();
      final navigator = Navigator(
        key: nestedKey,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => renderDocument(
                    doc,
                    theme: RenderTheme.fallback(),
                    data: const {},
                    controller: controller,
                  ),
                ),
              ),
              child: const Text('Відкрити у вкладці'),
            ),
          ),
        ),
      );
      return MaterialApp(
        home: Scaffold(
          body: forwardBack
              ? NavigatorPopHandler(
                  onPopWithResult: (_) => nestedKey.currentState!.maybePop(),
                  child: navigator,
                )
              : navigator,
        ),
      );
    }

    testWidgets('nested Navigator that the host forwards back to: a step in the document, then the route', (
      tester,
    ) async {
      await tester.pumpWidget(nested(_threeScreens(), forwardBack: true));
      await _tap(tester, 'Відкрити у вкладці');
      await _tap(tester, 'До другого');

      expect(await _systemBack(tester), isTrue);
      expect(find.text('Перший екран'), findsOneWidget);
      expect(find.text('Відкрити у вкладці'), findsNothing);

      // First document screen: the route of the NESTED navigator is popped.
      expect(await _systemBack(tester), isTrue);
      expect(find.text('Відкрити у вкладці'), findsOneWidget);
    });

    /*
     * THIS IS FLUTTER BEHAVIOR, NOT OURS: system back arrives at the root
     * `Navigator` and does not reach a nested one until the host forwards it
     * (`NavigatorPopHandler`). The test records the boundary: in such a host the
     * flow does not see the event, and the controller steps back.
     */
    testWidgets('nested Navigator WITHOUT forwarding: the event does not reach the flow, the controller works', (
      tester,
    ) async {
      final controller = ScreenFlowController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(nested(_threeScreens(), forwardBack: false, controller: controller));
      await _tap(tester, 'Відкрити у вкладці');
      await _tap(tester, 'До другого');

      expect(await _systemBack(tester), isFalse, reason: 'the root route is the only one - nothing to pop');
      expect(find.text('Другий екран'), findsOneWidget);

      expect(controller.canGoBack, isTrue);
      expect(controller.goBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Перший екран'), findsOneWidget);
    });
  });
}
