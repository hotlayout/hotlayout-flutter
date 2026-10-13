/// Documents OUTSIDE the contract tables.
///
/// A document arrives from the network; it is declared that the reader does not
/// crash on input of the wrong shape (the piece is ignored). Every row below is a document the schema or
/// validator would reject but the reader parses; one expectation: the frame
/// draws without an exception, and so does a gesture on it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action_catalog.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';
import 'package:hotlayout_flutter/src/render/layer_place.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';

import 'support/fixtures.dart';

Map<String, Object?> lit(Object? value) => {'kind': 'literal', 'value': value};

Map<String, Object?> text(String id, [String? value, Map<String, Object?> extra = const {}]) => {
  'id': id,
  'type': 'Text',
  'props': {'content': lit(value ?? id), 'align': 'start'},
  ...extra,
};

Map<String, Object?> box(String id, Map<String, Object?> style, [List<Map<String, Object?>> children = const [], Map<String, Object?> extra = const {}]) => {
  'id': id,
  'type': 'Container',
  'props': {'direction': 'column', 'gap': 'none'},
  'style': style,
  'children': children,
  ...extra,
};

Map<String, Object?> icon(String id) => {
  'id': id,
  'type': 'IconButton',
  'props': {'icon': 'info', 'label': lit(id), 'variant': 'ghost', 'size': 'lg', 'action': {'type': 'none'}},
};

Map<String, Object?> bar(String id, {int actions = 0, Map<String, Object?> extra = const {}}) => {
  'id': id,
  'type': 'AppBar',
  'props': {'title': lit('Title of the bar that is rather long'), 'subtitle': lit('sub'), 'showBack': true},
  'children': [for (var i = 0; i < actions; i += 1) icon('$id-a$i')],
  ...extra,
};

Map<String, Object?> stack(String id, List<Map<String, Object?>> children, [Map<String, Object?> extra = const {}]) => {
  'id': id,
  'type': 'Stack',
  'props': {'alignHorizontal': 'center', 'alignVertical': 'center'},
  'children': children,
  ...extra,
};

Map<String, Object?> row(String id, List<Map<String, Object?>> children, Map<String, Object?> props, [Map<String, Object?> extra = const {}]) => {
  'id': id,
  'type': 'Row',
  'props': {'gap': 'sm', ...props},
  'children': children,
  ...extra,
};

Map<String, Object?> steps(String id, [Map<String, Object?> props = const {}]) => {
  'id': id,
  'type': 'ProgressBar',
  'props': {'value': lit(2), 'max': lit(6), 'color': 'primary', 'labelFormat': 'none', 'segments': 12, ...props},
};

Map<String, Object?> image(String id, Object? ratio, [Map<String, Object?> extra = const {}]) => {
  'id': id,
  'type': 'Image',
  'props': {'source': {'kind': 'asset', 'token': 'placeholder'}, 'aspectRatio': ratio, 'fit': 'cover'},
  ...extra,
};

Map<String, Object?> layered(Map<String, Object?> node, Map<String, Object?> layer) => {...node, 'layer': layer};

List<Map<String, Object?>> cards(int n, {num width = 40}) => [for (var i = 0; i < n; i += 1) box('card$i', {'width': width, 'height': 30})];

UiDocument doc(List<Map<String, Object?>> children, {List<Map<String, Object?>> more = const [], Map<String, Object?> rootStyle = const {}, Map<String, Object?> first = const {}}) =>
    UiDocument.fromJson({
      'schemaVersion': UiDocument.supportedSchemaVersion,
      'documentId': 'attack',
      'name': 'attack',
      'initialScreenId': 'a',
      'screens': [
        {
          'screenId': 'a',
          'name': 'a',
          ...first,
          'root': {'id': 'root', 'type': 'Screen', 'props': {'gap': 'sm'}, 'style': rootStyle, 'children': children},
        },
        ...more,
      ],
    });

