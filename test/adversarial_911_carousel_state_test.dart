/// Carousel state (`carouselState`).
///
/// Declared: the open stop is kept while the screen stays in the stack (going
/// "back" to a screen restores the same card). The React reader keeps the
/// offset in the stack frame's memory. Here a page under another page is not
/// built at all (`_frameAt` draws only the top page and the layers above it),
/// and `Carousel` has no memory of its own -- only what the host's
/// `PageStorage` happens to provide remains.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Map<String, Object?> carousel(String id) => {
  'id': id,
  'type': 'Row',
  'props': {'gap': 'sm', 'scrollable': true, 'carousel': {'perView': 1, 'indicator': 'none'}},
  'children': [
    for (var i = 0; i < 5; i += 1)
      {
        'id': '$id-card$i',
        'type': 'Container',
        'props': {'direction': 'column', 'gap': 'none'},
        'style': {'height': 60},
        'children': [
          {'id': '$id-t$i', 'type': 'Text', 'props': {'content': lit('$id card $i'), 'align': 'start'}},
        ],
      },
  ],
};

UiDocument document() => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'attack',
  'name': 'attack',
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
          carousel('first'),
          carousel('second'),
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
        'children': [button('back', {'type': 'navigate.back'})],
      },
    },
  ],
});

List<double> offsets(WidgetTester tester) => [
  for (final element in find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)).evaluate())
    (element as StatefulElement).state is ScrollableState ? ((element.state as ScrollableState).position.pixels) : -1,
];

void main() {
  Future<void> run(WidgetTester tester, Widget Function(Widget screen) host) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(renderDocument(document(), theme: RenderTheme.fallback(), data: const {})));
    await tester.pumpAndSettle();
    expect(offsets(tester), [0, 0]);

    // The user scrolls the SECOND carousel by one card.
    await tester.drag(find.text('second card 0'), const Offset(-250, 0));
    await tester.pumpAndSettle();
    final before = offsets(tester);
    expect(before[0], 0);
    expect(before[1], greaterThan(100), reason: 'the second carousel moved to the second card');

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(Carousel), findsNothing, reason: 'a page under a page is not built');
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    // Declared: going "back" restores the same card; each carousel keeps its own.
    expect(offsets(tester), before);
  }

  testWidgets('host without PageStorage: after "back" the carousel stays on the same card', (tester) async {
    await run(
      tester,
      (screen) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(data: const MediaQueryData(), child: screen),
      ),
    );
  });

  testWidgets('host with MaterialApp (route PageStorage): same card, and only in the carousel that was scrolled', (tester) async {
    await run(tester, (screen) => MaterialApp(home: Scaffold(body: screen)));
  });
}
