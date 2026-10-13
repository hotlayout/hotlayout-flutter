/// THE ICON FROM DATA (schema 9.19.0, `x-iconFromData`): `iconPath` beside the icon of a document.
///
/// The shared table (`assets/contract/fixtures/icon-text/icon-text-cases.json`) runs row by row:
///
///  1. `iconPathCases` (22) -- which icon is meant (the rule), and what a REAL node draws with the data of the row:
///     an icon of the set, an empty box of the same size, or nothing; whether the drawing is mirrored in a screen
///     written right to left; the order of the parts of a button and a badge;
///  2. `iconPathDocumentCases` (9) -- every node is read and drawn without a crash, whatever the builder's verdict.
///
/// The model is the builder's `scripts/icon-text-cases.test.tsx` (the `iconPath…` groups).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/icon_from_data.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/icon_box.dart';
import 'package:hotlayout_flutter/src/render/icon_glyph.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/icon-text/icon-text-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json _obj(Object? value) => (value! as Map<Object?, Object?>).cast<String, Object?>();

const _Json _label = {'kind': 'literal', 'value': 'Label'};

/// The node of the row's widget with the row's props and the props that widget needs to be drawn at all.
_Json _nodeOf(String widget, _Json props) => switch (widget) {
  'Icon' => {'id': 'n', 'type': 'Icon', 'props': props},
  'Button' => {
    'id': 'n',
    'type': 'Button',
    'props': {'label': _label, 'variant': 'primary', 'action': {'type': 'none'}, 'fullWidth': false, ...props},
  },
  'Badge' => {
    'id': 'n',
    'type': 'Badge',
    'props': {'label': _label, 'tone': 'neutral', ...props},
  },
  'IconButton' => {
    'id': 'n',
    'type': 'IconButton',
    'props': {'label': {'kind': 'literal', 'value': 'Back'}, 'variant': 'primary', 'size': 'md', 'action': {'type': 'none'}, ...props},
  },
  'ListTile' => {
    'id': 'n',
    'type': 'ListTile',
    'props': {'leading': {'kind': 'none'}, 'title': _label, 'trailing': {'kind': 'none'}, ...props},
  },
  _ => throw StateError('widget $widget'),
};

IconGlyphPainter? _painter(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(find.descendant(of: find.byType(IconBox), matching: find.byType(CustomPaint)))) {
    if (paint.painter case final IconGlyphPainter painter) return painter;
  }
  return null;
}

void main() {
  test('the table has the promised rows', () {
    expect(_rows('iconPathCases'), hasLength(22));
    expect(_rows('iconPathDocumentCases'), hasLength(9));
  });

  group('iconPathCases', () {
    for (final row in _rows('iconPathCases')) {
      final props = _obj(row['props']);
      final data = _obj(row['data']);
      final expected = _obj(row['expect']);
      final widget = row['widget']! as String;

      test('${row['name']} (the rule)', () {
        final documentIcon = props.containsKey(widget == 'Icon' ? 'name' : 'icon')
            ? IconToken.parse(props[widget == 'Icon' ? 'name' : 'icon'])
            : null;
        final icon = resolveIconToken(documentIcon, iconPathOf(props['iconPath']), (path) => data[path]);
        final resolved = expected['resolved'];
        if (resolved == null) {
          expect(icon, isNull, reason: 'no icon at all');
          return;
        }
        expect(icon, isNotNull);
        expect(icon!.isKnown, expected['box'] == 'drawn', reason: 'a name of the set is drawn, anything else is an empty box');
        if (icon.isKnown) expect(icon.wire, resolved);
        expect(icon.isKnown && icon.isMirrored, expected['mirrored'], reason: 'mirrored by the resolved name');
      });

      for (final direction in ['ltr', 'rtl']) {
        testWidgets('${row['name']} (a real node, $direction)', (tester) async {
          await pumpDocument(
            tester,
            docWith([_nodeOf(widget, props)]),
            data: data,
            locale: direction == 'rtl' ? 'ar' : 'en',
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final box = expected['box']! as String;
          if (box == 'none') {
            expect(find.byType(IconBox), findsNothing, reason: 'no icon, no box');
            return;
          }
          expect(find.byType(IconBox), findsOneWidget);
          final painter = _painter(tester);
          expect(painter != null, box == 'drawn', reason: 'drawn or an empty box of the same size');
          // The drawing is mirrored only in a screen written right to left, and by the resolved name.
          expect(painter?.mirrored ?? false, direction == 'rtl' && expected['mirrored'] == true, reason: 'mirrored');

          final logical = (expected['logical'] as List<Object?>?)?.cast<String>();
          if (logical != null) {
            final boxRect = tester.getRect(find.byType(IconBox));
            final textRect = tester.getRect(find.text('Label'));
            final iconFirst = direction == 'rtl' ? boxRect.center.dx > textRect.center.dx : boxRect.center.dx < textRect.center.dx;
            expect(iconFirst ? ['icon', 'text'] : ['text', 'icon'], logical, reason: 'the logical order of the parts');
          }
        });
      }
    }

    testWidgets('the path is read at the scope of the node: the record of each row of a list', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'list',
            'type': 'Repeater',
            'props': {'source': 'items', 'item': 'item'},
            'children': [_nodeOf('Icon', {'name': 'star', 'iconPath': 'item.icon'})],
          },
        ]),
        data: {
          'items': [
            {'icon': 'flame'},
            {'icon': 'no-such-icon'},
            <String, Object?>{},
          ],
        },
      );
      // Three rows: a drawn icon, an empty box, and the icon of the document for a row with no value.
      expect(find.byType(IconBox), findsNWidgets(3));
      final drawn = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((paint) => paint.painter).whereType<IconGlyphPainter>();
      expect(drawn, hasLength(2), reason: 'flame and the star of the document are drawn, the unknown name is an empty box');
    });
  });

  group('iconPathDocumentCases: every node is read and drawn without a crash', () {
    for (final row in _rows('iconPathDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await pumpDocument(
          tester,
          docWith([_nodeOf(row['widget']! as String, _obj(row['props']))]),
          data: const {'account.lastIcon': 'flame', 'account.balance': 12.5},
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a slot of a list row never takes the icon from data', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _nodeOf('ListTile', {
            'leading': {'kind': 'icon', 'icon': 'star', 'iconPath': 'account.lastIcon'},
            'trailing': {'kind': 'text', 'text': _label, 'icon': 'check', 'iconPath': 'account.lastIcon'},
          }),
        ]),
        data: const {'account.lastIcon': 'flame'},
      );
      final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((paint) => paint.painter).whereType<IconGlyphPainter>();
      expect(painters, hasLength(2), reason: 'the two slots draw their own icons');
    });
  });

  test('x-iconFromData: the prop names and the rules of the artifact', () {
    final block = _obj(_schema['x-iconFromData']);
    expect(_obj(block['props'])['path'], 'iconPath');
    expect(_obj(_obj(block['props'])['name']), {'Icon': 'name', 'Button': 'icon', 'Badge': 'icon', 'IconButton': 'icon'});
    expect(block['absentValue'], 'the-icon-of-the-document');
    expect(block['nullValue'], 'the-icon-of-the-document');
    expect(block['emptyString'], 'the-icon-of-the-document');
    expect(block['mirroring'], 'by-the-resolved-name');
    expect(block['withoutIconInDocument'], 'no-icon-the-path-is-not-read');
  });
}
