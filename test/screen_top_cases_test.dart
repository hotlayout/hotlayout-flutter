/// THE TOP OF THE SCREEN (schema 9.19.0): the body under the app bar (`Screen.props.bodyTop`) and the top
/// safe inset the reader adds.
///
/// Shared tables of `media-chrome/media-chrome-cases.json`, six new groups and the inset values; every row
/// of them runs, most of them TWICE -- through the reader's formula and through a REAL widget:
///
///  1. `bodyTopCases` (7) -- the word of the field as the reader reads it;
///  2. `topZoneCases` (11) -- who owns the app bar zone, and whether the body starts at the top edge;
///  3. `screenTopZoneCases` (22) -- the zones in screen coordinates from the physical top;
///  4. `screenTopPressCases` (25) -- which zone takes a press at a point: asked of the real hit test;
///  5. `screenTopRuleCases` (27) -- the data of the artifact blocks `bodyTop` and `safeTop`;
///  6. `screenTopDocumentCases` (7) -- a document with the field is read, an unknown word is no field;
///  7. `safeTopValueCases` (10) -- what the reader makes of the inset the host gives.
///
/// The model is the builder's `scripts/screen-top-cases.test.tsx`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/screen_top_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/width_class.dart';
import 'package:hotlayout_flutter/src/render/modal_layer.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/media-chrome/media-chrome-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();
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

_Json _bar(String id, double height, {_Json? visibleIf}) => {
  'id': id,
  'type': 'AppBar',
  'props': {'title': _literal('Bar'), 'showBack': false},
  'style': {'height': height},
  'visibleIf': ?visibleIf,
};

/// A block of the given height. The schema's largest height is 1200, so a taller block is a column of
/// blocks that add up to it (the label stands in the first).
_Json _block(String id, double height, {String? pin, double pull = 0, bool pressable = false}) {
  const largest = 1000.0;
  final label = _text('$id-text', id == 'content' ? 'Початок' : id);
  _Json tall(String partId, double part, List<_Json> children) => {
    'id': partId,
    'type': 'Container',
    'props': {'direction': 'column'},
    'style': {'height': part},
    'children': children,
  };
  final children = <_Json>[];
  if (height <= largest) {
    children.add(label);
  } else {
    var rest = height;
    for (var index = 0; rest > 0; index += 1) {
      final part = math.min(rest, largest);
      children.add(tall('$id-part$index', part, [if (index == 0) label]));
      rest -= part;
    }
  }
  return {
    'id': id,
    'type': 'Container',
    'props': {
      'direction': 'column',
      if (pressable) 'action': {'type': 'share'},
    },
    if (height <= largest) 'style': {'height': height},
    'children': children,
    'pin': ?pin,
    if (pull > 0) 'pull': pull,
  };
}

_Json _navItem(String id, String label) => {
  'id': id,
  'type': 'NavItem',
  'props': {
    'icon': 'house',
    'label': _literal(label),
    'action': {'type': 'navigate.section', 'params': {'screenId': id}},
  },
};

_Json _screen(String id, List<_Json> children, {_Json? props, _Json? style, double? gap, String? presentation}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'root': {
    'id': '$id-root',
    'type': 'Screen',
    'props': {'gap': gap ?? 'none', ...?props},
    'style': ?style,
    'children': children,
  },
};

UiDocument _doc(List<_Json> screens) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'screen-top',
  'name': 'screen-top',
  'initialScreenId': screens.first['screenId'],
  'screens': screens,
});

RenderScreenZones _zones(WidgetTester tester) => tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);

Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

/// The children of the zone layout in the order the reader keeps them: bar, body, pinned, low.
({RenderBox? bar, RenderBox body, RenderBox? pinned, RenderBox? low}) _children(RenderScreenZones zones, {required bool bar, required bool pinned, required bool low}) {
  RenderBox? next = zones.firstChild;
  RenderBox? take(bool present) {
    if (!present) return null;
    final box = next!;
    next = zones.childAfter(box);
    return box;
  }

  final barBox = take(bar);
  final body = take(true)!;
  final pinnedBox = take(pinned);
  final lowBox = take(low);
  return (bar: barBox, body: body, pinned: pinnedBox, low: lowBox);
}

