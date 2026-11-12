import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart' show kModalScrimOpacity;
import 'package:hotlayout_flutter/src/model/screen_transition.dart';
import 'package:hotlayout_flutter/src/model/sheet_dismiss.dart' show kSheetExit;
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_flow.dart' show kEdgeSwipeKey;
import 'package:hotlayout_flutter/src/render/screen_transitions.dart';
import 'package:hotlayout_flutter/src/render/tab_strip.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// TRANSITIONS BETWEEN SCREENS.
///
/// How a step of the stack looks is the contract's (`x-screenTransition`; the numbers and the plan are checked against
/// its table in `screen_transition_cases_test.dart`): the document says which screen is shown and why, and the flow
/// plays the plan. These tests hold two things. First, that each cause of a show moves in its own way, in the right
/// direction for the writing direction and for the right time, at the places the plan's frame says. Second, and more
/// important, that motion never touches the flow: the show event comes at the moment of the step, exactly once; the
/// stack, the session and the record are what they would be without motion; and a leaving screen takes no touches.

typedef _Json = Map<String, Object?>;

_Json _navigate(String screenId) => {
  'type': 'navigate',
  'params': {'screenId': screenId},
};

const _Json _back = {'type': 'navigate.back'};

_Json _boundText(String id, String path) => {
  'id': id,
  'type': 'Text',
  'props': {
    'content': {'kind': 'binding', 'path': path, 'fallback': 'nothing'},
  },
};

UiDocument _flow({
  String? secondPresentation,
  Object? secondPlacement,
  String documentId = 'flow',
  String? firstTransition,
  String? secondTransition,
}) => docWithScreens([
  {
    ...screenEntry('first', [
      textNode('First screen', id: 't1'),
      _boundText('pick-1', 'pick'),
      buttonNode('Pick B', action: {
        'type': 'setValue',
        'params': {'path': 'pick', 'value': 'B'},
      }, id: 'pick'),
      buttonNode('Next', action: _navigate('second'), id: 'next'),
    ]),
    'transition': ?firstTransition,
  },
  {
    ...screenEntry('second', [
      textNode('Second screen', id: 't2'),
      _boundText('pick-2', 'pick'),
      buttonNode('Back', action: _back, id: 'back'),
    ], presentation: secondPresentation, modalPlacement: secondPlacement),
    'transition': ?secondTransition,
  },
], initialScreenId: 'first', documentId: documentId);

Future<List<ScreenShown>> _pump(
  WidgetTester tester,
  UiDocument doc, {
  TargetPlatform? platform,
  bool disableAnimations = false,
  HotlayoutTransitions transitions = HotlayoutTransitions.platform,
  String locale = 'en',
  ScreenFlowController? controller,
}) async {
  final shown = <ScreenShown>[];
  await pumpDocument(
    tester,
    doc,
    platform: platform,
    disableAnimations: disableAnimations,
    transitions: transitions,
    locale: locale,
    controller: controller,
    onScreenShown: shown.add,
  );
  return shown;
}

/// Whether [text] is on screen and takes touches (not inside a scene that is leaving).
bool _touchable(WidgetTester tester, String text) {
  final element = tester.element(find.text(text));
  var touchable = true;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is IgnorePointer && widget.ignoring) touchable = false;
    return true;
  });
  return touchable;
}

/// The plan of a step between two screens that name nothing.
ScreenTransitionPlan _plan(StackStep step, {TransitionScreen? from, TransitionScreen? to, double width = 393}) =>
    screenTransitionPlan(
      step: step,
      from: from ?? const TransitionScreen(),
      to: to ?? const TransitionScreen(),
      areaWidth: width,
    );

