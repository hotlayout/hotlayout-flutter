/// WIDTH ADAPTIVITY, STEP 1 (schema 9.18.0): width class,
/// `showOn`, `styleOn`, `propsOn`, `Screen.contentMaxWidth`.
///
/// The tests read the contract table ITSELF
/// (`assets/contract/fixtures/adaptive/adaptive-cases.json`, a copy of
/// `contract/fixtures/adaptive/adaptive-cases.json`, 231 rows in 16 groups) and
/// run the rows through the reader's formula (`width_class.dart`, tree resolution in a class) and a
/// REAL widget where the row is about geometry:
///
///  1. `classCases` (20), `layerCases` (3) -- class by width, cascade layers;
///  2. `styleCases` (22), `propsCases` (27) -- node style and props in a class;
///  3. `showCases` (22), `drawnCases` (7), `numberCases` (5), `tabCases` (4),
///     `weightCases` (5), `zoneCases` (5), `formCases` (6) -- visibility in every
///     place where the reader asks "visible";
///  4. `validityCases` (39) -- the reader has no validator, so a row is checked by
///     the reader NOT crashing on a document the validator would reject;
///  5. `contentCases` (22) -- the screen content column: formula and real screen;
///  6. `gridCases` (12), `boxCases` (12) -- grid and container geometry;
///  7. `ruleCases` (20) -- the `x-style.layout.widthClass` data block.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/form_rules.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/list_marker.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/width_class.dart';
import 'package:hotlayout_flutter/src/render/app_bar_layout.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = (json.decode(File('assets/contract/fixtures/adaptive/adaptive-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final _Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
List<Object?> _list(Object? value) => value! as List<Object?>;
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);
WidthClass _class(Object? wire) => WidthClass.values.firstWhere((v) => v.wire == wire);

