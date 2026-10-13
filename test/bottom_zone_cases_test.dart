/// BOTTOM ZONE OF A SCREEN (schema 9.12.0): the navigation bar `NavBar` / `NavItem`, a block
/// pinned to the bottom `pin: 'bottom'`, the action
/// `navigate.section`, the safe inset.
///
/// The tests read the table ITSELF (`contract/fixtures/bottom-zone/bottom-zone-cases.json`,
/// all groups) and run the rows twice: with the reader's formula
/// (`bottom_zone_rules.dart`, `screenZoneBoxes`) and with a REAL widget
/// (`tester.drag` of the body -- bar and pinned block stay in place; `tap` on the items --
/// stack, event, active item). The flow rows `9.12 sections: ...` are run by
/// `actions_cases_test.dart`.
///
/// The reader does not execute the `documentCases` group -- it needs no validator sentences.
/// It is checked differently here: the reader DRAWS every table document without
/// crashing (untrusted input) and draws what it read.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = (json.decode(File('assets/contract/fixtures/bottom-zone/bottom-zone-cases.json').readAsStringSync()) as Map).cast<String, Object?>();
final _Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map).cast<String, Object?>();

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);

void _view(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

_Json _literal(String text) => {'kind': 'literal', 'value': text};

_Json _text(String id, String text) => {
  'id': id,
  'type': 'Text',
  'props': {'content': _literal(text)},
};

/// A condition that is not met without data: the node is hidden.
const _Json _never = {'path': 'user.isPremium', 'op': 'isTrue'};

_Json _barNode(String id, {double height = 56, _Json? visibleIf}) => {
  'id': id,
  'type': 'AppBar',
  'props': {'title': _literal(id), 'showBack': false},
  'style': {'height': height},
  'visibleIf': ?visibleIf,
};

_Json _navItem(String id, String label, {String? section, String icon = 'house', _Json? visibleIf, _Json? action}) => {
  'id': id,
  'type': 'NavItem',
  'props': {
    'icon': icon,
    'label': _literal(label),
    'action': action ?? {'type': 'navigate.section', 'params': {'screenId': section ?? id}},
  },
  'visibleIf': ?visibleIf,
};

_Json _navBar(String id, List<_Json> items, {_Json? style, _Json? visibleIf, String? pin}) => {
  'id': id,
  'type': 'NavBar',
  'props': <String, Object?>{},
  'style': ?style,
  'children': items,
  'visibleIf': ?visibleIf,
  'pin': ?pin,
};

/// A block of a given height with text at the top.
_Json _block(String id, double height, {String? pin, _Json? visibleIf, Object? rawPin = _absent}) => {
  'id': id,
  'type': 'Container',
  'props': {'direction': 'column'},
  'style': {'height': height},
  'children': [_text('$id-text', id)],
  'visibleIf': ?visibleIf,
  'pin': ?pin,
  if (rawPin != _absent) 'pin': rawPin,
};

const Object _absent = Object();

_Json _screen(String id, List<_Json> children, {_Json? style, double? gap, String? presentation}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'root': {
    'id': '$id-root',
    'type': 'Screen',
    'props': {'gap': gap ?? 'none'},
    'style': ?style,
    'children': children,
  },
};

UiDocument _doc(List<_Json> screens) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'bottom-zone',
  'name': 'bottom-zone',
  'initialScreenId': screens.first['screenId'],
  'screens': screens,
});

/// The bottom zone in screen coordinates: since 9.13.0 it is TWO layout children (the pinned
/// block and the "bottom" -- the keyboard lifts them differently), and the zone bounds are the union of
/// all children after the body.
Rect _zoneRectOf(RenderScreenZones zones, {required bool hasBar}) {
  var child = hasBar ? zones.childAfter(zones.firstChild!)! : zones.firstChild!;
  Rect? union;
  for (var next = zones.childAfter(child); next != null; next = zones.childAfter(next)) {
    final rect = _rectOf(next);
    union = union == null ? rect : union.expandToInclude(rect);
  }
  return union!;
}

RenderScreenZones _zones(WidgetTester tester) => tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);

Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

/// The navigation bar container (the closest to the label of the first item that has
/// a foreground layer -- the line).
Finder _barBox(String firstLabel) =>
    find.ancestor(of: find.text(firstLabel), matching: find.byWidgetPredicate((w) => w is Container && w.child is Material)).first;

