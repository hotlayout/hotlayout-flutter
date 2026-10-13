/// CAROUSEL (schema 9.11.0):
/// the shared case table -- ENTIRELY through the renderer.
///
/// The table is ONE for all readers (`fixtures/carousel/carousel-cases.json`), and
/// the test reads the artifact itself: a row added in the builder starts
/// being checked here after `cp`, without edits to this file. No rows are skipped
/// silently: `readerOnly` rows (documents the builder will not produce) are just as
/// mandatory for the reader.
///
/// Six groups, and each runs two ways -- through the rule (`carousel_rules.dart`)
/// and through a real node on screen (scrolling by `drag` / `fling` and checking
/// where it stopped):
///  1. `hostCases` -- what can be a carousel (node parsing and widget presence);
///  2. `readCases` -- how a field value is read;
///  3. `cardCases` -- card width at 320 / 393 / 768;
///  4. `stopCases` -- snap stops (formula, physics, the stop after a gesture);
///  5. `activeCases` -- which stop is active (formula and the active dot);
///  6. `dotCases` -- how many dots and how much room they take.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/carousel_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/progress_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/demo_data.dart';
import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table =
      jsonDecode(File('assets/contract/fixtures/carousel/carousel-cases.json').readAsStringSync())
          as Map<String, Object?>;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final hostCases = rowsOf('hostCases');
  final readCases = rowsOf('readCases');
  final cardCases = rowsOf('cardCases');
  final stopCases = rowsOf('stopCases');
  final activeCases = rowsOf('activeCases');
  final dotCases = rowsOf('dotCases');
  final areaCases = rowsOf('areaCases');
  final stateCases = rowsOf('stateCases');

  final theme = RenderTheme.fromJson({
    ...(table['theme']! as Map<String, Object?>),
    'id': 'carousel-cases',
    'name': 'Carousel cases',
    'brightness': 'light',
  });
  final spacing = (table['theme']! as Map<String, Object?>)['spacing']! as Map<String, Object?>;

  /// Table token -> theme inset; a number is as is.
  double space(Object? ref) => ref is num ? ref.toDouble() : (spacing[ref]! as num).toDouble();

  test('the table is read entirely, and every field of it is known to this test', () {
    expect(hostCases, hasLength(8));
    expect(readCases, hasLength(17));
    expect(cardCases, hasLength(17));
    expect(stopCases, hasLength(10));
    expect(activeCases, hasLength(10));
    expect(dotCases, hasLength(10));
    expect(areaCases, hasLength(4));
    expect(stateCases, hasLength(6));
    const known = {
      'hostCases': {'name', 'type', 'props', 'readerOnly', 'expect'},
      'readCases': {'name', 'value', 'readerOnly', 'expect'},
      'cardCases': {'name', 'viewport', 'paddingStart', 'paddingEnd', 'gap', 'peek', 'perView', 'readerOnly', 'expect'},
      'stopCases': {'name', 'viewport', 'paddingStart', 'paddingEnd', 'gap', 'cards', 'expect'},
      'activeCases': {'name', 'stops', 'offset', 'expect'},
      'dotCases': {'name', 'indicator', 'stops', 'viewport', 'expect'},
      'areaCases': {'name', 'place', 'indicator', 'paddingStart', 'paddingEnd', 'gap', 'cards', 'expect'},
      'stateCases': {'name', 'a', 'b', 'sameState'},
    };
    for (final entry in known.entries) {
      final rows = rowsOf(entry.key);
      for (final row in rows) {
        expect(
          row.keys.toSet().difference(entry.value),
          isEmpty,
          reason: '${entry.key}/${row['name']}: unknown field',
        );
      }
      expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: '${entry.key}: names are unique');
    }
    // The theme values the test reads are the ones written in the table.
    expect(theme.spacing['lg'], 16);
    expect(theme.radii['pill'], 72);
  });

  // ───────────────────────────────────────────────────────── helpers ──

  void phone(WidgetTester tester, double width, {double height = 900}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  _Row card(String id, {Object? width, double? height = 40}) => {
    'id': id,
    'type': 'Container',
    'props': {'direction': 'column', 'gap': 'none'},
    'style': {
      'background': {'kind': 'color', 'color': 'surface'},
      'width': ?width,
      'minHeight': ?height,
    },
    'children': [
      {
        'id': '$id-text',
        'type': 'Text',
        'props': {
          'content': {'kind': 'literal', 'value': id},
        },
      },
    ],
  };

  _Row rowNode(
    List<_Row> cards, {
    Object? carousel = const <String, Object?>{},
    Object? gap = 'none',
    Object? paddingStart = 'none',
    Object? paddingEnd = 'none',
    bool scrollable = true,
  }) => {
    'id': 'row',
    'type': 'Row',
    'props': {
      'gap': gap,
      'align': 'start',
      'justify': 'start',
      'wrap': false,
      'scrollable': scrollable,
      'carousel': ?carousel,
    },
    'style': {
      'padding': {'start': paddingStart, 'end': paddingEnd},
    },
    'children': cards,
  };

  UiDocument bare(List<_Row> children) => UiDocumentBuilder.bare(children);

  /// A carousel's scroll view is not the screen's (that one is also a `SingleChildScrollView`).
  final carouselScroll = find.descendant(of: find.byType(Carousel), matching: find.byType(SingleChildScrollView));

  Carousel carouselOf(WidgetTester tester) => tester.widget<Carousel>(find.byType(Carousel));

  CarouselPhysics physicsOf(WidgetTester tester) {
    final scroll = tester.widget<SingleChildScrollView>(carouselScroll);
    return scroll.physics! as CarouselPhysics;
  }

  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)))
      .position;

  /// Width of the box of card `id`: the surface closest to the text.
  double cardWidth(WidgetTester tester, String id) =>
      tester.getSize(find.ancestor(of: find.text(id), matching: find.byType(DecoratedBox)).first).width;

  Finder dotWhere(bool Function(String key) test) => find.descendant(
    of: find.byType(Carousel),
    matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> && test((w.key! as ValueKey<String>).value)),
  );
  final activeDot = dotWhere((k) => k.startsWith('carousel-dot-active'));
  final inactiveDots = dotWhere((k) => k.startsWith('carousel-dot-') && !k.startsWith('carousel-dot-active'));
  final anyDots = dotWhere((k) => k.startsWith('carousel-dot'));

  List<int> activeAndCount(WidgetTester tester) {
    final all = tester.widgetList(anyDots).toList();
    final active = all.indexWhere((w) => (w.key! as ValueKey<String>).value.startsWith('carousel-dot-active'));
    return [all.length, active];
  }

  // ─────────────────────────────────────────────────────────── hostCases ──

  group('hostCases -- what can be a carousel', () {
    for (final row in hostCases) {
      final name = row['name']! as String;
      final type = row['type']! as String;
      final props = row['props']! as _Row;
      final expected = row['expect']! as bool;

      Map<String, Object?> node() => {
        'id': 'host',
        'type': type,
        'props': {
          ...props,
          'carousel': const <String, Object?>{},
          if (type == 'Row') ...{'gap': 'none'},
          if (type == 'Repeater') ...{'source': 'tasks', 'item': 'task', 'gap': 'sm'},
          if (type == 'Container') 'gap': 'none',
        },
        'children': [
          {
            'id': 'inner',
            'type': 'Text',
            'props': {
              'content': {'kind': 'binding', 'path': 'task.title', 'fallback': 'x'},
            },
          },
        ],
      };

      test('parsing: $name', () {
        final parsed = bare([node()]).initialScreen.root.children.first;
        final carousel = switch (parsed) {
          RowNode(:final carousel) => carousel,
          RepeaterNode(:final carousel) => carousel,
          _ => null,
        };
        expect(carousel != null, expected);
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester, 320);
        await pumpDocument(tester, bare([node()]), data: sampleScreenData, theme: theme);
        expect(tester.takeException(), isNull);
        expect(find.byType(Carousel), expected ? findsOneWidget : findsNothing);
      });
    }
  });

  // ──────────────────────────────────────────────────────────── readCases ──

  group('readCases -- how a field value is read', () {
    for (final row in readCases) {
      final name = row['name']! as String;
      final expected = row['expect'] as _Row?;

      test('rule: $name', () {
        final read = readCarousel(row['value']);
        if (expected == null) {
          expect(read, isNull);
          return;
        }
        expect(read, isNotNull);
        expect(read!.perView, expected['perView']);
        final peek = read.peek;
        expect(peek == null ? null : (peek.token ?? peek.value!.round()), expected['peek']);
        expect(read.dots ? 'dots' : 'none', expected['indicator']);
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester, 320);
        final cards = [card('c0'), card('c1')];
        await pumpDocument(tester, bare([rowNode(cards, carousel: row['value'])]), theme: theme);
        expect(tester.takeException(), isNull);
        // Not an object -- no carousel, while the row still scrolls, as in 9.10.
        expect(find.byType(Carousel), expected == null ? findsNothing : findsOneWidget);
        // The row scrolls both with and without a carousel: the scroll views on screen are its own and the screen's.
        expect(find.byType(SingleChildScrollView), findsNWidgets(2));
      });
    }
  });

  // ──────────────────────────────────────────────────────────── cardCases ──

  group('cardCases -- card width', () {
    for (final row in cardCases) {
      final name = row['name']! as String;
      final viewport = (row['viewport']! as num).toDouble();
      final perView = row['perView']! as int;
      final expected = (row['expect'] as num?)?.toDouble();
      final paddingEnd = row['paddingEnd'] ?? 'none';

      double peekOf(Object? peek) {
        final ref = readProgressThickness(peek);
        return (ref == null ? null : theme.resolveSpacing(ref)) ?? theme.spacing[kDefaultCarouselPeek]!;
      }

      test('rule: $name', () {
        final width = carouselCardWidth(
          viewport: viewport,
          paddingStart: space(row['paddingStart']),
          gap: space(row['gap']),
          peek: peekOf(row['peek']),
          perView: perView,
        );
        if (expected == null) {
          expect(width, isNull);
        } else {
          expect(width, closeTo(expected, 1e-9));
        }
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester, viewport);
        await pumpDocument(
          tester,
          bare([
            rowNode(
              // The card's own width is not read (`overridesOwnWidth`).
              [card('c0', width: 90), card('c1', width: 90), card('c2')],
              carousel: {'perView': perView, 'peek': ?row['peek']},
              gap: row['gap'],
              paddingStart: row['paddingStart'],
              paddingEnd: paddingEnd,
            ),
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
        if (expected == null) {
          // No card came out: the width is natural, as without the field.
          expect(carouselOf(tester).cardWidths, isNull);
          return;
        }
        expect(cardWidth(tester, 'c0'), closeTo(expected, 1e-6), reason: 'own width 90 is not read');
        expect(cardWidth(tester, 'c1'), closeTo(expected, 1e-6));
        expect(cardWidth(tester, 'c2'), closeTo(expected, 1e-6));
        // Start inset + perView × (width + gap) + peek = the visible area.
        final gap = space(row['gap']);
        expect(space(row['paddingStart']) + perView * (expected + gap) + peekOf(row['peek']), closeTo(viewport, 1e-6));
      });
    }
  });

  // ──────────────────────────────────────────────────────────── stopCases ──

  group('stopCases -- snap stops', () {
    for (final row in stopCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as _Row;
      final cards = [for (final w in row['cards']! as List<Object?>) (w! as num).toDouble()];
      final viewport = (row['viewport']! as num).toDouble();
      final paddingStart = (row['paddingStart']! as num).toDouble();
      final paddingEnd = (row['paddingEnd']! as num).toDouble();
      final gap = (row['gap']! as num).toDouble();
      final stops = [for (final s in expected['stops']! as List<Object?>) (s! as num).toDouble()];

      test('rule: $name', () {
        final result = carouselStops(
          viewport: viewport,
          paddingStart: paddingStart,
          paddingEnd: paddingEnd,
          gap: gap,
          cards: cards,
        );
        expect(result.maxScroll, closeTo((expected['maxScroll']! as num).toDouble(), 1e-9));
        expect(result.stops, hasLength(stops.length));
        for (var i = 0; i < stops.length; i += 1) {
          expect(result.stops[i], closeTo(stops[i], 1e-9), reason: 'stop $i');
        }
        expect(result.stopOfCard, expected['stopOfCard']);
      });

      if (cards.isEmpty) continue;

      for (final locale in ['en', 'ar']) {
        testWidgets('screen ($locale): $name', (tester) async {
          phone(tester, viewport);
          await pumpDocument(
            tester,
            bare([
              rowNode(
                [for (var i = 0; i < cards.length; i += 1) card('c$i', width: cards[i])],
                gap: gap,
                paddingStart: paddingStart,
                paddingEnd: paddingEnd,
              ),
            ]),
            theme: theme,
            locale: locale,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // The stops the physics sees are measured from the layout, and match the table.
          final live = physicsOf(tester).stops();
          expect(live, hasLength(stops.length));
          for (var i = 0; i < stops.length; i += 1) {
            expect(live[i], closeTo(stops[i], 1e-6), reason: 'stop $i on screen');
          }

          // By gesture to the end: scrolling stops at the LAST stop, not further.
          final position = positionOf(tester);
          expect(position.pixels, 0, reason: 'we start at the first stop');
          final toward = locale == 'ar' ? const Offset(2000, 0) : const Offset(-2000, 0);
          await tester.fling(carouselScroll, toward, 3000);
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(stops.last, 1e-6), reason: 'the end of scrolling is always a stop');
          // And back: to the first.
          await tester.fling(carouselScroll, toward * -1, 3000);
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(0, 1e-6));
        });
      }
    }
  });

  // ────────────────────────────────────────────────────────── activeCases ──

  group('activeCases -- active stop', () {
    for (final row in activeCases) {
      final name = row['name']! as String;
      final stops = [for (final s in row['stops']! as List<Object?>) (s! as num).toDouble()];
      final offset = (row['offset']! as num).toDouble();
      final expected = row['expect']! as int;

      test('rule: $name', () {
        expect(activeCarouselStop(stops, offset), expected);
      });

      // On screen: cards of such a width that the stops match the table.
      // An offset outside the bounds (bounce) cannot be tried -- the rule checks it.
      if (stops.length > 1 && offset >= 0 && offset <= stops.last) {
        testWidgets('screen: $name', (tester) async {
          phone(tester, 320);
          // The table stops [0, 280, 540] are three cards of 268 at 320.
          expect(stops, [0, 280, 540]);
          await pumpDocument(
            tester,
            bare([
              rowNode(
                [card('c0'), card('c1'), card('c2')],
                carousel: {'perView': 1, 'peek': 'xl'},
                gap: 'md',
                paddingStart: 'lg',
                paddingEnd: 'lg',
              ),
            ]),
            theme: theme,
          );
          await tester.pumpAndSettle();
          positionOf(tester).jumpTo(offset);
          await tester.pump();
          expect(positionOf(tester).pixels, closeTo(offset, 1e-6));
          expect(activeAndCount(tester), [3, expected]);
        });
      }
    }
  });

  // ───────────────────────────────────────────────────────────── dotCases ──

  group('dotCases -- dots', () {
    for (final row in dotCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as _Row;
      final stops = row['stops']! as int;
      final indicator = row['indicator']! as String;
      final dots = expected['dots']! as int;
      final viewport = (row['viewport']! as num).toDouble();
      final block = (expected['block']! as num).toDouble();

      test('rule: $name', () {
        expect(
          carouselDotCount(
            dots: indicator == 'dots',
            stopCount: stops,
            viewport: viewport,
            dotSize: theme.spacing[kCarouselDotSize]!,
            dotGap: theme.spacing[kCarouselDotGap]!,
          ),
          dots,
        );
        expect(
          carouselIndicatorBlock(dots, theme.spacing[kCarouselIndicatorGap]!, theme.spacing[kCarouselDotSize]!),
          block,
        );
      });

      testWidgets('screen: $name', (tester) async {
        // `stops` cards as wide as the area (`row.viewport`): each is a separate stop.
        phone(tester, viewport);
        await pumpDocument(
          tester,
          bare([
            rowNode(
              [for (var i = 0; i < stops; i += 1) card('c$i', height: 40)],
              carousel: {'perView': 1, 'peek': 0, 'indicator': indicator},
            ),
          ]),
          theme: theme,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(physicsOf(tester).stops(), hasLength(stops));
        final dotsOnScreen = activeAndCount(tester).first;
        expect(dotsOnScreen, dots);
        // Room for the dots: carousel height = card + gap and dot (or nothing).
        expect(tester.getSize(find.byType(Carousel)).height, closeTo(40 + block, 1e-6));
      });
    }
  });

  // ───────────────────────────────────────────── areaCases ──

  group('areaCases -- the presence of dots does not change the area', () {
    for (final row in areaCases) {
      final name = row['name']! as String;
      final expected = row['expect']! as _Row;
      final place = (row['place']! as num).toDouble();
      final cards = [for (final w in row['cards']! as List<Object?>) (w! as num).toDouble()];
      final stops = [for (final s in expected['stops']! as List<Object?>) (s! as num).toDouble()];
      final indicator = row['indicator']! as String;

      _Row strip() => rowNode(
        [for (var i = 0; i < cards.length; i += 1) card('c$i', width: cards[i])],
        carousel: {'indicator': indicator},
        gap: row['gap'],
        paddingStart: row['paddingStart'],
        paddingEnd: row['paddingEnd'],
      );

      Future<void> check(WidgetTester tester) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(carouselOf(tester).viewport, closeTo((expected['viewport']! as num).toDouble(), 1e-6), reason: 'area');
        final live = physicsOf(tester).stops();
        expect(live, hasLength(stops.length), reason: 'as many stops as without dots');
        for (var i = 0; i < stops.length; i += 1) {
          expect(live[i], closeTo(stops[i], 1e-6), reason: 'stop $i');
        }
        expect(anyDots.evaluate().length, expected['dots']);
        // The shell is the same box: the place width, with dots and without.
        expect(tester.getSize(find.byType(Carousel)).width, closeTo(place, 1e-6));
      }

      testWidgets('place ${place.round()} (box with a named width): $name', (tester) async {
        phone(tester, 400);
        await pumpDocument(
          tester,
          bare([
            {
              'id': 'place',
              'type': 'Container',
              'props': {'direction': 'column', 'gap': 'none'},
              'style': {'width': place},
              'children': [strip()],
            },
          ]),
          theme: theme,
        );
        await check(tester);
      });

      if (place == 252) {
        testWidgets('place from a neighbour in a row container (360 - 100 - 8): $name', (tester) async {
          phone(tester, 400);
          await pumpDocument(
            tester,
            bare([
              {
                'id': 'outer',
                'type': 'Container',
                'props': {'direction': 'row', 'gap': 'sm'},
                'style': {'width': 360},
                'children': [
                  {...strip(), 'weight': 1},
                  card('sibling', width: 100),
                ],
              },
            ]),
            theme: theme,
          );
          await check(tester);
        });
      }
    }
  });

  // ───────────────────────────────────────────── stateCases ──

  group('stateCases -- the carousel state key', () {
    for (final row in stateCases) {
      test('rule: ${row['name']}', () {
        String key(Object? side) {
          final map = side! as _Row;
          return carouselStateKey(map['node']! as String, [for (final i in map['instance']! as List<Object?>) i! as int]);
        }

        expect(key(row['a']) == key(row['b']), row['sameState']);
      });
    }
  });

  group('dots that do not fit', () {
    // Ten `sm` dots at `sm` spacing -- 152 dp. An indicator that does not fit in the
    // area is not drawn and takes no room -- the same rule as "more than 10
    // stops": a row that sticks out past the edge is worse than none.
    test('rule: a row wider than the area -- no dots', () {
      expect(carouselDotCount(dots: true, stopCount: 10, viewport: 100, dotSize: 8, dotGap: 8), 0);
      expect(carouselDotCount(dots: true, stopCount: 10, viewport: 152, dotSize: 8, dotGap: 8), 10);
      expect(carouselDotCount(dots: true, stopCount: 10, viewport: 151, dotSize: 8, dotGap: 8), 0);
      expect(carouselDotCount(dots: true, stopCount: 3, viewport: 100, dotSize: 8, dotGap: 8), 3);
    });

    testWidgets('ten stops in an area of 100: no dots, they take no room, no overflow', (
      tester,
    ) async {
      phone(tester, 100);
      await pumpDocument(
        tester,
        bare([
          rowNode(
            [for (var i = 0; i < 10; i += 1) card('c$i', height: 40)],
            carousel: {'perView': 1, 'peek': 0, 'indicator': 'dots'},
          ),
        ]),
        theme: theme,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow of the dot row');
      expect(physicsOf(tester).stops(), hasLength(10));
      expect(anyDots, findsNothing);
      expect(tester.getSize(find.byType(Carousel)).height, closeTo(40, 1e-6));
    });
  });

  // ─────────────────────────────────────────────── gesture on a real layout ──

  group('gesture: three cards of 268 at 320', () {
    _Row threeCards({String indicator = 'dots'}) => rowNode(
      [card('c0'), card('c1'), card('c2')],
      carousel: {'perView': 1, 'peek': 'xl', 'indicator': indicator},
      gap: 'md',
      paddingStart: 'lg',
      paddingEnd: 'lg',
    );

    testWidgets('snaps to the start of each card: 0 -> 280 -> 540 (not 560) -> back', (tester) async {
      phone(tester, 320);
      await pumpDocument(tester, bare([threeCards()]), theme: theme);
      await tester.pumpAndSettle();
      final position = positionOf(tester);
      expect(position.pixels, 0);
      expect(activeAndCount(tester), [3, 0]);

      await tester.drag(carouselScroll, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(280, 1e-6), reason: 'half a step moves to the next card');
      expect(activeAndCount(tester), [3, 1]);
      // The second card stands on the start inset line.
      expect(
        tester.getTopLeft(find.ancestor(of: find.text('c1'), matching: find.byType(DecoratedBox)).first).dx,
        closeTo(16, 1e-6),
      );

      await tester.drag(carouselScroll, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(540, 1e-6), reason: 'the last card stops at the end of scrolling');
      expect(activeAndCount(tester), [3, 2]);
      // The last card stands the same distance from the edge as the first: 16 on the right.
      expect(
        tester.getTopRight(find.ancestor(of: find.text('c2'), matching: find.byType(DecoratedBox)).first).dx,
        closeTo(320 - 16, 1e-6),
      );

      await tester.drag(carouselScroll, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(540, 1e-6), reason: 'short of half a step -- it stays');
      await tester.drag(carouselScroll, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(280, 1e-6));
    });

    testWidgets('a fast fling leads to the NEXT stop, not a far one', (tester) async {
      phone(tester, 320);
      await pumpDocument(tester, bare([threeCards()]), theme: theme);
      await tester.pumpAndSettle();
      await tester.fling(carouselScroll, const Offset(-120, 0), 1500);
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(280, 1e-6));
    });

    testWidgets('right-to-left writing: the first card is on the right, the offset is from the logical start', (tester) async {
      phone(tester, 320);
      await pumpDocument(tester, bare([threeCards()]), theme: theme, locale: 'ar');
      await tester.pumpAndSettle();
      final first = find.ancestor(of: find.text('c0'), matching: find.byType(DecoratedBox)).first;
      expect(tester.getTopRight(first).dx, closeTo(320 - 16, 1e-6));
      await tester.drag(carouselScroll, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(280, 1e-6));
      expect(
        tester.getTopRight(find.ancestor(of: find.text('c1'), matching: find.byType(DecoratedBox)).first).dx,
        closeTo(320 - 16, 1e-6),
      );
      // Dots in reading order: the active second is to the right of the first, to the left of the third.
      final active = tester.getCenter(activeDot).dx;
      final xs = [for (final e in inactiveDots.evaluate()) tester.getCenter(find.byWidget(e.widget)).dx]..sort();
      expect(xs.where((x) => x > active), hasLength(1));
      expect(xs.where((x) => x < active), hasLength(1));
    });

    testWidgets('dots: width of the sm diameter, sm between them, not a control and not in the accessibility tree', (tester) async {
      phone(tester, 320);
      await pumpDocument(tester, bare([threeCards()]), theme: theme);
      await tester.pumpAndSettle();
      final dots = anyDots;
      expect(dots, findsNWidgets(3));
      final rects = [for (final e in dots.evaluate()) tester.getRect(find.byWidget(e.widget))];
      expect(rects.first.width, 8);
      expect(rects.first.height, 8);
      expect(rects[1].left - rects[0].right, 8);
      // Centred horizontally, with an sm gap under the area.
      final scroll = tester.getRect(carouselScroll);
      expect(rects[1].center.dx, closeTo(scroll.center.dx, 1e-6));
      expect(rects.first.top - scroll.bottom, 8);
      // Decoration: ExcludeSemantics over them, no touch handler.
      expect(find.ancestor(of: dots.first, matching: find.byType(ExcludeSemantics)), findsWidgets);
      expect(
        find.descendant(
          of: find.ancestor(of: dots.first, matching: find.byType(ExcludeSemantics)).first,
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      // The active color is primary, the inactive is the same with 0.3 opacity.
      final active = tester.widget<Container>(activeDot);
      final inactive = tester.widget<Container>(inactiveDots.first);
      final activeColor = (active.decoration! as BoxDecoration).color!;
      final inactiveColor = (inactive.decoration! as BoxDecoration).color!;
      expect(activeColor.toARGB32(), 0xFF4F46E5);
      expect(inactiveColor.a, closeTo(activeColor.a * 0.3, 1e-6));
      expect(inactiveColor.toARGB32() & 0x00FFFFFF, 0x4F46E5);
    });

    testWidgets('semantics: a list with list items, the dots do not get into the tree', (tester) async {
      final handle = tester.ensureSemantics();
      phone(tester, 320);
      await pumpDocument(tester, bare([threeCards()]), theme: theme);
      await tester.pumpAndSettle();
      final roles = <SemanticsRole>[];
      void walk(SemanticsNode node) {
        roles.add(node.getSemanticsData().role);
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(tester.getSemantics(find.byType(Scaffold)));
      expect(roles.where((r) => r == SemanticsRole.list), isNotEmpty);
      expect(roles.where((r) => r == SemanticsRole.listItem), hasLength(3));
      handle.dispose();
    });

    testWidgets('reader state: the same offset survives a screen repaint', (tester) async {
      phone(tester, 320);
      await pumpDocument(tester, bare([threeCards()]), theme: theme);
      await tester.pumpAndSettle();
      await tester.drag(carouselScroll, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(280, 1e-6));
      await pumpDocument(tester, bare([threeCards()]), theme: theme);
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(280, 1e-6));
      expect(activeAndCount(tester), [3, 1]);
    });
  });

  group('data list in a row', () {
    _Row repeater({Object? carousel, int? columns, String direction = 'row'}) => {
      'id': 'list',
      'type': 'Repeater',
      'props': {
        'source': 'tasks',
        'item': 'task',
        'direction': direction,
        'gap': 'md',
        'columns': ?columns,
        'carousel': ?carousel,
      },
      'style': {
        'padding': {'start': 'lg', 'end': 'lg'},
      },
      'children': [card('tpl', height: 40)],
    };

    testWidgets('with the field it scrolls on its own: a card per record, each with its own record', (tester) async {
      phone(tester, 320);
      final tasks = sampleScreenData['tasks']! as List<Object?>;
      await pumpDocument(
        tester,
        bare([
          repeater(carousel: {'perView': 1, 'peek': 'xl'}),
        ]),
        data: sampleScreenData,
        theme: theme,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Carousel), findsOneWidget);
      expect(physicsOf(tester).stops(), hasLength(tasks.length));
      expect(activeAndCount(tester).first, tasks.length);
    });

    testWidgets('without the field a list in a row does not scroll (as in 9.10)', (tester) async {
      phone(tester, 320);
      await pumpDocument(tester, bare([repeater()]), data: sampleScreenData, theme: theme);
      expect(find.byType(Carousel), findsNothing);
      expect(find.byType(SingleChildScrollView), findsOneWidget, reason: 'only the screen scroll');
    });

    testWidgets('a grid ("columns") is never a carousel: the field is skipped', (tester) async {
      phone(tester, 320);
      await pumpDocument(
        tester,
        bare([
          repeater(carousel: {'perView': 1}, columns: 2),
        ]),
        data: sampleScreenData,
        theme: theme,
      );
      expect(find.byType(Carousel), findsNothing);
    });

    testWidgets('a list in a column is never a carousel', (tester) async {
      phone(tester, 320);
      await pumpDocument(
        tester,
        bare([
          repeater(carousel: {'perView': 1}, direction: 'column'),
        ]),
        data: sampleScreenData,
        theme: theme,
      );
      expect(find.byType(Carousel), findsNothing);
    });
  });
}
