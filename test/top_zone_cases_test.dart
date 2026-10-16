/// THE TOP ZONE OF A SCREEN (schema 9.24.0, `pin: 'top'`).
///
/// The shared table `fixtures/top-zone/top-zone-cases.json` runs group by group by the reader's rule and, where the
/// table speaks of a screen, through REAL widgets: the run of pinned children, the box of the zone with and without an
/// app bar, the body that starts below it and is clipped by it, the nodes that never scroll and take their own
/// presses, and the word that is not read.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/top_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/top-zone/top-zone-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
double _num(Object? value) => (value! as num).toDouble();

String _typeOf(String type) => type;

List<RootChildInfo> _infos(List<_Json> children) => [
  for (final child in children) (type: _typeOf(child['type']! as String), pin: child['pin'] == 'bottom'),
];

ScreenZoneChildren _zones(List<_Json> children, {bool screenTop = false}) => screenChildrenByZone(
  _infos(children),
  topPins: [for (final child in children) child['pin'] == 'top'],
  bodyAtScreenTop: screenTop,
);

List<String> _ids(List<_Json> children, int from, int to) => [for (var i = from; i < to; i += 1) children[i]['id']! as String];

_Json _text(String id, String text) => {
  'id': id,
  'type': 'Text',
  'props': {'content': {'kind': 'literal', 'value': text}},
};

_Json _block(String id, double height, {String? pin, double? pull, Object? visibleIf}) => {
  'id': id,
  'type': 'Container',
  'props': {'direction': 'column'},
  'style': {'height': height},
  'children': [_text('$id-t', id)],
  'pin': ?pin,
  'pull': ?pull,
  'visibleIf': ?visibleIf,
};

_Json _bar(double height) => {
  'id': 'bar',
  'type': 'AppBar',
  'props': {'title': {'kind': 'literal', 'value': 'Bar'}, 'showBack': false},
  'style': {'height': height},
};

UiDocument _doc(List<_Json> children, {double paddingTop = 0, Object gap = 'md', Object? bodyTop, String? presentation}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'top-zone',
  'name': 'top-zone',
  'initialScreenId': 'a',
  'screens': [
    {
      'screenId': 'a',
      'name': 'a',
      'presentation': ?presentation,
      'root': {
        'id': 'root',
        'type': 'Screen',
        'props': {'gap': gap, 'bodyTop': ?bodyTop},
        'style': {'padding': {'top': paddingTop}},
        'children': children,
      },
    },
  ],
});

String get kSupportedSchemaVersion => UiDocument.supportedSchemaVersion;