/// Data from the listed paths: each is met (`true`), exactly like "met" in the table.
ScreenData _met(List<Object?> paths) {
  final document = <String, Object?>{};
  for (final path in paths.cast<String>()) {
    final parts = path.split('.');
    var at = document;
    for (final part in parts.take(parts.length - 1)) {
      at = (at[part] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    at[parts.last] = true;
  }
  return ScreenData(document);
}

/// A table row node parsed in a class: type and raw fields, as the reader sees them.
UiNode _parse(_Json fields, WidthClass widthClass, {String type = 'Container', String id = 'node'}) =>
    UiNode.parse({'id': id, 'type': type, 'props': <String, Object?>{}, ...fields}, widthClass: widthClass);

ChildNode _child(_Json fields, WidthClass widthClass, {String type = 'Container', String id = 'node'}) =>
    _parse(fields, widthClass, type: type, id: id) as ChildNode;

void _view(WidgetTester tester, double width, [double height = 1200]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

String _hex(int i) => '#11${(i + 16).toRadixString(16).padLeft(2, '0')}cc';
Color _color(int i) => Color(int.parse('ff${_hex(i).substring(1)}', radix: 16));
Finder _box(int i) => find.byWidgetPredicate(
  (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == _color(i),
  description: 'box ${_hex(i)}',
);

_Json _bg(int i) => {'kind': 'color', 'color': {'value': _hex(i)}};

/// A geometry row cell: a column with named height, width and classes.
_Json _cell(int i, _Json spec) => {
  'id': 'c$i',
  'type': 'Container',
  'props': {'direction': 'column'},
  'style': {'background': _bg(i), 'height': spec['height'], 'width': ?spec['width']},
  'weight': ?spec['weight'],
  'showOn': ?spec['showOn'],
};

UiDocument _document(_Json root, {List<_Json> extraScreens = const []}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'adaptive',
  'name': 'adaptive',
  'initialScreenId': 's',
  'screens': [
    {'screenId': 's', 'name': 's', 'root': root},
    ...extraScreens,
  ],
});

_Json _screenRoot(List<_Json> children, {_Json? props, _Json? style, _Json? propsOn}) => {
  'id': 'root',
  'type': 'Screen',
  'props': {'gap': 'none', ...?props},
  'style': ?style,
  'propsOn': ?propsOn,
  'children': children,
};

void main() {
  // ───────────────────────────── table structure ─────────────────────────────

  test('table: 231 rows in sixteen groups', () {
    final counts = {
      'classCases': 20,
      'layerCases': 3,
      'styleCases': 22,
      'propsCases': 27,
      'showCases': 22,
      'drawnCases': 7,
      'numberCases': 5,
      'tabCases': 4,
      'weightCases': 5,
      'zoneCases': 5,
      'formCases': 6,
      'validityCases': 39,
      'contentCases': 22,
      'gridCases': 12,
      'boxCases': 12,
      'ruleCases': 20,
    };
    for (final entry in counts.entries) {
      expect(_rows(entry.key), hasLength(entry.value), reason: entry.key);
    }
    expect(counts.values.reduce((a, b) => a + b), 231);
  });

  // ───────────────────────────── class and cascade ─────────────────────────────

  group('classCases: class by width', () {
    for (final row in _rows('classCases')) {
      test(row['name']! as String, () {
        // A string and a missing width mean "unknown": in Dart that is `null`, a number is not taken from a string.
        final width = row['width'];
        expect(widthClassOf(width is num ? width : null).wire, row['expect']);
      });
    }

    test('bounds are exactly those in the data: a class starts at its own number and not earlier', () {
      for (final widthClass in WidthClass.values) {
        final from = kWidthClassFrom[widthClass]!;
        expect(widthClassOf(from), widthClass);
        if (from > 0) expect(widthClassOf(from - 0.001), isNot(widthClass));
      }
      expect(widthClassOf(double.nan), WidthClass.compact);
      expect(widthClassOf(double.infinity), WidthClass.compact);
    });
  });

  group('layerCases: cascade layers', () {
    for (final row in _rows('layerCases')) {
      test(row['name']! as String, () {
        expect([for (final layer in widthClassLayers(_class(row['widthClass']))) layer.wire], row['expect']);
      });
    }
  });

  // ───────────────────────────── style ─────────────────────────────

  void sameStyle(NodeStyle? actual, Object? expected, String reason) {
    final want = NodeStyle.parse(expected);
    if (want == null) {
      expect(actual, isNull, reason: reason);
      return;
    }
    expect(actual, isNotNull, reason: reason);
    final a = actual!;
    expect(a.color, want.color, reason: '$reason: color');
    expect(a.typography, want.typography, reason: '$reason: typography');
    expect(a.padding, want.padding, reason: '$reason: padding');
    expect(a.margin, want.margin, reason: '$reason: margin');
    expect(a.radius, want.radius, reason: '$reason: radius');
    expect(a.border, want.border, reason: '$reason: border');
    expect(a.background, want.background, reason: '$reason: background');
    expect(a.shadow, want.shadow, reason: '$reason: shadow');
    expect(a.opacity, want.opacity, reason: '$reason: opacity');
  }

  group('styleCases: style by class', () {
    for (final row in _rows('styleCases')) {
      test(row['name']! as String, () {
        final node = _child(_obj(row['node']), _class(row['widthClass']));
        final style = resolveNodeStyle(node.style, node.styleWhen, _met(_list(row['met'])));
        sameStyle(style, row['expect'], row['name']! as String);
      });
    }

    test('without `styleOn` the class does not change the base: the same style in every class', () {
      for (final row in _rows('styleCases')) {
        final raw = {..._obj(row['node'])}..remove('styleOn');
        final styles = [for (final widthClass in WidthClass.values) _child(raw, widthClass).style];
        for (final style in styles) {
          sameStyle(style, _obj(row['node'])['style'], row['name']! as String);
        }
      }
    });
  });

  // ───────────────────────────── props ─────────────────────────────

  group('propsCases: properties by class', () {
    for (final row in _rows('propsCases')) {
      test(row['name']! as String, () {
        final node = _obj(row['node']);
        final got = effectivePropsOf(
          node['type']! as String,
          _obj(node['props']),
          node['propsOn'],
          _class(row['widthClass']),
        );
        expect(got.props, row['expect']);
      });
    }

    test('nothing overridden -- the same props object', () {
      for (final row in _rows('propsCases')) {
        final node = _obj(row['node']);
        final props = _obj(node['props']);
        expect(effectivePropsOf(node['type']! as String, props, node['propsOn'], WidthClass.compact).props, same(props));
      }
    });

    test('node parsing in a class reads the effective props: grid columns, container direction, card count', () {
      final grid = {
        'type': 'Grid',
        'props': {'columns': 2, 'gap': 'sm'},
        'propsOn': {'medium': {'columns': 1}, 'expanded': {'columns': 6}},
      };
      expect((_child(grid, WidthClass.compact, type: 'Grid') as GridNode).columns, 2);
      expect((_child(grid, WidthClass.medium, type: 'Grid') as GridNode).columns, 1);
      expect((_child(grid, WidthClass.expanded, type: 'Grid') as GridNode).columns, 6);
      // The base keeps its bounds 2...4: columns outside them are clamped, as before.
      final base = {
        'type': 'Grid',
        'props': {'columns': 9},
      };
      expect((_child(base, WidthClass.expanded, type: 'Grid') as GridNode).columns, 4);
      expect((_child({'type': 'Grid', 'props': {'columns': 1}}, WidthClass.compact, type: 'Grid') as GridNode).columns, 2);
      // A number outside the override bounds is clamped to 1...6.
      final loud = {
        'type': 'Grid',
        'props': {'columns': 2},
        'propsOn': {'expanded': {'columns': 99}},
      };
      expect((_child(loud, WidthClass.expanded, type: 'Grid') as GridNode).columns, 6);
      final list = {
        'type': 'Repeater',
        'props': {'source': 'tasks', 'item': 'task'},
        'propsOn': {'medium': {'columns': 2}, 'expanded': {'columns': 3}},
      };
      expect((_child(list, WidthClass.compact, type: 'Repeater') as RepeaterNode).columns, isNull);
      expect((_child(list, WidthClass.medium, type: 'Repeater') as RepeaterNode).columns, 2);
      expect((_child(list, WidthClass.expanded, type: 'Repeater') as RepeaterNode).columns, 3);
    });

    test('screen content width: from the base or an override, the class does not act on it except by naming it', () {
      final screen = {
        'type': 'Screen',
        'props': {'gap': 'sm'},
        'propsOn': {'expanded': {'contentMaxWidth': 1120}},
        'children': <Object?>[],
      };
      expect((_parse(screen, WidthClass.medium, type: 'Screen') as ScreenNode).contentMaxWidth, isNull);
      expect((_parse(screen, WidthClass.expanded, type: 'Screen') as ScreenNode).contentMaxWidth, 1120);
      // Outside the bounds -- clamped; not an integer -- no field.
      for (final (value, want) in [(100, 320), (5000, 1920), (900.5, null), ('900', null), (null, null)]) {
        final node = _parse({'props': {'contentMaxWidth': value}, 'children': <Object?>[]}, WidthClass.compact, type: 'Screen');
        expect((node as ScreenNode).contentMaxWidth, want, reason: '$value');
      }
    });
  });

  // ───────────────────────────── visibility ─────────────────────────────

  group('showCases: whether a node is shown', () {
    for (final row in _rows('showCases')) {
      test(row['name']! as String, () {
        final node = _child(_obj(row['node']), _class(row['widthClass']));
        expect(node.isVisible(_met(_list(row['met']))), row['expect']);
      });
    }

    test('the two halves are independent: a class never shows what a condition hid, and vice versa', () {
      for (final row in _rows('showCases')) {
        final raw = _obj(row['node']);
        final widthClass = _class(row['widthClass']);
        final byClass = showsOnWidthClass(showOnOf(raw['showOn']), widthClass);
        final condition = raw['visibleIf'] == null ? null : _obj(raw['visibleIf']);
        final byData = condition == null || _list(row['met']).contains(condition['path']);
        expect(row['expect'], byClass && byData, reason: row['name']! as String);
      }
    });
  });

  group('drawnCases: who is drawn', () {
    for (final row in _rows('drawnCases')) {
      test(row['name']! as String, () {
        final widthClass = _class(row['widthClass']);
        final data = _met(_list(row['met']));
        final visible = [
          for (final item in _list(row['items'])) _child(_obj(item), widthClass).isVisible(data),
        ];
        final drawn = row['kind'] == 'appBarActions' ? appBarDrawnActions(visible) : navDrawnItems(visible);
        expect(drawn, row['expect']);
      });
    }
  });

  group('numberCases: list item numbers', () {
    for (final row in _rows('numberCases')) {
      test(row['name']! as String, () {
        final widthClass = _class(row['widthClass']);
        final data = _met(_list(row['met']));
        final items = [
          for (final item in _list(row['items']).cast<_Json>())
            _child({
              ...item,
              'props': {'content': {'kind': 'literal', 'value': 'x'}, 'marker': item['marker']},
            }..remove('marker'), widthClass, type: 'Text'),
        ];
        final markers = [for (final item in items) drawnMarkerOf((item as TextNode).marker)];
        final visible = [for (final item in items) item.isVisible(data)];
        expect([for (var i = 0; i < items.length; i++) listNumberOf(markers, i, visible)], row['expect']);
      });
    }
  });

  group('tabCases: open tab', () {
    for (final row in _rows('tabCases')) {
      test(row['name']! as String, () {
        final widthClass = _class(row['widthClass']);
        final data = _met(_list(row['met']));
        final visible = [
          for (final tab in _list(row['tabs'])) _child(_obj(tab), widthClass, type: 'Tab').isVisible(data),
        ];
        expect(openTabIndex((row['initialTab']! as num).toInt(), visible), row['expect']);
      });
    }
  });

  group('zoneCases: screen zones', () {
    for (final row in _rows('zoneCases')) {
      test(row['name']! as String, () {
        final widthClass = _class(row['widthClass']);
        final data = _met(_list(row['met']));
        final children = [
          for (final spec in _list(row['children']))
            _child({..._obj(spec)}..remove('id')..remove('type'), widthClass, type: _obj(spec)['type']! as String, id: _obj(spec)['id']! as String),
        ];
        final zones = screenChildrenByZone([
          for (final child in children)
            (
              type: child is AppBarNode ? 'AppBar' : (child is NavBarNode ? kNavBarType : 'other'),
              pin: child.pin,
            ),
        ]);
        String? id(int? index) => index == null ? null : children[index].id;
        bool? shown(int? index) => index == null ? null : children[index].isVisible(data);
        final body = [for (var i = zones.bodyFrom; i < zones.bodyTo; i++) i];
        // Who is in which zone is BY THE DOCUMENT: a class, like a condition, does not reorder zones, it only hides.
        expect({
          'appBar': id(zones.appBar),
          'pinned': id(zones.pinned),
          'navBar': id(zones.navBar),
          'body': [for (final i in body) children[i].id],
          'shown': {
            'appBar': shown(zones.appBar),
            'pinned': shown(zones.pinned),
            'navBar': shown(zones.navBar),
            'body': [for (final i in body) shown(i)],
          },
        }, row['expect']);
      });
    }
  });

  group('formCases: required form fields', () {
    for (final row in _rows('formCases')) {
      test(row['name']! as String, () {
        final widthClass = _class(row['widthClass']);
        final values = _obj(row['values']);
        final fields = <_Json>[
          for (final field in _list(row['fields']).cast<_Json>())
            () {
              final show = {...field}
                ..remove('id')
                ..remove('path')
                ..remove('under');
              final input = {
                'id': field['id'],
                'type': 'TextField',
                ...show,
                'props': {
                  'label': {'kind': 'literal', 'value': 'x'},
                  'value': {'kind': 'binding', 'path': field['path']},
                  'required': true,
                },
              };
              if (field['under'] == null) return input;
              return {
                'id': '${field['id']}-wrap',
                'type': 'Column',
                'props': <String, Object?>{},
                ..._obj(field['under']),
                'children': [input],
              };
            }(),
        ];
        final root = UiNode.parse(_screenRoot(fields), widthClass: widthClass);
        final counted = [for (final field in requiredFieldsOf(root)) if (!field.hiddenByClass) field.nodeId];
        expect(counted, _obj(row['expect'])['required']);
        // Field values and the paths that satisfy conditions (`met`) are in one data document.
        final document = <String, Object?>{};
        void put(String path, Object? value) {
          final parts = path.split('.');
          var at = document;
          for (final part in parts.take(parts.length - 1)) {
            at = (at[part] ??= <String, Object?>{}) as Map<String, Object?>;
          }
          at[parts.last] = value;
        }

        for (final entry in values.entries) {
          put(entry.key, entry.value);
        }
        for (final path in _list(row['met']).cast<String>()) {
          put(path, true);
        }
        final data = ScreenData(document);
        expect(isFormFilled(root, data), _obj(row['expect'])['filled']);
      });
    }
  });

  // ───────────────────────────── row weights ─────────────────────────────

  group('weightCases: weights in a row', () {
    for (final row in _rows('weightCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final inline = _num(row['inline']);
        final widthClass = _class(row['widthClass']);
        _view(tester, inline + 32);
        final children = _list(row['children']).cast<_Json>();
        final host = {
          'id': 'host',
          'type': 'Row',
          'props': {'gap': _num(row['gap']), 'align': 'start', 'justify': 'start', 'wrap': false},
          'children': [
            for (var i = 0; i < children.length; i++)
              {
                'id': 'c$i',
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'background': _bg(i), 'height': 20, 'width': children[i]['width']},
                'weight': children[i]['weight'],
                'showOn': children[i]['showOn'],
                'visibleIf': children[i]['visibleIf'],
              },
          ],
        };
        await pumpDocument(
          tester,
          _document(_screenRoot([host], style: {'padding': 16})),
          data: {
            for (final path in _list(row['met']).cast<String>()) path.split('.').first: {path.split('.').last: true},
          },
        );
        expect(tester.takeException(), isNull);
        expect(widthClassOf(inline + 32), widthClass, reason: 'the row describes the class frame');
        final expected = _list(row['expect']);
        for (var i = 0; i < expected.length; i++) {
          if (expected[i] == null) {
            expect(_box(i), findsNothing, reason: 'child $i hid');
          } else {
            expect(tester.getSize(_box(i)).width, _near(_num(expected[i])), reason: 'width of child $i');
          }
        }
      });
    }
  });

  // ───────────────────────────── validity ─────────────────────────────

  group('validityCases: the reader does not crash on any table document', () {
    // The reader has no validator: a document the validator rejects is still read and
    // drawn by the reader (`x-compatibility`: the document comes from the network). We check that this is
    // really so at every width.
    for (final row in _rows('validityCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final rootFields = row['root'] == null ? <String, Object?>{} : _obj(row['root']);
        for (final width in [393.0, 768.0, 1280.0]) {
          _view(tester, width);
          final root = {
            ..._screenRoot([
              for (final (i, child) in _list(row['children']).indexed) _nodeWithDefaults(_obj(child), 'n$i'),
            ]),
            ...rootFields,
            'props': {'gap': 'none', ...?(rootFields['props'] as Map?)?.cast<String, Object?>()},
          };
          await pumpDocument(tester, _document(root));
          expect(tester.takeException(), isNull, reason: 'width $width');
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  // ───────────────────────────── content width ─────────────────────────────

  group('contentCases: screen content column', () {
    for (final row in _rows('contentCases')) {
      final rtl = row['rtl'] == true;
      final padding = _obj(row['padding']);
      final max = row['contentMaxWidth'] == null ? null : (row['contentMaxWidth']! as num).toInt();
      InlineInset inset(Object? raw) => raw == null ? (start: 0.0, end: 0.0) : (start: _num(_obj(raw)['start']), end: _num(_obj(raw)['end']));

      test('formula: ${row['name']}', () {
        final rects = screenContentRects(
          width: _num(row['width']),
          padding: inset(padding),
          contentMaxWidth: max,
          appBarInset: inset(row['appBarInset']),
          navBarInset: inset(row['navBarInset']),
          rtl: rtl,
        );
        final expected = _obj(row['expect']);
        for (final (zone, rect) in [
          ('body', rects.body),
          ('pinned', rects.pinned),
          ('appBar', rects.appBar),
          ('navBar', rects.navBar),
        ]) {
          expect(rect.x, _near(_num(_obj(expected[zone])['x'])), reason: '$zone: x');
          expect(rect.width, _near(_num(_obj(expected[zone])['width'])), reason: '$zone: width');
        }
      });

      testWidgets('real screen: ${row['name']}', (tester) async {
        final width = _num(row['width']);
        _view(tester, width, 900);
        final barInset = row['appBarInset'] == null ? null : _obj(row['appBarInset']);
        final navInset = row['navBarInset'] == null ? null : _obj(row['navBarInset']);
        final children = <_Json>[
          {
            'id': 'bar',
            'type': 'AppBar',
            'props': {'title': {'kind': 'literal', 'value': 'T'}, 'showBack': false},
            if (barInset != null) 'style': {'padding': barInset},
          },
          {
            'id': 'card',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'background': _bg(1), 'height': 60},
          },
          {
            'id': 'pin',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'background': _bg(2), 'height': 40},
            'pin': 'bottom',
          },
          {
            'id': 'nav',
            'type': 'NavBar',
            // The `contentCases` rows are about the BOTTOM bar (step 1): in a wide place a bar without this
            // word goes to the top (step 2, `wide_chrome_cases_test.dart`).
            'props': {'widePlacement': 'bottom'},
            if (navInset != null) 'style': {'padding': navInset},
            'children': [
              for (final id in ['a', 'b', 'c'])
                {
                  'id': id,
                  'type': 'NavItem',
                  'props': {
                    'icon': 'house',
                    'label': {'kind': 'literal', 'value': id},
                    'action': {'type': 'navigate.section', 'params': {'screenId': id}},
                  },
                },
            ],
          },
        ];
        await pumpDocument(
          tester,
          _document(
            _screenRoot(
              children,
              props: {'contentMaxWidth': ?max},
              style: {'padding': padding},
            ),
          ),
          locale: rtl ? 'ar' : null,
        );
        expect(tester.takeException(), isNull);
        final expected = _obj(row['expect']);
        void check(String zone, Rect rect) {
          expect(rect.left, _near(_num(_obj(expected[zone])['x'])), reason: '$zone: x');
          expect(rect.width, _near(_num(_obj(expected[zone])['width'])), reason: '$zone: width');
        }

        check('body', tester.getRect(_box(1)));
        check('pinned', tester.getRect(_box(2)));
        check('appBar', tester.getRect(find.byType(AppBarLayout)));
        final items = [for (final id in ['a', 'b', 'c']) tester.getRect(find.byKey(ValueKey('sdui-nav-item-$id')))];
        final left = items.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final right = items.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        check('navBar', Rect.fromLTRB(left, 0, right, 1));
      });
    }

    testWidgets('root and app bar background edge to edge, though the content is in the column', (tester) async {
      _view(tester, 1280, 700);
      await pumpDocument(
        tester,
        _document(
          _screenRoot(
            [
              {
                'id': 'card',
                'type': 'Container',
                'props': {'direction': 'column'},
                'style': {'background': _bg(1), 'height': 60},
              },
            ],
            props: {'contentMaxWidth': 600},
            style: {'background': _bg(7)},
          ),
        ),
      );
      expect(tester.getRect(_box(7)).width, 1280);
      expect(tester.getRect(_box(1)).width, 600);
      expect(tester.getRect(_box(1)).left, 340);
    });
  });

  // ───────────────────────────── grid and container ─────────────────────────────

  group('gridCases: grid 2 -> 3 -> 4', () {
    for (final row in _rows('gridCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final frame = _num(row['frame']);
        _view(tester, frame);
        final expected = _obj(row['expect']);
        expect(widthClassOf(frame).wire, expected['widthClass']);
        final cells = _list(row['cells']).cast<_Json>();
        final host = {
          'id': 'host',
          ..._obj(row['node']),
          'style': {'background': _bg(99)},
          'children': [for (var i = 0; i < cells.length; i++) _cell(i, cells[i])],
        };
        await pumpDocument(
          tester,
          _document(_screenRoot([host], style: {'padding': 16})),
          locale: row['rtl'] == true ? 'ar' : null,
        );
        expect(tester.takeException(), isNull);
        final hostRect = tester.getRect(_box(99));
        final rects = _list(expected['rects']);
        for (var i = 0; i < rects.length; i++) {
          if (rects[i] == null) {
            expect(_box(i), findsNothing, reason: 'cell $i hidden');
            continue;
          }
          final want = _obj(rects[i]);
          final rect = tester.getRect(_box(i));
          expect(rect.left - hostRect.left, _near(_num(want['x'])), reason: 'x of cell $i');
          expect(rect.top - hostRect.top, _near(_num(want['y'])), reason: 'y of cell $i');
          expect(rect.width, _near(_num(want['width'])), reason: 'width of cell $i');
          expect(rect.height, _near(_num(want['height'])), reason: 'height of cell $i');
        }
      });
    }
  });

  group('boxCases: container column -> row with weights', () {
    for (final row in _rows('boxCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final frame = _num(row['frame']);
        _view(tester, frame);
        final expected = _obj(row['expect']);
        expect(widthClassOf(frame).wire, expected['widthClass']);
        final children = _list(row['children']).cast<_Json>();
        final host = {
          'id': 'host',
          ..._obj(row['node']),
          'style': {'background': _bg(99)},
          'children': [for (var i = 0; i < children.length; i++) _cell(i, children[i])],
        };
        await pumpDocument(
          tester,
          _document(_screenRoot([host], style: {'padding': 16})),
          locale: row['rtl'] == true ? 'ar' : null,
        );
        expect(tester.takeException(), isNull);
        final hostRect = tester.getRect(_box(99));
        final rects = _list(expected['rects']);
        for (var i = 0; i < rects.length; i++) {
          if (rects[i] == null) {
            expect(_box(i), findsNothing, reason: 'child $i hidden');
            continue;
          }
          final want = _obj(rects[i]);
          final rect = tester.getRect(_box(i));
          expect(rect.left - hostRect.left, _near(_num(want['x'])), reason: 'x of child $i');
          expect(rect.top - hostRect.top, _near(_num(want['y'])), reason: 'y of child $i');
          expect(rect.width, _near(_num(want['width'])), reason: 'width of child $i');
          expect(rect.height, _near(_num(want['height'])), reason: 'height of child $i');
        }
      });
    }
  });

  // ───────────────────────────── artifact data ─────────────────────────────

  group('ruleCases: data block x-style.layout.widthClass', () {
    final block = _obj(_obj(_obj(_schema['x-style'])['layout'])['widthClass']);

    for (final row in _rows('ruleCases')) {
      test(row['name']! as String, () {
        Object? at = block;
        for (final part in (row['rule']! as String).split('.')) {
          at = at is List ? at[int.parse(part)] : (at! as Map)[part];
        }
        expect(at, row['expect']);
      });
    }

    test('the reader mirror is exactly the artifact block without the table address', () {
      final rest = {...block}..remove('cases');
      expect(jsonDecode(jsonEncode(kWidthClassLayout)), rest);
      expect(block['cases'], 'contract/fixtures/adaptive/adaptive-cases.json');
    });

    test('reader bounds come from data, not knowledge: class numbers and `columns`', () {
      final classes = _list(block['classes']).cast<_Json>();
      for (final entry in classes) {
        expect(kWidthClassFrom[_class(entry['class'])], (entry['from']! as num).toDouble());
      }
      final columns = _obj(_obj(block['props'])['columns']);
      expect(kOverrideMinColumns, columns['min']);
      expect(kOverrideMaxColumns, columns['max']);
      final contentMax = _obj(block['contentMaxWidth']);
      expect(kContentMaxWidthMin, contentMax['min']);
      expect(kContentMaxWidthMax, contentMax['max']);
    });

    test('closed props list: per type exactly the keys in the artifact', () {
      final byWidget = _list(_obj(block['props'])['byWidget']).cast<_Json>();
      expect({for (final entry in byWidget) entry['type']! as String: _list(entry['props'])}, kResponsiveProps);
    });

    test('capabilities are named with version 9.18.0', () {
      final features = _obj(_obj(_schema['x-compatibility'])['features']);
      for (final key in ['widthClassVisibility', 'widthClassStyle', 'widthClassProps', 'screenContentMaxWidth']) {
        expect(features[key], '9.18.0', reason: key);
      }
    });
  });

  // ───────────────────────────── reader behaviour ─────────────────────────────

  group('reader: tree cache, state on class change, tolerance', () {
    UiDocument adaptive() => _document(
      _screenRoot([
        {
          'id': 'a',
          'type': 'Container',
          'props': {'direction': 'column'},
          'style': {'height': 10},
          'propsOn': {'expanded': {'gap': 'lg'}},
        },
        {
          'id': 'b',
          'type': 'TextField',
          'props': {
            'label': {'kind': 'literal', 'value': 'name'},
            'value': {'kind': 'binding', 'path': 'form.name'},
          },
        },
      ]),
    );

    test('the tree is resolved once per class: the same object on a repeated query', () {
      final screen = adaptive().screens.single;
      expect(screen.rootIn(WidthClass.expanded), same(screen.rootIn(WidthClass.expanded)));
      expect(screen.rootIn(WidthClass.compact), same(screen.root));
      expect(screen.rootIn(WidthClass.medium), same(screen.rootIn(WidthClass.medium)));
    });

    test('a document without adaptivity gets no copy: the same root in every class', () {
      final screen = _document(_screenRoot([
        {'id': 'a', 'type': 'Container', 'props': {'direction': 'column'}},
      ])).screens.single;
      for (final widthClass in WidthClass.values) {
        expect(screen.rootIn(widthClass), same(screen.root));
      }
    });

    testWidgets('a class change does not lose what was typed in the field or the focus', (tester) async {
      _view(tester, 393, 800);
      await pumpDocument(tester, adaptive());
      await tester.enterText(find.byType(EditableText), 'Ann');
      await tester.pump();
      final focusBefore = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
      expect(focusBefore.hasFocus, isTrue);
      // Rotation: the box became tablet-sized, the class changed, the screen is the same.
      _view(tester, 1280, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, 'Ann');
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('the class is measured by the box the screen stands in, not by the window', (tester) async {
      _view(tester, 1280, 800);
      final doc = _document(_screenRoot([
        {
          'id': 'wide',
          'type': 'Container',
          'props': {'direction': 'column'},
          'style': {'background': _bg(1), 'height': 10},
          'showOn': ['expanded'],
        },
        {
          'id': 'narrow',
          'type': 'Container',
          'props': {'direction': 'column'},
          'style': {'background': _bg(2), 'height': 10},
          'showOn': ['compact'],
        },
      ]));
      Future<void> pumpIn(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: renderDocument(doc, theme: RenderTheme.fallback(), data: const {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      // The window is 1280, but the screen stands in a 400 column: that is `compact`.
      await pumpIn(400);
      expect(_box(2), findsOneWidget);
      expect(_box(1), findsNothing);
      await pumpIn(1100);
      expect(_box(1), findsOneWidget);
      expect(_box(2), findsNothing);
    });

    testWidgets('hostile shapes do not break the reader: showOn, styleOn, propsOn of the wrong shape', (tester) async {
      _view(tester, 1280, 800);
      final hostile = <_Json>[
        {'showOn': 'expanded'},
        {'showOn': [1, null, {}]},
        {'showOn': <Object?>[]},
        {'styleOn': 5},
        {'styleOn': {'expanded': 'x', 'medium': null, 'huge': {'padding': 'xl'}}},
        {'propsOn': 'wide'},
        {'propsOn': {'expanded': 7}},
        {'propsOn': {'expanded': {'gap': {'a': 1}, 'columns': 'many', 'direction': 3}}},
        {'propsOn': {'__proto__': {'gap': 'xl'}, 'constructor': {'gap': 'xl'}}},
      ];
      for (final fields in hostile) {
        await pumpDocument(
          tester,
          _document(_screenRoot([
            {
              'id': 'g',
              'type': 'Grid',
              'props': {'columns': 2},
              ...fields,
              'children': [
                {'id': 'k', 'type': 'Container', 'props': {'direction': 'column'}, 'style': {'height': 10}},
              ],
            },
          ])),
        );
        expect(tester.takeException(), isNull, reason: '$fields');
      }
    });
  });
}

/// A table node with what the builder's `createDefaultNode` adds to a freshly
/// created node: the reader does not require it, but the canvas otherwise draws an empty screen.
_Json _nodeWithDefaults(_Json spec, String id) {
  final type = spec['type']! as String;
  final props = <String, Object?>{
    ...switch (type) {
      'Grid' => {'columns': 2, 'gap': 'sm'},
      'Container' => {'direction': 'column', 'gap': 'sm'},
      'Column' => {'gap': 'sm', 'align': 'start'},
      'Row' => {'gap': 'sm', 'align': 'center', 'justify': 'start', 'wrap': false},
      'Repeater' => {'source': 'tasks', 'item': 'task', 'gap': 'sm'},
      'Divider' => {'orientation': 'horizontal'},
      'Text' => {'content': {'kind': 'literal', 'value': 'x'}},
      _ => <String, Object?>{},
    },
    ...?(spec['props'] as Map?)?.cast<String, Object?>(),
  };
  return {
    'id': id,
    ...spec,
    'props': props,
    if (spec['children'] is List)
      'children': [for (final (i, c) in (spec['children']! as List).indexed) _nodeWithDefaults((c as Map).cast<String, Object?>(), '$id-$i')],
  };
}
