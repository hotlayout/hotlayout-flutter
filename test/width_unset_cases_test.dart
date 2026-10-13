/// "NOTHING" IN A WIDTH LAYER (schema 9.19.0, `x-style.layout.widthUnset`): the key `unset` of `styleOn` and of
/// `propsOn`.
///
/// The shared table (`assets/contract/fixtures/adaptive/adaptive-cases.json`, five new groups) runs row by row:
///
///  1. `unsetStyleCases` (14) -- the base style of a node on each class: what a layer removes is removed first, then
///     the layer is laid on; what is removed on `medium` stays removed on `expanded` until named again;
///  2. `unsetStateCases` (3) -- a state of the node is laid on top of that and may name a removed field;
///  3. `unsetPropsCases` (7) -- the same for the properties the contract lets a layer remove (today the content width
///     of a screen); a property with a word of its own is not removed by the key;
///  4. `unsetDocumentCases` (12) and `unsetScreenCases` (5) -- every document is read and drawn at every width
///     without a crash, whatever the builder's verdict; a real screen loses its content limit on `expanded`.
///
/// The model is the builder's `scripts/adaptive-cases.test.tsx` (the `unset…` groups).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/width_class.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

final Json _table = jsonDecode(File('assets/contract/fixtures/adaptive/adaptive-cases.json').readAsStringSync()) as Json;
final Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Json;

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();

WidthClass _class(Object? wire) => WidthClass.values.firstWhere((value) => value.wire == wire);

ChildNode _child(Json fields, WidthClass widthClass) =>
    UiNode.parse({'id': 'node', 'type': 'Container', 'props': <String, Object?>{}, ...fields}, widthClass: widthClass) as ChildNode;

void _sameStyle(NodeStyle? actual, Object? expected, String reason) {
  final want = NodeStyle.parse(expected);
  if (want == null) {
    expect(actual, isNull, reason: reason);
    return;
  }
  expect(actual, isNotNull, reason: reason);
  expect(actual!.color, want.color, reason: '$reason: color');
  expect(actual.padding, want.padding, reason: '$reason: padding');
  expect(actual.background, want.background, reason: '$reason: background');
  expect(actual.maxWidth?.toString(), want.maxWidth?.toString(), reason: '$reason: maxWidth');
  expect(actual.isEmpty, want.isEmpty);
}

Json _document(Json root) => {
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'unset',
  'name': 'unset',
  'initialScreenId': 's',
  'screens': [
    {'screenId': 's', 'name': 's', 'root': root},
  ],
};

void main() {
  test('the table has the promised rows', () {
    expect(_rows('unsetStyleCases'), hasLength(14));
    expect(_rows('unsetStateCases'), hasLength(3));
    expect(_rows('unsetPropsCases'), hasLength(7));
    expect(_rows('unsetDocumentCases'), hasLength(12));
    expect(_rows('unsetScreenCases'), hasLength(5));
  });

  group('unsetStyleCases: the base style on each class', () {
    for (final row in _rows('unsetStyleCases')) {
      test(row['name']! as String, () {
        final node = asJson(row['node']);
        final expected = asJson(row['expected']);
        for (final widthClass in WidthClass.values) {
          _sameStyle(_child(node, widthClass).style, expected[widthClass.wire], '${row['name']} on ${widthClass.wire}');
        }
      });
    }
  });

  group('unsetStateCases: a state is laid on top', () {
    for (final row in _rows('unsetStateCases')) {
      test(row['name']! as String, () {
        final node = _child(asJson(row['node']), _class(row['widthClass']));
        final data = ScreenData({'task': {'completed': row['met'] == true}});
        _sameStyle(resolveNodeStyle(node.style, node.styleWhen, data), row['expected'], row['name']! as String);
      });
    }
  });

  group('unsetPropsCases: the properties on each class', () {
    for (final row in _rows('unsetPropsCases')) {
      test(row['name']! as String, () {
        final node = asJson(row['node']);
        final expected = asJson(row['expected']);
        for (final widthClass in WidthClass.values) {
          final got = effectivePropsOf(node['type']! as String, asJson(node['props']), node['propsOn'], widthClass);
          expect(got.props[row['prop']], expected[widthClass.wire], reason: '${row['name']} on ${widthClass.wire}');
        }
      });
    }

    test('the properties a layer may remove are the artifact\'s', () {
      final block = asJson(asJson(asJson(_schema['x-style'])['layout'])['widthUnset']);
      final byWidget = (asJson(block['props'])['byWidget']! as List<Object?>).cast<Json>();
      expect({for (final entry in byWidget) entry['type']! as String: (entry['props']! as List<Object?>).cast<String>()}, kUnsettableProps);
      expect(block['prop'], 'unset');
      expect(block['in'], ['styleOn', 'propsOn']);
      expect(block['order'], ['remove-the-fields-named-for-the-class', 'then-lay-the-layer-of-the-class']);
      expect(asJson(block['namedAndRemovedInOneLayer'])['reader'], 'the-named-value-wins');
      expect(block['malformed'], 'nothing-is-removed');
    });
  });

  group('unsetDocumentCases: every document is read and drawn at every width', () {
    for (final row in _rows('unsetDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final node = {'id': 'node', 'props': <String, Object?>{}, ...asJson(row['node'])};
        for (final width in [393.0, 768.0, 1280.0]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1200);
          addTearDown(tester.view.reset);
          await pumpDocument(
            tester,
            UiDocument.fromJson(_document({'id': 'root', 'type': 'Screen', 'props': {'gap': 'none'}, 'children': [node]})),
          );
          expect(tester.takeException(), isNull, reason: 'width $width');
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  group('unsetScreenCases: the root of the screen', () {
    for (final row in _rows('unsetScreenCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final fields = asJson(row['root']);
        for (final width in [393.0, 768.0, 1280.0]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1200);
          addTearDown(tester.view.reset);
          await pumpDocument(
            tester,
            UiDocument.fromJson(_document({'id': 'root', 'type': 'Screen', ...fields, 'props': {'gap': 'none', ...asJson(fields['props'])}, 'children': [textNode('Hello')]})),
          );
          expect(tester.takeException(), isNull, reason: 'width $width');
          await tester.pumpWidget(const SizedBox());
        }
      });
    }

    testWidgets('a real screen: the content limit is there on medium and gone on expanded', (tester) async {
      final root = {
        'id': 'root',
        'type': 'Screen',
        'props': {'gap': 'none', 'contentMaxWidth': 400},
        'propsOn': {'unset': {'expanded': ['contentMaxWidth']}},
        'children': [textNode('Hello', style: {'background': {'kind': 'color', 'color': 'surface'}})],
      };
      Future<double> contentWidth(double width) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1200);
        addTearDown(tester.view.reset);
        await pumpDocument(tester, UiDocument.fromJson(_document(root)));
        final size = tester.getSize(find.text('Hello'));
        await tester.pumpWidget(const SizedBox());
        return size.width;
      }

      expect(await contentWidth(768), lessThanOrEqualTo(400), reason: 'the limit holds on medium');
      expect(await contentWidth(1280), greaterThan(400), reason: 'the limit is removed on expanded');
    });
  });
}
