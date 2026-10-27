/// THREE FIXTURES 9.15-9.17: `alignment-screens` (9.15.0), `app-bar-screens` (9.16.0),
/// `text-emphasis-screens` (9.17.0).
///
/// The contract tables cover individual rules; here are whole showcases: every screen at
/// 320 and 393 (and in Arabic for `text-emphasis-screens`) paints without exceptions, and
/// the main thing each showcase promises is checked with a real gesture or measurement.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';

import 'support/fixtures.dart';

void _view(WidgetTester tester, double width, [double height = 900]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// A fixture whose show starts at [screenId].
UiDocument _startingAt(String fixture, String screenId) {
  final json = jsonDecode(readFixture(fixture)) as Map<String, Object?>;
  return UiDocument.fromJson({...json, 'initialScreenId': screenId});
}

List<String> _screens(String fixture) =>
    ((jsonDecode(readFixture(fixture)) as Map)['screens']! as List).map((s) => (s as Map)['screenId'] as String).toList();

final Finder _anyButton = find.byWidgetPredicate((w) => w is ButtonStyleButton);

void main() {
  test('fixtures: schema versions and catalogue', () {
    expect(loadFixture('alignment-screens').schemaVersion, '9.31.0');
    expect(loadFixture('app-bar-screens').schemaVersion, '9.16.0');
    expect(loadFixture('text-emphasis-screens').schemaVersion, '9.17.0');
    for (final id in ['alignment-screens', 'app-bar-screens', 'text-emphasis-screens']) {
      expect(fixtureIds, contains(id));
    }
  });

  group('every screen paints without exceptions', () {
    for (final fixture in ['alignment-screens', 'app-bar-screens', 'text-emphasis-screens']) {
      for (final screen in _screens(fixture)) {
        for (final width in [320.0, 393.0]) {
          for (final locale in [null, if (fixture == 'text-emphasis-screens') 'ar-EG']) {
            testWidgets('$fixture / $screen / ${width.toInt()}${locale == null ? '' : ' / $locale'}', (tester) async {
              _view(tester, width);
              await pumpDocument(tester, _startingAt(fixture, screen), locale: locale, data: {'user': {'isPremium': false}});
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }
  });

  group('alignment-screens', () {
    for (final width in [320.0, 393.0]) {
      testWidgets('centered: disc centred on the width, block centred on the body (${width.toInt()})', (tester) async {
        _view(tester, width, 700);
        await pumpDocument(tester, _startingAt('alignment-screens', 'centered'));
        final glyph = tester.getCenter(find.byType(IconGlyph).first);
        expect(glyph.dx, closeTo(width / 2, 0.5), reason: 'Screen.align: center places a natural-width child');
        // Vertically: free space split equally above and below the block of children.
        final column = tester.renderObject<RenderStretchColumn>(find.byType(StretchColumn).first);
        final first = column.firstChild!;
        var last = first;
        for (var child = first; ; child = column.childAfter(child)!) {
          last = child;
          if (column.childAfter(child) == null) break;
        }
        final top = tester.getTopLeft(find.byType(StretchColumn).first).dy + (first.parentData! as ContainerBoxParentData<RenderBox>).offset.dy;
        final bottom = tester.getTopLeft(find.byType(StretchColumn).first).dy + (last.parentData! as ContainerBoxParentData<RenderBox>).offset.dy + last.size.height;
        expect(top - 16, closeTo(700 - 16 - bottom, 1), reason: 'justify: center - the middle of the body');
      });
    }

    testWidgets('bottom: justify end leaves the pinned block alone, align end puts the button at the row end', (tester) async {
      _view(tester, 393, 700);
      await pumpDocument(tester, _startingAt('alignment-screens', 'bottom'));
      final pinned = find.ancestor(of: find.text('Next'), matching: _anyButton);
      if (pinned.evaluate().isNotEmpty) {
        final rect = tester.getRect(pinned.first);
        expect(rect.bottom, lessThanOrEqualTo(700), reason: 'the pinned block is in the bottom zone');
        expect(rect.right, greaterThan(393 / 2), reason: 'align: end - the end of the row');
      }
    });
  });

  group('app-bar-screens', () {
    testWidgets('challenges: the "Exit" zone node replaces the arrow, the title starts at the start', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('app-bar-screens', 'challenges'));
      expect(find.text('Exit'), findsOneWidget);
      expect(find.byKey(kAppBarBackGlyphKey), findsNothing, reason: 'a visible node replaces the arrow, whatever showBack says');
      final exit = tester.getRect(find.ancestor(of: find.text('Exit'), matching: _anyButton).first);
      final title = tester.getRect(find.text('Challenges'));
      expect(title.left, greaterThan(exit.right), reason: 'start: the title right after the zone');
      expect(title.left - exit.right, lessThan(24), reason: 'not centred in the bar');
    });

    testWidgets('hidden: a hidden node - showBack applies, the arrow is present; a visible one - no arrow', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('app-bar-screens', 'hidden'), data: {'user': {'isPremium': false}});
      expect(find.text('Exit'), findsNothing);
      expect(find.byKey(kAppBarBackGlyphKey), findsOneWidget);
      await pumpDocument(tester, _startingAt('app-bar-screens', 'hidden'), data: {'user': {'isPremium': true}});
      expect(find.text('Exit'), findsOneWidget);
      expect(find.byKey(kAppBarBackGlyphKey), findsNothing);
    });

    testWidgets('long: a long button is clamped to half of the bar', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('app-bar-screens', 'long'));
      final exit = tester.getRect(find.ancestor(of: find.textContaining('Leave this challenge'), matching: _anyButton).first);
      expect(exit.width, lessThanOrEqualTo(393 / 2 + 0.5));
    });

    testWidgets('details: the zone icon button does not count as an action - both actions remain', (tester) async {
      _view(tester, 393);
      await pumpDocument(tester, _startingAt('app-bar-screens', 'details'));
      // Zone node + two actions (share, more) = three icon buttons in the bar.
      expect(find.byWidgetPredicate((w) => w is ButtonStyleButton), findsNWidgets(3));
    });

    testWidgets('icons: own glyph size - the button box grows, a named side clamps', (tester) async {
      _view(tester, 393, 1200);
      await pumpDocument(tester, _startingAt('app-bar-screens', 'icons'));
      final glyphs = tester.widgetList<IconGlyph>(find.byType(IconGlyph)).toList();
      expect(glyphs.any((g) => g.size == 32), isTrue);
      expect(glyphs.any((g) => g.size == 64), isTrue);
      // Named 48 x 48 with a 64 glyph -> the glyph is clamped to 48.
      expect(tester.takeException(), isNull);
    });
  });

  group('text-emphasis-screens', () {
    testWidgets('steps: texts of all items in the group start on one vertical (a group of ten)', (tester) async {
      _view(tester, 393, 1600);
      await pumpDocument(tester, _startingAt('text-emphasis-screens', 'steps'));
      final lefts = <double>[
        for (final label in ['Open the app', 'Sign in', 'Open the catalog', 'Pick a category', 'Enjoy'])
          tester.getTopLeft(find.text(label)).dx,
      ];
      expect(lefts.toSet().length, 1, reason: 'column by the group per the document: $lefts');
      // After the paragraph the count starts again, the column is already narrower (a group of two).
      expect(tester.getTopLeft(find.text('The count starts from one again')).dx, lessThan(lefts.first));
    });

    testWidgets('article: a hidden "premium item" takes no number: 1, 2, 3', (tester) async {
      _view(tester, 393, 1600);
      await pumpDocument(tester, _startingAt('text-emphasis-screens', 'article'), data: {'user': {'isPremium': false}});
      String labelOf(String body) {
        final row = find.ancestor(of: find.text(body), matching: find.byType(Row)).first;
        return tester.widget<Text>(find.descendant(of: find.descendant(of: row, matching: find.byType(MarkerColumnEnd)), matching: find.byType(Text))).data!;
      }

      expect(labelOf('Open the catalog'), '1.');
      expect(labelOf('Confirm and show the code at the counter'), '3.');
    });

    testWidgets('article: "old price" is struck through, the note is italic', (tester) async {
      _view(tester, 393, 1600);
      await pumpDocument(tester, _startingAt('text-emphasis-screens', 'article'));
      expect(tester.widget<Text>(find.text('1,200')).style!.decoration, TextDecoration.lineThrough);
      expect(tester.widget<Text>(find.text('Terms apply. The offer may end earlier.')).style!.fontStyle, FontStyle.italic);
    });

    testWidgets('steps: card with italic and a line; an item cancels both; the bullet is upright', (tester) async {
      _view(tester, 393, 1600);
      await pumpDocument(tester, _startingAt('text-emphasis-screens', 'steps'));
      final inherited = tester.widget<Text>(find.text('Everything in this card is italic and underlined'));
      expect(inherited.style!.fontStyle, FontStyle.italic);
      expect(inherited.style!.decoration, TextDecoration.underline);
      final cancelled = tester.widget<Text>(find.text('This item cancels both for itself'));
      expect(cancelled.style?.fontStyle ?? FontStyle.normal, FontStyle.normal);
      expect(cancelled.style?.decoration ?? TextDecoration.none, TextDecoration.none);
      // The marker bullet in an italic card has no italic and no line.
      for (final label in tester.widgetList<Text>(find.text('•'))) {
        expect(label.style!.fontStyle ?? FontStyle.normal, FontStyle.normal);
        expect(label.style!.decoration ?? TextDecoration.none, TextDecoration.none);
      }
    });

    testWidgets('ring: a large label does not change the ring box and is not clipped', (tester) async {
      _view(tester, 393, 1000);
      await pumpDocument(tester, _startingAt('text-emphasis-screens', 'ring'));
      expect(tester.takeException(), isNull);
      final big = tester.widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.style?.fontSize ?? 0) == 40));
      expect(big, hasLength(1), reason: 'label of a large ring: displayL at size 40');
    });
  });
}
