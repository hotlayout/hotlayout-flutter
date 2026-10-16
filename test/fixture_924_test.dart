/// THE FRAME `appear-swipe-dot-screens` (schema 9.24.0): every screen in three languages on two phone widths, then
/// each scene as its story says.
///
///  * Home: the greeting and the chips stand while the cards scroll under them; the balance, the ring and the bars
///    grow from zero at every show (also after the other section); the dot on "Missions" flashes when the progress
///    changes;
///  * Missions: the title stands, the bars grow;
///  * Redeem: after the swipe the thumb stays at the end with the indicator, then "Done".
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show HotlayoutTransitions;
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';
import 'package:hotlayout_flutter/src/render/widgets/nav_bar.dart';

import 'support/fixtures.dart';

const _id = 'appear-swipe-dot-screens';

UiDocument _startingAt(String screenId) {
  final json = jsonDecode(readFixture(_id)) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

void _view(WidgetTester tester, double width, [double height = 800]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _data = <String, Object?>{'task.progress': 3, 'user.points': 12480};

Finder _balance() => find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(RegExp(r'^[0-9,.\s ]+$')) && (w.data ?? '').isNotEmpty);

/// Frames of 100 ms: a page transition ends on a frame, so one long pump is not the same as several.
Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('the fixture is in the catalogue, at 9.24.0, in two languages', () {
    final doc = loadFixture(_id);
    expect(doc.schemaVersion, '9.24.0');
    expect(fixtureIds, contains(_id));
    expect(doc.locales, ['en', 'uk']);
  });

  group('every screen is drawn without exceptions', () {
    for (final screen in ['home', 'missions', 'redeem', 'done']) {
      for (final width in [320.0, 393.0]) {
        for (final locale in [null, 'uk', 'ar']) {
          testWidgets('$screen at $width (${locale ?? 'en'})', (tester) async {
            _view(tester, width);
            await pumpDocument(tester, _startingAt(screen), data: _data, locale: locale, safeTop: 47, safeBottom: 34);
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('Home', () {
    testWidgets('the greeting and the chips stand while the cards scroll under them', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('home'), data: _data, safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      final hello = tester.getRect(find.text('Good evening, Mira').first);
      final scroll = find.byType(SingleChildScrollView).last;
      final before = tester.getRect(scroll);
      expect(hello.top, greaterThanOrEqualTo(47), reason: 'below the safe inset');
      expect(before.top, greaterThan(hello.bottom), reason: 'the body starts below the zone');
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(find.text('Good evening, Mira').first), hello);
      expect(tester.getRect(scroll), before);
    });

    testWidgets('the balance, the ring and the bars grow from zero at the first show', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('home'), data: _data, safeTop: 47, safeBottom: 34);
      expect(find.text('0'), findsWidgets, reason: 'the first frame of the balance is zero');
      await tester.pump(const Duration(milliseconds: 350));
      final mid = _balance().evaluate().map((e) => (e.widget as Text).data!).first;
      expect(mid, isNot('0'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('12,480'), findsOneWidget);
      expect(find.byType(ProgressTrack), findsWidgets);
    });

    testWidgets('after the other section the numbers grow again', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('home'), data: _data, safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('12,480'), findsOneWidget);
      await tester.tap(find.text('Missions').last);
      await _frames(tester, 20);
      expect(find.text('12,480'), findsNothing);
      await tester.tap(find.text('Home').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('12,480'), findsNothing, reason: 'it starts from zero again');
      await _frames(tester, 20);
      expect(find.text('12,480'), findsOneWidget);
    });

    testWidgets('the dot on Missions flashes when the progress changes', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('home'), data: {..._data, 'task.progress': 0}, safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(NavBadgeMark), findsNothing);
      await pumpDocument(tester, _startingAt('home'), data: _data, safeTop: 47, safeBottom: 34);
      await tester.pump();
      expect(find.byType(NavBadgeMark), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 192));
      expect(tester.widget<NavBadgeMark>(find.byType(NavBadgeMark)).scale, closeTo(1.25, 1e-3));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<NavBadgeMark>(find.byType(NavBadgeMark)).scale, 1);
    });
  });

  group('Missions', () {
    testWidgets('the title stands while the cards scroll', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('missions'), data: _data, safeTop: 47, safeBottom: 34);
      await tester.pump(const Duration(seconds: 2));
      final title = tester.getRect(find.text('Missions').first);
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getRect(find.text('Missions').first), title);
    });
  });

  group('Redeem', () {
    testWidgets('after the swipe the thumb stands at the end with the indicator, then "Done"', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('redeem'), data: _data, safeBottom: 34);
      final track = tester.getRect(find.byType(SwipeConfirmTrack));
      final thumb = find.descendant(
        of: find.byType(SwipeConfirmTrack),
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle),
      );
      final start = tester.getRect(thumb);
      final gesture = await tester.startGesture(start.center);
      for (var i = 0; i < 20; i += 1) {
        await gesture.moveBy(Offset(track.width / 20, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(SwipeConfirmTrack), findsOneWidget, reason: 'the sheet stays until the next screen arrives');
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('It’s yours!'), findsWidgets);
    });
  });

  group('the appearance and the screen transitions', () {
    Map<String, Object?> grows(String id) => {
      'id': id,
      'type': 'Text',
      'props': {
        'content': {'kind': 'binding', 'path': 'user.points', 'fallback': '0', 'format': 'number'},
        'animateIn': true,
      },
    };

    Map<String, Object?> go(String label, String screen, {String id = 'go'}) =>
        buttonNode(label, action: {'type': 'navigate', 'params': {'screenId': screen}}, id: id);

    UiDocument doc() => docWithScreens([
      screenEntry('first', [grows('a'), go('Next', 'second')]),
      screenEntry('second', [grows('b'), buttonNode('Back', action: const {'type': 'navigate.back'}, id: 'back'), go('Sheet', 'sheet', id: 'sheet-go')]),
      screenEntry('sheet', [textNode('Sheet body', id: 'sheet-text'), buttonNode('Close', action: const {'type': 'navigate.back'}, id: 'close')], presentation: 'modal'),
    ], initialScreenId: 'first');

    testWidgets('a page pushed forward grows together with its slide, not after it', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, doc(), data: const {'user.points': 1000});
      await _frames(tester, 20);
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // The page is still sliding (300 ms), and its number is already on the way up.
      final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
      expect(texts.where((t) => RegExp(r'^[0-9,]+$').hasMatch(t) && t != '0' && t != '1,000'), isNotEmpty, reason: '$texts');
      await _frames(tester, 20);
      expect(find.text('1,000'), findsOneWidget);
    });

    testWidgets('"back" shows the page again: its number grows again', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, doc(), data: const {'user.points': 1000});
      await _frames(tester, 20);
      await tester.tap(find.text('Next'));
      await _frames(tester, 20);
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      // The leaving page still shows its final number; the page shown again counts up from zero.
      final numbers = [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          if (RegExp(r'^[0-9,]+$').hasMatch(text.data ?? '')) int.parse(text.data!.replaceAll(',', '')),
      ];
      expect(numbers.any((n) => n < 1000), isTrue, reason: '$numbers');
      await _frames(tester, 20);
      expect(find.text('1,000'), findsOneWidget);
    });

    testWidgets('closing a modal layer is not a show of the page under it', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, doc(), data: const {'user.points': 1000});
      await _frames(tester, 20);
      await tester.tap(find.text('Next'));
      await _frames(tester, 20);
      await tester.tap(find.text('Sheet'));
      await _frames(tester, 20);
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('1,000'), findsOneWidget, reason: 'the number under the layer stays');
      await _frames(tester, 10);
    });

    testWidgets('transitions: none and reduced motion show the number at once', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, doc(), data: const {'user.points': 1000}, transitions: HotlayoutTransitions.none, disableAnimations: true);
      expect(find.text('1,000'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('1,000'), findsOneWidget);
    });
  });
}
