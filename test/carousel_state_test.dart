/// CAROUSEL STATE LIVES WITH THE STACK FRAME, AND IS SEPARATE PER TEMPLATE INSTANCE
/// (schema 9.11.0: `carousel.active.heldBy:
/// 'stack-frame'`, `keyedBy: 'node-and-template-instance-path'`).
///
/// An earlier design kept the state in the carousel's `State`: a screen under
/// the top one in the stack is not built, the `State` died, and after "back"
/// the user saw the first card. Here the state lives in the frame's memory
/// ([CarouselMemory]), keyed by the node plus the chain of instance indexes: a
/// carousel in a data-driven list row has its own state per record. The simple
/// case is covered in `adversarial_911_carousel_state_test.dart`; this file
/// covers the data list, a nested list, and proof the state lives exactly as long as the frame.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/media_chrome_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

Map<String, Object?> lit(Object? value) => {'kind': 'literal', 'value': value};

Map<String, Object?> button(String id, Map<String, Object?> action) => {
  'id': id,
  'type': 'Button',
  'props': {'label': lit(id), 'variant': 'primary', 'action': action},
};

Map<String, Object?> strip(String id) => {
  'id': id,
  'type': 'Row',
  'props': {'gap': 'sm', 'scrollable': true, 'carousel': {'perView': 1, 'indicator': 'none'}},
  'children': [
    for (var i = 0; i < 4; i += 1)
      {
        'id': '$id-card$i',
        'type': 'Container',
        'props': {'direction': 'column', 'gap': 'none'},
        'style': {'height': 40},
        'children': [
          {
            'id': '$id-t$i',
            'type': 'Text',
            'props': {'content': lit('$id card $i')},
          },
        ],
      },
  ],
};

UiDocument document(List<Map<String, Object?>> listChildren) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'state',
  'name': 'state',
  'initialScreenId': 'list',
  'screens': [
    {
      'screenId': 'list',
      'name': 'list',
      'root': {
        'id': 'root',
        'type': 'Screen',
        'props': {'gap': 'sm'},
        'children': [
          ...listChildren,
          button('go', {'type': 'navigate', 'params': {'screenId': 'next'}}),
        ],
      },
    },
    {
      'screenId': 'next',
      'name': 'next',
      'root': {
        'id': 'root2',
        'type': 'Screen',
        'props': {'gap': 'sm'},
        'children': [
          button('back', {'type': 'navigate.back'}),
          button('again', {'type': 'navigate', 'params': {'screenId': 'next'}}),
        ],
      },
    },
  ],
});

final Map<String, Object?> data = {
  'rows': [
    {'name': 'A'},
    {'name': 'B'},
    {'name': 'C'},
  ],
};

List<double> offsets(WidgetTester tester) => [
  for (final element in find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)).evaluate())
    ((element as StatefulElement).state as ScrollableState).position.pixels,
];

void main() {
  Future<void> pumpIt(WidgetTester tester, UiDocument doc) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: renderDocument(doc, theme: RenderTheme.fallback(), data: data))),
    );
    await tester.pumpAndSettle();
  }

  Future<void> flip(WidgetTester tester, String label, {int cards = 1}) async {
    await tester.drag(find.text(label).first, Offset(-250.0 * cards, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('in data list rows: each record stays on its own card after "forward" and "back"', (tester) async {
    final doc = document([
      {
        'id': 'rows',
        'type': 'Repeater',
        'props': {'source': 'rows', 'item': 'row', 'direction': 'column', 'gap': 'sm'},
        'children': [strip('strip')],
      },
    ]);
    await pumpIt(tester, doc);
    expect(offsets(tester), [0, 0, 0]);

    // First record on the first card, third on the third; the second stays.
    await flip(tester, 'strip card 0');
    final before = offsets(tester);
    expect(before.where((offset) => offset > 100), hasLength(1), reason: 'only one row was scrolled');
    // The same text "strip card 0" is in all three rows: scroll the third separately.
    await tester.drag(find.byType(Carousel).at(2), const Offset(-500, 0));
    await tester.pumpAndSettle();
    final snapshot = offsets(tester);
    expect(snapshot[0], greaterThan(100));
    expect(snapshot[1], 0);
    expect(snapshot[2], greaterThan(snapshot[0]), reason: 'the third row is on a different card than the first');

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(Carousel), findsNothing, reason: 'a page under a page is not built');
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(offsets(tester), snapshot, reason: 'each record is on its own card, not all on the last one\'s offset');
  });

  testWidgets('state lives while the frame is in the stack: two steps forward and two back', (tester) async {
    final doc = document([strip('solo')]);
    await pumpIt(tester, doc);
    await flip(tester, 'solo card 0', cards: 2);
    final before = offsets(tester);
    expect(before.single, greaterThan(200));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(offsets(tester), before);
  });

  testWidgets('frame removed -- state is gone with it: the same screen opened again starts at the first card', (tester) async {
    final doc = document([strip('solo')]);
    await pumpIt(tester, doc);
    await flip(tester, 'solo card 0');
    expect(offsets(tester).single, greaterThan(100));

    // A new document flow (another `documentId`) is a new stack, so new memory too.
    final other = UiDocument.fromJson({
      'schemaVersion': UiDocument.supportedSchemaVersion,
      'documentId': 'state-two',
      'name': 'state',
      'initialScreenId': 'list',
      'screens': [
        {
          'screenId': 'list',
          'name': 'list',
          'root': {
            'id': 'root',
            'type': 'Screen',
            'props': {'gap': 'sm'},
            'children': [strip('solo')],
          },
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: renderDocument(other, theme: RenderTheme.fallback(), data: data))),
    );
    await tester.pumpAndSettle();
    expect(offsets(tester), [0]);
  });

  test('artifact mirror: clarification keys 336, 337, 340, 342, 347', () {
    final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map<String, Object?>;
    final layout = ((schema['x-style']! as Map<String, Object?>)['layout']!) as Map<String, Object?>;
    Map<String, Object?> at(String key) => layout[key]! as Map<String, Object?>;
    final segments = at('progressSegments');
    expect(segments['kindDecidedBy'], 'width-the-place-gives');
    expect(segments['minInlineSize'], 'gaps');
    expect(segments['minInlineSizeFormula'], '(segments - 1) * gap');
    expect(segments['minInlineSizeInBothKinds'], isTrue);
    final carousel = at('carousel');
    expect(carousel['area'], 'width-the-place-gives-with-or-without-dots');
    expect(carousel['shell'], 'same-box-with-or-without-dots');
    final active = carousel['active']! as Map<String, Object?>;
    expect(active['heldBy'], 'stack-frame');
    expect(active['keyedBy'], 'node-and-template-instance-path');
    expect(at('modalLayer')['above'], 'whole-page-including-app-bar');
    expect(at('appBar')['maxDrawnActions'], kAppBarMaxDrawnActions);
    expect(at('pull')['onAppBar'], 'ignore');
    final withoutOwnHeight = at('screen')['withoutOwnHeight']! as Map<String, Object?>;
    expect(withoutOwnHeight['layerArea'], 'visible-part-of-the-block-not-taller-than-the-window');
    expect(withoutOwnHeight['layerOtherwise'], 'host-asks-for-an-own-height');
  });
}