void main() {
  const screenWidth = 800.0;

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final rtl in [false, true]) {
      final name = '${platform.name}, ${rtl ? 'rtl' : 'ltr'}';
      UiDocument doc() => _flow();
      // Toward the end of the line: right in left-to-right writing, left in right-to-left.
      final toEnd = rtl ? -1.0 : 1.0;

      testWidgets('forward: the new page comes in from the end of the line, the old one drifts back ($name)', (tester) async {
        final shown = await _pump(tester, doc(), platform: platform, locale: rtl ? 'ar' : 'en');
        final firstRest = tester.getTopLeft(find.text('First screen')).dx;
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('First screen'), findsOneWidget, reason: 'the covered page is still drawn');
        expect(_touchable(tester, 'First screen'), isFalse, reason: 'and takes no touches');
        expect(_touchable(tester, 'Second screen'), isTrue);
        expect(shown.map((event) => event.cause), [ScreenShownCause.entry, ScreenShownCause.forward],
            reason: 'the show is reported at the step, not at the end of the motion');

        // The numbers of the plan, on both platforms alike.
        final frame = screenTransitionFrame(_plan(StackStep.push), 100);
        final moving = tester.getTopLeft(find.text('Second screen')).dx;
        expect(moving - firstRest, closeTo(toEnd * frame.incoming.x * screenWidth, 1), reason: 'the new page');
        expect(tester.getTopLeft(find.text('First screen')).dx - firstRest,
            closeTo(toEnd * frame.outgoing.x * screenWidth, 1), reason: 'the old page drifts back by a share of the width');

        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump();
        expect(find.text('First screen'), findsNothing);
        expect(tester.getTopLeft(find.text('Second screen')).dx, closeTo(firstRest, 0.5));
        expect(shown, hasLength(2), reason: 'the end of the motion is not a show');
      });

      testWidgets('back: the page leaves toward the end of the line, the old one comes back ($name)', (tester) async {
        final shown = await _pump(tester, doc(), platform: platform, locale: rtl ? 'ar' : 'en');
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        final rest = tester.getTopLeft(find.text('Second screen')).dx;
        await tester.tap(find.text('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));

        expect(find.text('Second screen'), findsOneWidget, reason: 'the closed page is drawn while it leaves');
        expect(_touchable(tester, 'Second screen'), isFalse);
        expect(_touchable(tester, 'First screen'), isTrue);
        final frame = screenTransitionFrame(_plan(StackStep.pop), 75);
        expect(tester.getTopLeft(find.text('Second screen')).dx - rest, closeTo(toEnd * frame.outgoing.x * screenWidth, 1));
        expect(tester.getTopLeft(find.text('First screen')).dx - rest,
            closeTo(toEnd * frame.incoming.x * screenWidth, 1), reason: 'the page beneath comes back from its drift');
        expect(shown.last.cause, ScreenShownCause.back);
        expect(shown.last.screenId, 'first');

        await tester.pumpAndSettle();
        expect(find.text('Second screen'), findsNothing);
        expect(shown, hasLength(3));
      });
    }
  }

  testWidgets('a page step is the same motion on every platform: no native navigation transition', (tester) async {
    await _pump(tester, _flow(), platform: TargetPlatform.iOS);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PageMotion), findsNWidgets(2));
    expect(find.descendant(of: find.byType(PageMotion), matching: find.byType(CupertinoPageTransition)), findsNothing);
  });

  testWidgets('a page step takes the page duration', (tester) async {
    await _pump(tester, _flow());
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: kPageMotionMs - 20));
    expect(find.text('First screen'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(find.text('First screen'), findsNothing);
  });

  /// A phone: a modal layer without a placement is a SHEET only on a compact area (a wider one shows it as a window).
  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 800);
    addTearDown(tester.view.reset);
  }

  /// Opens `second` as a layer and lets the layer start its motion: the step is built by the first pump, the layer's own
  /// clock starts on the frame after it.
  Future<void> openLayer(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
  }

  double layerY(WidgetTester tester) => tester.getTopLeft(find.byKey(kModalLayerKey)).dy;

  double layerOpacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.ancestor(of: find.byKey(kModalLayerKey), matching: find.byType(Opacity)).first).opacity;

  double layerScale(WidgetTester tester) => tester
      .widget<Transform>(find.ancestor(of: find.byKey(kModalLayerKey), matching: find.byType(Transform)).first)
      .transform
      .storage[0];

  /// The opacity of the scrim: the share of its resting colour the plan says.
  double scrimOpacity(WidgetTester tester) {
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(GestureDetector), matching: find.byType(ColoredBox)).first,
    );
    return box.color.a;
  }

  testWidgets('a modal sheet rises from below by its own height and goes down when closed, the scrim with it', (tester) async {
    phone(tester);
    final shown = await _pump(tester, _flow(secondPresentation: 'modal'));
    await openLayer(tester);
    await tester.pump(const Duration(milliseconds: 70));
    final height = tester.getSize(find.byKey(kModalLayerKey)).height;
    final rising = layerY(tester);
    final inFrame = screenTransitionFrame(_plan(StackStep.push, to: const TransitionScreen(modal: true)), 70);
    expect(inFrame.incoming.y, closeTo(0.3928, 1e-3));
    expect(scrimOpacity(tester), closeTo(kModalScrimOpacity * inFrame.scrim, 0.01), reason: 'the scrim thickens with it');
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pumpAndSettle();
    final rest = layerY(tester);
    expect(rising - rest, closeTo(inFrame.incoming.y * height, 1), reason: 'by its own height, on the curve of the plan');
    expect(find.descendant(of: find.byType(ModalLayer), matching: find.byType(CupertinoPageTransition)), findsNothing, reason: 'a modal layer is not a page step');
    expect(scrimOpacity(tester), closeTo(kModalScrimOpacity, 1e-6));

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(shown.map((event) => event.cause).last, ScreenShownCause.back, reason: 'closed at the step');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final outFrame = screenTransitionFrame(_plan(StackStep.pop, from: const TransitionScreen(modal: true)), 110);
    expect(find.byKey(kModalLayerKey), findsOneWidget, reason: 'the sheet goes down');
    expect(layerY(tester) - rest, closeTo(outFrame.outgoing.y * height, 1));
    expect(scrimOpacity(tester), closeTo(kModalScrimOpacity * outFrame.scrim, 0.01));
    expect(_touchable(tester, 'Second screen'), isFalse, reason: 'a closing layer takes no touches');
    expect(_touchable(tester, 'Next'), isTrue);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.byKey(kModalLayerKey), findsNothing);
    expect(shown, hasLength(3));
  });

  testWidgets('a sheet takes its own time: 280 ms to open, 220 ms to close', (tester) async {
    phone(tester);
    await _pump(tester, _flow(secondPresentation: 'modal'));
    await openLayer(tester);
    await tester.pump(const Duration(milliseconds: kSheetOpenMs - 20));
    final before = layerY(tester);
    await tester.pump(const Duration(milliseconds: 40));
    final after = layerY(tester);
    expect(before, greaterThan(after));
    await tester.pump(const Duration(milliseconds: 20));
    expect(layerY(tester), after, reason: 'in place at 280 ms');
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: kSheetCloseMs - 20));
    expect(find.byKey(kModalLayerKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(find.byKey(kModalLayerKey), findsNothing);
  });

  testWidgets('a centred window grows from 96 % while it fades in, and fades out without a zoom', (tester) async {
    phone(tester);
    await _pump(tester, _flow(secondPresentation: 'modal', secondPlacement: 'center'));
    await openLayer(tester);
    await tester.pump(const Duration(milliseconds: 50));
    final frame = screenTransitionFrame(
      _plan(StackStep.push, to: const TransitionScreen(modal: true, placement: 'center')),
      50,
    );
    expect(layerScale(tester), closeTo(frame.incoming.scale, 1e-3));
    expect(layerScale(tester), inExclusiveRange(kModalWindowStartScale, 1));
    expect(layerOpacity(tester), closeTo(frame.incoming.opacity, 1e-3));
    await tester.pumpAndSettle();
    expect(layerScale(tester), 1);
    expect(layerOpacity(tester), 1);

    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(layerScale(tester), 1, reason: 'closing is a fade only');
    expect(layerOpacity(tester), closeTo(0.6752, 1e-3));
    await tester.pumpAndSettle();
    expect(find.byKey(kModalLayerKey), findsNothing);
  });

  testWidgets('a sheet on a wide area is shown as a window and opens as a window', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    await _pump(tester, _flow(secondPresentation: 'modal'));
    await openLayer(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(layerScale(tester), inExclusiveRange(kModalWindowStartScale, 1), reason: 'the window grows, it does not rise');
    await tester.pumpAndSettle();
    expect(layerScale(tester), 1);
  });

  group('the field `transition` of a screen', () {
    testWidgets('fade on a page: the old page fades out over the new one, which stands still', (tester) async {
      final shown = await _pump(tester, _flow(secondTransition: 'fade'));
      final rest = tester.getTopLeft(find.text('First screen')).dx;
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PageMotion), findsNothing, reason: 'no page slides');
      expect(tester.getTopLeft(find.text('Second screen')).dx, closeTo(rest, 0.5), reason: 'the new page stands still');
      final fading = tester.widget<Opacity>(find.ancestor(of: find.text('First screen'), matching: find.byType(Opacity)).last);
      expect(fading.opacity, closeTo(screenTransitionFrame(_plan(StackStep.push, to: const TransitionScreen(transition: ScreenTransitionWord.fade)), 100).outgoing.opacity, 1e-3));
      expect(_touchable(tester, 'First screen'), isFalse);
      expect(_touchable(tester, 'Second screen'), isTrue);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(find.text('First screen'), findsNothing, reason: 'the cross-dissolve takes 200 ms');
      expect(shown, hasLength(2));
    });

    testWidgets('fade on the page that leaves: going back dissolves it, over the page beneath', (tester) async {
      await _pump(tester, _flow(secondTransition: 'fade'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PageMotion), findsNothing);
      final leaving = tester.widget<Opacity>(find.ancestor(of: find.text('Second screen'), matching: find.byType(Opacity)).last);
      expect(leaving.opacity, closeTo(0.2244, 1e-3));
      await tester.pumpAndSettle();
      expect(find.text('Second screen'), findsNothing);
    });

    testWidgets('the page under a fade page still slides back: the screen that leaves decides', (tester) async {
      await _pump(tester, _flow(firstTransition: 'fade'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(find.byType(PageMotion), findsNWidgets(2), reason: 'a push and a pop are the second screen\'s to say');
    });

    testWidgets('none: the page comes and goes at once', (tester) async {
      final shown = await _pump(tester, _flow(secondTransition: 'none'));
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('First screen'), findsNothing);
      expect(find.byType(PageMotion), findsNothing);
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('Second screen'), findsNothing);
      expect(shown.map((event) => event.cause), [ScreenShownCause.entry, ScreenShownCause.forward, ScreenShownCause.back]);
    });

    testWidgets('a layer that says fade only changes its opacity: no rise, no zoom, the scrim with it', (tester) async {
    phone(tester);
      await _pump(tester, _flow(secondPresentation: 'modal', secondTransition: 'fade'));
      await openLayer(tester);
      await tester.pump(const Duration(milliseconds: 50));
      final rising = layerY(tester);
      expect(layerOpacity(tester), closeTo(0.2366, 1e-3));
      expect(layerScale(tester), 1);
      expect(scrimOpacity(tester), closeTo(kModalScrimOpacity * 0.2366, 0.01));
      await tester.pumpAndSettle();
      expect(layerY(tester), rising, reason: 'it did not move');
      expect(layerOpacity(tester), 1);
    });

    testWidgets('a layer that says none is there at once and goes at once', (tester) async {
    phone(tester);
      await _pump(tester, _flow(secondPresentation: 'modal', secondTransition: 'none'));
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(layerOpacity(tester), 1);
      expect(scrimOpacity(tester), closeTo(kModalScrimOpacity, 1e-6));
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.byKey(kModalLayerKey), findsNothing);
    });

    testWidgets('a layer over another layer keeps the scrim still', (tester) async {
    phone(tester);
      final doc = docWithScreens([
        screenEntry('first', [buttonNode('Next', action: _navigate('second'), id: 'next')]),
        screenEntry('second', [
          textNode('Second screen', id: 't2'),
          buttonNode('Over', action: _navigate('third'), id: 'over'),
        ], presentation: 'modal'),
        screenEntry('third', [textNode('Third screen', id: 't3'), buttonNode('Back', action: _back, id: 'back')], presentation: 'modal'),
      ], initialScreenId: 'first');
      await _pump(tester, doc);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Second screen'), findsOneWidget);
      await tester.tap(find.text('Over'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final scrims = tester
          .widgetList<ColoredBox>(find.descendant(of: find.byType(GestureDetector), matching: find.byType(ColoredBox)))
          .map((box) => box.color.a)
          .toList();
      expect(scrims, hasLength(2));
      expect(scrims.last, closeTo(kModalScrimOpacity, 1e-6), reason: 'the layer opens over a layer: the scrim stands');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final closing = tester
          .widgetList<ColoredBox>(find.descendant(of: find.byType(GestureDetector), matching: find.byType(ColoredBox)))
          .map((box) => box.color.a)
          .toList();
      expect(closing.last, closeTo(kModalScrimOpacity, 1e-6), reason: 'and when it closes back to a layer');
      await tester.pumpAndSettle();
    });

    testWidgets('a sheet that the finger took down plays nothing when the stack goes back', (tester) async {
    phone(tester);
      await _pump(tester, _flow(secondPresentation: 'modal'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(find.text('Second screen')));
      for (var step = 0; step < 14; step += 1) {
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      // The exit of the drag takes 200 ms (`kSheetExit`); the step back that follows it must not play the 220 ms of a
      // closing sheet over it: the layer is gone as soon as it has left.
      var frames = 0;
      while (find.byKey(kModalLayerKey).evaluate().isNotEmpty && frames < 100) {
        await tester.pump(const Duration(milliseconds: 16));
        frames += 1;
      }
      expect(frames * 16, lessThan(kSheetExit.durationMs + 80), reason: 'it left once, not twice');
      expect(find.byKey(kModalLayerKey), findsNothing);
      expect(find.text('Second screen'), findsNothing);
      expect(find.text('First screen'), findsOneWidget);
    });
  });

  testWidgets('the first screen and a new document appear without motion', (tester) async {
    await _pump(tester, _flow());
    expect(find.byType(PageMotion), findsNothing);
    expect(find.text('First screen'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Another document is a new flow: an `entry` show, no motion from the old one.
    await _pump(tester, _flow(documentId: 'other'));
    expect(find.byType(PageMotion), findsNothing);
    expect(find.text('Second screen'), findsNothing);
  });

  for (final mode in ['disableAnimations', 'transitions: none']) {
    testWidgets('$mode: every change is instant', (tester) async {
      final shown = await _pump(
        tester,
        _flow(secondPresentation: 'modal'),
        platform: TargetPlatform.iOS,
        disableAnimations: mode == 'disableAnimations',
        transitions: mode == 'disableAnimations' ? HotlayoutTransitions.platform : HotlayoutTransitions.none,
      );
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();
      final layer = tester.getTopLeft(find.byKey(kModalLayerKey)).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(kModalLayerKey)).dy, layer, reason: 'the sheet is in place at once');
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.byKey(kModalLayerKey), findsNothing);
      expect(shown.map((event) => event.cause), [
        ScreenShownCause.entry,
        ScreenShownCause.forward,
        ScreenShownCause.back,
      ]);
      expect(find.byKey(kEdgeSwipeKey), findsNothing);
    });

    testWidgets('$mode: a page step is instant', (tester) async {
      await _pump(
        tester,
        _flow(),
        disableAnimations: mode == 'disableAnimations',
        transitions: mode == 'disableAnimations' ? HotlayoutTransitions.platform : HotlayoutTransitions.none,
      );
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('First screen'), findsNothing);
      expect(find.byType(PageMotion), findsNothing);
    });
  }

  testWidgets('a quick double tap on "forward" takes one step', (tester) async {
    final flow = ScreenFlowController();
    addTearDown(flow.dispose);
    final shown = await _pump(tester, _flow(), controller: flow);
    final next = tester.getCenter(find.text('Next'));
    await tester.tapAt(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tapAt(next);
    await tester.pumpAndSettle();
    expect(shown.where((event) => event.cause == ScreenShownCause.forward), hasLength(1));
    expect(flow.currentScreenId, 'second');
    expect(flow.goBack(), isTrue);
    await tester.pumpAndSettle();
    expect(flow.canGoBack, isFalse, reason: 'one screen deep, as without motion');
  });

  testWidgets('the stack, the record and the session hold during a transition', (tester) async {
    final flow = ScreenFlowController();
    addTearDown(flow.dispose);
    final shown = await _pump(tester, _flow(), controller: flow);
    await tester.tap(find.text('Pick B'));
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(flow.currentScreenId, 'second');
    expect(flow.canGoBack, isTrue);
    expect(find.text('B'), findsNWidgets(2), reason: 'both scenes read the same session');

    // A step back while the page is still coming in: taken at once, and the motion plays back.
    expect(flow.goBack(), isTrue);
    await tester.pump();
    expect(flow.currentScreenId, 'first');
    await tester.pumpAndSettle();
    expect(find.text('Second screen'), findsNothing);
    expect(find.text('B'), findsOneWidget, reason: 'the session outlives the steps');
    expect(shown.map((event) => event.cause), [
      ScreenShownCause.entry,
      ScreenShownCause.forward,
      ScreenShownCause.back,
    ]);
  });

  group('a section switch', () {
    _Json navItem(String id, String section) => {
      'id': id,
      'type': 'NavItem',
      'props': {
        'icon': 'house',
        'label': {'kind': 'literal', 'value': id},
        'action': {'type': 'navigate.section', 'params': {'screenId': section}},
      },
    };
    _Json navBar() => {
      'id': 'nav',
      'type': 'NavBar',
      'props': <String, Object?>{},
      'children': [navItem('Home', 'home'), navItem('Shop', 'shop')],
    };
    UiDocument sections() => docWithScreens([
      screenEntry('home', [textNode('Home body', id: 'home-body'), navBar()]),
      screenEntry('shop', [textNode('Shop body', id: 'shop-body'), navBar()]),
    ], initialScreenId: 'home');

    testWidgets('has no motion of its own: the new screen is there at once', (tester) async {
      final shown = await _pump(tester, sections());
      await tester.tap(find.text('Shop'));
      await tester.pump();
      expect(find.byType(PageMotion), findsNothing);
      expect(find.text('Home body'), findsNothing);
      expect(find.text('Shop body'), findsOneWidget);
      expect(shown.last.cause, ScreenShownCause.switchSection);
      expect(shown, hasLength(2));
    });

    testWidgets('a section that says fade cross-dissolves: the old screen lies over the new one and fades out', (tester) async {
      final doc = docWithScreens([
        screenEntry('home', [textNode('Home body', id: 'home-body'), navBar()]),
        {
          ...screenEntry('shop', [textNode('Shop body', id: 'shop-body'), navBar()]),
          'transition': 'fade',
        },
      ], initialScreenId: 'home');
      final shown = await _pump(tester, doc);
      await tester.tap(find.text('Shop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PageMotion), findsNothing, reason: 'no page slides');
      expect(find.text('Home body'), findsOneWidget);
      expect(find.text('Shop body'), findsOneWidget);
      double opacityOf(String text) =>
          tester.widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)).last).opacity;
      expect(opacityOf('Home body'), closeTo(0.2244, 1e-3), reason: 'the old screen fades out');
      expect(find.ancestor(of: find.text('Shop body'), matching: find.byType(Opacity)), findsNothing, reason: 'the new one stands whole');
      expect(_touchable(tester, 'Home body'), isFalse);
      expect(shown.last.cause, ScreenShownCause.switchSection);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(find.text('Home body'), findsNothing);
      expect(shown, hasLength(2));
    });
  });

  group('tabs', () {
    _Json tab(String id, String title) => {
      'id': id,
      'type': 'Tab',
      'props': {
        'title': {'kind': 'literal', 'value': title},
      },
      'children': [textNode('$title panel', id: '$id-body')],
    };
    UiDocument tabsDoc() => docWith([
      {
        'id': 'tabs',
        'type': 'Tabs',
        'props': {'initialTab': 0},
        'children': [tab('a', 'Tasks'), tab('b', 'Collection')],
      },
    ]);

    testWidgets('the indicator slides from the old title to the new one', (tester) async {
      await _pump(tester, tabsDoc());
      expect(find.byKey(kTabIndicatorKey), findsNothing, reason: 'at rest each title draws its own');
      final from = tester.getRect(find.text('Tasks'));
      final to = tester.getRect(find.text('Collection'));
      await tester.tap(find.text('Collection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final moving = tester.getRect(find.byKey(kTabIndicatorKey));
      expect(moving.center.dx, inExclusiveRange(from.center.dx, to.center.dx));
      expect(find.text('Tasks panel'), findsOneWidget, reason: 'the panels cross-fade');
      expect(find.text('Collection panel'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(kTabIndicatorKey), findsNothing);
      expect(find.text('Tasks panel'), findsNothing);
    });

    testWidgets('transitions: none — the tab changes at once', (tester) async {
      await _pump(tester, tabsDoc(), transitions: HotlayoutTransitions.none);
      await tester.tap(find.text('Collection'));
      await tester.pump();
      expect(find.byKey(kTabIndicatorKey), findsNothing);
      expect(find.text('Tasks panel'), findsNothing);
    });
  });

  group('the edge swipe back', () {
    Future<List<ScreenShown>> onSecond(
      WidgetTester tester, {
      TargetPlatform platform = TargetPlatform.iOS,
      bool rtl = false,
    }) async {
      final shown = await _pump(tester, _flow(), platform: platform, locale: rtl ? 'ar' : 'en');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      return shown;
    }

    for (final rtl in [false, true]) {
      testWidgets('a swipe past half the width goes back (${rtl ? 'rtl' : 'ltr'})', (tester) async {
        final shown = await onSecond(tester, rtl: rtl);
        final width = tester.getSize(find.byType(Scaffold)).width;
        final start = Offset(rtl ? width - 4 : 4, 300);
        final gesture = await tester.startGesture(start);
        for (var step = 1; step <= 12; step += 1) {
          await gesture.moveBy(Offset((rtl ? -1 : 1) * width * 0.05, 0));
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(find.text('First screen'), findsOneWidget, reason: 'the page below is revealed under the finger');
        expect(shown.last.cause, ScreenShownCause.forward, reason: 'nothing is shown before the finger lets go');
        await tester.pump(const Duration(milliseconds: 400));
        await gesture.up();
        await tester.pump();
        expect(shown.last.cause, ScreenShownCause.back);
        expect(shown.last.screenId, 'first');
        await tester.pumpAndSettle();
        expect(find.text('Second screen'), findsNothing);
        expect(shown, hasLength(3));
      });
    }

    testWidgets('a short swipe gives up: nothing changes and nothing is reported', (tester) async {
      final shown = await onSecond(tester);
      final gesture = await tester.startGesture(const Offset(4, 300));
      for (var step = 1; step <= 4; step += 1) {
        await gesture.moveBy(const Offset(15, 0));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('First screen'), findsNothing);
      expect(find.text('Second screen'), findsOneWidget);
      expect(shown, hasLength(2));
      expect(_touchable(tester, 'Back'), isTrue);
    });

    testWidgets('onSystemBack may keep the screen', (tester) async {
      final shown = <ScreenShown>[];
      var asked = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: renderDocument(
              _flow(),
              theme: RenderTheme.fallback(),
              data: const {},
              onScreenShown: shown.add,
              onSystemBack: () {
                asked += 1;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(4, 300), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.text('Second screen'), findsOneWidget);
      expect(shown, hasLength(2));
    });

    testWidgets('no swipe on Android, on the first screen, or under a modal layer', (tester) async {
      await onSecond(tester, platform: TargetPlatform.android);
      expect(find.byKey(kEdgeSwipeKey), findsNothing);

      await _pump(tester, _flow(documentId: 'ios'), platform: TargetPlatform.iOS);
      expect(find.byKey(kEdgeSwipeKey), findsNothing, reason: 'the first screen is the host route\'s');

      await _pump(tester, _flow(secondPresentation: 'modal', documentId: 'modal'), platform: TargetPlatform.iOS);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byKey(kEdgeSwipeKey), findsNothing, reason: 'a sheet is closed by its scrim or "back"');
    });
  });
}
