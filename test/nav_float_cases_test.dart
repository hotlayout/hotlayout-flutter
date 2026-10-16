/// THE FLOATING BAR AND THE DOT ON AN ITEM (schema 9.22.0, `NavBar.float`, `NavItem.badgeWhen`).
///
/// The shared table (`assets/contract/fixtures/bottom-zone/bottom-zone-cases.json`, the 9.22 groups) runs row by
/// row, by the reader's formula and by a REAL widget:
///
///  1. `floatZoneCases` -- the geometry of a screen whose bottom zone lies over the body: the body area reaches the
///     bottom, the content gets the height of the zone at its end, the scroll limit is the one it was, the safe inset
///     is outside the box of the bar;
///  2. `floatPlaceCases` -- where the field is read at all;
///  3. `navBadgeCases` -- when the dot stands;
///  4. `navBadgeBoxCases` -- where the dot stands on the glyph, in both directions of writing;
///  5. `nav922RuleCases` -- the rules as data: the artifact and the code mirror.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/wide_chrome_rules.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';
import 'package:hotlayout_flutter/src/render/widgets/nav_bar.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

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

_Json _barNode(String id, double height) => {
  'id': id,
  'type': 'AppBar',
  'props': {'title': _literal(id), 'showBack': false},
  'style': {'height': height},
};

_Json _navItem(String id, String label, {_Json props = const {}}) => {
  'id': id,
  'type': 'NavItem',
  'props': {
    'icon': 'house',
    'label': _literal(label),
    'action': {'type': 'navigate.section', 'params': {'screenId': id}},
    ...props,
  },
};

_Json _navBar(List<_Json> items, {Object? float, _Json? style}) => {
  'id': 'nav',
  'type': 'NavBar',
  'props': <String, Object?>{'float': ?float},
  'style': ?style,
  'children': items,
};

_Json _block(String id, double height) => {
  'id': id,
  'type': 'Container',
  'props': {'direction': 'column'},
  'style': {'height': height},
  'children': [_text('$id-text', id)],
  'pin': 'bottom',
};

UiDocument _doc(List<_Json> children, {_Json? style, double gap = 0}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'nav-float',
  'name': 'nav-float',
  'initialScreenId': 's',
  'screens': [
    {
      'screenId': 's',
      'name': 's',
      'root': {
        'id': 's-root',
        'type': 'Screen',
        'props': {'gap': gap},
        'style': ?style,
        'children': children,
      },
    },
  ],
});

