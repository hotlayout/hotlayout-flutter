import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';
import 'package:hotlayout_flutter/src/render/motion.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_flow.dart' show kEdgeSwipeKey;
import 'package:hotlayout_flutter/src/render/screen_transitions.dart';
import 'package:hotlayout_flutter/src/render/tab_strip.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// TRANSITIONS BETWEEN SCREENS.
///
/// Motion is the reader's own: the document says which screen is shown and why, and the flow
/// animates the change the way the platform does. These tests hold two things. First, that each
/// cause of a show moves in its own way, in the right direction for the writing direction and for
/// the right time. Second, and more important, that motion never touches the flow: the show event
/// comes at the moment of the step, exactly once; the stack, the session and the record are what
/// they would be without motion; and a leaving screen takes no touches.

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

UiDocument _flow({String? secondPresentation, Object? secondPlacement, String documentId = 'flow'}) => docWithScreens([
  screenEntry('first', [
    textNode('First screen', id: 't1'),
    _boundText('pick-1', 'pick'),
    buttonNode('Pick B', action: {
      'type': 'setValue',
      'params': {'path': 'pick', 'value': 'B'},
    }, id: 'pick'),
    buttonNode('Next', action: _navigate('second'), id: 'next'),
  ]),
  screenEntry('second', [
    textNode('Second screen', id: 't2'),
    _boundText('pick-2', 'pick'),
    buttonNode('Back', action: _back, id: 'back'),
  ], presentation: secondPresentation, modalPlacement: secondPlacement),
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

void main() {
  group('the rules', () {
    test('a Material page step: the page on top comes from the end of the line and fades in', () {
      final start = materialPageLook(role: PageRole.over, progress: 0, forward: true);
      final end = materialPageLook(role: PageRole.over, progress: 1, forward: true);
      expect(start.opacity, 0);
      expect(start.shift, closeTo(0.25, 1e-9));
      expect(end.opacity, 1);
      expect(end.shift, 0);
      final under = materialPageLook(role: PageRole.under, progress: 1, forward: true);
      expect(under.shift, closeTo(-0.25, 1e-9), reason: 'the covered page drifts back toward the start of the line');
      expect(under.opacity, 0);
    });

    test('a Material step back is the step forward played in reverse', () {
      final leaving = materialPageLook(role: PageRole.over, progress: 1, forward: false);
      expect(leaving.opacity, 1, reason: 'the page on top starts whole');
      final gone = materialPageLook(role: PageRole.over, progress: 0, forward: false);
      expect(gone.opacity, 0);
      expect(gone.shift, closeTo(0.25, 1e-9));
      final revealed = materialPageLook(role: PageRole.under, progress: 0, forward: false);
      expect(revealed.opacity, 1);
      expect(revealed.shift, 0);
    });

    test('a section switch: the old screen stays whole while the new one comes in', () {
      for (final p in [0.0, 0.2, 0.4, 0.6]) {
        expect(sectionSwitchLook(p).outgoing, 1, reason: 'at $p');
      }
      expect(sectionSwitchLook(0).incoming, 0);
      expect(sectionSwitchLook(0.6).incoming, 1);
      expect(sectionSwitchLook(1).outgoing, 0);
    });
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final rtl in [false, true]) {
      final name = '${platform.name}, ${rtl ? 'rtl' : 'ltr'}';
      UiDocument doc() => _flow();

      testWidgets('forward: the new page comes in from the end of the line ($name)', (tester) async {
        final shown = await _pump(tester, doc(), platform: platform, locale: rtl ? 'ar' : 'en');
        final firstRest = tester.getTopLeft(find.text('First screen')).dx;
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('First screen'), findsOneWidget, reason: 'the covered page is still drawn');
        expect(_touchable(tester, 'First screen'), isFalse, reason: 'and takes no touches');
        expect(_touchable(tester, 'Second screen'), isTrue);
        if (platform == TargetPlatform.iOS) expect(find.byType(CupertinoPageTransition), findsWidgets);
        final moving = tester.getTopLeft(find.text('Second screen')).dx;
        expect(shown.map((event) => event.cause), [ScreenShownCause.entry, ScreenShownCause.forward],
            reason: 'the show is reported at the step, not at the end of the motion');

        await tester.pump(Motion.page);
        await tester.pump();
        expect(find.text('First screen'), findsNothing);
        final rest = tester.getTopLeft(find.text('Second screen')).dx;
        if (rtl) {
          expect(moving, lessThan(rest), reason: 'from the left in right-to-left writing');
        } else {
          expect(moving, greaterThan(rest), reason: 'from the right in left-to-right writing');
        }
        expect(rest, closeTo(firstRest, 0.5));
        expect(shown, hasLength(2), reason: 'the end of the motion is not a show');
      });

      testWidgets('back: the page leaves toward the end of the line ($name)', (tester) async {
        final shown = await _pump(tester, doc(), platform: platform, locale: rtl ? 'ar' : 'en');
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        final rest = tester.getTopLeft(find.text('Second screen')).dx;
        await tester.tap(find.text('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(find.text('Second screen'), findsOneWidget, reason: 'the closed page is drawn while it leaves');
        expect(_touchable(tester, 'Second screen'), isFalse);
        expect(_touchable(tester, 'First screen'), isTrue);
        final moving = tester.getTopLeft(find.text('Second screen')).dx;
        if (rtl) {
          expect(moving, lessThan(rest));
        } else {
          expect(moving, greaterThan(rest));
        }
        expect(shown.last.cause, ScreenShownCause.back);
        expect(shown.last.screenId, 'first');

        await tester.pumpAndSettle();
        expect(find.text('Second screen'), findsNothing);
        expect(shown, hasLength(3));
      });
    }
  }

  testWidgets('a page step takes the page duration', (tester) async {
    await _pump(tester, _flow());
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(Motion.page - const Duration(milliseconds: 20));
    expect(find.text('First screen'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(find.text('First screen'), findsNothing);
  });

  testWidgets('a modal sheet rises from the bottom and sinks back when closed', (tester) async {
    final shown = await _pump(tester, _flow(secondPresentation: 'modal'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final rising = tester.getTopLeft(find.byKey(kModalLayerKey)).dy;
    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.byKey(kModalLayerKey)).dy;
    expect(rising, greaterThan(rest), reason: 'the sheet comes from below');
    expect(find.byType(CupertinoPageTransition), findsNothing, reason: 'a modal layer is not a page step');

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(shown.map((event) => event.cause).last, ScreenShownCause.back, reason: 'closed at the step');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(kModalLayerKey), findsOneWidget, reason: 'the sheet sinks away');
    expect(tester.getTopLeft(find.byKey(kModalLayerKey)).dy, greaterThan(rest));
    expect(_touchable(tester, 'Second screen'), isFalse, reason: 'a closing layer takes no touches');
    expect(_touchable(tester, 'Next'), isTrue);

    await tester.pumpAndSettle();
    expect(find.byKey(kModalLayerKey), findsNothing);
    expect(shown, hasLength(3));
  });

  testWidgets('a centred window grows from 96 % while it fades in, and back', (tester) async {
    await _pump(tester, _flow(secondPresentation: 'modal', secondPlacement: 'center'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    double scale() => tester
        .widget<Transform>(find.ancestor(of: find.byKey(kModalLayerKey), matching: find.byType(Transform)).first)
        .transform
        .storage[0];
    expect(scale(), inExclusiveRange(kModalWindowStartScale, 1));
    await tester.pumpAndSettle();
    expect(scale(), 1);

    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(), lessThan(1));
    await tester.pumpAndSettle();
    expect(find.byKey(kModalLayerKey), findsNothing);
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

    testWidgets('cross-fades: the new screen over the old one, which stays whole', (tester) async {
      final shown = await _pump(tester, sections());
      await tester.tap(find.text('Shop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(PageMotion), findsNothing, reason: 'no page slides');
      expect(find.text('Home body'), findsOneWidget);
      expect(find.text('Shop body'), findsOneWidget);
      double opacityOf(String text) =>
          tester.widget<Opacity>(find.ancestor(of: find.text(text), matching: find.byType(Opacity)).last).opacity;
      expect(opacityOf('Home body'), 1);
      expect(opacityOf('Shop body'), inExclusiveRange(0, 1));
      expect(_touchable(tester, 'Home body'), isFalse);
      expect(shown.last.cause, ScreenShownCause.switchSection);
      await tester.pump(Motion.sheet);
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
