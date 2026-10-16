/// "SWIPE TO CONFIRM" (schema 9.22.0, `Button.confirm: 'swipe'`).
///
/// The shared table (`assets/contract/fixtures/swipe-confirm/swipe-confirm-cases.json`) runs row by row, by the
/// reader's formula and, where the table speaks of a press, by a REAL button:
///
///  1. `geometryCases`, `naturalWidthCases`, `thumbCases` -- the track, the thumb, the label strip;
///  2. `progressCases`, `releaseCases`, `captureCases` -- the gesture;
///  3. `pressCases` -- every way of pressing, on a real button: a pointer tap, a drag, Enter, Space, a held Enter,
///     a disabled button;
///  4. `schemaCases`, `ruleCases` -- the word, and the rules as data.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/swipe_confirm.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/swipe_confirm_button.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

final _Row _table =
    jsonDecode(File('assets/contract/fixtures/swipe-confirm/swipe-confirm-cases.json').readAsStringSync()) as _Row;
final _Row _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;

List<_Row> _rows(String key) => (_table[key]! as List<Object?>).cast<_Row>();
double _n(Object? value) => (value! as num).toDouble();

SwipeTrack _trackOf(Object? raw, {double? width}) {
  final track = raw! as _Row;
  return (
    height: _n(track['height']),
    width: width ?? _n(track['width'] ?? 0),
    border: _n(track['border']),
    inset: _n(track['inset']),
  );
}

const _action = {
  'type': 'openUrl',
  'params': {'url': 'https://example.com/redeem'},
  'track': {'event': 'redeem_confirmed'},
};

Map<String, Object?> _swipeButton({bool disabled = false, String size = 'lg', Map<String, Object?>? style, bool fullWidth = true}) => {
  'id': 'btn',
  'type': 'Button',
  'props': <String, Object?>{
    'label': {'kind': 'literal', 'value': 'Pay'},
    'variant': 'primary',
    'action': _action,
    'fullWidth': fullWidth,
    'confirm': 'swipe',
    'size': size,
    if (disabled) 'disabledIf': {'path': 'ui.locked', 'op': 'isEmpty'},
  },
  'style': ?style,
};

Finder _thumb() => find.descendant(
  of: find.byType(SwipeConfirmTrack),
  matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle),
);