RenderScreenZones _zones(WidgetTester tester) => tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
Rect _rectOf(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;

void main() {
  test('the groups have the promised rows', () {
    expect(_rows('floatZoneCases'), hasLength(9));
    expect(_rows('floatPlaceCases'), hasLength(7));
    expect(_rows('navBadgeCases'), hasLength(9));
    expect(_rows('navBadgeBoxCases'), hasLength(4));
    expect(_rows('nav922RuleCases'), hasLength(12));
  });

  group('floatZoneCases: the zone over the body', () {
    for (final row in _rows('floatZoneCases')) {
      final expected = _obj(row['expect']);
      final padding = _obj(row['padding']);
      final height = _num(row['height']);
      final barHeight = row['appBarHeight'] == null ? null : _num(row['appBarHeight']);
      final body = _num(row['bodyContentHeight']);
      final pull = _num(row['firstPull'] ?? 0);
      final gap = _num(row['gap']);
      final scrollTop = _num(row['scrollTop'] ?? 0);
      final input = _obj(row['bottom']);
      final pinnedHeight = input['pinnedHeight'] == null ? null : _num(input['pinnedHeight']);
      final navHeight = input['navBarHeight'] == null ? null : _num(input['navBarHeight']);
      final safeBottom = _num(input['safeBottom'] ?? 0);
      final floatField = row['navFloat'] == true;

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
          pinnedHeight: pinnedHeight,
          navBarHeight: navHeight,
          safeBottom: safeBottom,
          navFloat: floatField,
        );
        expect(zones.height, _near(_num(expected['height'])));
        expect(zones.bodyTop, _near(_num(_obj(expected['body'])['top'])));
        expect(zones.bodyHeight, _near(_num(_obj(expected['body'])['height'])));
        expect(zones.contentTop, _near(_num(expected['contentTop'])));
        expect(zones.contentHeight, _near(_num(expected['contentHeight'])));
        expect(zones.maxScroll, _near(_num(expected['maxScroll'])));
        expect(zones.scrollTop, _near(_num(expected['scrollTop'])));
        expect(zones.scrolls, expected['scrolls']);
        expect(zones.float, expected['float']);
        final want = _obj(expected['bottom']);
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
        final content = <_Json>[
          if (barHeight != null) _barNode('bar', barHeight),
          {
            'id': 'content',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'height': body},
            'children': [_text('mark', 'Початок')],
            if (pull > 0) 'pull': pull,
          },
          if (pinnedHeight != null) _block('Прибитий', pinnedHeight),
          if (navHeight != null)
            _navBar([_navItem('a', 'Home'), _navItem('b', 'Two'), _navItem('c', 'Three')], float: floatField ? true : null),
        ];
        await pumpDocument(
          tester,
          _doc(content, style: {'padding': {'top': _num(padding['top']), 'bottom': _num(padding['bottom'])}}, gap: gap),
          safeBottom: safeBottom,
        );
        expect(tester.takeException(), isNull);

        final zones = _zones(tester);
        final frame = _rectOf(zones);
        final scroll = find.byType(SingleChildScrollView);
        if (scrollTop > 0) {
          await tester.drag(scroll.last, Offset(0, -scrollTop));
          await tester.pumpAndSettle();
        }

        final bodyRect = _rectOf(barHeight == null ? zones.firstChild! : zones.childAfter(zones.firstChild!)!);
        expect(math.max(0.0, bodyRect.top - frame.top), _near(_num(_obj(expected['body'])['top'])), reason: 'top of the body area');
        expect(bodyRect.height, _near(_num(_obj(expected['body'])['height'])), reason: 'height of the body area');

        final want = _obj(expected['bottom']);
        // The zone is the last children of the layout; its union is the zone.
        var zoneRect = _rectOf(zones.lastChild!);
        for (var child = zones.lastChild; child != null && child != (barHeight == null ? zones.firstChild : zones.childAfter(zones.firstChild!)); child = zones.childBefore(child)) {
          zoneRect = zoneRect.expandToInclude(_rectOf(child));
        }
        expect(zoneRect.top - frame.top, _near(_num(want['top'])), reason: 'top of the zone');
        expect(zoneRect.height, _near(_num(want['height'])), reason: 'height of the zone');
        final pinned = want['pinned'];
        if (pinned != null) {
          expect(tester.getTopLeft(find.text('Прибитий')).dy - frame.top, _near(_num(_obj(pinned)['top'])), reason: 'top of the pinned block');
        }
        final nav = want['navBar'];
        if (nav != null) {
          final bar = find.ancestor(of: find.text('Home'), matching: find.byWidgetPredicate((w) => w is Container && w.child is Material)).first;
          final navRect = tester.getRect(bar);
          expect(navRect.top - frame.top, _near(_num(_obj(nav)['top'])), reason: 'top of the bar');
          expect(navRect.height, _near(_num(_obj(nav)['height'])), reason: 'the box of the bar does not take the inset');
          expect(frame.bottom - navRect.bottom, _near(floatField ? safeBottom : 0), reason: 'the inset is under the box of the bar');
        }

        expect(tester.getTopLeft(find.text('Початок')).dy - frame.top, _near(_num(expected['contentTop'])));
        final position = tester.state<ScrollableState>(find.descendant(of: scroll.last, matching: find.byType(Scrollable)).first).position;
        expect(position.maxScrollExtent, _near(_num(expected['maxScroll'])));
        expect(position.pixels, _near(_num(expected['scrollTop'])));
        RenderObject? node = tester.renderObject(find.descendant(of: scroll.last, matching: find.byType(Padding)).first);
        while (node != null && node.parent.runtimeType.toString() != '_RenderSingleChildViewport') {
          node = node.parent;
        }
        final rawTop = bodyRect.top - frame.top;
        expect((node! as RenderBox).size.height, _near(_num(expected['contentHeight']) + math.max(0.0, -rawTop)));
      });
    }
  });

  group('floatPlaceCases: where the field is read', () {
    const places = {'bottom': NavBarPlace.bottom, 'appBar': NavBarPlace.appBar, 'top': NavBarPlace.top};
    for (final row in _rows('floatPlaceCases')) {
      final props = _obj(row['props']);
      test('formula and parsing: ${row['name']}', () {
        final place = places[row['navPlace']];
        expect(navFloatsIn(place, navFloatOf(props['float'])), row['expect']);
        final node = UiNode.parse({'id': 'nav', 'type': 'NavBar', 'props': props, 'children': <Object?>[]});
        expect((node as NavBarNode).float, props['float'] == true);
      });
    }

    testWidgets('the field is not read where the bar stands at the top (a wide screen)', (tester) async {
      _view(tester, 900, 600);
      final content = [
        _text('body', 'Тіло'),
        _navBar([_navItem('a', 'Home'), _navItem('b', 'Two')], float: true),
      ];
      await pumpDocument(tester, _doc(content));
      expect(tester.takeException(), isNull);
      // The bar at the top: no zone at the bottom, so nothing floats and no tail is added.
      expect(find.byType(ZoneTailPadding), findsNothing);
    });
  });

  group('navBadgeCases: when the dot stands', () {
    for (final row in _rows('navBadgeCases')) {
      final props = _obj(row['props']);
      final data = row['data'] == null ? <String, Object?>{} : _obj(row['data']);
      final expected = row['expect']! as bool;

      test('condition: ${row['name']}', () {
        final item = UiNode.parse({
          'id': 'item',
          'type': 'NavItem',
          'props': {'icon': 'house', 'label': _literal('Home'), 'action': {'type': 'none'}, ...props},
        }) as NavItemNode;
        final condition = item.badgeWhen;
        final holds = condition != null && condition.evaluate(ScreenData(data));
        expect(holds, expected);
      });

      testWidgets('screen: ${row['name']}', (tester) async {
        _view(tester, 320, 568);
        await pumpDocument(
          tester,
          _doc([_text('body', 'Тіло'), _navBar([_navItem('a', 'Home', props: props), _navItem('b', 'Two')])]),
          data: data,
        );
        expect(find.byType(NavBadgeMark), expected ? findsOneWidget : findsNothing);
      });
    }
  });

  group('navBadgeBoxCases: where the dot stands', () {
    for (final row in _rows('navBadgeBoxCases')) {
      final glyph = _obj(row['glyph']);
      final want = _obj(row['expect']);
      test('formula: ${row['name']}', () {
        final box = navBadgeBoxOf(
          glyphLeft: _num(glyph['left']),
          glyphTop: _num(glyph['top']),
          glyphSize: _num(glyph['size']),
          rtl: row['rtl']! as bool,
        );
        expect(box.left, _near(_num(want['left'])));
        expect(box.top, _near(_num(want['top'])));
        expect(box.size, _near(_num(want['size'])));
      });
    }

    for (final locale in ['en', 'ar']) {
      testWidgets('the dot on a real glyph ($locale): the centre on the top corner on the side of the end', (tester) async {
        _view(tester, 320, 568);
        await pumpDocument(
          tester,
          _doc([
            _text('body', 'Тіло'),
            _navBar([
              _navItem('a', 'Home', props: {'badgeWhen': {'path': 'user.unread', 'op': 'gt', 'value': 0}}),
              _navItem('b', 'Two'),
            ]),
          ]),
          data: {'user.unread': 3},
          locale: locale,
        );
        final mark = find.byType(NavBadgeMark);
        expect(mark, findsOneWidget);
        final markRect = tester.getRect(mark);
        final dot = tester.getRect(find.descendant(of: mark, matching: find.byType(DecoratedBox)));
        expect(dot.width, 8);
        expect(dot.height, 8);
        final glyphSize = markRect.width;
        final corner = locale == 'ar' ? markRect.left : markRect.right;
        expect(dot.center.dx, _near(corner));
        expect(dot.center.dy, _near(markRect.top + (markRect.height - glyphSize) / 2));
        // The dot changes nothing in the size of the item.
        final withDot = tester.getSize(find.byKey(const ValueKey('sdui-nav-item-a')));
        final without = tester.getSize(find.byKey(const ValueKey('sdui-nav-item-b')));
        expect(withDot, without);
      });
    }
  });

  group('nav922RuleCases: the artifact and the code mirror', () {
    final layout = _obj(_obj(_schema['x-style'])['layout']);
    for (final row in _rows('nav922RuleCases')) {
      test('${row['block']}.${row['rule']} -- ${row['name']}', () {
        final block = _obj(layout[row['block']]);
        expect(block[row['rule']], row['expect']);
      });
    }
    test('the diameter and the colour', () {
      expect(kNavBadgeDiameter, 8);
      expect(_obj(layout['navBadge'])['color'], 'accent');
    });
  });

  testWidgets('a floating bar with a margin and a radius: the margin box is the height of the zone, no built-in pill', (tester) async {
    _view(tester, 320, 568);
    await pumpDocument(
      tester,
      _doc(
        [
          {
            'id': 'content',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'height': 900},
            'children': [_text('mark', 'Початок')],
          },
          _navBar(
            [_navItem('a', 'Home'), _navItem('b', 'Two')],
            float: true,
            style: {'margin': {'start': 'md', 'end': 'md', 'bottom': 'sm'}, 'radius': 'xl'},
          ),
        ],
      ),
      safeBottom: 20,
    );
    final theme = RenderTheme.fallback();
    final zones = _zones(tester);
    final zoneRect = _rectOf(zones.lastChild!);
    final bar = find.ancestor(of: find.text('Home'), matching: find.byWidgetPredicate((w) => w is Container && w.child is Material)).first;
    final barRect = tester.getRect(bar);
    expect(zoneRect.height, _near(barRect.height + theme.space(SpacingToken.sm) + 20), reason: 'the margin box plus the inset');
    expect(barRect.left, _near(theme.space(SpacingToken.md)));
    expect(barRect.right, _near(320 - theme.space(SpacingToken.md)));
    // The body reaches the bottom: the last of the content scrolls clear of the zone.
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    expect(tester.getBottomLeft(find.text('Початок')).dy, lessThan(zoneRect.top + 1000));
  });
}