/// The height of a navigation bar of three items in the built-in theme, without the safe inset.
const double _realNavHeight = 61;

/// A zone result in the shape the table writes it.
_Json _shape(ScreenTopBoxes boxes) {
  final zones = boxes.zones;
  final bottom = zones.bottom;
  final bar = boxes.appBar;
  return {
    'height': zones.height,
    'appBar': bar == null ? null : {'top': bar.top, 'height': bar.height, 'contentTop': bar.contentTop},
    'body': {'top': zones.bodyTop, 'height': zones.bodyHeight},
    'contentTop': zones.contentTop,
    'contentHeight': zones.contentHeight,
    'maxScroll': zones.maxScroll,
    'scrollTop': zones.scrollTop,
    'bottom': bottom == null
        ? null
        : {
            'top': bottom.top,
            'height': bottom.height,
            'pinned': bottom.pinnedTop == null ? null : {'top': bottom.pinnedTop, 'height': bottom.pinnedHeight},
            'navBar': bottom.navTop == null
                ? null
                : {'top': bottom.navTop, 'height': bottom.navHeight, 'contentHeight': bottom.navContentHeight},
            'safeBottom': bottom.safeBottom,
          },
  };
}

void main() {
  test('the groups have the promised number of rows', () {
    expect(_rows('bodyTopCases'), hasLength(7));
    expect(_rows('topZoneCases'), hasLength(11));
    expect(_rows('screenTopZoneCases'), hasLength(22));
    expect(_rows('screenTopPressCases'), hasLength(25));
    expect(_rows('screenTopRuleCases'), hasLength(27));
    expect(_rows('screenTopDocumentCases'), hasLength(7));
    expect(_rows('safeTopValueCases'), hasLength(10));
  });

  // ───────────────────────────── bodyTopCases ─────────────────────────────

  group('bodyTopCases: the word of the field', () {
    for (final row in _rows('bodyTopCases')) {
      test(row['name']! as String, () {
        final value = row['value'];
        final word = bodyTopOf(value);
        expect(word?.wire, row['expect']);
        // The same through a parsed screen root: the field lives in the root's props.
        final root = UiNode.parse({
          'id': 'root',
          'type': 'Screen',
          'props': {if (row.containsKey('value')) 'bodyTop': value},
          'children': <Object?>[],
        }) as ScreenNode;
        expect(root.bodyTop?.wire, row['expect']);
      });
    }
  });

  // ───────────────────────────── topZoneCases ─────────────────────────────

  group('topZoneCases: who owns the app bar zone', () {
    for (final row in _rows('topZoneCases')) {
      test(row['name']! as String, () {
        final types = (row['children']! as List<Object?>).cast<String>();
        final hidden = {for (final index in (row['hidden'] as List<Object?>? ?? const [])) index! as int};
        final owner = topZoneOwnerIn(
          [for (final type in types) (type: type, pin: false)],
          WidthClass.values.firstWhere((value) => value.name == row['widthClass']),
          navPlacement: navWidePlacementOf(row['widePlacement']),
          hidden: hidden,
        );
        expect(owner.name, row['owner']);
        expect(bodyStartsAtScreenTop(BodyTop.screenTop, owner), row['atScreenTop']);
        expect(bodyStartsAtScreenTop(null, owner), isFalse, reason: 'without the field the body never starts at the top');
      });
    }
  });

  // ──────────────────────────── screenTopZoneCases ────────────────────────────

  group('screenTopZoneCases: zones from the physical top', () {
    for (final row in _rows('screenTopZoneCases')) {
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
      final safeTop = _num(row['safeTop'] ?? 0);

      test('formula: ${row['name']}', () {
        final boxes = screenTopBoxesOf(
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
          bodyTop: bodyTopOf(row['bodyTop']),
          safeTop: row['safeTop'],
        );
        final zones = boxes.zones;
        expect(zones.height, _near(_num(expected['height'])));
        final bar = expected['appBar'];
        if (bar == null) {
          expect(boxes.appBar, isNull);
        } else {
          expect(boxes.appBar!.top, _near(_num(_obj(bar)['top'])));
          expect(boxes.appBar!.height, _near(_num(_obj(bar)['height'])));
          expect(boxes.appBar!.contentTop, _near(_num(_obj(bar)['contentTop'])));
        }
        expect(zones.bodyTop, _near(_num(_obj(expected['body'])['top'])));
        expect(zones.bodyHeight, _near(_num(_obj(expected['body'])['height'])));
        expect(zones.contentTop, _near(_num(expected['contentTop'])));
        expect(zones.contentHeight, _near(_num(expected['contentHeight'])));
        expect(zones.maxScroll, _near(_num(expected['maxScroll'])));
        expect(zones.scrollTop, _near(_num(expected['scrollTop'])));
        expect(zones.scrolls, expected['scrolls']);
        expect(boxes.bodyAtScreenTop, expected['bodyAtScreenTop']);
        expect(boxes.safeTop, _near(_num(expected['safeTop'])));
        final bottom = expected['bottom'];
        if (bottom == null) {
          expect(zones.bottom, isNull);
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
        // The width is in the name of the row where it matters (`768 × 1024`); the zones do not read it.
        final named = RegExp(r'(\d+) × \d+').firstMatch(row['name']! as String);
        _view(tester, named == null ? 393 : double.parse(named.group(1)!), height);
        final hasBar = barHeight != null;
        final hasPinned = pinnedHeight != null;
        final hasNav = navHeight != null;
        // The table says 57 for the height of a navigation bar; the real bar of the built-in theme is
        // 61 (as in the bottom zone table). The rows with a bar are checked against the formula that
        // the table has already vouched for, fed with the real height.
        final expected = hasNav
            ? _shape(
                screenTopBoxesOf(
                  height: height,
                  appBarHeight: barHeight,
                  paddingTop: _num(padding['top']),
                  paddingBottom: _num(padding['bottom']),
                  gap: gap,
                  bodyContentHeight: body,
                  firstPull: pull,
                  scrollTop: scrollTop,
                  pinnedHeight: pinnedHeight,
                  navBarHeight: _realNavHeight,
                  safeBottom: safeBottom,
                  bodyTop: bodyTopOf(row['bodyTop']),
                  safeTop: row['safeTop'],
                ),
              )
            : _obj(row['expect']);
        final children = <_Json>[
          if (hasBar) _bar('bar', barHeight),
          if (body != null) _block('content', body, pull: pull),
          if (hasPinned) _block('Прибитий', pinnedHeight, pin: 'bottom'),
          if (hasNav) {
            'id': 'nav',
            'type': 'NavBar',
            'props': <String, Object?>{},
            'children': [_navItem('a', 'Home'), _navItem('b', 'Two'), _navItem('c', 'Three')],
          },
        ];
        final style = {'padding': {'top': _num(padding['top']), 'bottom': _num(padding['bottom'])}};
        final props = {if (row['bodyTop'] != null) 'bodyTop': row['bodyTop']};
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
                _screen('layer', children, props: props, style: style, gap: gap, presentation: 'modal'),
              ]
            : [_screen('s', children, props: props, style: style, gap: gap)];
        await pumpDocument(tester, _doc(screens), safeTop: safeTop, safeBottom: safeBottom);
        if (shrink) {
          await tester.tap(find.text('Відкрити'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);

        final zones = _zones(tester);
        final frame = _rectOf(zones);
        final parts = _children(zones, bar: hasBar, pinned: hasPinned, low: hasPinned || hasNav);
        final scroll = find.byType(SingleChildScrollView);

        if (scrollTop > 0) {
          final before = hasBar ? tester.getTopLeft(find.text('Bar')) : null;
          await tester.drag(scroll.last, Offset(0, -scrollTop));
          await tester.pumpAndSettle();
          if (before != null) expect(tester.getTopLeft(find.text('Bar')), before, reason: 'the app bar stands');
        }

        expect(frame.height, _near(_num(expected['height'])), reason: 'height of the layout');
        if (expected['appBar'] != null) {
          final box = (parts.bar! as RenderPadding).child!;
          final want = _obj(expected['appBar']);
          expect(_rectOf(box).top - frame.top, _near(_num(want['top'])), reason: 'the bar box top');
          expect(box.size.height, _near(_num(want['height'])), reason: 'the bar box is taller by the inset');
        } else {
          expect(parts.bar, isNull);
        }
        final bodyRect = _rectOf(parts.body);
        final visibleTop = math.max(0.0, bodyRect.top - frame.top);
        expect(visibleTop, _near(_num(_obj(expected['body'])['top'])), reason: 'the body area top');
        expect(bodyRect.top - frame.top + parts.body.size.height - visibleTop, _near(_num(_obj(expected['body'])['height'])), reason: 'the body area height');
        if (body != null) {
          expect(tester.getTopLeft(find.text('Початок')).dy - frame.top, _near(_num(expected['contentTop'])), reason: 'the first child');
        }
        final position = tester.state<ScrollableState>(find.descendant(of: scroll.last, matching: find.byType(Scrollable)).first).position;
        expect(position.maxScrollExtent, _near(_num(expected['maxScroll'])), reason: 'maxScroll');
        expect(position.pixels, _near(_num(expected['scrollTop'])), reason: 'scrollTop');
        final bottom = expected['bottom'];
        if (bottom != null && !hasNav) {
          final want = _obj(bottom);
          expect(_rectOf(parts.pinned!).top - frame.top, _near(_num(_obj(want['pinned'])['top'])), reason: 'the pinned block');
          expect(_rectOf(parts.low!).top - frame.top + parts.low!.size.height - (_rectOf(parts.pinned!).top - frame.top), _near(_num(want['height'])), reason: 'the zone height');
        }
        if (hasNav) {
          final want = _obj(_obj(bottom)['navBar']);
          expect(_rectOf(parts.low!).top - frame.top, _near(_num(want['top'])), reason: 'the navigation bar');
          expect(parts.low!.size.height, _near(_num(want['height'])), reason: 'the navigation bar with the inset');
        }
      });
    }
  });

  // ──────────────────────────── screenTopPressCases ────────────────────────────

  group('screenTopPressCases: who takes a press', () {
    for (final row in _rows('screenTopPressCases')) {
      final screen = _obj(row['screen']);
      final point = _obj(row['point']);
      final width = _num(screen['width']);
      final height = _num(screen['height']);
      final rtl = screen['direction'] == 'rtl';
      final side = _obj(screen['sidePadding']);
      final barHeight = screen['appBarHeight'] == null ? null : _num(screen['appBarHeight']);
      final padding = _obj(screen['padding']);
      final bottom = screen['bottom'] == null ? <String, Object?>{} : _obj(screen['bottom']);
      final pinnedHeight = bottom['pinnedHeight'] == null ? null : _num(bottom['pinnedHeight']);
      final pull = _num(screen['firstPull'] ?? 0);
      final gap = _num(screen['gap']);
      final scrollTop = _num(screen['scrollTop'] ?? 0);

      test('formula: ${row['name']}', () {
        final boxes = screenTopBoxesOf(
          height: height,
          appBarHeight: barHeight,
          paddingTop: _num(padding['top']),
          paddingBottom: _num(padding['bottom']),
          gap: gap,
          bodyContentHeight: _num(screen['bodyContentHeight']),
          firstPull: pull,
          scrollTop: scrollTop,
          pinnedHeight: pinnedHeight,
          bodyTop: bodyTopOf(screen['bodyTop']),
          safeTop: screen['safeTop'],
        );
        final start = _num(side['start']);
        final end = _num(side['end']);
        // The box of the bar stands inside the side padding: the start padding is on the left in LTR.
        final left = rtl ? end : start;
        final zone = screenPressZoneAt(
          boxes,
          y: _num(point['y']),
          x: _num(point['x']),
          barLeft: left,
          barWidth: width - start - end,
        );
        expect(zone.name, row['expect']);
      });

      testWidgets('real hit test: ${row['name']}', (tester) async {
        _view(tester, width, height);
        final children = <_Json>[
          if (barHeight != null) _bar('bar', barHeight),
          _block('content', _num(screen['bodyContentHeight']), pull: pull, pressable: true),
          if (pinnedHeight != null) _block('pin', pinnedHeight, pin: 'bottom', pressable: true),
        ];
        final style = {
          'padding': {
            'top': _num(padding['top']),
            'bottom': _num(padding['bottom']),
            'start': _num(side['start']),
            'end': _num(side['end']),
          },
        };
        final props = {if (screen['bodyTop'] != null) 'bodyTop': screen['bodyTop']};
        final ran = <String>[];
        await pumpDocument(
          tester,
          _doc([_screen('s', children, props: props, style: style, gap: gap)]),
          locale: rtl ? 'ar' : null,
          safeTop: _num(screen['safeTop'] ?? 0),
          onAction: (action, nodeId) => ran.add(nodeId),
        );
        expect(tester.takeException(), isNull);
        if (scrollTop > 0) {
          await tester.drag(find.byType(SingleChildScrollView).last, Offset(0, -scrollTop));
          await tester.pumpAndSettle();
        }

        final zones = _zones(tester);
        final parts = _children(zones, bar: barHeight != null, pinned: pinnedHeight != null, low: pinnedHeight != null);
        final at = Offset(_num(point['x']), _num(point['y']));
        final result = HitTestResult();
        tester.binding.hitTestInView(result, at, tester.view.viewId);
        bool hit(RenderBox? zone) {
          if (zone == null) return false;
          for (final entry in result.path) {
            final target = entry.target;
            if (target is! RenderObject) continue;
            for (RenderObject? node = target; node != null; node = node.parent) {
              if (identical(node, zone)) return true;
            }
          }
          return false;
        }

        final zone = hit(parts.low) || hit(parts.pinned)
            ? 'bottom'
            : hit(parts.bar)
            ? 'appBar'
            : hit(parts.body)
            ? 'body'
            : 'none';
        expect(zone, row['expect'], reason: 'the zone the hit test lands in');

        // A real tap, too: the body under the bar and the beside-the-box padding is the only place
        // where the pressable body gets it, and the zone it lands in is the answer.
        await tester.tapAt(at);
        await tester.pump();
        final expectedRan = switch (row['expect']) {
          'body' => ['content'],
          'bottom' => ['pin'],
          _ => <String>[],
        };
        // The pressable card has no point where nothing is drawn: a point of the body without the card
        // (the root's padding) lands in the body zone, and runs nothing.
        if (zone != 'body') expect(ran, expectedRan);
      });
    }
  });

  // ──────────────────────────── screenTopRuleCases ────────────────────────────

  group('screenTopRuleCases: the data of the artifact', () {
    final layout = _obj(_obj(_schema['x-style'])['layout']);
    for (final row in _rows('screenTopRuleCases')) {
      test(row['name']! as String, () {
        Object? at = layout;
        for (final key in (row['rule']! as String).split('.')) {
          at = (at! as Map)[key];
        }
        expect(at, row['expect'], reason: row['rule'] as String?);
      });
    }

    test('the blocks the new ones replace stay as they were: the reader reads them through the new keys', () {
      final replaces = (_obj(layout['bodyTop'])['replaces']! as List<Object?>).cast<String>();
      expect(replaces, contains('x-style.layout.screen.body.clip'));
      expect(_obj(layout['safeTop'])['replaces'], ['x-statusBar.safeArea', 'x-style.layout.wideNav.ownBar.safeAreaTop']);
    });
  });

  // ─────────────────────────── screenTopDocumentCases ───────────────────────────

  group('screenTopDocumentCases: a document with the field is read', () {
    for (final row in _rows('screenTopDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final props = _obj(row['props']);
        final bar = row['appBar'] != false;
        final root = {
          'id': 'root',
          'type': 'Screen',
          'props': props,
          if (row['propsOn'] != null) 'propsOn': row['propsOn'],
          'children': [if (bar) _bar('bar', 48), _text('t', 'Text')],
        };
        // The field does not depend on the width class: `propsOn` does not name it.
        for (final widthClass in WidthClass.values) {
          final parsed = UiNode.parse(root, widthClass: widthClass) as ScreenNode;
          expect(parsed.bodyTop, bodyTopOf(props['bodyTop']), reason: '${widthClass.name}: the base value');
        }
        await pumpDocument(tester, _doc([_screen('s', [if (bar) _bar('bar', 48), _text('t', 'Text')], props: props)]));
        expect(tester.takeException(), isNull, reason: 'a reader draws what arrived, whatever the schema says');
        expect(find.text('Text'), findsOneWidget);
      });
    }
  });

  // ───────────────────────────── safeTopValueCases ─────────────────────────────

  group('safeTopValueCases: the inset the host gives', () {
    for (final row in _rows('safeTopValueCases')) {
      test(row['name']! as String, () {
        expect(safeTopOf(row['safeTop'], _num(row['height'])), _near(_num(row['effective'])));
      });
    }

    test('NaN and infinity are zero (JSON cannot carry them)', () {
      expect(safeTopOf(double.nan, 852), 0);
      expect(safeTopOf(double.infinity, 852), 0);
      expect(safeTopOf(double.negativeInfinity, 852), 0);
    });

    testWidgets('a hostile inset from the host does not break the screen', (tester) async {
      _view(tester, 393, 852);
      await pumpDocument(
        tester,
        _doc([_screen('s', [_bar('bar', 48), _text('t', 'Text')])]),
        safeTop: double.infinity,
      );
      expect(tester.takeException(), isNull);
      expect(_zones(tester).size.height, 852);
    });
  });

  group('the reader of a host that accounted for the inset itself', () {
    testWidgets('no inset and no field: the screen is as it was before 9.19.0', (tester) async {
      _view(tester, 393, 852);
      await pumpDocument(tester, _doc([_screen('s', [_bar('bar', 48), _block('content', 100)], style: {'padding': {'top': 16, 'bottom': 0}})]));
      final zones = _zones(tester);
      final parts = _children(zones, bar: true, pinned: false, low: false);
      expect((parts.bar! as RenderPadding).child!.size.height, 48);
      expect(_rectOf(parts.body).top, 64);
    });
  });

  group('a modal layer and the top inset (safeTop.modal)', () {
    UiDocument layered({Object? placement, double contentHeight = 400}) => UiDocument.fromJson({
      'schemaVersion': UiDocument.supportedSchemaVersion,
      'documentId': 'layer',
      'name': 'layer',
      'initialScreenId': 'page',
      'screens': [
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
        {
          ..._screen('layer', [_bar('bar', 48), _block('content', contentHeight)], presentation: 'modal'),
          'modalPlacement': ?placement,
        },
      ],
    });

    testWidgets('a sheet is no taller than the area below the inset; the bar in it has no inset', (tester) async {
      _view(tester, 393, 852);
      await pumpDocument(tester, layered(contentHeight: 1100), safeTop: 47);
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();
      final layer = tester.getRect(find.byKey(kModalLayerKey));
      expect(layer.top, greaterThanOrEqualTo(47), reason: 'the sheet does not go under the status bar');
      expect(layer.bottom, 852);
      final zones = _zones(tester);
      expect((_children(zones, bar: true, pinned: false, low: false).bar! as RenderPadding).child!.size.height, 48,
          reason: 'inside a layer there is no inset');
    });

    testWidgets('a window is centred in the area below the inset', (tester) async {
      _view(tester, 393, 852);
      await pumpDocument(tester, layered(placement: 'center', contentHeight: 200), safeTop: 60);
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();
      final layer = tester.getRect(find.byKey(kModalLayerKey));
      expect(layer.center.dy, closeTo(60 + (852 - 60) / 2, 0.5));
    });
  });
}
