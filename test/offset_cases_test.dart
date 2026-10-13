/// Offset overlays (schema 9.10.0): `layer` on a stack child and `pull` on a
/// flow child.
///
/// The tests read the contract table itself
/// (`assets/contract/fixtures/offset/offset-cases.json`, a copy of
/// `contract/fixtures/offset/offset-cases.json`) and run EVERY reader-relevant
/// row twice: through the reader's reference formula
/// (`lib/src/model/offset_rules.dart`, `layout_rules.dart`) and through a REAL widget.
///
///  1. `layerCases` (12) - rectangle, angle, hit, overhang: the formula, then
///     a real document in both writing directions; tap points are checked by
///     Flutter's real hit test (`hitTestOnBinding`), not by the formula;
///  2. `layerReadCases` (21) - what the reader takes from the field value;
///  3. `layerPlaceCases` (8) - where the field is read and who sizes the stack;
///  4. `layerDocumentCases` (16) - the constructor validator's reference: the
///     reader parses and draws such a document without failing, and reads
///     exactly as much as the read table says;
///  5. `pullCases` (10) - flow arithmetic: the formula, then a real column and
///     a real row (both directions);
///  6. `pullReadCases` (19) - where `pull` is read and along which axis;
///  7. `pullDocumentCases` (11) - the same as (4), for `pull`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/bottom_zone_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/layout_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/offset_rules.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/layer_place.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
List<_Json> _rows(String key) => (_table[key]! as List).map(_obj).toList();

final _Json _table =
    jsonDecode(File('assets/contract/fixtures/offset/offset-cases.json').readAsStringSync()) as _Json;

final Map<String, double> _spacing = {
  for (final entry in _obj(_obj(_table['tokens'])['spacing']).entries) entry.key: (entry.value! as num).toDouble(),
};

double _px(Object by) => by is String ? _spacing[by]! : (by as num).toDouble();

AlignToken _word(Object? raw) => AlignToken.values.firstWhere((token) => token.wire == raw);

Rect _rect(_Json json) => Rect.fromLTWH(
  (json['x']! as num).toDouble(),
  (json['y']! as num).toDouble(),
  (json['width']! as num).toDouble(),
  (json['height']! as num).toDouble(),
);

Size _size(_Json json) => Size((json['width']! as num).toDouble(), (json['height']! as num).toDouble());

