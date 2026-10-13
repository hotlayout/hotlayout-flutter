/// SCREEN ANATOMY: the app bar stays put, only the body scrolls (schema 9.9.0).
///
/// The tests read the table ITSELF (`media-chrome-cases.json`, groups
/// `screenAppBarCases`, `zoneCases`, `screenRuleCases`, `modalAreaCases`) and run EVERY
/// row twice: with the reader formula
/// (`screenAppBarIndex`, `screenZoneBoxes` in `media_chrome_rules.dart`) and
/// with a REAL widget (`tester.drag` of the body, positions of the bar, body and
/// background).
///
/// The first attempt at 9.9.0 moved the app bar into the scroll ("the bar travels with the
/// content"); that was rejected: on mobile the app bar stays on top.
/// The "app bar outside the scroll" test here is a deliberate decision, not a whim.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = (json.decode(File('assets/contract/fixtures/media-chrome/media-chrome-cases.json').readAsStringSync()) as Map).cast<String, Object?>();
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

_Json _text(String id, String text, {_Json? visibleIf}) => {
  'id': id,
  'type': 'Text',
  'props': {'content': _literal(text)},
  'visibleIf': ?visibleIf,
};

_Json _barNode(String id, String title, {double? height, _Json? visibleIf, _Json? style}) => {
  'id': id,
  'type': 'AppBar',
  'props': {'title': _literal(title), 'showBack': true},
  'style': {'height': ?height, ...?style},
  'visibleIf': ?visibleIf,
};

_Json _screen(String id, List<_Json> children, {_Json? style, double? gap, String? presentation, Object? placement}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'modalPlacement': ?placement,
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
  'documentId': 'anatomy',
  'name': 'anatomy',
  'initialScreenId': screens.first['screenId'],
  'screens': screens,
});

/// A condition that is not met without data: the node is hidden.
const _Json _never = {'path': 'user.isPremium', 'op': 'isTrue'};

RenderScreenZones _zones(WidgetTester tester) => tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);

Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