final Map<String, UiDocument Function()> hostile = {
  'pull 128 on the first child without an app bar': () => doc([text('t', 'x', {'pull': 128}), text('u')]),
  'pull larger than all column children -- negative sum': () => doc([
    box('c', {}, [for (var i = 0; i < 6; i += 1) text('t$i', 'x', {'pull': 128})]),
  ]),
  'pull in a row -- negative width': () => doc([
    row('r', [for (var i = 0; i < 6; i += 1) text('t$i', 'x', {'pull': 128})], {}),
  ]),
  'pull in a scrolling row': () => doc([
    row('r', [for (var i = 0; i < 6; i += 1) text('t$i', 'x', {'pull': 128})], {'scrollable': true}),
  ]),
  'app bar, and pull of the first body child larger than the screen': () => doc([bar('b'), box('hero', {'height': 10}, [], {'pull': 128}), text('u')]),
  'app bar hidden by a condition, pull remained': () => doc([
    bar('b', extra: {'visibleIf': {'path': 'user.none', 'op': 'isNotEmpty'}}),
    box('hero', {'height': 10}, [], {'pull': 128}),
  ]),
  'app bar with forty actions': () => doc([bar('b', actions: 40), text('u')]),
  'app bar not the first child': () => doc([text('u'), bar('b', actions: 2), text('v')]),
  'two app bars': () => doc([bar('b1', actions: 1), bar('b2', actions: 3), text('v')]),
  'app bar inside an app bar and inside a stack': () => doc([
    bar('b1', extra: {'children': [bar('b2'), icon('i')]}),
    stack('s', [bar('b3', actions: 2), layered(bar('b4'), {'rotate': 90})]),
  ]),
  'stack of overlays only': () => doc([
    stack('s', [layered(text('a'), {'rotate': 45}), layered(text('b'), {'offset': {'x': {'toward': 'end', 'by': 128}}})]),
  ]),
  'stack: stretched layer and overlay, no size layer': () => doc([
    stack('s', [box('f', {}, [], {'fill': true}), layered(text('b'), {'rotate': -180})]),
  ]),
  'fill + layer + weight + pull on one layer': () => doc([
    stack('s', [box('base', {'height': 40}), layered(box('f', {'height': 10}, [], {'fill': true, 'weight': 3, 'pull': 128}), {'alignHorizontal': 'end', 'rotate': 33})]),
  ]),
  'layer on a child of a non-stack (column, row, grid)': () => doc([
    layered(text('a'), {'rotate': 45, 'offset': {'y': {'toward': 'top', 'by': 128}}}),
    row('r', [layered(text('b'), {'rotate': 45}), text('c')], {}),
    {'id': 'g', 'type': 'Grid', 'props': {'columns': 2, 'gap': 'sm'}, 'children': [layered(text('d'), {'rotate': 45}), text('e')]},
  ]),
  'five hundred overlays': () => doc([
    stack('s', [box('base', {'height': 60}), for (var i = 0; i < 500; i += 1) layered(text('l$i', 'x'), {'rotate': (i % 361) - 180, 'offset': {'x': {'toward': i.isEven ? 'end' : 'start', 'by': i % 129}}})]),
  ]),
  'overlay larger than the stack, offset by an unknown token': () => doc([
    stack('s', [box('base', {'height': 4, 'width': 4}), layered(box('big', {'width': 2000, 'height': 2000}), {'offset': {'x': {'toward': 'end', 'by': 'noSuchToken'}, 'y': {'toward': 'sideways', 'by': 12}}, 'rotate': 12.5})]),
  ]),
  'stack in a stack in a scrolling row': () => doc([
    row('r', [stack('s', [stack('s2', [layered(text('a'), {'rotate': 10})]), layered(text('b'), {'rotate': 10})])], {'scrollable': true}),
  ]),
  'carousel: perView 6 in a 1 px box': () => doc([
    box('narrow', {'width': 1}, [row('r', cards(8), {'scrollable': true, 'carousel': {'perView': 6}})]),
  ]),
  'carousel: gap and peek larger than the area': () => doc([
    row('r', cards(8), {'scrollable': true, 'gap': 128, 'carousel': {'perView': 6, 'peek': 128}}, {'style': {'padding': {'start': 128, 'end': 128}}}),
  ]),
  'carousel without cards': () => doc([row('r', const [], {'scrollable': true, 'carousel': {'perView': 2}})]),
  'carousel in a carousel': () => doc([
    row('r', [row('inner', cards(12), {'scrollable': true, 'carousel': {'perView': 3}}), ...cards(4)], {'scrollable': true, 'carousel': {'perView': 1}}),
  ]),
  'carousel + wrap; carousel without scrolling': () => doc([
    row('r', cards(12), {'scrollable': true, 'wrap': true, 'carousel': {'perView': 2}}),
    row('r2', cards(12), {'carousel': {'perView': 2}}),
    row('r3', cards(12), {'wrap': true, 'carousel': {'perView': 2}}),
  ]),
  'carousel: parts of the wrong shape': () => doc([
    row('r', cards(12), {'scrollable': true, 'carousel': {'perView': 2.5, 'peek': -4, 'indicator': 7}}),
    row('r2', cards(12), {'scrollable': true, 'carousel': 'yes'}),
    row('r3', cards(12), {'scrollable': true, 'carousel': {'perView': 0, 'peek': {'token': 'x'}}}),
    row('r4', cards(12), {'scrollable': true, 'carousel': {'perView': 99999999999, 'peek': 1e308}}),
  ]),
  'carousel: card with weight, stretched, pulled, overlay': () => doc([
    row('r', [box('c1', {'height': 20}, [], {'weight': 2, 'fill': true, 'pull': 64}), layered(box('c2', {'height': 20}), {'rotate': 30}), steps('p'), row('wide', cards(3), {})], {'scrollable': true, 'carousel': {'perView': 2}}),
  ]),
  'carousel in a stack as an overlay': () => doc([
    stack('s', [box('base', {'height': 40}), layered(row('r', cards(12), {'scrollable': true, 'carousel': {'perView': 2}}), {'rotate': 15})]),
  ]),
  'steps: 12 steps in a 1 px box, in a stack, in a scrolling row': () => doc([
    box('narrow', {'width': 1}, [steps('p1')]),
    stack('s', [steps('p2')]),
    row('r', [steps('p3'), text('t')], {'scrollable': true}),
  ]),
  'steps: garbage in segments and currentColor, gradient by an unknown token': () => doc([
    steps('p1', {'segments': 1e308}),
    steps('p2', {'segments': -3}),
    steps('p3', {'segments': '12'}),
    steps('p4', {'segments': 12, 'currentColor': {'token': 'noSuch', 'opacity': 7}}),
    steps('p5', {'segments': 12, 'gradient': {'angle': 1e9, 'stops': [{'color': 'noSuch', 'position': 0}, {'color': 'alsoNot', 'position': 1}]}}),
    steps('p6', {'segments': 12, 'thickness': 0, 'value': lit(-5), 'max': lit(0)}),
    steps('p7', {'segments': 12, 'value': lit(1e308), 'max': lit(1e-308)}),
  ]),
  'image: ratios at the limit and beyond it': () => doc([
    image('i1', {'width': 1e308, 'height': 1e-308}),
    image('i2', {'width': 0, 'height': 0}),
    image('i3', {'width': -1, 'height': 5}),
    image('i4', {'width': '16', 'height': '9'}),
    image('i5', '9999:1'),
    image('i6', {'width': 1, 'height': 1e6}, {'style': {'width': 300}}),
    row('r', [image('i7', {'width': 1000, 'height': 1}), image('i8', {'width': 1, 'height': 1000}, {'fill': true})], {'scrollable': true}),
    stack('s', [image('i9', {'width': 1, 'height': 4}, {'fill': true}), layered(image('i10', {'width': 4, 'height': 1}), {'rotate': 90})]),
  ]),
  'carousel in a row next to a neighbour': () => doc([
    row('outer', [row('car', cards(12, width: 20), {'scrollable': true, 'gap': 'none', 'carousel': {'perView': 2}}), text('sib', 'W' * 25)], {'gap': 'none'}),
  ]),
  'carousel in a row with weights': () => doc([
    row('outer', [row('car', cards(12), {'scrollable': true, 'carousel': {'perView': 2}}, {'weight': 2}), text('sib', 'x', {'weight': 1})], {}),
  ]),
  'carousel without perView in a row next to a neighbour': () => doc([
    row('outer', [row('car', cards(12, width: 20), {'scrollable': true, 'carousel': {'indicator': 'dots'}}), text('sib', 'W' * 25)], {}),
  ]),
  'carousel in a grid cell': () => doc([
    {'id': 'g', 'type': 'Grid', 'props': {'columns': 2, 'gap': 'sm'}, 'children': [row('car', cards(12), {'scrollable': true, 'carousel': {'perView': 2}}), text('e')]},
  ]),
  'carousel in a row container and in an ordinary stack layer': () => doc([
    {'id': 'cr', 'type': 'Container', 'props': {'direction': 'row', 'gap': 'sm'}, 'children': [row('car', cards(12), {'scrollable': true, 'carousel': {'perView': 2}}), text('e')]},
    stack('s', [row('car2', cards(12), {'scrollable': true, 'carousel': {'perView': 2}}), text('over')]),
  ]),
  'carousel in a tab': () => doc([
    {'id': 'tabs', 'type': 'Tabs', 'props': {}, 'children': [
      {'id': 'tab1', 'type': 'Tab', 'props': {'title': lit('one')}, 'children': [row('car', cards(12), {'scrollable': true, 'carousel': {'perView': 2}})]},
      {'id': 'tab2', 'type': 'Tab', 'props': {'title': lit('two')}, 'children': [text('e')]},
    ]},
  ]),
  'first screen -- a window with a carousel and steps': () => UiDocument.fromJson({
    'schemaVersion': UiDocument.supportedSchemaVersion,
    'documentId': 'attack',
    'name': 'attack',
    'initialScreenId': 'a',
    'screens': [
      {'screenId': 'a', 'name': 'a', 'presentation': 'modal', 'modalPlacement': 'center', 'root': {'id': 'root', 'type': 'Screen', 'props': {'gap': 'sm'}, 'children': [bar('b', actions: 2), row('car', cards(12), {'scrollable': true, 'carousel': {'perView': 2}}, {'pull': 128}), steps('p'), stack('s', [steps('p2'), layered(steps('p3'), {'rotate': 90})])]}},
    ],
  }),
  'first screen modal, window in the centre': () => doc([bar('b'), text('t')], first: {'presentation': 'modal', 'modalPlacement': 'center', 'statusBarIcons': 'light'}),
  'modalPlacement and statusBarIcons with the wrong words': () => doc([text('t')], first: {'modalPlacement': 'left', 'statusBarIcons': 'neon', 'presentation': 'popover'}),
};