/// Device: logical pixels, so table coordinates are screen coordinates.
void _view(WidgetTester tester, [double width = 800, double height = 900]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

Map<String, Object?> _filled(String id, {double? width, double? height, Map<String, Object?> node = const {}}) => {
  'id': id,
  'type': 'Container',
  'props': {'direction': 'column', 'gap': 'none'},
  'style': {
    'width': ?width,
    'height': ?height,
    'background': colorBackground('primary'),
  },
  ...node,
};

Map<String, Object?> _stackNode(
  String id,
  List<Map<String, Object?>> children, {
  String alignHorizontal = 'center',
  String alignVertical = 'center',
  Size? size,
  Map<String, Object?> node = const {},
}) => {
  'id': id,
  'type': 'Stack',
  'props': {'alignHorizontal': alignHorizontal, 'alignVertical': alignVertical},
  if (size != null) 'style': {'width': size.width, 'height': size.height},
  'children': children,
  ...node,
};

/// Parses a node into a tree together with its parent, as a document does.
({UiNode parent, List<ChildNode> children}) _parseFamily(String parentType, Map<String, Object?> parentProps, List<Map<String, Object?>> children, {String? nodeType}) {
  final raw = {
    'id': 'parent',
    'type': parentType,
    'props': parentProps,
    'children': [
      for (var i = 0; i < children.length; i++)
        {
          'id': 'child$i',
          'type': nodeType ?? 'Container',
          'props': nodeType == 'AppBar' ? {'title': {'kind': 'literal', 'value': 'Title'}, 'showBack': false} : const {},
          ...children[i],
        },
    ],
  };
  // `Screen` is parsed separately from the rest: it is never a child.
  final parent = UiNode.parse(parentType == 'Grid' ? {...raw, 'props': {'columns': 2, ...parentProps}} : raw);
  return (parent: parent, children: parent.children);
}

/// The nearest ancestor of this object whose parent is [parentIs]: the node box in
/// the flow, however many wrappers (padding, size, column stretch) lie between.
///
/// [nth] - which match counts (from the label upward): the label itself sits in the column
/// of its card, so a column needs the SECOND match - the card itself.
RenderBox _flowChild(WidgetTester tester, String label, bool Function(RenderObject parent) parentIs, {int nth = 0}) {
  RenderObject? node = tester.renderObject(find.text(label));
  var seen = 0;
  while (node != null) {
    if (node.parent != null && parentIs(node.parent!)) {
      if (seen == nth) break;
      seen += 1;
    }
    node = node.parent;
  }
  expect(node, isNotNull, reason: 'flow of child "$label" not found');
  return node! as RenderBox;
}

bool _inside(RenderObject? target, RenderObject ancestor) {
  for (var node = target; node != null; node = node.parent) {
    if (identical(node, ancestor)) return true;
  }
  return false;
}

/// Whether anyone inside [subtree] receives a tap at this (global) point -
/// Flutter's real hit test over the whole tree, not a formula.
bool _hits(WidgetTester tester, Offset global, RenderObject subtree) {
  final result = tester.hitTestOnBinding(global);
  return result.path.any((entry) => entry.target is RenderObject && _inside(entry.target as RenderObject, subtree));
}

void main() {
  group('table is read', () {
    test('seven groups, ninety-nine rows, tokens are the built-in theme spacings', () {
      expect(
        [for (final key in ['layerCases', 'layerReadCases', 'layerPlaceCases', 'layerDocumentCases', 'pullCases', 'pullReadCases', 'pullDocumentCases']) _rows(key).length],
        [12, 21, 10, 16, 10, 20, 12],
      );
      final theme = RenderTheme.fallback();
      for (final entry in _spacing.entries) {
        expect(theme.spacing[entry.key], entry.value, reason: 'token ${entry.key}: the table and the built-in theme disagree');
      }
    });
  });

  // ───────────────────────────── layerReadCases ─────────────────────────────

  group('layerReadCases: what the reader takes from the field value', () {
    for (final row in _rows('layerReadCases')) {
      test(row['name']! as String, () {
        final read = readLayerValue(row['value']);
        final expected = row['expect'];
        if (expected == null) {
          expect(read, isNull);
          return;
        }
        final want = _obj(expected);
        expect(read, isNotNull);
        expect(read!.alignHorizontal?.wire, want['alignHorizontal']);
        expect(read.alignVertical?.wire, want['alignVertical']);
        void axis(LayerAxisOffset? actual, Object? wanted) {
          if (wanted == null) {
            expect(actual, isNull);
            return;
          }
          final json = _obj(wanted);
          expect(actual, isNotNull);
          expect(actual!.toward, json['toward']);
          final by = json['by'];
          expect(actual.by.token ?? actual.by.value, by is num ? by.toDouble() : by);
        }

        axis(read.offsetX, want['offsetX']);
        axis(read.offsetY, want['offsetY']);
        expect(read.rotate, want['rotate']);
      });
    }

    test('a document with an unreadable field is parsed by the same reading', () {
      // The node from the read table goes through real parsing, not just the function.
      for (final row in _rows('layerReadCases')) {
        final family = _parseFamily('Stack', const {}, [
          const {},
          {'layer': row['value']},
        ]);
        expect(family.children[1].layer == null, row['expect'] == null, reason: row['name']! as String);
      }
    });
  });

  // ───────────────────────────── layerPlaceCases ────────────────────────────

  group('layerPlaceCases: where the field is read and who sizes the stack', () {
    for (final row in _rows('layerPlaceCases')) {
      test(row['name']! as String, () {
        final children = (row['children']! as List).map(_obj).toList();
        final family = _parseFamily(row['parent']! as String, const {}, children);
        final overlays = (row['overlays']! as List).cast<bool>();
        final sizes = (row['sizesStack']! as List).cast<bool>();
        for (var i = 0; i < children.length; i++) {
          expect(readerLayerOf(family.children[i], family.parent) != null, overlays[i], reason: 'overlay #$i');
          expect(sizesStack(family.children[i], family.parent), sizes[i], reason: 'stack size #$i');
        }
      });
    }
  });

  // Rows with the `hidden` field: "the stack has a sizing layer" is counted
  // by the DOCUMENT. Real screen: a sizing layer hidden by a condition does not turn overlays
  // into sizing layers - the stack has zero size, and the overlay stays an overlay.
  group('layerPlaceCases with hidden: real widget', () {
    for (final row in _rows('layerPlaceCases').where((row) => row['hidden'] != null)) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester, 320, 568);
        final children = (row['children']! as List).map(_obj).toList();
        final hidden = (row['hidden']! as List).cast<bool>();
        final overlays = (row['overlays']! as List).cast<bool>();
        final doc = UiDocumentBuilder.bare([
          _stackNode('stack', [
            for (var i = 0; i < children.length; i++)
              _filled('n$i', width: 40, height: 20, node: {
                ...children[i],
                // Really "hidden now": a condition without data is not met.
                if (hidden[i]) 'visibleIf': {'path': 'user.isPremium', 'op': 'isTrue'},
              }),
          ], size: null),
        ]);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);

        // How many overlays are drawn: the reader positions them relative to the stack box.
        final drawnOverlays = [for (var i = 0; i < children.length; i++) if (overlays[i] && !hidden[i]) i];
        expect(find.byType(LayerPlace), findsNWidgets(drawnOverlays.length), reason: 'overlays stay overlays');
        final sizers = row['visibleSizers']! as int;
        final stack = tester.getSize(find.ancestor(of: find.byType(LayerPlace), matching: find.byType(Stack)).first);
        if (sizers == 0) {
          expect(stack.height, 0, reason: 'sizing layer hidden: zero-size stack');
        } else {
          expect(stack.height, 20, reason: 'a visible sizing layer sizes the stack');
        }
      });
    }
  });

  // ──────────────────────────────── layerCases ──────────────────────────────

  group('layerCases: formula', () {
    for (final row in _rows('layerCases')) {
      for (final direction in ['ltr', 'rtl']) {
        test('${row['name']} — $direction', () {
          final side = _obj(row[direction]);
          final stackAlign = _obj(row['stackAlign']);
          final placement = readLayerValue(row['layer'])!;
          final geometry = layerGeometry(
            LayerGeometryInput(
              stack: _size(_obj(row['stack'])),
              layer: _size(_obj(row['size'])),
              alignHorizontal: placement.alignHorizontal ?? _word(stackAlign['horizontal']),
              alignVertical: placement.alignVertical ?? _word(stackAlign['vertical']),
              offsetXToward: placement.offsetX?.toward,
              offsetX: placement.offsetX == null ? 0 : _px(placement.offsetX!.by.token ?? placement.offsetX!.by.value!),
              offsetYToward: placement.offsetY?.toward,
              offsetY: placement.offsetY == null ? 0 : _px(placement.offsetY!.by.token ?? placement.offsetY!.by.value!),
              rotate: placement.rotate,
              rtl: direction == 'rtl',
            ),
          );
          final want = _rect(_obj(side['rect']));
          expect(geometry.rect.left, closeTo(want.left, 1e-9));
          expect(geometry.rect.top, closeTo(want.top, 1e-9));
          expect(geometry.rect.width, closeTo(want.width, 1e-9));
          expect(geometry.rect.height, closeTo(want.height, 1e-9));
          expect(geometry.angle, closeTo((side['angle']! as num).toDouble(), 1e-9));
          expect(geometry.protrudes, row['protrudes']);
          for (final tap in (side['taps']! as List).map(_obj)) {
            final point = Offset((tap['x']! as num).toDouble(), (tap['y']! as num).toDouble());
            expect(layerContainsPoint(geometry, point), tap['hits'], reason: 'point $point');
          }
        });
      }
    }
  });

  group('layerCases: real widget', () {
    for (final row in _rows('layerCases')) {
      for (final direction in ['ltr', 'rtl']) {
        testWidgets('${row['name']} — $direction', (tester) async {
          _view(tester);
          final stackSize = _size(_obj(row['stack']));
          final stackAlign = _obj(row['stackAlign']);
          final side = _obj(row[direction]);
          final layerSize = _size(_obj(row['size']));
          final doc = UiDocumentBuilder.bare([
            _stackNode(
              'stack',
              [
                // The layer that sizes the stack (required in a stack, `noSizingLayer`).
                {'id': 'sizer', 'type': 'Container', 'props': const {}},
                _filled('overlay', width: layerSize.width, height: layerSize.height, node: {'layer': row['layer']}),
              ],
              alignHorizontal: stackAlign['horizontal']! as String,
              alignVertical: stackAlign['vertical']! as String,
              size: stackSize,
            ),
          ]);
          await pumpDocument(tester, doc, locale: direction == 'rtl' ? 'ar' : 'en');
          expect(tester.takeException(), isNull);

          final place = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace));
          // An overlay does not change the stack size.
          expect(place.size, stackSize);
          final geometry = place.geometry!;
          final want = _rect(_obj(side['rect']));
          expect(geometry.rect.left, closeTo(want.left, 1e-6));
          expect(geometry.rect.top, closeTo(want.top, 1e-6));
          expect(geometry.rect.size.width, closeTo(want.width, 1e-6));
          expect(geometry.rect.size.height, closeTo(want.height, 1e-6));
          expect(geometry.angle, closeTo((side['angle']! as num).toDouble(), 1e-6));
          expect(geometry.protrudes, row['protrudes']);

          // The layer is really DRAWN where the formula says: the centre and the corner of the
          // child's matrix in stack coordinates.
          final child = place.child!;
          expect(child.size, layerSize);
          final matrix = child.getTransformTo(place);
          final center = MatrixUtils.transformPoint(matrix, child.size.center(Offset.zero));
          expect(center.dx, closeTo(want.center.dx, 1e-6));
          expect(center.dy, closeTo(want.center.dy, 1e-6));
          final drawnAngle = math.atan2(matrix.storage[1], matrix.storage[0]) * 180 / math.pi;
          expect(drawnAngle, closeTo((side['angle']! as num).toDouble(), 1e-6));

          // Taps use the real hit test over the whole tree.
          for (final tap in (side['taps']! as List).map(_obj)) {
            final point = Offset((tap['x']! as num).toDouble(), (tap['y']! as num).toDouble());
            final global = place.localToGlobal(point);
            expect(_hits(tester, global, child), tap['hits'], reason: 'point $point (in stack coordinates)');
          }
        });
      }
    }

    testWidgets('the stack itself does not clip: Clip.none', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode('stack', [
          _filled('base', width: 48, height: 48),
          _filled('badge', width: 20, height: 16, node: {
            'layer': {
              'alignHorizontal': 'end',
              'alignVertical': 'start',
              'offset': {
                'x': {'toward': 'end', 'by': 'xs'},
                'y': {'toward': 'top', 'by': 'xs'},
              },
            },
          }),
        ]),
      ]);
      await pumpDocument(tester, doc);
      final stack = tester.widget<Stack>(find.ancestor(of: find.byType(LayerPlace), matching: find.byType(Stack)).first);
      expect(stack.clipBehavior, Clip.none);
    });
  });

  // ─────────────────────────── stack: size and propagation ─────────────────────

  group('an overlay does not size the stack', () {
    testWidgets('an overlay taller and wider than the stack does not stretch it', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
          'children': [
            _stackNode('stack', [
              _filled('base', width: 30, height: 20),
              _filled('big', width: 60, height: 50, node: {'layer': const <String, Object?>{}}),
            ]),
          ],
        },
      ]);
      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
      final place = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace));
      // The stack follows the layer without `layer`; the overlay width is at most the stack's (30), its height is its own.
      expect(place.size, const Size(30, 20));
      expect(place.child!.size.width, 30);
      expect(place.child!.size.height, 50);
    });

    testWidgets('a long overlay label wraps at the stack width, with natural height', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode(
          'stack',
          [
            _filled('base', width: 120, height: 20),
            {
              'id': 'caption',
              'type': 'Text',
              'props': {
                'content': {'kind': 'literal', 'value': 'A very long caption that cannot fit on one line of a narrow stack'},
                'align': 'start',
                'overflow': 'visible',
              },
              'layer': {'alignVertical': 'start'},
            },
          ],
          size: const Size(120, 20),
        ),
      ]);
      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
      final place = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace));
      expect(place.child!.size.width, lessThanOrEqualTo(120));
      expect(place.child!.size.height, greaterThan(20), reason: 'natural height, not limited by the stack');
    });

    for (final row in [
      (name: 'outside a stack (column) the field is not read', parent: 'Column'),
      (name: 'in a grid cell the field is not read', parent: 'Grid'),
    ]) {
      testWidgets(row.name, (tester) async {
        _view(tester);
        final doc = UiDocumentBuilder.bare([
          {
            'id': 'p',
            'type': row.parent,
            'props': row.parent == 'Grid' ? {'columns': 2, 'gap': 'none'} : {'gap': 'none'},
            'children': [
              _filled('a', width: 20, height: 20),
              _filled('b', width: 20, height: 20, node: {'layer': const <String, Object?>{}}),
            ],
          },
        ]);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);
        expect(find.byType(LayerPlace), findsNothing);
      });
    }

    testWidgets('`fill` beats `layer`; one stretched and one overlay - the overlay sizes as a plain layer', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode('stack', [
          _filled('base', width: 40, height: 40),
          _filled('both', node: {'fill': true, 'layer': {'alignHorizontal': 'end'}}),
        ]),
        _stackNode('only', [
          _filled('stretched', node: {'fill': true}),
          _filled('solo', width: 30, height: 30, node: {'layer': const <String, Object?>{}}),
        ]),
      ]);
      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
      // Neither stack has an overlay: in the first `fill` wins,
      // in the second there is no sizing layer - the field is read by neither.
      expect(find.byType(LayerPlace), findsNothing);
    });

    testWidgets('the sizing layer is hidden by a condition: an overlay stays an overlay only when something can size the stack', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode('stack', [
          _filled('base', width: 40, height: 40),
          _filled('badge', width: 10, height: 10, node: {'layer': const <String, Object?>{}}),
        ]),
      ]);
      await pumpDocument(tester, doc);
      expect(find.byType(LayerPlace), findsOneWidget);
    });

    testWidgets('an unreadable toward and a negative amount lose only their own axis; the rest applies', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode(
          'stack',
          [
            {'id': 'sizer', 'type': 'Container', 'props': const {}},
            _filled('badge', width: 10, height: 10, node: {
              'layer': {
                'alignHorizontal': 'start',
                'alignVertical': 'start',
                'offset': {
                  'x': {'toward': 'left', 'by': 4},
                  'y': {'toward': 'bottom', 'by': 6},
                },
                'rotate': 45.5,
              },
            }),
          ],
          size: const Size(50, 50),
        ),
      ]);
      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
      final geometry = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace)).geometry!;
      expect(geometry.rect.topLeft, const Offset(0, 6));
      expect(geometry.angle, 0);
    });

    testWidgets('an offset token the theme does not declare means no offset on that axis', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode(
          'stack',
          [
            {'id': 'sizer', 'type': 'Container', 'props': const {}},
            _filled('badge', width: 10, height: 10, node: {
              'layer': {
                'alignHorizontal': 'start',
                'alignVertical': 'start',
                'offset': {
                  'x': {'toward': 'end', 'by': 'huge'},
                  'y': {'toward': 'bottom', 'by': 'sm'},
                },
              },
            }),
          ],
          size: const Size(50, 50),
        ),
      ]);
      await pumpDocument(tester, doc);
      final geometry = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace)).geometry!;
      expect(geometry.rect.topLeft, const Offset(0, 8));
    });

    testWidgets('layer order is document order: an overlay written first lies under the rest', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _stackNode(
          'stack',
          [
            _filled('under', width: 30, height: 30, node: {'layer': const <String, Object?>{}}),
            _filled('base', width: 30, height: 30),
          ],
          size: const Size(30, 30),
        ),
      ]);
      await pumpDocument(tester, doc);
      final place = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace));
      final centre = place.localToGlobal(const Offset(15, 15));
      final path = tester.hitTestOnBinding(centre).path.map((e) => e.target).whereType<RenderObject>();
      // The top one is a plain layer (`base`): the overlay is not under the finger.
      expect(path.any((target) => _inside(target, place.child!)), isFalse);
    });

    testWidgets('real tap: an overlay button catches the touch where it is drawn, and not at the old place', (tester) async {
      _view(tester);
      final actions = <String>[];
      final doc = UiDocumentBuilder.bare([
        _stackNode(
          'stack',
          [
            _filled('base', width: 200, height: 120),
            {
              'id': 'info',
              'type': 'IconButton',
              'props': {
                'icon': 'info',
                'label': {'kind': 'literal', 'value': 'Info'},
                'variant': 'secondary',
                'action': {'type': 'open.info'},
              },
              'layer': {
                'alignHorizontal': 'end',
                'alignVertical': 'end',
                'offset': {
                  'x': {'toward': 'start', 'by': 'md'},
                  'y': {'toward': 'top', 'by': 'md'},
                },
              },
            },
          ],
          alignHorizontal: 'start',
          alignVertical: 'start',
          size: const Size(200, 120),
        ),
      ]);
      await pumpDocument(tester, doc, onAction: (action, nodeId) => actions.add('${action.type}:$nodeId'));
      final place = tester.renderObject<RenderLayerPlace>(find.byType(LayerPlace));
      final rect = place.geometry!.rect;
      // Bottom end corner, shifted inward by `md`.
      expect(rect.right, 200 - 12);
      expect(rect.bottom, 120 - 12);
      // The old place (in the very corner): the button is no longer there.
      await tester.tapAt(place.localToGlobal(const Offset(199, 119)));
      expect(actions, isEmpty);
      await tester.tapAt(place.localToGlobal(rect.center));
      expect(actions, ['open.info:info']);
    });
  });

  // ─────────────────────────────── layerDocumentCases ───────────────────────

  group('layerDocumentCases: the reader parses, draws and does not fail', () {
    for (final row in _rows('layerDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester);
        final children = [
          for (var i = 0; i < (row['children']! as List).length; i++)
            _filled('c$i', width: 20, height: 20, node: _obj((row['children']! as List)[i])),
        ];
        final parent = row['parent']! as String;
        final doc = UiDocumentBuilder.bare([
          {
            'id': 'parent',
            'type': parent,
            'props': parent == 'Stack' ? const {} : {'gap': 'none'},
            'children': children,
          },
        ]);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);

        // A node becomes an overlay when: the parent is a stack, there is no `fill`, the value is
        // an object and the stack keeps a sizing layer. This is reading, not
        // validation: the schema and validator codes are the constructor's reference.
        final raw = (row['children']! as List).map(_obj).toList();
        bool isObject(_Json node) => node['layer'] is Map;
        final sizing = raw.any((node) => node['fill'] != true && !isObject(node));
        final expected = parent == 'Stack' && sizing ? raw.where((node) => node['fill'] != true && isObject(node)).length : 0;
        expect(find.byType(LayerPlace), findsNWidgets(expected));
      });
    }
  });

  // ─────────────────────────────── pullReadCases ────────────────────────────

  group('pullReadCases: where pull is read and along which axis', () {
    for (final row in _rows('pullReadCases')) {
      test(row['name']! as String, () {
        final family = _parseFamily(row['parent']! as String, _obj(row['parentProps']), [_obj(row['node'])], nodeType: row['nodeType'] as String?);
        final read = effectivePull(family.children.single, family.parent);
        final want = row['expect'];
        if (want == null) {
          expect(read, isNull);
          return;
        }
        final json = _obj(want);
        expect(read, isNotNull);
        final by = json['by'];
        expect(read!.token ?? read.value, by is num ? by.toDouble() : by);
        expect(pullAxisOf(family.parent), json['axis'] == 'column' ? Axis.vertical : Axis.horizontal);
      });
    }

    test('`Screen` as parent: the axis is a column', () {
      final screen = UiNode.parse({
        'id': 'root',
        'type': 'Screen',
        'props': const {},
        'children': [
          {'id': 'a', 'type': 'Container', 'props': const {}, 'pull': 24},
        ],
      });
      expect(effectivePull(screen.children.single, screen)?.value, 24);
      expect(pullAxisOf(screen), Axis.vertical);
    });
  });

  // ─────────────────────────────── pullDocumentCases ────────────────────────

  group('pullDocumentCases: the reader parses, draws and does not fail', () {
    for (final row in _rows('pullDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester);
        final parent = row['parent']! as String;
        final props = _obj(row['parentProps']);
        final nodeType = row['nodeType'] as String?;
        final issues = (row['issues']! as List).cast<String>();
        final UiDocument doc;
        final ({UiNode parent, List<ChildNode> children}) family;
        if (nodeType == 'AppBar') {
          // The header is a screen zone, the first child of the `Screen` root (row "347").
          final bar = {
            'id': 'bar',
            'type': 'AppBar',
            'props': {'title': {'kind': 'literal', 'value': 'Title'}, 'showBack': false},
            ..._obj(row['node']),
          };
          doc = UiDocumentBuilder.bare([bar, _filled('a', width: 30, height: 30)]);
          family = _parseFamily(parent, props, [_obj(row['node'])], nodeType: nodeType);
        } else {
          doc = UiDocumentBuilder.bare([
            {
              'id': 'parent',
              'type': parent,
              'props': {if (parent == 'Grid') 'columns': 2, 'gap': 'none', ...props},
              'children': [
                _filled('a', width: 30, height: 30),
                _filled('b', width: 30, height: 30, node: _obj(row['node'])),
              ],
            },
          ]);
          family = _parseFamily(parent, props, [
            _filled('a', width: 30, height: 30),
            _filled('b', width: 30, height: 30, node: _obj(row['node'])),
          ]);
        }
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);

        final readable =
            row['schema'] == true &&
            !issues.contains('v.pullOutsideFlow') &&
            !issues.contains('v.pullWithWeight') &&
            !issues.contains('v.pullOnAppBar');
        final child = nodeType == 'AppBar' ? family.children[0] : family.children[1];
        expect(effectivePull(child, family.parent) != null, readable);
      });
    }
  });

  // ───────────────────────────────── pullCases ──────────────────────────────

  group('pullCases: formula', () {
    for (final row in _rows('pullCases')) {
      test(row['name']! as String, () {
        final children = [
          for (final child in (row['children']! as List).map(_obj))
            PullFlowChild((child['size']! as num).toDouble(), ((child['pull'] ?? 0) as num).toDouble()),
        ];
        final flow = pullFlow(children, (row['gap']! as num).toDouble());
        expect(flow.starts, [for (final start in row['starts']! as List) (start as num).toDouble()]);
        expect(flow.size, (row['size']! as num).toDouble());
      });
    }
  });

  Map<String, Object?> pulled(int index, _Json child, {required Axis axis}) => _filled(
    'c$index',
    width: axis == Axis.horizontal ? (child['size']! as num).toDouble() : null,
    height: axis == Axis.vertical ? (child['size']! as num).toDouble() : null,
    node: {
      'children': [textNode('c$index', id: 'c$index-text')],
      if (child['pull'] != null) 'pull': child['pull'],
    },
  );

  group('pullCases: real column', () {
    for (final row in _rows('pullCases')) {
      testWidgets(row['name']! as String, (tester) async {
        _view(tester);
        final children = (row['children']! as List).map(_obj).toList();
        final doc = UiDocumentBuilder.bare([
          {
            'id': 'col',
            'type': 'Column',
            'props': {'gap': (row['gap']! as num).toInt(), 'align': 'start'},
            'children': [for (var i = 0; i < children.length; i++) pulled(i, children[i], axis: Axis.vertical)],
          },
        ]);
        await pumpDocument(tester, doc);
        expect(tester.takeException(), isNull);

        final starts = [for (final start in row['starts']! as List) (start as num).toDouble()];
        late RenderObject column;
        for (var i = 0; i < children.length; i++) {
          final box = _flowChild(tester, 'c$i', (parent) => parent is RenderStretchColumn, nth: 1);
          column = box.parent!;
          expect((box.parentData! as ContainerBoxParentData<RenderBox>).offset.dy, closeTo(starts[i], 1e-6), reason: 'start of c$i');
          expect(box.size.height, (children[i]['size']! as num).toDouble());
        }
        expect((column as RenderBox).size.height, (row['size']! as num).toDouble());
      });
    }

    testWidgets('direct child of the screen: Screen is also a flow where pull applies', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        _filled('a', height: 100, node: {'children': [textNode('c0', id: 't0')]}),
        _filled('b', height: 50, node: {'pull': 24, 'children': [textNode('c1', id: 't1')]}),
      ]);
      await pumpDocument(tester, doc);
      final second = _flowChild(tester, 'c1', (parent) => parent is RenderStretchColumn, nth: 1);
      expect((second.parentData! as ContainerBoxParentData<RenderBox>).offset.dy, 76);
    });

    testWidgets('a tab is not a pull flow: the field of the child is not read', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'acc',
          'type': 'Accordion',
          'props': {
            'title': {'kind': 'literal', 'value': 'T'},
            'initiallyExpanded': true,
          },
          'children': [
            _filled('a', height: 40, node: {'children': [textNode('c0', id: 't0')]}),
            _filled('b', height: 40, node: {'pull': 24, 'children': [textNode('c1', id: 't1')]}),
          ],
        },
      ]);
      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
      final a = _flowChild(tester, 'c0', (parent) => parent is RenderStretchColumn, nth: 1);
      final b = _flowChild(tester, 'c1', (parent) => parent is RenderStretchColumn, nth: 1);
      final aY = (a.parentData! as ContainerBoxParentData<RenderBox>).offset.dy;
      final bY = (b.parentData! as ContainerBoxParentData<RenderBox>).offset.dy;
      // Only the `sm` gap lies between them; the pull (24) does not apply.
      expect(bY - aY, 40 + RenderTheme.fallback().space(SpacingToken.sm));
    });

    testWidgets('overlap band: the later one catches the tap, above it the earlier one', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'col',
          'type': 'Column',
          'props': {'gap': 'none', 'align': 'start'},
          'children': [
            _filled('a', height: 100, node: {'children': [textNode('c0', id: 't0')]}),
            _filled('b', height: 100, node: {'pull': 24, 'children': [textNode('c1', id: 't1')]}),
          ],
        },
      ]);
      await pumpDocument(tester, doc);
      final a = _flowChild(tester, 'c0', (parent) => parent is RenderStretchColumn, nth: 1);
      final b = _flowChild(tester, 'c1', (parent) => parent is RenderStretchColumn, nth: 1);
      // The overlap is [76, 100) along the column's vertical.
      Offset at(double y) => a.parent! is RenderBox ? (a.parent! as RenderBox).localToGlobal(Offset(100, y)) : Offset.zero;
      expect(_hits(tester, at(90), b), isTrue, reason: 'in the overlap band - the later one');
      expect(_hits(tester, at(90), a), isFalse, reason: 'the earlier one does not catch there');
      expect(_hits(tester, at(50), a), isTrue, reason: 'above the band - the earlier one');
    });

    testWidgets('a pulled first child is not clipped by the edge of the parent', (tester) async {
      _view(tester);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'col',
          'type': 'Column',
          'props': {'gap': 'none', 'align': 'start'},
          'style': {'padding': 24},
          'children': [
            _filled('a', height: 40, node: {'pull': 16, 'children': [textNode('c0', id: 't0')]}),
          ],
        },
      ]);
      await pumpDocument(tester, doc);
      expect(tester.takeException(), isNull);
      final a = _flowChild(tester, 'c0', (parent) => parent is RenderStretchColumn, nth: 1);
      expect((a.parentData! as ContainerBoxParentData<RenderBox>).offset.dy, -16);
      // The column (no padding) is 24 high: forty minus sixteen.
      expect((a.parent! as RenderBox).size.height, 24);
    });
  });

  group('pullCases: real row', () {
    for (final row in _rows('pullCases')) {
      for (final direction in ['ltr', 'rtl']) {
        testWidgets('${row['name']} — $direction', (tester) async {
          _view(tester);
          final children = (row['children']! as List).map(_obj).toList();
          // A row in a row: the inner one without weight is sized by content, so its
          // width is the parent's content length from the table.
          final doc = UiDocumentBuilder.bare([
            {
              'id': 'outer',
              'type': 'Row',
              'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
              'children': [
                {
                  'id': 'inner',
                  'type': 'Row',
                  'props': {'gap': (row['gap']! as num).toInt(), 'align': 'start', 'justify': 'start', 'wrap': false},
                  'children': [for (var i = 0; i < children.length; i++) pulled(i, children[i], axis: Axis.horizontal)],
                },
              ],
            },
          ]);
          await pumpDocument(tester, doc, locale: direction == 'rtl' ? 'ar' : 'en');
          expect(tester.takeException(), isNull);

          final starts = [for (final start in row['starts']! as List) (start as num).toDouble()];
          late RenderBox inner;
          for (var i = 0; i < children.length; i++) {
            final box = _flowChild(tester, 'c$i', (parent) => parent is RenderRowLayout && parent.parent is! RenderViewport);
            inner = box.parent! as RenderBox;
            final dx = (box.parentData! as ContainerBoxParentData<RenderBox>).offset.dx;
            // The start is logical: in RTL it is measured from the row's right edge.
            final start = direction == 'rtl' ? inner.size.width - dx - box.size.width : dx;
            expect(start, closeTo(starts[i], 1e-6), reason: 'start of c$i');
          }
          expect(inner.size.width, closeTo((row['size']! as num).toDouble(), 1e-6));
        });
      }
    }

    testWidgets('weight beats pull: a child with weight does not read `pull`', (tester) async {
      _view(tester, 400);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
          'children': [
            _filled('a', width: 100, node: {'children': [textNode('c0', id: 't0')]}),
            _filled('b', node: {'weight': 1, 'pull': 24, 'children': [textNode('c1', id: 't1')]}),
          ],
        },
      ]);
      await pumpDocument(tester, doc);
      final b = _flowChild(tester, 'c1', (parent) => parent is RenderRowLayout);
      expect((b.parentData! as ContainerBoxParentData<RenderBox>).offset.dx, 100);
    });

    testWidgets('a pulled child without weight next to a weighted one: the free space of the row grows by pull', (tester) async {
      _view(tester, 400);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
          'children': [
            _filled('a', width: 100, node: {'children': [textNode('c0', id: 't0')]}),
            _filled('b', width: 100, node: {'pull': 30, 'children': [textNode('c1', id: 't1')]}),
            _filled('c', node: {'weight': 1, 'children': [textNode('c2', id: 't2')]}),
          ],
        },
      ]);
      await pumpDocument(tester, doc);
      final b = _flowChild(tester, 'c1', (parent) => parent is RenderRowLayout);
      final c = _flowChild(tester, 'c2', (parent) => parent is RenderRowLayout);
      expect((b.parentData! as ContainerBoxParentData<RenderBox>).offset.dx, 70);
      // The share takes the remainder: 400 - 100 - 100 + 30.
      expect((c.parentData! as ContainerBoxParentData<RenderBox>).offset.dx, 170);
      expect(c.size.width, 230);
    });
  });

  group('reader and versions', () {
    test('the reader version is numeric: 9.10.0 is newer than 9.9.0', () {
      final reader = SchemaVersion.tryParse(kSupportedSchemaVersion)!;
      expect(reader.compareTo(const SchemaVersion(9, 10, 0)), greaterThanOrEqualTo(0));
      expect(reader.compareTo(const SchemaVersion(9, 9, 0)), greaterThan(0));
      expect(SchemaVersion.tryParse('9.10.0')!.compareTo(SchemaVersion.tryParse('9.9.0')!), greaterThan(0));
    });
  });

  group('artifact mirror', () {
    final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

    test('the reader version is the same as in the artifact', () {
      expect(schema['x-schemaVersion'], kSupportedSchemaVersion);
    });

    test('the ten 9.10.0 policy rows precede the 9.11.0 rows and match', () {
      final compatibility = _obj(schema['x-compatibility']);
      final policy = _obj(compatibility['policy']);
      expect(kOffsetPolicy, hasLength(10));
      for (final entry in kOffsetPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      expect(
        policy.keys.toList().sublist(policy.length - 10 - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length), policy.length - kCarouselPolicy.length - kBottomZonePolicy.length - (kInputsPolicy.length + kFormPolicy.length)),
        kOffsetPolicy.keys.toList(),
      );
      final features = _obj(compatibility['features']);
      for (final feature in ['layerPlacement', 'flowPull']) {
        expect(features[feature], '9.10.0', reason: feature);
        expect(kFeatureCatalog[feature], '9.10.0', reason: feature);
        expect(supportsFeature(feature), isTrue, reason: feature);
        expect(supportsFeature(feature, readerVersion: '9.9.0'), isFalse, reason: feature);
      }
    });

    test('x-style.layout.layer and pull: angle bounds and direction words', () {
      final layout = _obj(_obj(schema['x-style'])['layout']);
      final layer = _obj(layout['layer']);
      expect(_obj(layer['rotateRange']), {'min': kMinLayerRotate, 'max': kMaxLayerRotate});
      expect(layer['field'], 'layer');
      expect(layer['unreadable'], isA<Map<String, Object?>>());
      expect(_obj(layout['pull'])['field'], 'pull');
      final defs = _obj(schema[r'$defs']);
      final offset = _obj(_obj(_obj(defs['LayerOffset'])['properties']));
      expect((_obj(_obj(_obj(offset['x'])['properties'])['toward'])['enum']! as List), kLayerOffsetXToward);
      expect((_obj(_obj(_obj(offset['y'])['properties'])['toward'])['enum']! as List), kLayerOffsetYToward);
    });
  });
}