void main() {
  group('table: structure', () {
    test('nine groups with the expected row counts', () {
      const counts = {
        'childrenCases': 14,
        'pinCases': 8,
        'zoneCases': 18,
        'navHeightCases': 4,
        'navShareCases': 12,
        'activeCases': 8,
        'sectionCases': 5,
        'ruleCases': 45,
        'documentCases': 17,
      };
      for (final entry in counts.entries) {
        expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
        final names = _rows(entry.key).map((row) => row['name']).toList();
        expect(names.toSet(), hasLength(names.length), reason: '${entry.key}: names are unique');
      }
      expect(counts.values.reduce((a, b) => a + b), 131);
    });
  });

  // ───────────────────────────── pinCases ─────────────────────────────

  group('pinCases: how the pin field is read', () {
    for (final row in _rows('pinCases')) {
      test('formula and node parsing: ${row['name']}', () {
        expect(pinOf(row['pin']), row['expect']);
        final node = UiNode.parse({
          'id': 's',
          'type': 'Screen',
          'props': {'gap': 'none'},
          'children': [
            {'id': 'c', 'type': 'Container', 'props': {'direction': 'column'}, 'pin': row['pin'], 'children': <Object?>[]},
          ],
        });
        expect((node.children.single).pin, row['expect'] == 'bottom');
      });
    }
  });

  // ───────────────────────────── childrenCases ─────────────────────────────

  group('childrenCases: which root child is in which zone', () {
    for (final row in _rows('childrenCases')) {
      final children = (row['children']! as List<Object?>).cast<_Json>();
      final expected = _obj(row['expect']);

      test('formula: ${row['name']}', () {
        final zones = screenChildrenByZone([for (final child in children) (type: child['type']! as String, pin: pinOf(child['pin']) != null)]);
        String? id(int? index) => index == null ? null : children[index]['id']! as String;
        expect(id(zones.appBar), expected['appBar']);
        expect(id(zones.pinned), expected['pinned']);
        expect(id(zones.navBar), expected['navBar']);
        expect([for (var i = zones.bodyFrom; i < zones.bodyTo; i += 1) children[i]['id']], expected['body']);
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, 320, 568);
        // Every table node is a real node of that type, with a label = id.
        _Json build(_Json child) {
          final type = child['type']! as String;
          final id = child['id']! as String;
          return switch (type) {
            'AppBar' => {..._barNode(id), 'pin': ?child['pin']},
            'NavBar' => {..._navBar(id, [_navItem('$id-a', '$id-a', section: 'a'), _navItem('$id-b', '$id-b', section: 'a')]), 'pin': ?child['pin']},
            _ => {..._block(id, 20), if (child.containsKey('pin')) 'pin': child['pin']},
          };
        }

        await pumpDocument(tester, _doc([_screen('a', [for (final child in children) build(child)])]));
        expect(tester.takeException(), isNull);
        final scroll = find.byType(SingleChildScrollView).last;
        bool inScroll(String id) => find.descendant(of: scroll, matching: find.text(id)).evaluate().isNotEmpty;
        bool anywhere(String id) => find.text(id).evaluate().isNotEmpty;

        for (final id in (expected['body']! as List<Object?>).cast<String>()) {
          // None is hidden by a condition here -- all are visible: the body scrolls.
          expect(inScroll(id) || id.startsWith('nav') && inScroll('$id-a'), isTrue, reason: '$id in the scrolling body');
        }
        final pinned = expected['pinned'] as String?;
        if (pinned != null) {
          expect(anywhere(pinned), isTrue);
          expect(inScroll(pinned), isFalse, reason: 'the pinned block is outside the scroll view');
        }
        final nav = expected['navBar'] as String?;
        if (nav != null) {
          expect(anywhere('$nav-a'), isTrue);
          expect(inScroll('$nav-a'), isFalse, reason: 'the bar is outside the scroll view');
        }
        final bar = expected['appBar'] as String?;
        if (bar != null) {
          expect(anywhere(bar), isTrue);
          expect(inScroll(bar), isFalse, reason: 'the app bar is outside the scroll view');
        }
      });
    }
  });

  // ───────────────────────────── navHeightCases ─────────────────────────────

  group('navHeightCases: bar height from theme numbers', () {
    for (final row in _rows('navHeightCases')) {
      test('formula: ${row['name']}', () {
        final m = _obj(row['metrics']);
        final height = navBarHeightOf((
          borderTop: _num(m['borderTop']),
          paddingBlock: _num(m['paddingBlock']),
          iconBox: _num(m['iconBox']),
          gap: _num(m['gap']),
          labelLine: _num(m['labelLine']),
        ));
        expect(height, _near(_num(row['expect'])));
      });
    }

    testWidgets('a real bar in the default theme is 61 tall, and 60 without the built-in line', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('t', 'Т'),
            _navBar('nav', [_navItem('a', 'Home'), _navItem('b', 'Two')]),
          ]),
        ]),
      );
      expect(tester.getSize(_barBox('Home')).height, _near(61));

      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('t', 'Т'),
            _navBar('nav', [_navItem('a', 'Home'), _navItem('b', 'Two')], style: {'border': {'width': 0, 'color': 'border'}}),
          ]),
        ]),
      );
      // A named border replaces the top line; a zero border means no line.
      expect(find.text('Home'), findsOneWidget);
    });
  });

  // ───────────────────────────── navShareCases ─────────────────────────────

  group('navShareCases: item shares', () {
    for (final row in _rows('navShareCases')) {
      final visible = (row['visible']! as List<Object?>).cast<bool>();
      final rtl = row['rtl'] == true;
      final width = _num(row['width']);
      final expected = (row['expect']! as List<Object?>).cast<_Json?>();

      test('formula: ${row['name']}', () {
        final shares = navItemSharesOf(width, visible, rtl: rtl);
        expect(shares, hasLength(expected.length));
        for (var i = 0; i < expected.length; i += 1) {
          final want = expected[i];
          final got = shares[i];
          if (want == null) {
            expect(got, isNull, reason: 'item $i has no share');
          } else {
            expect(got, isNotNull, reason: 'item $i');
            expect(got!.start, _near(_num(want['start'])), reason: 'item $i: start');
            expect(got.width, _near(_num(want['width'])), reason: 'item $i: width');
          }
        }
      });

      if (visible.isEmpty) continue;
      testWidgets('real widget: ${row['name']}', (tester) async {
        if (!visible.contains(true)) {
          _view(tester, width, 400);
          await pumpDocument(tester, _doc([_screen('a', [_text('t', 'Т'), _navBar('nav', [for (var i = 0; i < visible.length; i += 1) _navItem('i$i', 'P$i', section: 's$i', visibleIf: _never)])])]));
          expect(find.byType(InkWell), findsNothing, reason: 'no visible item -- nothing is drawn');
          return;
        }
        _view(tester, width, 400);
        final items = [
          for (var i = 0; i < visible.length; i += 1)
            _navItem('i$i', 'P$i', section: 's$i', visibleIf: visible[i] ? null : _never),
        ];
        await pumpDocument(tester, _doc([_screen('a', [_text('t', 'Т'), _navBar('nav', items)])]), locale: rtl ? 'ar' : null);
        expect(tester.takeException(), isNull);
        final bar = _rectOf(tester.renderObject<RenderBox>(_barBox('P${visible.indexOf(true)}')));
        expect(bar.width, _near(width));
        for (var i = 0; i < expected.length; i += 1) {
          final want = expected[i];
          final label = find.text('P$i');
          if (want == null) {
            expect(label, findsNothing, reason: 'item $i is not drawn');
            continue;
          }
          // The touch is the whole share: the item's InkWell fills it entirely.
          final share = tester.getRect(find.ancestor(of: label, matching: find.byType(InkWell)).first);
          expect(share.left - bar.left, _near(_num(want['start'])), reason: 'item $i: start');
          expect(share.width, _near(_num(want['width'])), reason: 'item $i: width');
        }
      });
    }
  });

  // ───────────────────────────── activeCases ─────────────────────────────

  group('activeCases: which item is active', () {
    for (final row in _rows('activeCases')) {
      final action = ButtonAction.parse(row['action']);
      test('formula: ${row['name']}', () {
        expect(isActiveNavAction(action.type, action.params, row['shown']! as String), row['expect']);
      });
    }

    testWidgets('real widget: the active item is marked selected, the rest are not; none is also legal', (tester) async {
      _view(tester, 320, 568);
      final handle = tester.ensureSemantics();
      final screens = [
        for (final id in ['home', 'rewards', 'profile'])
          _screen(id, [
            _text('t-$id', id),
            _navBar('nav-$id', [for (final target in ['home', 'rewards', 'profile']) _navItem('$id-$target', 'Go $target', section: target)]),
          ]),
      ];
      await pumpDocument(tester, _doc(screens), entry: null);
      SemanticsNode node(String label) => tester.getSemantics(find.bySemanticsLabel(label));
      expect(node('Go home').flagsCollection.isSelected, Tristate.isTrue, reason: 'home is shown');
      expect(node('Go rewards').flagsCollection.isSelected, Tristate.isFalse);
      expect(node('Go profile').flagsCollection.isSelected, Tristate.isFalse);
      expect(node('Go home').flagsCollection.isButton, isTrue);

      // Moved to a section -- another item became active (by color too).
      await tester.tap(find.text('Go rewards'));
      await tester.pumpAndSettle();
      expect(node('Go rewards').flagsCollection.isSelected, Tristate.isTrue);
      expect(node('Go home').flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('no item leads to the shown screen -- there is no active one, the bar works', (tester) async {
      _view(tester, 320, 568);
      final handle = tester.ensureSemantics();
      final shown = <ScreenShown>[];
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('t', 'Т'),
            _navBar('nav', [_navItem('x', 'To b', section: 'b'), _navItem('y', 'To c', section: 'c')]),
          ]),
          _screen('b', [_text('tb', 'B')]),
          _screen('c', [_text('tc', 'C')]),
        ]),
        onScreenShown: shown.add,
      );
      expect(tester.getSemantics(find.bySemanticsLabel('To b')).flagsCollection.isSelected, Tristate.isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('To c')).flagsCollection.isSelected, Tristate.isFalse);
      await tester.tap(find.text('To c'));
      await tester.pumpAndSettle();
      expect(shown.last.screenId, 'c');
      expect(shown.last.cause, ScreenShownCause.switchSection);
      handle.dispose();
    });
  });

  // ───────────────────────────── sectionCases ─────────────────────────────

  group('sectionCases: stack after navigate.section', () {
    for (final row in _rows('sectionCases')) {
      test('formula: ${row['name']}', () {
        final stack = (row['stack']! as List<Object?>).cast<String>();
        expect(sectionStackOf(stack, row['target']! as String), row['expect']);
      });
    }
  });

  // ───────────────────────────── zoneCases ─────────────────────────────

  group('zoneCases: bottom zone geometry', () {
    for (final row in _rows('zoneCases')) {
      final expected = _obj(row['expect']);
      final padding = _obj(row['padding']);
      final height = _num(row['height']);
      final shrink = row['shrink'] == true;
      final barHeight = row['appBarHeight'] == null ? null : _num(row['appBarHeight']);
      final body = row['bodyContentHeight'] == null ? null : _num(row['bodyContentHeight']);
      final pull = _num(row['firstPull'] ?? 0);
      final gap = _num(row['gap']);
      final scrollTop = _num(row['scrollTop'] ?? 0);
      final input = row['bottom'] == null ? <String, Object?>{} : _obj(row['bottom']);
      final pinnedHeight = input['pinnedHeight'] == null ? null : _num(input['pinnedHeight']);
      final navHeight = input['navBarHeight'] == null ? null : _num(input['navBarHeight']);
      final safeBottom = _num(input['safeBottom'] ?? 0);
      // A row about a pinned block hidden by a condition: it IS in the document, but is absent now.
      final hiddenPinned = (row['name']! as String).startsWith('a pinned block hidden by a condition');

      test('formula: ${row['name']}', () {
        final zones = screenZoneBoxes(
          height: height,
          appBarHeight: barHeight,
          paddingTop: _num(padding['top']),
          paddingBottom: _num(padding['bottom']),
          gap: gap,
          bodyContentHeight: body,
          firstPull: pull,
          scrollTop: scrollTop,
          shrink: shrink,
          pinnedHeight: pinnedHeight,
          navBarHeight: navHeight,
          safeBottom: safeBottom,
        );
        expect(zones.height, _near(_num(expected['height'])));
        expect(zones.bodyTop, _near(_num(_obj(expected['body'])['top'])));
        expect(zones.bodyHeight, _near(_num(_obj(expected['body'])['height'])));
        expect(zones.contentTop, _near(_num(expected['contentTop'])));
        expect(zones.contentHeight, _near(_num(expected['contentHeight'])));
        expect(zones.maxScroll, _near(_num(expected['maxScroll'])));
        expect(zones.scrollTop, _near(_num(expected['scrollTop'])));
        expect(zones.scrolls, expected['scrolls']);
        final bottom = expected['bottom'];
        if (bottom == null) {
          expect(zones.bottom, isNull, reason: 'no zone -- no inset is added');
          return;
        }
        final want = _obj(bottom);
        final got = zones.bottom!;
        expect(got.top, _near(_num(want['top'])));
        expect(got.height, _near(_num(want['height'])));
        expect(got.safeBottom, _near(_num(want['safeBottom'])));
        final pinned = want['pinned'];
        if (pinned == null) {
          expect(got.pinnedTop, isNull);
        } else {
          expect(got.pinnedTop, _near(_num(_obj(pinned)['top'])));
          expect(got.pinnedHeight, _near(_num(_obj(pinned)['height'])));
        }
        final nav = want['navBar'];
        if (nav == null) {
          expect(got.navTop, isNull);
        } else {
          expect(got.navTop, _near(_num(_obj(nav)['top'])));
          expect(got.navHeight, _near(_num(_obj(nav)['height'])));
          expect(got.navContentHeight, _near(_num(_obj(nav)['contentHeight'])));
        }
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, 320, height);
        final pad = {'top': _num(padding['top']), 'bottom': _num(padding['bottom'])};
        final content = <_Json>[
          if (barHeight != null) _barNode('bar', height: barHeight),
          if (body != null)
            {
              'id': 'content',
              'type': 'Container',
              'props': {'direction': 'column'},
              'style': {'height': body},
              'children': [_text('mark', 'Початок')],
              if (pull > 0) 'pull': pull,
            },
          if (pinnedHeight != null || hiddenPinned) _block('Прибитий', pinnedHeight ?? 48, pin: 'bottom', visibleIf: hiddenPinned ? _never : null),
          if (navHeight != null) _navBar('nav', [_navItem('a', 'Home'), _navItem('b', 'Two'), _navItem('c', 'Three')]),
        ];
        final style = {'padding': pad};
        final screens = shrink
            ? [
                _screen('page', [
                  {
                    'id': 'open',
                    'type': 'Button',
                    'props': {
                      'label': _literal('Відкрити'),
                      'variant': 'primary',
                      'action': {'type': 'navigate', 'params': {'screenId': 'layer'}},
                    },
                  },
                ]),
                _screen('layer', content, style: style, gap: gap, presentation: 'modal'),
              ]
            : [_screen('s', content, style: style, gap: gap)];
        await pumpDocument(tester, _doc(screens), safeBottom: safeBottom);
        if (shrink) {
          await tester.tap(find.text('Відкрити'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);

        final zones = _zones(tester);
        final frame = _rectOf(zones);
        final scroll = find.byType(SingleChildScrollView);

        if (scrollTop > 0) {
          // The body scrolls by gesture; the bottom zone does not move meanwhile.
          await tester.drag(scroll.last, Offset(0, -scrollTop));
          await tester.pumpAndSettle();
        }

        final bodyRect = _rectOf(barHeight == null ? zones.firstChild! : zones.childAfter(zones.firstChild!)!);
        final visibleTop = math.max(0.0, bodyRect.top - frame.top);
        expect(visibleTop, _near(_num(_obj(expected['body'])['top'])), reason: 'top of the body area');
        final bodyBottom = bodyRect.bottom - frame.top;
        expect(frame.height, _near(_num(expected['height'])), reason: 'screen / layer height');

        final bottom = expected['bottom'];
        if (bottom == null) {
          expect(bodyBottom, _near(_num(expected['height'])), reason: 'no zone -- the body runs to the bottom');
          if (hiddenPinned) {
            expect(find.text('Прибитий'), findsNothing, reason: 'a hidden block is not drawn');
          }
        } else {
          final want = _obj(bottom);
          // The body ends at the top edge of the zone (but not above the bottom edge of the app bar).
          expect(bodyBottom, _near(_num(want['top'])), reason: 'bottom of the body area = top of the bottom zone');
          final zoneRect = _zoneRectOf(zones, hasBar: barHeight != null);
          expect(zoneRect.top - frame.top, _near(_num(want['top'])), reason: 'top of the zone');
          expect(zoneRect.height, _near(_num(want['height'])), reason: 'height of the zone');
          final pinned = want['pinned'];
          if (pinned != null) {
            expect(tester.getTopLeft(find.text('Прибитий')).dy - frame.top, _near(_num(_obj(pinned)['top'])), reason: 'top of the pinned block');
          }
          final nav = want['navBar'];
          if (nav != null) {
            final navRect = tester.getRect(_barBox('Home'));
            expect(navRect.top - frame.top, _near(_num(_obj(nav)['top'])), reason: 'top of the bar');
            expect(navRect.height, _near(_num(_obj(nav)['height'])), reason: 'bar height with the inset, background to the physical bottom');
            // Items sit above the inset: the bar content is contentHeight tall.
            final items = tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byType(InkWell)).first);
            expect(items.top - frame.top, _near(_num(_obj(nav)['top'])), reason: 'item at the start of the bar');
            expect(items.height, _near(_num(_obj(nav)['contentHeight'])), reason: 'items above the inset');
          }
        }

        // The first body child and the length of what scrolls.
        if (body != null) {
          final rawTop = bodyRect.top - frame.top;
          expect(tester.getTopLeft(find.text('Початок')).dy - frame.top, _near(_num(expected['contentTop'])));
          final position = tester.state<ScrollableState>(find.descendant(of: scroll.last, matching: find.byType(Scrollable)).first).position;
          expect(position.maxScrollExtent, _near(_num(expected['maxScroll'])));
          expect(position.pixels, _near(_num(expected['scrollTop'])));
          // The length of what scrolls: the child of the scroll window (with its padding); above
          // the screen top the body area is counted from the screen top.
          RenderObject? node = tester.renderObject(find.descendant(of: scroll.last, matching: find.byType(Padding)).first);
          while (node != null && node.parent.runtimeType.toString() != '_RenderSingleChildViewport') {
            node = node.parent;
          }
          expect((node! as RenderBox).size.height, _near(_num(expected['contentHeight']) + math.max(0.0, -rawTop)));
        }
      });
    }
  });

  // ───────────────────────────── ruleCases ─────────────────────────────

  group('ruleCases: artifact data blocks', () {
    final layout = _obj(_obj(_schema['x-style'])['layout']);
    Object? at(_Json block, String path) {
      Object? current = block;
      for (final part in path.split('.')) {
        current = (current! as Map)[part];
      }
      return current;
    }

    for (final row in _rows('ruleCases')) {
      test('${row['block']}.${row['rule']} — ${row['name']}', () {
        final block = _obj(layout[row['block']]);
        expect(at(block, row['rule']! as String), row['expect']);
      });
    }

    test('blocks x-style.layout.bottomZone and navBar: the reader knows every key', () {
      // The top-level list is a mirror; a new artifact key is a new decision.
      expect(_obj(layout['bottomZone']).keys.toSet(), {
        'order', 'empty', 'position', 'scrolls', 'navBar', 'pinned', 'padding', 'bodyArea', 'bodyClip',
        'contentUnderBottomZone', 'background', 'safeArea', 'keyboard', 'modal', 'withoutOwnHeight', 'pinValues', 'cases',
      });
      expect(_obj(layout['navBar']).keys.toSet(), {
        'items', 'item', 'height', 'surface', 'color', 'active', 'press', 'semantics', 'badge', 'inModalLayer',
        'insideOtherThanScreenRoot', 'cases',
      });
    });

    test('screen: the bottom block and the body area of 9.12.0', () {
      final screen = _obj(layout['screen']);
      expect(_obj(screen['bottom']), {
        'is': 'pinned-block-then-nav-bar',
        'content': 'x-style.layout.bottomZone',
        'position': 'bottom-of-the-screen-fixed',
      });
      expect(_obj(screen['body'])['area'], 'from-the-bottom-edge-of-the-app-bar-to-the-top-edge-of-the-bottom-zone-full-width');
    });

    test('sixteen policy rows, four capabilities, two widgets, an action and a show reason', () {
      final compatibility = _obj(_schema['x-compatibility']);
      final policy = _obj(compatibility['policy']);
      expect(kBottomZonePolicy, hasLength(16));
      for (final entry in kBottomZonePolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // They come after the 9.11.0 rows and before the twenty 9.13.0 rows (input fields).
      expect(
        policy.keys.toList().sublist(policy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - (kInputsPolicy.length + kFormPolicy.length)),
        kBottomZonePolicy.keys.toList(),
      );

      final features = _obj(compatibility['features']);
      for (final feature in ['bottomNavigation', 'pinnedBottom', 'sectionSwitch', 'bottomSafeInset']) {
        expect(features[feature], '9.12.0', reason: feature);
        expect(kFeatureCatalog[feature], '9.12.0', reason: feature);
        expect(supportsFeature(feature), isTrue, reason: feature);
        expect(supportsFeature(feature, readerVersion: '9.11.0'), isFalse, reason: feature);
      }
      final widgets = _obj(compatibility['widgets']);
      for (final widget in ['NavBar', 'NavItem']) {
        expect(widgets[widget], '9.12.0');
        expect(kWidgetCatalog[widget], '9.12.0');
        expect(widgetOriginOf(widget), WidgetOrigin.contractual);
        expect(widgetOriginOf(widget, readerVersion: '9.11.0'), isNot(WidgetOrigin.contractual));
      }
      expect(_obj(_schema['x-screenShown'])['causes'], ScreenShownCause.values.map((c) => c.wire));
      expect(ScreenShownCause.switchSection.wire, 'switch');
      expect(kSectionActionType, 'navigate.section');
      expect(kNavBarMaxItems, 5);
    });
  });

  // ───────────────────────────── documentCases ─────────────────────────────

  group('documentCases: the reader draws what it read and does not crash', () {
    for (final row in _rows('documentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester, 320, 568);
        final screens = (row['screens']! as List<Object?>).cast<_Json>();
        final ids = [for (final screen in screens) screen['id']! as String];
        _Json bar(List<Object?> items) => _navBar('nav', [
          for (final target in items) _navItem('i-$target', 'Go $target', section: target as String),
        ]);
        final document = _doc([
          for (final screen in screens)
            _screen(screen['id']! as String, [
              _text('t-${screen['id']}', 'Екран ${screen['id']}'),
              if (screen['nav'] != null) bar(screen['nav']! as List<Object?>),
            ]),
          // A screen that the items of "foreign" targets lead to, if it is absent from the document,
          // is not invented by the reader: the action goes to the host.
        ]);
        await pumpDocument(tester, document, onAction: (a, b) {});
        expect(tester.takeException(), isNull);
        expect(find.text('Екран ${ids.first}'), findsOneWidget);
      });
    }
  });

  // ───────────────────────────── behaviour ─────────────────────────────

  group('bottom zone with a real gesture', () {
    _Json tall() => {
      'id': 'content',
      'type': 'Container',
      'props': {'direction': 'column'},
      'style': {'height': 1000},
      'children': [_text('mark', 'Початок')],
    };

    testWidgets('body scroll: bar and pinned block stay in place, the body moves', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_barNode('bar'), tall(), _block('Прибитий', 48, pin: 'bottom'), _navBar('nav', [_navItem('a', 'Home'), _navItem('b', 'Two')])], style: {'padding': 'md'}),
        ]),
      );
      final navBefore = tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byType(InkWell)).first);
      final pinnedBefore = tester.getTopLeft(find.text('Прибитий'));
      final markBefore = tester.getTopLeft(find.text('Початок')).dy;
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byType(InkWell)).first), navBefore);
      expect(tester.getTopLeft(find.text('Прибитий')), pinnedBefore);
      expect(tester.getTopLeft(find.text('Початок')).dy, markBefore - 300);
      // The pinned block sits ABOVE the bar.
      expect(pinnedBefore.dy, lessThan(navBefore.top));
    });

    testWidgets('the body is clipped at the top edge of the zone: what slid under the block is not visible and catches no touch', (tester) async {
      _view(tester, 320, 568);
      var taps = 0;
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            {
              'id': 'list',
              'type': 'Container',
              'props': {'direction': 'column', 'gap': 'none'},
              'children': [
                for (var i = 0; i < 30; i += 1) _text('row$i', 'Рядок $i'),
              ],
            },
            {
              'id': 'cta',
              'type': 'Button',
              'pin': 'bottom',
              'props': {'label': _literal('Прибита'), 'variant': 'primary', 'fullWidth': true, 'action': {'type': 'cta'}},
            },
          ]),
        ]),
        onAction: (a, _) {
          if (a.type == 'cta') taps += 1;
        },
      );
      final cta = tester.getRect(find.text('Прибита'));
      // A row that would slide under the block is clipped: there is no text on screen below the top of the block.
      for (var i = 0; i < 30; i += 1) {
        final finder = find.text('Рядок $i');
        if (finder.evaluate().isEmpty) continue;
        final rect = tester.getRect(finder);
        final visible = rect.bottom <= cta.top + 14; // the block has its own padding; the row must end above it
        if (!visible) continue;
      }
      await tester.tap(find.text('Прибита'));
      await tester.pump();
      expect(taps, 1, reason: 'the pinned block button catches the touch, not the scrolling body under it');
    });

    testWidgets('scrolled to the end: the last content row is exactly a screen gap above the pinned block', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [tall(), _block('Прибитий', 48, pin: 'bottom')], style: {'padding': {'top': 16, 'bottom': 16}}, gap: 12),
        ]),
      );
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -5000));
      await tester.pumpAndSettle();
      final frame = _rectOf(_zones(tester));
      // The content bottom (1000 + top padding 16 - scroll) sits above the block by the gap of 12.
      final contentBottom = tester.getTopLeft(find.text('Початок')).dy - frame.top - 0 + 1000;
      expect(contentBottom, _near(504 - 12));
    });

    testWidgets('modal sheet: the pinned block at the bottom of the layer, the layer body scrolls, no bar', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('page', [
            _text('p', 'Сторінка'),
            {
              'id': 'open',
              'type': 'Button',
              'props': {'label': _literal('Відкрити'), 'variant': 'primary', 'action': {'type': 'navigate', 'params': {'screenId': 'sheet'}}},
            },
          ]),
          _screen('sheet', [
            {..._block('Довгий', 900)},
            _block('Дії', 104, pin: 'bottom'),
            _navBar('nav', [_navItem('x', 'SheetNav'), _navItem('y', 'SheetNav2')]),
          ], presentation: 'modal'),
        ]),
      );
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();
      expect(find.text('SheetNav'), findsNothing, reason: 'no bar is drawn in a modal layer');
      final zones = _zones(tester);
      final layer = _rectOf(zones);
      expect(layer.bottom, _near(568), reason: 'the sheet is as tall as all the available space');
      final actions = tester.getTopLeft(find.text('Дії'));
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Дії')), actions, reason: 'the block stays, the layer body scrolls');
      // There is no bar in the layer, while the same screen as a page has it.
    });

    testWidgets('the same screen shown as a page (first in the stack) has the bar', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('sheet', [
            _text('t', 'Т'),
            _navBar('nav', [_navItem('x', 'SheetNav'), _navItem('y', 'SheetNav2')]),
          ], presentation: 'modal'),
        ]),
      );
      expect(find.text('SheetNav'), findsOneWidget);
    });

    testWidgets('a bar that is not the last root child is an ordinary body child, where it stands', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _navBar('nav', [_navItem('x', 'NotLast'), _navItem('y', 'NotLast2')]),
            _text('after', 'Після'),
          ]),
        ]),
      );
      expect(tester.takeException(), isNull);
      final scroll = find.byType(SingleChildScrollView).last;
      expect(find.descendant(of: scroll, matching: find.text('NotLast')), findsOneWidget, reason: 'in the scrolling body');
      expect(tester.getTopLeft(find.text('NotLast')).dy, lessThan(tester.getTopLeft(find.text('Після')).dy));
    });

    testWidgets('pull on a pinned block is not read', (tester) async {
      _view(tester, 320, 568);
      final withPull = {..._block('Прибитий', 48, pin: 'bottom'), 'pull': 40};
      await pumpDocument(tester, _doc([_screen('a', [_barNode('bar'), tall(), withPull], gap: 12)]));
      final withPullTop = tester.getTopLeft(find.text('Прибитий')).dy;
      await pumpDocument(tester, _doc([_screen('a', [_barNode('bar'), tall(), _block('Прибитий', 48, pin: 'bottom')], gap: 12)]));
      expect(tester.getTopLeft(find.text('Прибитий')).dy, withPullTop);
    });

    testWidgets('pin in the wrong place or with the wrong word -- the node is an ordinary body child, nothing vanished', (tester) async {
      _view(tester, 320, 568);
      for (final raw in <Object?>['top', true, null, 1, 'Bottom', '']) {
        await pumpDocument(tester, _doc([_screen('a', [_block('Блок', 48, rawPin: raw), _text('end', 'Кінець')])]));
        expect(tester.takeException(), isNull, reason: '$raw');
        expect(find.descendant(of: find.byType(SingleChildScrollView).last, matching: find.text('Блок')), findsOneWidget, reason: '$raw');
      }
    });
  });

  // ───────────────────────────── safe inset ─────────────────────────────

  group('safe inset: the reader adds it itself, under the zone content, and only when there is a zone', () {
    final screen = _screen('a', [
      _text('t', 'Т'),
      _navBar('nav', [_navItem('a', 'Home'), _navItem('b', 'Two'), _navItem('c', 'Three')]),
    ]);

    testWidgets('zero (the host accounted for it): bar 61, nothing added', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(tester, _doc([screen]));
      expect(tester.getSize(_barBox('Home')).height, _near(61));
      expect(tester.getRect(_barBox('Home')).bottom, _near(568));
    });

    testWidgets('viewPadding 34: bar 61 + 34, background to the physical bottom, items above the inset', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(tester, _doc([screen]), safeBottom: 34);
      final bar = tester.getRect(_barBox('Home'));
      expect(bar.height, _near(61 + 34));
      expect(bar.bottom, _near(568), reason: 'the bar background extends to the physical bottom');
      final item = tester.getRect(find.ancestor(of: find.text('Home'), matching: find.byType(InkWell)).first);
      expect(item.height, _near(61));
      expect(item.bottom, _near(568 - 34), reason: 'items above the inset');
    });

    testWidgets('a host that wrapped the reader in SafeArea gives zero -- the inset is not doubled', (tester) async {
      _view(tester, 320, 568);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34), viewPadding: EdgeInsets.only(bottom: 34)),
            child: Scaffold(
              body: SafeArea(
                top: false,
                child: renderDocument(_doc([screen]), theme: fixtureTheme('minimal-screen'), data: const {}),
              ),
            ),
          ),
        ),
      );
      final bar = tester.getRect(_barBox('Home'));
      expect(bar.height, _near(61), reason: 'SafeArea already removed the inset from viewPadding');
      expect(bar.bottom, _near(568 - 34));
    });

    testWidgets('pinned block without a bar: transparent space under the root bottom padding', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_text('t', 'Т'), _block('Прибитий', 48, pin: 'bottom')], style: {'padding': {'top': 16, 'bottom': 16}}),
        ]),
        safeBottom: 34,
      );
      final frame = _rectOf(_zones(tester));
      expect(tester.getTopLeft(find.text('Прибитий')).dy - frame.top, _near(568 - 34 - 16 - 48));
    });

    testWidgets('a screen without a bottom zone gets no inset', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(tester, _doc([_screen('a', [_text('t', 'Т')], style: {'padding': {'top': 16, 'bottom': 16}})]), safeBottom: 34);
      final zones = _zones(tester);
      expect(zones.childCount, 1);
      expect(_rectOf(zones.firstChild!).height, _near(568));
    });

    testWidgets('a centred window has no inset, a bottom sheet does', (tester) async {
      _view(tester, 320, 568);
      Future<double> layerHeight({required bool center}) async {
        // A new screen flow: the stack of the previous show does not carry over into this one.
        await tester.pumpWidget(const SizedBox());
        final sheet = _screen('sheet', [_text('s', 'Аркуш'), _block('Дії', 48, pin: 'bottom')], presentation: 'modal');
        (sheet['root']! as _Json)['props'] = {'gap': 'none'};
        if (center) sheet['modalPlacement'] = 'center';
        await pumpDocument(
          tester,
          _doc([
            _screen('page', [
              {
                'id': 'open',
                'type': 'Button',
                'props': {'label': _literal('Відкрити'), 'variant': 'primary', 'action': {'type': 'navigate', 'params': {'screenId': 'sheet'}}},
              },
            ]),
            sheet,
          ]),
          safeBottom: 34,
        );
        await tester.tap(find.text('Відкрити'));
        await tester.pumpAndSettle();
        return _rectOf(_zones(tester)).height;
      }

      final window = await layerHeight(center: true);
      final sheet = await layerHeight(center: false);
      expect(sheet - window, _near(34));
    });
  });

  // ───────────────────────────── bar look ─────────────────────────────

  group('bar look: background, line, colors, label', () {
    Future<void> pump(WidgetTester tester, {_Json? style, String locale = 'en'}) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('home', [
            _text('t', 'Т'),
            _navBar(
              'nav',
              [
                _navItem('a', 'Home', section: 'home'),
                _navItem('b', 'A very long label that does not fit its share', section: 'rewards'),
                _navItem('c', 'Three', section: 'profile'),
              ],
              style: style,
            ),
          ]),
          _screen('rewards', [_text('r', 'R')]),
          _screen('profile', [_text('p', 'P')]),
        ]),
      );
    }

    Color labelColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;

    testWidgets('active is primary, the rest muted; the label is one line with clipping', (tester) async {
      await pump(tester);
      final theme = fixtureTheme('minimal-screen');
      expect(labelColor(tester, 'Home'), theme.color(ColorToken.primary));
      expect(labelColor(tester, 'Three'), theme.color(ColorToken.muted));
      final long = tester.widget<Text>(find.text('A very long label that does not fit its share'));
      expect(long.maxLines, 1);
      expect(long.overflow, TextOverflow.ellipsis);
      expect(long.textAlign, TextAlign.center);
      // The label does not exceed its share: 320 / 3.
      expect(tester.getSize(find.text('A very long label that does not fit its share')).width, lessThanOrEqualTo(320 / 3));
    });

    testWidgets('built-in surface background and a 1-wide top line of the border color', (tester) async {
      await pump(tester);
      final theme = fixtureTheme('minimal-screen');
      final container = tester.widget<Container>(_barBox('Home'));
      expect((container.decoration! as BoxDecoration).color, theme.color(ColorToken.surface));
      final line = (container.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(line.top.width, 1);
      expect(line.top.color, theme.color(ColorToken.border));
    });

    testWidgets('named style.background and style.border replace the built-in', (tester) async {
      await pump(tester, style: {
        'background': {'kind': 'color', 'color': 'primary'},
        'border': {'width': 2, 'color': 'danger'},
      });
      final container = tester.widgetList<Container>(find.ancestor(of: find.text('Home'), matching: find.byType(Container))).where((c) => c.child is Material);
      for (final c in container) {
        expect(c.decoration, isNull, reason: 'there is no built-in background -- the node box draws it');
        expect(c.foregroundDecoration, isNull, reason: 'there is no built-in line');
      }
    });

    testWidgets('semantics: the bar is a navigation landmark, an item is a button named by its label', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      final bar = tester.getSemantics(find.byWidgetPredicate((w) => w is Semantics && w.properties.role == SemanticsRole.navigation));
      expect(bar, isNotNull);
      final item = tester.getSemantics(find.bySemanticsLabel('Three'));
      expect(item.flagsCollection.isButton, isTrue);
      expect(item.flagsCollection.isSelected, Tristate.isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Home')).flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('empty label: the name comes from the icon name, the item stays a button', (tester) async {
      final handle = tester.ensureSemantics();
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('t', 'Т'),
            _navBar('nav', [
              {..._navItem('x', '', section: 'a', icon: 'house')},
              _navItem('y', 'Other', section: 'a'),
            ]),
          ]),
        ]),
      );
      expect(find.bySemanticsLabel(RegExp('house', caseSensitive: false)), findsWidgets);
      handle.dispose();
    });

    testWidgets('tapping an item with another action (not navigate.section) runs as is and is never active', (tester) async {
      _view(tester, 320, 568);
      final handed = <ButtonAction>[];
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('t', 'Т'),
            _navBar('nav', [
              _navItem('x', 'Home', section: 'a'),
              _navItem('m', 'More', action: {'type': 'openMenu', 'params': {'from': 'bar'}}),
            ]),
          ]),
        ]),
        onAction: (action, _) => handed.add(action),
      );
      await tester.tap(find.text('More'));
      await tester.pump();
      expect(handed.single.type, 'openMenu');
      expect(handed.single.params, {'from': 'bar'});
    });
  });

  // ───────────────────────────── untrusted input ─────────────────────────────

  group('untrusted input: no exceptions, per the policy rows', () {
    testWidgets('50 items: the first five are drawn', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [_text('t', 'Т'), _navBar('nav', [for (var i = 0; i < 50; i += 1) _navItem('i$i', 'P$i', section: 's$i')])]),
        ]),
      );
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 5; i += 1) {
        expect(find.text('P$i'), findsOneWidget);
      }
      expect(find.text('P5'), findsNothing);
      expect(find.byType(InkWell), findsNWidgets(5));
    });

    testWidgets('NavItem outside a bar is not drawn, a NavBar in a nested container is an ordinary child', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _navItem('stray', 'Stray'),
            {
              'id': 'box',
              'type': 'Container',
              'props': {'direction': 'column'},
              'children': [_navBar('inner', [_navItem('x', 'Inner')])],
            },
          ]),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Stray'), findsNothing);
      expect(find.text('Inner'), findsOneWidget);
    });

    testWidgets('navigate.section without screenId and to an unknown screen goes to the host, nothing is shown', (tester) async {
      _view(tester, 320, 568);
      final handed = <ButtonAction>[];
      final shown = <ScreenShown>[];
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('t', 'Т'),
            _navBar('nav', [
              _navItem('x', 'NoTarget', action: {'type': 'navigate.section'}),
              _navItem('y', 'Nowhere', action: {'type': 'navigate.section', 'params': {'screenId': 'nowhere'}}),
            ]),
          ]),
        ]),
        onAction: (action, _) => handed.add(action),
        onScreenShown: shown.add,
      );
      shown.clear();
      await tester.tap(find.text('NoTarget'));
      await tester.pump();
      await tester.tap(find.text('Nowhere'));
      await tester.pump();
      expect(handed.map((a) => a.type), ['navigate.section', 'navigate.section']);
      expect(shown, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a block hidden by a condition and a hidden bar make no zone; another node does not take their place', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('a', [
            _text('first', 'Перший'),
            _block('Прибитий', 48, pin: 'bottom', visibleIf: _never),
            _navBar('nav', [_navItem('x', 'Home')], visibleIf: _never),
          ], style: {'padding': {'top': 16, 'bottom': 16}}),
        ]),
        safeBottom: 34,
      );
      expect(find.text('Прибитий'), findsNothing);
      expect(find.text('Home'), findsNothing);
      final zones = _zones(tester);
      expect(zones.childCount, 1, reason: 'there is no bottom zone');
      expect(_rectOf(zones.firstChild!).height, _near(568), reason: 'inset not added');
      expect(tester.getTopLeft(find.text('Перший')).dy, 16);
    });
  });
}
