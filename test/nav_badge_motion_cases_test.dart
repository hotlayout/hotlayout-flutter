/// THE MOTION OF THE DOT ON AN ITEM (schema 9.24.0, `x-style.layout.navBadgeMotion`).
///
/// The `navBadgeMotion…` groups of `fixtures/bottom-zone/bottom-zone-cases.json`, each row run by the rule, and the
/// mechanism through a REAL bar: the condition changes its answer on a shown screen, and the dot is read at moments
/// of its appearance and fading. The first show, a screen shown again and reduced motion give no motion.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/widgets/nav_bar.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/bottom-zone/bottom-zone-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

UiDocument _doc() => docWithScreens([
  screenEntry('home', [
    textNode('Body', id: 'body'),
    {
      'id': 'nav',
      'type': 'NavBar',
      'props': <String, Object?>{},
      'children': [
        {
          'id': 'a',
          'type': 'NavItem',
          'props': {
            'icon': 'house',
            'label': {'kind': 'literal', 'value': 'Home'},
            'action': {'type': 'none'},
            'badgeWhen': {'path': 'user.unread', 'op': 'gt', 'value': 0},
          },
        },
        {
          'id': 'b',
          'type': 'NavItem',
          'props': {
            'icon': 'house',
            'label': {'kind': 'literal', 'value': 'Two'},
            'action': {'type': 'none'},
          },
        },
      ],
    },
  ]),
], initialScreenId: 'home');

Finder _mark() => find.byType(NavBadgeMark);

double _scale(WidgetTester tester) => tester.widget<Transform>(find.descendant(of: _mark(), matching: find.byType(Transform)).last).transform.storage[0];

double _opacity(WidgetTester tester) => tester.widget<Opacity>(find.descendant(of: _mark(), matching: find.byType(Opacity))).opacity;

void main() {
  test('the groups have the promised rows', () {
    expect(_rows('navBadgeMotionCases'), hasLength(6));
    expect(_rows('navBadgeAppearScaleCases'), hasLength(6));
    expect(_rows('navBadgeDisappearOpacityCases'), hasLength(4));
  });

  test('x-style.layout.navBadgeMotion: the mirror against the artifact', () {
    final block = ((_schema['x-style']! as _Json)['layout']! as _Json)['navBadgeMotion']! as _Json;
    expect((block['appear']! as _Json)['durationMs'], kNavBadgeAppearMs);
    expect((block['appear']! as _Json)['scale'], [0, kNavBadgePeakScale, 1]);
    expect((block['appear']! as _Json)['at'], [0, kNavBadgePeakAt, 1]);
    expect((block['disappear']! as _Json)['durationMs'], kNavBadgeDisappearMs);
    expect(block['refines'], ['x-style.layout.navBadge.shown']);
    expect(block['accessibleName'], 'unchanged');
    expect(block['cases'], 'contract/fixtures/bottom-zone/bottom-zone-cases.json');
  });

  group('navBadgeMotionCases: whether the dot moves', () {
    for (final row in _rows('navBadgeMotionCases')) {
      test(row['name']! as String, () {
        final input = row['input']! as _Json;
        final change = navBadgeChangeOf(
          shownBefore: input['shownBefore']! as bool,
          before: input['before']! as bool,
          after: input['after']! as bool,
          reducedMotion: input['reducedMotion'] == true,
        );
        expect(change.name, row['expect']);
      });
    }
  });

  group('navBadgeAppearScaleCases', () {
    for (final row in _rows('navBadgeAppearScaleCases')) {
      test(row['name']! as String, () => expect(navBadgeAppearScaleAt(row['t']! as num), closeTo((row['expect']! as num).toDouble(), 1e-9)));
    }
  });

  group('navBadgeDisappearOpacityCases', () {
    for (final row in _rows('navBadgeDisappearOpacityCases')) {
      test(row['name']! as String, () => expect(navBadgeDisappearOpacityAt(row['t']! as num), closeTo((row['expect']! as num).toDouble(), 1e-9)));
    }
  });

  group('on a real bar', () {
    testWidgets('the first show with the dot: no flash', (tester) async {
      await pumpDocument(tester, _doc(), data: {'user.unread': 2});
      expect(_mark(), findsOneWidget);
      expect(_scale(tester), 1);
      expect(_opacity(tester), 1);
    });

    testWidgets('the condition becomes true on a shown screen: the flash, then the dot at rest', (tester) async {
      await pumpDocument(tester, _doc(), data: {'user.unread': 0});
      expect(_mark(), findsNothing);
      await pumpDocument(tester, _doc(), data: {'user.unread': 2});
      await tester.pump();
      expect(_mark(), findsOneWidget);
      expect(_scale(tester), closeTo(0, 1e-9));
      await tester.pump(const Duration(milliseconds: 192));
      expect(_scale(tester), closeTo(1.25, 1e-3));
      await tester.pump(const Duration(milliseconds: 64));
      expect(_scale(tester), closeTo(1.125, 1e-3));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scale(tester), 1);
      expect(_opacity(tester), 1);
    });

    testWidgets('the condition becomes false: the dot fades and stays in place until the end', (tester) async {
      await pumpDocument(tester, _doc(), data: {'user.unread': 2});
      await pumpDocument(tester, _doc(), data: {'user.unread': 0});
      await tester.pump();
      expect(_mark(), findsOneWidget);
      expect(_opacity(tester), closeTo(1, 1e-9));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacity(tester), closeTo(0.5, 1e-3));
      expect(_scale(tester), 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(_mark(), findsNothing);
    });

    testWidgets('the item does not change size or name during the motion', (tester) async {
      await pumpDocument(tester, _doc(), data: {'user.unread': 0});
      final before = tester.getSize(find.text('Home'));
      await pumpDocument(tester, _doc(), data: {'user.unread': 2});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.text('Home')), before);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('a new change during the motion starts its own motion from its start', (tester) async {
      await pumpDocument(tester, _doc(), data: {'user.unread': 0});
      await pumpDocument(tester, _doc(), data: {'user.unread': 2});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await pumpDocument(tester, _doc(), data: {'user.unread': 0});
      await tester.pump();
      expect(_opacity(tester), closeTo(1, 1e-9));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacity(tester), closeTo(0.5, 1e-3));
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('reduced motion: the dot appears and disappears at once', (tester) async {
      await pumpDocument(tester, _doc(), data: {'user.unread': 0}, disableAnimations: true);
      await pumpDocument(tester, _doc(), data: {'user.unread': 2}, disableAnimations: true);
      expect(_mark(), findsOneWidget);
      expect(_scale(tester), 1);
      await pumpDocument(tester, _doc(), data: {'user.unread': 0}, disableAnimations: true);
      expect(_mark(), findsNothing);
    });

    testWidgets('the dot is not announced', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, _doc(), data: {'user.unread': 0});
      await pumpDocument(tester, _doc(), data: {'user.unread': 2});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
      handle.dispose();
    });
  });
}