void main() {
  test('the groups have the promised rows', () {
    expect(_rows('geometryCases'), hasLength(4));
    expect(_rows('naturalWidthCases'), hasLength(2));
    expect(_rows('progressCases'), hasLength(7));
    expect(_rows('releaseCases'), hasLength(5));
    expect(_rows('thumbCases'), hasLength(5));
    expect(_rows('captureCases'), hasLength(4));
    expect(_rows('pressCases'), hasLength(8));
    expect(_rows('schemaCases'), hasLength(4));
    expect(_rows('ruleCases'), hasLength(10));
  });

  group('geometryCases', () {
    for (final row in _rows('geometryCases')) {
      test(row['name']! as String, () {
        final want = row['expect']! as _Row;
        final geometry = swipeGeometryOf(_trackOf(row['track']));
        expect(geometry.diameter, want['diameter']);
        expect(geometry.thumbRoom, want['thumbRoom']);
        expect(geometry.travel, want['travel']);
        final label = want['label']! as _Row;
        expect(geometry.label.start, label['start']);
        expect(geometry.label.width, label['width']);
      });
    }
  });

  group('naturalWidthCases', () {
    for (final row in _rows('naturalWidthCases')) {
      test(row['name']! as String, () {
        final track = _trackOf(row['track']);
        expect(swipeNaturalWidthOf(_n(row['label']), height: track.height, border: track.border, inset: track.inset), row['expect']);
      });
    }
  });

  group('progressCases', () {
    for (final row in _rows('progressCases')) {
      test(row['name']! as String, () {
        expect(swipeProgressOf(_n(row['dx']), _n(row['travel']), rtl: row['rtl']! as bool), closeTo(_n(row['expect']), 1e-9));
      });
    }
  });

  group('releaseCases', () {
    for (final row in _rows('releaseCases')) {
      test(row['name']! as String, () {
        final release = swipeReleaseOf(_n(row['progress']), disabled: row['disabled']! as bool);
        expect(release.name == 'act' ? 'act' : 'return', row['expect']);
      });
    }
  });

  group('thumbCases', () {
    for (final row in _rows('thumbCases')) {
      test(row['name']! as String, () {
        expect(swipeThumbStartOf(_trackOf(row['track']), _n(row['progress'])), closeTo(_n(row['expect']), 1e-9));
      });
    }
  });

  group('captureCases', () {
    for (final row in _rows('captureCases')) {
      test(row['name']! as String, () => expect(swipeCapturedBy(_n(row['dx']), _n(row['dy'])), row['expect']));
    }
  });

  group('schemaCases: the word', () {
    final defs = _schema[r'$defs']! as _Row;
    for (final row in _rows('schemaCases')) {
      test(row['name']! as String, () {
        final props = row['props']! as _Row;
        // The artifact: the word is a property of `ButtonProps` only, with the one word `swipe`.
        final owner = defs['${row['widget']}Props']! as _Row;
        final declared = (owner['properties']! as _Row)['confirm'] as _Row?;
        final accepted = props['confirm'] == null || (declared != null && (declared['enum']! as List<Object?>).contains(props['confirm']));
        expect(accepted, row['valid']);
        // The reader reads only the word `swipe`.
        final node = UiNode.parse({
          'id': 'b',
          'type': row['widget'],
          'props': {'label': {'kind': 'literal', 'value': 'x'}, 'action': {'type': 'none'}, ...props},
        });
        if (node is ButtonNode) expect(node.confirmBySwipe, props['confirm'] == 'swipe');
      });
    }
  });

  group('ruleCases: the artifact and the code mirror', () {
    final block = _schema['x-swipeConfirm']! as _Row;
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
    test('the numbers', () {
      expect(block['threshold'], kSwipeThreshold);
      expect(block['words'], [kConfirmSwipe]);
    });
  });

  group('geometry on a real track', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('the thumb, the label strip and the natural width ($locale)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(345, 600);
        addTearDown(tester.view.reset);
        await pumpDocument(
          tester,
          UiDocumentBuilder.bare([_swipeButton(style: {'border': {'width': 1, 'color': 'border'}})]),
          locale: locale,
        );
        final track = tester.getRect(find.byType(SwipeConfirmTrack));
        final geometry = swipeGeometryOf((height: track.height, width: track.width, border: 1, inset: 4));
        final rtl = locale == 'ar';
        final thumb = tester.getRect(_thumb());
        expect(thumb.width, geometry.diameter);
        expect(thumb.height, geometry.diameter);
        final startEdge = rtl ? track.right - thumb.right : thumb.left - track.left;
        expect(startEdge, closeTo(swipeThumbStartOf((height: track.height, width: track.width, border: 1, inset: 4), 0), 1e-6));
        // The label is centred in the strip between the two places of the thumb.
        final label = tester.getRect(find.text('Pay'));
        expect(label.center.dx, closeTo(track.center.dx, 0.6));
        expect(label.width, lessThanOrEqualTo(geometry.label.width + 0.01));
      });
    }

    testWidgets('the track is the height of the size: 48 for lg without a border', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([_swipeButton()]));
      expect(tester.getSize(find.byType(SwipeConfirmTrack)).height, 48);
    });

    testWidgets('natural width: the label plus the room of the thumb on both sides', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([_swipeButton(fullWidth: false)]));
      final track = tester.getSize(find.byType(SwipeConfirmTrack));
      final label = tester.getSize(find.text('Pay'));
      final room = swipeGeometryOf((height: track.height, width: 0, border: 0, inset: 4)).thumbRoom;
      expect(track.width, closeTo(label.width + 2 * room, 0.01));
    });

    testWidgets('the thumb is the background of the role; the own background paints the track', (tester) async {
      await pumpDocument(tester, UiDocumentBuilder.bare([_swipeButton(style: {'background': {'kind': 'color', 'color': 'accent'}})]));
      final thumb = tester.widget<DecoratedBox>(_thumb());
      final theme = RenderTheme.fallback();
      expect((thumb.decoration as BoxDecoration).color, theme.buttonVariant(ButtonVariantToken.primary).background);
      final trackBox = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(SwipeConfirmTrack), matching: find.byType(DecoratedBox)).first,
      );
      expect((trackBox.decoration as BoxDecoration).color, theme.color(ColorToken.accent));
    });

    testWidgets('a role without a background: primary and onPrimary', (tester) async {
      final node = _swipeButton();
      (node['props']! as Map<String, Object?>)['variant'] = 'ghost';
      await pumpDocument(tester, UiDocumentBuilder.bare([node]));
      expect(((tester.widget<DecoratedBox>(_thumb())).decoration as BoxDecoration).color, RenderTheme.fallback().color(ColorToken.primary));
    });
  });

  group('pressCases: on a real button', () {
    for (final row in _rows('pressCases')) {
      final way = row['way']! as String;
      final disabled = row['disabled']! as bool;
      final expectAct = row['expect'] == 'act';

      for (final locale in ['en', 'ar']) {
        testWidgets('${row['name']} ($locale)', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(345, 600);
          addTearDown(tester.view.reset);
          final order = <String>[];
          await pumpDocument(
            tester,
            UiDocumentBuilder.bare([_swipeButton(disabled: disabled)]),
            locale: locale,
            onTrack: (event, nodeId, record) => order.add('track:${event.event}'),
            onAction: (action, nodeId) => order.add('action:${action.type}'),
          );
          final rtl = locale == 'ar';
          final track = tester.getRect(find.byType(SwipeConfirmTrack));
          final geometry = swipeGeometryOf((height: track.height, width: track.width, border: 0, inset: 4));
          final before = tester.getRect(_thumb());
          final sign = rtl ? -1.0 : 1.0;

          Future<void> focus() async {
            Focus.of(tester.element(find.descendant(of: find.byType(SwipeConfirmTrack), matching: find.byType(IntrinsicWidth))), scopeOk: false)
                .requestFocus();
            await tester.pump();
          }

          switch (way) {
            case 'pointerTap':
              await tester.tap(find.byType(SwipeConfirmTrack));
              await tester.pump();
            case 'dragPastThreshold' || 'dragShort':
              final share = way == 'dragShort' ? 0.5 : 0.95;
              final gesture = await tester.startGesture(Offset(before.center.dx, track.center.dy));
              final steps = 20;
              for (var i = 1; i <= steps; i += 1) {
                await gesture.moveBy(Offset(sign * geometry.travel * share / steps, 0));
                await tester.pump();
              }
              if (!disabled) {
                final moved = (rtl ? before.right - tester.getRect(_thumb()).right : tester.getRect(_thumb()).left - before.left);
                expect(moved, closeTo(geometry.travel * share, 1.5), reason: 'the thumb follows the finger');
              } else {
                expect(tester.getRect(_thumb()), before, reason: 'a disabled thumb does not move');
              }
              await gesture.up();
              await tester.pumpAndSettle();
              expect(tester.getRect(_thumb()), before, reason: 'after a release the thumb is at the start');
            case 'enter' || 'space':
              await focus();
              final key = way == 'enter' ? LogicalKeyboardKey.enter : LogicalKeyboardKey.space;
              await tester.sendKeyDownEvent(key);
              await tester.sendKeyUpEvent(key);
              await tester.pump();
            case 'enterRepeat':
              await focus();
              await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
              for (var i = 0; i < 5; i += 1) {
                await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
              }
              await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
              await tester.pump();
              // The first press of a held key acts; its repeats do not (the table speaks of the repeat).
              expect(order.where((entry) => entry.startsWith('action')).length, lessThanOrEqualTo(1));
              order.clear();
            default:
              fail('unknown way $way');
          }
          if (expectAct) {
            expect(order, ['track:redeem_confirmed', 'action:openUrl'], reason: 'the track event first, then the action, once');
          } else {
            expect(order, isEmpty);
          }
        });
      }
    }
  });

  testWidgets('assistive technology: a button named by the label; "activate" acts at once', (tester) async {
    final handle = tester.ensureSemantics();
    final order = <String>[];
    await pumpDocument(
      tester,
      UiDocumentBuilder.bare([_swipeButton()]),
      onAction: (action, nodeId) => order.add(action.type),
      onTrack: (event, nodeId, record) => order.add('track'),
    );
    final node = tester.getSemantics(find.byType(SwipeConfirmTrack));
    // ignore: deprecated_member_use
    expect(node.label, 'Pay');
    expect(node.flagsCollection.isButton, isTrue);
    tester.semantics.tap(find.semantics.byLabel('Pay'));
    await tester.pump();
    expect(order, ['track', 'openUrl']);
    handle.dispose();
  });

  testWidgets('a disabled button is a disabled button for assistive technology and does not act', (tester) async {
    final handle = tester.ensureSemantics();
    final order = <String>[];
    await pumpDocument(tester, UiDocumentBuilder.bare([_swipeButton(disabled: true)]), onAction: (action, nodeId) => order.add(action.type));
    final node = tester.getSemantics(find.byType(SwipeConfirmTrack));
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(order, isEmpty);
    handle.dispose();
  });

  testWidgets('a diagonal-free vertical scroll over the track scrolls the body and the thumb stays', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(345, 300);
    addTearDown(tester.view.reset);
    final order = <String>[];
    await pumpDocument(
      tester,
      UiDocumentBuilder.bare([
        _swipeButton(),
        {'id': 'tall', 'type': 'Container', 'props': {'direction': 'column'}, 'style': {'height': 600}, 'children': [textNode('x')]},
      ]),
      onAction: (action, nodeId) => order.add(action.type),
    );
    final before = tester.getRect(_thumb());
    await tester.drag(find.byType(SwipeConfirmTrack), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(order, isEmpty);
    expect(tester.getRect(_thumb()).left, before.left);
    expect(tester.getRect(_thumb()).top, lessThan(before.top), reason: 'the body scrolled');
  });
}