void main() {
  group('table: structure', () {
    test('four groups with the expected row counts', () {
      const counts = {'screenAppBarCases': 7, 'zoneCases': 19, 'screenRuleCases': 16, 'modalAreaCases': 3};
      for (final entry in counts.entries) {
        expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
      }
    });
  });

  // ─────────────────────────── screenAppBarCases ───────────────────────────

  group('screenAppBarCases: which child is the app bar zone', () {
    for (final row in _rows('screenAppBarCases')) {
      final types = (row['children']! as List).cast<String>();
      final hidden = [for (final h in (row['hidden'] as List?) ?? const []) h as bool];

      test('formula: ${row['name']}', () {
        expect(screenAppBarIndex(types), row['expect']);
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, 320, 568);
        // Every node has a recognisable caption; `Column` is a column with a caption.
        final children = <_Json>[
          for (var i = 0; i < types.length; i++)
            switch (types[i]) {
              'AppBar' => _barNode('n$i', 'Шапка $i', visibleIf: hidden.length > i && hidden[i] ? _never : null),
              'Column' => {
                'id': 'n$i',
                'type': 'Column',
                'props': const <String, Object?>{},
                'children': [_text('t$i', 'Колонка $i')],
                'visibleIf': hidden.length > i && hidden[i] ? _never : null,
              },
              _ => _text('n$i', 'Текст $i', visibleIf: hidden.length > i && hidden[i] ? _never : null),
            },
        ];
        await pumpDocument(tester, _doc([_screen('s', children)]));
        expect(tester.takeException(), isNull);

        final scroll = find.byType(SingleChildScrollView);
        final zone = row['expect'] as int?;
        for (var i = 0; i < types.length; i++) {
          if (types[i] != 'AppBar') continue;
          final isHidden = hidden.length > i && hidden[i];
          final shown = find.text('Шапка $i');
          if (isHidden) {
            expect(shown, findsNothing, reason: 'an app bar hidden by a condition is not drawn');
            continue;
          }
          expect(shown, findsOneWidget);
          final inBody = find.descendant(of: scroll, matching: shown);
          // The app bar zone is outside the scroll; an app bar not in its place is a body child.
          expect(inBody, zone == i ? findsNothing : findsOneWidget, reason: 'app bar $i');
        }
        // An app bar zone hidden by a condition is empty now, and the next node does not become the bar.
        expect(find.byType(ScreenZones), findsOneWidget);
        final shownBars = types.indexed.where((e) => e.$2 == 'AppBar' && !(hidden.length > e.$1 && hidden[e.$1])).length;
        final zoneNow = row['zoneNow'] as bool? ?? zone != null;
        expect(_zones(tester).childCount, zoneNow ? 2 : 1, reason: 'zoneNow');
        if (!zoneNow && shownBars > 0) {
          expect(find.descendant(of: scroll, matching: find.text('Шапка 1')), findsOneWidget);
        }
      });
    }
  });

  // ───────────────────────────── zoneCases ─────────────────────────────

  group('zoneCases: screen zones', () {
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
      // A row about a hidden AppBar: the bar IS in the document, but is absent right now.
      final hiddenBar = (row['name']! as String).startsWith('an app bar hidden by a condition');

      test('formula: ${row['name']}', () {
        final zones = screenZoneBoxes(
          height: height,
          appBarHeight: hiddenBar ? null : barHeight,
          paddingTop: _num(padding['top']),
          paddingBottom: _num(padding['bottom']),
          gap: gap,
          bodyContentHeight: body,
          firstPull: pull,
          scrollTop: scrollTop,
          shrink: shrink,
        );
        expect(zones.height, _near(_num(expected['height'])));
        final bar = expected['appBar'];
        if (bar == null) {
          expect(zones.appBarTop, isNull);
        } else {
          expect(zones.appBarTop, _near(_num(_obj(bar)['top'])));
          expect(zones.appBarHeight, _near(_num(_obj(bar)['height'])));
        }
        expect(zones.bodyTop, _near(_num(_obj(expected['body'])['top'])));
        expect(zones.bodyHeight, _near(_num(_obj(expected['body'])['height'])));
        expect(zones.contentTop, _near(_num(expected['contentTop'])));
        expect(zones.contentHeight, _near(_num(expected['contentHeight'])));
        expect(zones.maxScroll, _near(_num(expected['maxScroll'])));
        expect(zones.scrollTop, _near(_num(expected['scrollTop'])));
        expect(zones.scrolls, expected['scrolls']);
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, 320, height);
        final pad = {'top': _num(padding['top']), 'bottom': _num(padding['bottom'])};
        final children = <_Json>[
          if (barHeight != null) _barNode('bar', 'Шапка', height: barHeight, visibleIf: hiddenBar ? _never : null),
          if (body != null)
            {
              'id': 'content',
              'type': 'Container',
              'props': {'direction': 'column'},
              'style': {'height': body},
              'children': [_text('mark', 'Початок')],
              if (pull > 0) 'pull': pull,
            },
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
                _screen('layer', children, style: style, gap: gap, presentation: 'modal'),
              ]
            : [_screen('s', children, style: style, gap: gap)];
        await pumpDocument(tester, _doc(screens));
        if (shrink) {
          await tester.tap(find.text('Відкрити'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);

        final zones = _zones(tester);
        final frame = _rectOf(zones);
        final bodyBox = zones.lastChild!;
        final scroll = find.byType(SingleChildScrollView);

        if (scrollTop > 0) {
          // The body scrolls by gesture; the app bar does not move.
          final barBefore = barHeight == null || hiddenBar ? null : tester.getTopLeft(find.text('Шапка'));
          await tester.drag(scroll.last, Offset(0, -scrollTop));
          await tester.pumpAndSettle();
          if (barBefore != null) {
            expect(tester.getTopLeft(find.text('Шапка')), barBefore, reason: 'the app bar is the same at any scrollTop');
          }
        }

        // App bar: its box (not the screen padding) and the zone height.
        if (expected['appBar'] == null) {
          expect(zones.childCount, 1);
        } else {
          final bar = zones.firstChild! as RenderPadding;
          final inner = bar.child!;
          expect(_rectOf(inner).top - frame.top, _near(_num(_obj(expected['appBar'])['top'])));
          expect(inner.size.height, _near(_num(_obj(expected['appBar'])['height'])));
        }
        // Body area: from the bottom edge of the app bar (minus the overlap), not above the screen top.
        final rawTop = _rectOf(bodyBox).top - frame.top;
        final visibleTop = math.max(0.0, rawTop);
        expect(visibleTop, _near(_num(_obj(expected['body'])['top'])));
        expect(rawTop + bodyBox.size.height - visibleTop, _near(_num(_obj(expected['body'])['height'])));
        expect(frame.height, _near(_num(expected['height'])));

        // The first body child and the length of what scrolls.
        if (body != null) {
          expect(tester.getTopLeft(find.text('Початок')).dy - frame.top, _near(_num(expected['contentTop'])));
        }
        // The length of what scrolls: the child of the scroll window (with its padding).
        // Below the screen top the body area is counted from its own edge, above it - from
        // the screen top, so in a row with an overlap larger than the bar the difference is
        // exactly the part of the area that is off screen.
        RenderObject? node = tester.renderObject(find.descendant(of: scroll.last, matching: find.byType(Padding)).first);
        while (node != null && node.parent.runtimeType.toString() != '_RenderSingleChildViewport') {
          node = node.parent;
        }
        final contentHeight = (node! as RenderBox).size.height;
        expect(contentHeight, _near(_num(expected['contentHeight']) + math.max(0.0, -rawTop)));
        final position = tester.state<ScrollableState>(find.descendant(of: scroll.last, matching: find.byType(Scrollable)).first).position;
        expect(position.maxScrollExtent, _near(_num(expected['maxScroll'])));
        expect(position.pixels, _near(_num(expected['scrollTop'])));
      });
    }
  });

  // ─────────────────────────── behaviour: background, clipping, taps ───────────────────────────

  group('app bar, body and background with a real gesture', () {
    _Json tall(String id) => {
      'id': id,
      'type': 'Container',
      'props': {'direction': 'column'},
      'style': {'height': 1000},
      'children': [_text('mark', 'Початок')],
    };

    testWidgets('the root background does not scroll: the screen DecoratedBox stays, the content moves', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('s', [_barNode('bar', 'Шапка', height: 56), tall('content')], style: {'background': {'kind': 'color', 'color': 'surface'}}),
        ]),
      );
      final background = find.ancestor(of: find.byType(ScreenZones), matching: find.byType(DecoratedBox)).first;
      final before = tester.getRect(background);
      final markBefore = tester.getTopLeft(find.text('Початок')).dy;
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(background), before, reason: 'the background is under all zones and does not scroll');
      expect(tester.getTopLeft(find.text('Початок')).dy, markBefore - 300);
      expect(before.size, const Size(320, 568), reason: 'the background spans the full screen height, under the app bar too');
      // The background is an ancestor of the zone layout, not one of its children.
      expect(find.descendant(of: background, matching: find.byType(ScreenZones)), findsOneWidget);
    });

    testWidgets('an app bar hidden by a condition returns the top padding to the body', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen('s', [_barNode('bar', 'Шапка', height: 56, visibleIf: _never), tall('content')], style: {'padding': {'top': 16, 'bottom': 16}}),
        ]),
      );
      expect(find.text('Шапка'), findsNothing);
      expect(tester.getTopLeft(find.text('Початок')).dy, 16);
    });

    testWidgets('app bar outside the scroll: a tap on it does not reach the body, a tap in the overlap strip goes to the body', (tester) async {
      _view(tester, 320, 568);
      await pumpDocument(
        tester,
        _doc([
          _screen(
            's',
            [
              _barNode('bar', 'Шапка', height: 56),
              {
                'id': 'content',
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'height': 200},
                'pull': 40,
                'children': [
                  {
                    'id': 'tap',
                    'type': 'Button',
                    'props': {
                      'label': _literal('Тисни'),
                      'variant': 'primary',
                      'action': {'type': 'navigate', 'params': {'screenId': 'next'}},
                    },
                  },
                ],
              },
            ],
            gap: 12,
          ),
          _screen('next', [_text('arrived', 'Прийшли')]),
        ]),
      );
      // Overlap 28: the button lies over the bottom edge of the app bar, the body is on top.
      final tapBox = tester.getRect(find.text('Тисни'));
      expect(tapBox.top, lessThan(56), reason: 'pulled by 40 over a gap of 12: the button top is above the bar edge');
      await tester.tapAt(Offset(tapBox.center.dx, 50));
      await tester.pumpAndSettle();
      expect(find.text('Прийшли'), findsOneWidget, reason: 'the overlap strip belongs to the body');
    });
  });

  // ─────────────────────────────── screenRuleCases ───────────────────────────────

  group('screenRuleCases: artifact rows', () {
    final screen = _obj(_obj(_obj(_schema['x-style'])['layout'])['screen']);

    for (final row in _rows('screenRuleCases')) {
      test('${row['rule']}: ${row['name']}', () {
        Object? at = screen;
        for (final key in (row['rule']! as String).split('.')) {
          at = _obj(at)[key];
        }
        expect(at, row['expect']);
      });
    }

    test('policy and feature are named: appBarScroll, modalOverflow, appBarFixed', () {
      final compatibility = _obj(_schema['x-compatibility']);
      final policy = _obj(compatibility['policy']);
      expect(kMediaChromePolicy['appBarScroll'], policy['appBarScroll']);
      expect(kMediaChromePolicy['modalOverflow'], policy['modalOverflow']);
      expect(_obj(compatibility['features'])['appBarFixed'], '9.9.0');
      expect(_obj(compatibility['features']).containsKey('appBarScrollsWithContent'), isFalse);
    });
  });

  // ─────────────────────────────── modalAreaCases ───────────────────────────────

  group('modalAreaCases: a window in the area given by the host', () {
    for (final row in _rows('modalAreaCases')) {
      final frame = _obj(row['frame']);
      final insets = _obj(row['insets']);
      final area = _obj(row['area']);
      final expected = _obj(row['expect']);
      final margin = _num(row['margin']);
      final contentHeight = _num(row['contentHeight']);

      test('formula: ${row['name']}', () {
        final box = modalBoxOf(
          placement: 'center',
          viewportWidth: _num(area['width']),
          viewportHeight: _num(area['height']),
          contentHeight: contentHeight,
          margin: margin,
        );
        expect(_num(area['x']) + box.x, _near(_num(expected['x'])));
        expect(_num(area['y']) + box.y, _near(_num(expected['y'])));
        expect(box.width, _near(_num(expected['width'])));
        expect(box.height, _near(_num(expected['height'])));
        expect(_num(area['y']) + box.y + box.height / 2, _near(_num(expected['centerY'])));
      });

      testWidgets('real widget: ${row['name']}', (tester) async {
        _view(tester, _num(frame['width']), _num(frame['height']));
        final doc = _doc([
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
          _screen(
            'layer',
            [
              {
                'id': 'content',
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'height': contentHeight},
                'children': const <Object?>[],
              },
            ],
            presentation: 'modal',
            placement: 'center',
          ),
        ]);
        // The host puts the reader in the area between bars (like SafeArea) and draws the bars itself.
        await tester.pumpWidget(
          MaterialApp(
            home: Padding(
              padding: EdgeInsets.only(top: _num(insets['top']), bottom: _num(insets['bottom'])),
              child: Material(child: renderDocument(doc, theme: RenderTheme.fallback(), data: const {})),
            ),
          ),
        );
        await tester.tap(find.text('Відкрити'));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(kModalLayerKey));
        expect(rect.left, _near(_num(expected['x'])));
        expect(rect.top, _near(_num(expected['y'])));
        expect(rect.width, _near(_num(expected['width'])));
        expect(rect.height, _near(_num(expected['height'])));
        expect(rect.center.dy, _near(_num(expected['centerY'])));
      });
    }
  });
}