void main() {
  for (final entry in hostile.entries) {
    for (final width in [320.0, 1.0]) {
      testWidgets('${entry.key} — width ${width.round()}: frame without an exception', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 600);
        addTearDown(tester.view.reset);
        final problems = <String>[];
        void drain(String when) {
          for (Object? error = tester.takeException(); error != null; error = tester.takeException()) {
            problems.add('$when: ${error.toString().split('\n').first}');
          }
        }

        await pumpDocument(tester, entry.value());
        drain('first frame');
        await tester.pump(const Duration(milliseconds: 300));
        drain('second frame');
        // A gesture along and across -- the carousel, body scrolling.
        if (width > 100) {
          await tester.dragFrom(const Offset(160, 60), const Offset(-200, 0));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.dragFrom(const Offset(160, 300), const Offset(0, -200));
          await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
          drain('after the gesture');
        }
        expect(problems, isEmpty);
      });
    }
  }

  // Canaries: the documents above really reach the new widgets (otherwise "no exception" says nothing).
  testWidgets('canary: five hundred overlays are drawn, a carousel in a carousel -- two scroll views', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.reset);
    await pumpDocument(tester, hostile['five hundred overlays']!());
    expect(find.byType(LayerPlace), findsNWidgets(500));
    await pumpDocument(tester, hostile['carousel in a carousel']!());
    expect(find.byType(Scrollable).evaluate().length, greaterThanOrEqualTo(2));
    await pumpDocument(tester, hostile['app bar with forty actions']!());
    expect(find.byType(ScreenZones), findsOneWidget);
    // `appBarExtraActions: 'draw-first-two'`: of forty actions the first two are drawn;
    // the canary used to assert the opposite ("the reader does not limit actions").
    int drawn(String id) => find.byTooltip(id).evaluate().length + find.bySemanticsLabel(id).evaluate().length;
    expect(drawn('b-a0'), greaterThan(0));
    expect(drawn('b-a1'), greaterThan(0));
    expect(drawn('b-a2'), 0);
    expect(drawn('b-a39'), 0);
  });

  /*
   * DIVERGENCE FROM REACT (input outside the tables): the first shown screen that the
   * document called modal. The rule of the contract: the first shown screen
   * cannot be modal; if one is met (a broken file) it is drawn as a page.
   * The React reader tells the host `presentation: 'page'` and gives no `modalPlacement`
   * (`infoOf(screen, isFirst)`), and its root takes the block entirely. Flutter
   * used to say `modal` + `center` and shrink the root to its content (`shrink`); now
   * the "effective presentation" (`_presentationAt`) is one for drawing and for the event.
   */
  testWidgets('first screen "modal": the show event says page without a layer place, the root takes the area', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.reset);
    final shown = <ScreenShown>[];
    await pumpDocument(tester, hostile['first screen modal, window in the centre']!(), onScreenShown: shown.add);
    await tester.pump();
    expect(shown, hasLength(1));
    // In one comparison -- so all three divergences are visible, not just the first.
    expect(
      {
        'presentation': shown.single.presentation,
        'modalPlacement': shown.single.modalPlacement,
        'rootHeight': tester.getSize(find.byType(ScreenZones)).height,
      },
      {'presentation': 'page', 'modalPlacement': null, 'rootHeight': 600.0},
      reason: 'the first shown screen is never modal: a page over the whole area, the layer place is not read',
    );
  });

  /*
   * INPUT OUTSIDE THE TABLES -- the same answers as the React reader
   * (the same inputs run against the React package): no divergences here.
   */
  testWidgets('as in React: an app bar that is not first -- no zone; a second app bar -- in the body; layer outside a stack and carousel without scrolling are not read', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.reset);
    int zoneChildren() => tester.renderObject<RenderScreenZones>(find.byType(ScreenZones)).childCount;

    await pumpDocument(tester, hostile['app bar not the first child']!());
    expect(zoneChildren(), 1, reason: 'body only: an app bar that is not the first child does not become a zone');
    await pumpDocument(tester, hostile['two app bars']!());
    expect(zoneChildren(), 2, reason: 'app bar zone and body; the second app bar lies in the body');

    await pumpDocument(tester, hostile['layer on a child of a non-stack (column, row, grid)']!());
    expect(find.byType(LayerPlace), findsNothing);

    await pumpDocument(tester, hostile['carousel + wrap; carousel without scrolling']!());
    expect(find.byType(Carousel), findsOneWidget, reason: 'scrollable + wrap: scrolling is stronger, the carousel works; without scrollable the field is not read');

    await pumpDocument(tester, hostile['carousel: parts of the wrong shape']!());
    expect(find.byType(Carousel), findsNWidgets(3), reason: '`carousel: "yes"` — not a carousel; the rest are carousels with natural width');
  });
}