void _view(WidgetTester tester, [double width = 320, double height = 568]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

Rect _bodyRect(WidgetTester tester) => tester.getRect(find.byType(SingleChildScrollView).last);

void main() {
  test('the groups have the promised rows', () {
    expect(_rows('childrenCases'), hasLength(10));
    expect(_rows('pinCases'), hasLength(5));
    expect(_rows('geometryCases'), hasLength(6));
    expect(_rows('documentCases'), hasLength(5));
    expect(_rows('ruleCases'), hasLength(8));
  });

  test('x-style.layout.topZone: the mirror against the artifact', () {
    final block = ((_schema['x-style']! as _Json)['layout']! as _Json)['topZone']! as _Json;
    expect(block['field'], kTopZoneRules['field']);
    expect(block['word'], kPinTop);
    expect(block['counts'], kTopZoneRules['counts']);
    expect(block['scrolls'], kTopZoneRules['scrolls']);
    expect(block['olderReader'], kTopZoneRules['olderReader']);
    expect(block['never'], ['AppBar', 'NavBar']);
    expect(block['cases'], 'contract/fixtures/top-zone/top-zone-cases.json');
  });

  group('childrenCases: which child stands in which zone', () {
    for (final row in _rows('childrenCases')) {
      test(row['name']! as String, () {
        final children = (row['children']! as List<Object?>).cast<_Json>();
        final screenTop = _obj(row['rootProps'] ?? <String, Object?>{})['bodyTop'] == 'screenTop';
        final zones = _zones(children, screenTop: screenTop);
        final expected = _obj(row['expect']);
        expect(zones.appBar == null ? null : children[zones.appBar!]['id'], expected['appBar']);
        expect(_ids(children, zones.topFrom, zones.topTo), expected['topPinned']);
        expect(_ids(children, zones.bodyFrom, zones.bodyTo), expected['body']);
        expect(zones.pinned == null ? null : children[zones.pinned!]['id'], expected['pinned']);
        expect(zones.navBar == null ? null : children[zones.navBar!]['id'], expected['navBar']);
      });
    }
  });

  group('pinCases: whether a node carries the word', () {
    for (final row in _rows('pinCases')) {
      test(row['name']! as String, () {
        final node = UiNode.parse({..._text('n', 'x'), ..._obj(row['node'])}) as TextNode;
        expect(node.pinTop, row['expect']);
        expect(pinTopOf(_obj(row['node'])['pin']), row['expect']);
      });
    }
  });

  group('geometryCases: the box of the zone', () {
    for (final row in _rows('geometryCases')) {
      test(row['name']! as String, () {
        final input = _obj(row['input']);
        final box = topZoneOf(
          appBarHeight: input['appBarHeight'] == null ? null : _num(input['appBarHeight']),
          pinned: [
            for (final entry in (input['pinned']! as List<Object?>).cast<_Json>())
              (height: _num(entry['height']), pull: entry['pull'] == null ? 0.0 : _num(entry['pull'])),
          ],
          rootPaddingTop: _num(input['rootPaddingTop']),
          gap: _num(input['gap']),
          safeTop: input['safeTop'] == null ? 0 : _num(input['safeTop']),
        );
        final expected = _obj(row['expect']);
        expect(box.height, _num(expected['height']));
        expect(box.bodyTop, _num(expected['bodyTop']));
        final bar = expected['appBar'] == null ? null : _obj(expected['appBar']);
        expect(box.appBar?.top, bar == null ? null : _num(bar['top']));
        expect(box.appBar?.height, bar == null ? null : _num(bar['height']));
        final pinned = (expected['pinned']! as List<Object?>).cast<_Json>();
        expect([for (final entry in box.pinned) entry.top], [for (final entry in pinned) _num(entry['top'])]);
        expect([for (final entry in box.pinned) entry.height], [for (final entry in pinned) _num(entry['height'])]);
      });
    }
  });

  group('geometryCases on real widgets (the same shape, the screen gap of the theme)', () {
    const gap = 12.0;
    for (final row in _rows('geometryCases')) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester);
        final input = _obj(row['input']);
        final safe = input['safeTop'] == null ? 0.0 : _num(input['safeTop']);
        final pinned = (input['pinned']! as List<Object?>).cast<_Json>();
        final barHeight = input['appBarHeight'] == null ? null : _num(input['appBarHeight']);
        final padding = _num(input['rootPaddingTop']);
        final expected = topZoneOf(
          appBarHeight: barHeight,
          pinned: [for (final entry in pinned) (height: _num(entry['height']), pull: entry['pull'] == null ? 0.0 : _num(entry['pull']))],
          rootPaddingTop: padding,
          gap: gap,
          safeTop: safe,
        );
        await pumpDocument(
          tester,
          _doc([
            if (barHeight != null) _bar(barHeight - safe),
            for (var i = 0; i < pinned.length; i += 1)
              _block('p$i', _num(pinned[i]['height']), pin: 'top', pull: pinned[i]['pull'] == null ? null : _num(pinned[i]['pull'])),
            _block('body', 900),
          ], paddingTop: padding),
          safeTop: safe,
        );
        expect(tester.takeException(), isNull);
        for (var i = 0; i < pinned.length; i += 1) {
          expect(_top(tester, 'p$i'), closeTo(expected.pinned[i].top, 0.01), reason: 'the top of node $i');
        }
        // The body area starts at the bottom edge of the zone.
        expect(_bodyRect(tester).top, closeTo(expected.bodyTop, 0.01));
      });
    }
  });

  group('on a real screen', () {
    testWidgets('the zone does not scroll: only the body does, and it is clipped at the zone', (tester) async {
      _view(tester);
      await pumpDocument(tester, _doc([_bar(56), _block('head', 48, pin: 'top'), _block('chips', 40, pin: 'top'), _block('body', 1200)]));
      final head = _top(tester, 'head');
      final chips = _top(tester, 'chips');
      final bodyTop = _bodyRect(tester).top;
      expect(head, 56 + 12);
      expect(chips, head + 48 + 12);
      expect(bodyTop, chips + 40);
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pump();
      expect(_top(tester, 'head'), head);
      expect(_top(tester, 'chips'), chips);
      expect(_bodyRect(tester).top, bodyTop, reason: 'the body area stands; what scrolls out of it is clipped');
      expect(_top(tester, 'body'), lessThan(bodyTop), reason: 'the content has scrolled out under the zone');
    });

    testWidgets('a hidden node takes no room; all hidden: there is no zone and the body keeps the top padding', (tester) async {
      _view(tester);
      const hidden = {'path': 'user.vip', 'op': 'isTrue'};
      await pumpDocument(tester, _doc([_bar(56), _block('head', 48, pin: 'top', visibleIf: hidden), _block('chips', 40, pin: 'top'), _block('body', 900)]));
      expect(find.text('head'), findsNothing);
      expect(_top(tester, 'chips'), 56 + 12);
      expect(_bodyRect(tester).top, 56 + 12 + 40);
      await pumpDocument(tester, _doc([_bar(56), _block('head', 48, pin: 'top', visibleIf: hidden), _block('body', 900)]));
      expect(_bodyRect(tester).top, 56, reason: 'no zone: the body starts under the app bar as before');
    });

    testWidgets('without an app bar the safe inset and the root padding stand above the first node, outside the boxes', (tester) async {
      _view(tester);
      await pumpDocument(tester, _doc([_block('head', 60, pin: 'top'), _block('body', 900)], paddingTop: 8), safeTop: 47);
      expect(_top(tester, 'head'), 55);
      expect(_bodyRect(tester).top, 115);
    });

    testWidgets('the word after a child without it is not read: the node scrolls with the body', (tester) async {
      _view(tester);
      await pumpDocument(tester, _doc([_bar(56), _block('a', 100), _block('head', 48, pin: 'top'), _block('tall', 1200)]));
      final before = _top(tester, 'head');
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -80));
      await tester.pump();
      expect(_top(tester, 'head'), lessThan(before));
    });

    testWidgets('with bodyTop: screenTop the word is not read', (tester) async {
      _view(tester);
      await pumpDocument(tester, _doc([_bar(56), _block('head', 48, pin: 'top'), _block('tall', 1200)], bodyTop: 'screenTop'));
      final before = _top(tester, 'head');
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -80));
      await tester.pump();
      expect(_top(tester, 'head'), lessThan(before));
    });

    testWidgets('a pulled first body child lifts the body area onto the zone, as onto the app bar', (tester) async {
      _view(tester);
      await pumpDocument(tester, _doc([_bar(56), _block('head', 48, pin: 'top'), _block('hero', 100, pull: 40), _block('tall', 900)]));
      // The overlap is the pull minus the screen gap: 40 - 12.
      expect(_bodyRect(tester).top, 56 + 12 + 48 - 28);
    });

    testWidgets('nodes of the zone take their own presses', (tester) async {
      _view(tester);
      final pressed = <String>[];
      await pumpDocument(
        tester,
        _doc([
          _bar(56),
          {
            'id': 'head',
            'type': 'Container',
            'props': {'direction': 'column'},
            'pin': 'top',
            'children': [buttonNode('Open', action: const {'type': 'open'}, id: 'open')],
          },
          _block('tall', 1200),
        ]),
        onAction: (action, id) => pressed.add(action.type),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(pressed, ['open']);
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -200));
      await tester.pump();
      await tester.tap(find.text('Open'));
      expect(pressed, ['open', 'open'], reason: 'the node is still there after the body scrolled');
    });

    testWidgets('a layer over the previous screen draws the zone at the top of the layer', (tester) async {
      _view(tester);
      await pumpDocument(tester, _doc([_block('head', 48, pin: 'top'), _text('body', 'Body')], presentation: 'page'));
      expect(find.text('head'), findsOneWidget);
      await pumpDocument(tester, _doc([_bar(56), _block('head', 48, pin: 'top'), _text('body', 'Body')]));
      expect(tester.takeException(), isNull);
    });
  });

  group('documentCases: why the word is not read', () {
    for (final row in _rows('documentCases')) {
      test(row['name']! as String, () {
        final children = (row['children']! as List<Object?>).cast<_Json>();
        final node = children.firstWhere((child) => child['id'] == row['node']);
        final screenTop = _obj(row['rootProps'] ?? <String, Object?>{})['bodyTop'] == 'screenTop';
        final zones = _zones(children, screenTop: screenTop);
        final index = children.indexOf(node);
        final issue = topPinIssueOf(
          pinTop: node['pin'] == 'top',
          type: node['type']! as String,
          parentType: row['parentType'] as String? ?? 'Screen',
          bodyAtScreenTop: screenTop,
          inRun: index >= zones.topFrom && index < zones.topTo,
        );
        expect(issue?.name, row['expect']);
      });
    }
  });

  group('ruleCases: the artifact and the code mirror', () {
    final block = ((_schema['x-style']! as _Json)['layout']! as _Json)['topZone']! as _Json;
    Object? at(String path) {
      Object? current = block;
      for (final part in path.split('.')) {
        current = (current! as Map)[part];
      }
      return current;
    }

    for (final row in _rows('ruleCases')) {
      test(row['name']! as String, () => expect(at(row['rule']! as String), row['expect']));
    }
  });
}
