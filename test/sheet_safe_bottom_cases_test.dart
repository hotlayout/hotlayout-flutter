/// The bottom safe inset of a modal sheet (schema 9.31.0, `x-style.layout.sheetSafeBottom`): the shared table
/// `fixtures/sheet-safe-bottom/sheet-safe-bottom-cases.json`. Every row runs through the pure rules; the rows whose
/// inset is a real number also run through the real widgets with the inset given the way a phone gives it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/sheet_safe_bottom.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

typedef _Json = Map<String, Object?>;

final _Json _table =
    (json.decode(
              File(
                'assets/contract/fixtures/sheet-safe-bottom/sheet-safe-bottom-cases.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();
final _Json _schema =
    (json.decode(File('assets/contract/screen-schema.json').readAsStringSync())
            as Map)
        .cast<String, Object?>();

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();
_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
double _num(Object? value) => (value! as num).toDouble();
Matcher _near(num expected) => closeTo(expected.toDouble(), 0.01);

_Json _literal(String text) => {'kind': 'literal', 'value': text};

_Json _screen(
  String id,
  List<_Json> children, {
  String? presentation,
  Object? placement,
}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'modalPlacement': ?placement,
  'root': {
    'id': '$id-root',
    'type': 'Screen',
    'props': {'gap': 'none'},
    'style': {'background': 'surface'},
    'children': children,
  },
};

/// A page with one button that opens the layer, and the layer with a content box of [contentHeight] and, when
/// asked, a pinned block.
UiDocument _document({
  double? contentHeight,
  bool withLast = true,
  required bool pinned,
  Object? placement,
}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'sheet-safe-bottom',
  'name': 'sheet-safe-bottom',
  'initialScreenId': 'page',
  'screens': [
    _screen('page', [
      {
        'id': 'open',
        'type': 'Button',
        'props': {
          'label': _literal('Open'),
          'variant': 'primary',
          'action': {
            'type': 'navigate',
            'params': {'screenId': 'layer'},
          },
        },
      },
    ]),
    _screen(
      'layer',
      [
        if (contentHeight != null)
          {
            'id': 'content',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'height': contentHeight},
            'children': const <Object?>[],
          },
        // The last node of the sheet: the pinned block when there is one, otherwise the last child of the body.
        if (withLast)
          {
            'id': 'last',
            'type': 'Text',
            'props': {'content': _literal('Last')},
            'pin': ?(pinned ? 'bottom' : null),
          },
      ],
      presentation: 'modal',
      placement: placement,
    ),
  ],
});

Future<void> _open(
  WidgetTester tester,
  UiDocument doc, {
  required double width,
  required double height,
  required double bottom,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  tester.view.viewPadding = FakeViewPadding(bottom: bottom);
  tester.view.padding = FakeViewPadding(bottom: bottom);
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: renderDocument(
          doc,
          theme: RenderTheme.fallback(),
          data: const {},
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test('the table is read in full', () {
    expect(_rows('placementCases'), hasLength(19));
    expect(_rows('geometryCases'), hasLength(6));
    expect(_rows('ruleCases'), hasLength(8));
  });

  group('placementCases', () {
    for (final row in _rows('placementCases')) {
      final input = _obj(row['input']);
      final expected = _obj(row['expect']);

      test('rule: ${row['name']}', () {
        final place = sheetSafeBottomOf(
          presentation: input['presentation'],
          modalPlacement: input['modalPlacement'],
          areaWidth: _num(input['areaWidth']),
          safeBottom: input['safeBottom'],
          bottomZone: input['bottomZone']! as bool,
        );
        expect(place.root, _near(_num(expected['root'])));
        expect(place.zone, _near(_num(expected['zone'])));
      });

      final inset = input['safeBottom'];
      // The widget runs only for a layer and an inset a phone can give: a string or a negative number is not an inset.
      if (input['presentation'] != 'modal' || inset is! num || inset < 0) {
        continue;
      }

      testWidgets('widget: ${row['name']}', (tester) async {
        final doc = _document(
          pinned: input['bottomZone']! as bool,
          placement: input['modalPlacement'],
        );
        await _open(
          tester,
          doc,
          width: _num(input['areaWidth']),
          height: 852,
          bottom: inset.toDouble(),
        );
        final layer = tester.getRect(find.byKey(kModalLayerKey));
        // The whole inset, root and zone together, lies under the last node and only once; a window and a sheet shown
        // as a window have none of it inside the layer. The text box is the node: nothing else lies under it.
        final total = _num(expected['root']) + _num(expected['zone']);
        expect(
          layer.bottom - tester.getRect(find.text('Last')).bottom,
          _near(total),
          reason: row['name']! as String,
        );
      });
    }
  });

  group('geometryCases', () {
    for (final row in _rows('geometryCases')) {
      final input = _obj(row['input']);
      final expected = _obj(row['expect']);

      test('rule: ${row['name']}', () {
        final box = sheetBoxOf(
          areaHeight: _num(input['areaHeight']),
          contentHeight: _num(input['contentHeight']),
          safeBottom: input['safeBottom'],
        );
        expect(box.y, _near(_num(expected['y'])));
        expect(box.height, _near(_num(expected['height'])));
        expect(box.contentBottom, _near(_num(expected['contentBottom'])));
        expect(box.scrolls, expected['scrolls']);
      });

      final inset = input['safeBottom'];
      if (inset is! num) {
        continue;
      }

      testWidgets('widget: ${row['name']}', (tester) async {
        final doc = _document(
          contentHeight: _num(input['contentHeight']),
          withLast: false,
          pinned: false,
        );
        await _open(
          tester,
          doc,
          width: 393,
          height: _num(input['areaHeight']),
          bottom: inset.toDouble(),
        );
        final layer = tester.getRect(find.byKey(kModalLayerKey));
        expect(layer.top, _near(_num(expected['y'])));
        expect(layer.height, _near(_num(expected['height'])));
        // The bottom of the layer is the bottom of the area: the box reaches the physical bottom.
        expect(layer.bottom, _near(_num(input['areaHeight'])));
        // The box is the content plus the inset, so the content stands `contentBottom` below the top of the box.
        expect(
          layer.height - _num(expected['contentBottom']),
          _near(_num(input['safeBottom']).clamp(0, _num(input['areaHeight']))),
        );
      });
    }
  });

  group('ruleCases: the data of the artifact', () {
    final block = _obj(
      _obj(_obj(_schema['x-style'])['layout'])['sheetSafeBottom'],
    );
    for (final row in _rows('ruleCases')) {
      test(row['name']! as String, () {
        Object? at = block;
        for (final key in (row['rule']! as String).split('.')) {
          at = _obj(at)[key];
        }
        expect(at, row['expect']);
      });
    }

    test('the capability is in the catalog from 9.31.0', () {
      expect(kFeatureCatalog['sheetSafeBottom'], '9.31.0');
      expect(supportsFeature('sheetSafeBottom'), isTrue);
      expect(
        supportsFeature('sheetSafeBottom', readerVersion: '9.30.0'),
        isFalse,
      );
    });
  });
}
