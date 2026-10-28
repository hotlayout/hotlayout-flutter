/// The carousel tells the active stop (schema 9.32.0, `x-carouselStop`): the `stop...` groups of the shared table
/// `fixtures/carousel/carousel-cases.json`.
///
/// `stopPathCases`, `stopShownCases`, `stopFollowCases`, `stopWriteCases` and `stopRuleCases` run through the pure
/// rules (`carousel_stop.dart`), the path rows also through node parsing. `stopRunCases` run on a REAL screen with
/// real fingers: show, swipe, wheel, hold and release, own dots, "reduce motion"; what is written is read the way a
/// host reads it (`onWrite`), and `onAction` must stay silent. `stopDocumentCases` is the table of the builder's
/// validator: this reader validates nothing, so it is not run here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show renderDocument;
import 'package:hotlayout_flutter/src/model/carousel_stop.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

const String _path = 'account.cardIndex';

void main() {
  final table = (jsonDecode(File('assets/contract/fixtures/carousel/carousel-cases.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  final schema = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  Object? valueOf(_Row row, String key) => row[key];

  final theme = RenderTheme.fromJson({
    ...(table['theme']! as _Row),
    'id': 'carousel-stop-cases',
    'name': 'Carousel stop cases',
    'brightness': 'light',
  });

  test('the table is read in full', () {
    expect(rowsOf('stopPathCases'), hasLength(8));
    expect(rowsOf('stopShownCases'), hasLength(13));
    expect(rowsOf('stopFollowCases'), hasLength(9));
    expect(rowsOf('stopWriteCases'), hasLength(7));
    expect(rowsOf('stopRunCases'), hasLength(14));
    expect(rowsOf('stopRuleCases'), hasLength(9));
    expect(rowsOf('stopDocumentCases'), hasLength(10));
  });

  group('the data of the artifact', () {
    test('`x-carouselStop` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kCarouselStopRules)), schema['x-carouselStop']);
    });

    test('the block `x-style.layout.carousel` does not mention the field', () {
      final layout = ((schema['x-style']! as _Row)['layout']! as _Row);
      expect(jsonEncode(layout['carousel']), isNot(contains('stopPath')));
    });

    test('the capability is in the catalog from 9.32.0', () {
      expect(kFeatureCatalog['carouselStop'], '9.32.0');
      expect(supportsFeature('carouselStop'), isTrue);
      expect(supportsFeature('carouselStop', readerVersion: '9.31.0'), isFalse);
    });

    for (final row in rowsOf('stopRuleCases')) {
      test('rule: ${row['name']}', () {
        Object? at = schema['x-carouselStop'];
        for (final key in (row['rule']! as String).split('.')) {
          at = (at! as _Row)[key];
        }
        expect(at, row['expect']);
      });
    }
  });

  group('the functions', () {
    for (final row in rowsOf('stopPathCases')) {
      test('path: ${row['name']}', () {
        final props = row['props']! as _Row;
        // The field alone is read by its shape; that a node hosts a carousel at all is node parsing's call.
        if (row['expect'] != null) expect(carouselStopPathOf(props['carousel']), row['expect']);
        // Through node parsing: only a host reads the field.
        final node = UiDocumentBuilder.bare([
          {
            'id': 'host',
            'type': row['type'],
            'props': {...props, if (row['type'] == 'Repeater') 'item': 'item', if (row['type'] == 'Row') 'gap': 'none'},
            'children': const <_Row>[],
          },
        ]).initialScreen.root.children.first;
        final carousel = switch (node) {
          RowNode(:final carousel) => carousel,
          RepeaterNode(:final carousel) => carousel,
          _ => null,
        };
        expect(carousel?.stopPath, row['expect']);
      });
    }

    for (final row in rowsOf('stopShownCases')) {
      test('shown: ${row['name']}', () {
        expect(carouselShownStop(valueOf(row, 'value'), row['stops']! as int), row['expect']);
      });
    }

    for (final row in rowsOf('stopFollowCases')) {
      test('follow: ${row['name']}', () {
        expect(
          carouselStopFollow(
            previous: valueOf(row, 'previous'),
            next: valueOf(row, 'next'),
            stopCount: row['stops']! as int,
            active: row['active']! as int,
          ),
          row['expect'],
        );
      });
    }

    for (final row in rowsOf('stopWriteCases')) {
      test('write: ${row['name']}', () {
        expect(
          carouselStopWrite(
            settled: row['settled']! as int,
            byPerson: row['byPerson']! as bool,
            current: valueOf(row, 'current'),
          ),
          row['expect'],
        );
      });
    }
  });

  // ──────────────────────────── a real screen ────────────────────────────

  final layout = (table['stopRunLayout']! as _Row);
  final runScreen = (table['stopRunScreen']! as List<Object?>).cast<_Row>();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = Size((layout['viewport']! as num).toDouble(), 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The table's screen on the real layout of the table: the viewport 320, the start and end padding 16, the gap 12
  /// and the card 268 come from the tokens of the table theme (`lg`, `md`) and a peek of `xl`; the own dots get a
  /// text so they have a box to tap.
  UiDocument documentOf({bool field = true}) {
    final nodes = [
      for (final node in runScreen)
        if (node['id'] == 'row')
          {
            ...node,
            'props': {
              ...(node['props']! as _Row),
              'gap': 'md',
              'carousel': {
                for (final entry in ((node['props']! as _Row)['carousel']! as _Row).entries)
                  if (field || entry.key != 'stopPath') entry.key: entry.value,
                'peek': 'xl',
              },
            },
            'style': {
              'padding': {'start': 'lg', 'end': 'lg'},
            },
          }
        else if ((node['id']! as String).startsWith('dot-'))
          node
        else if (node['id'] == 'dots')
          {
            ...node,
            'children': [
              for (final dot in (node['children']! as List<Object?>).cast<_Row>())
                {
                  ...dot,
                  'children': [
                    {
                      'id': '${dot['id']}-text',
                      'type': 'Text',
                      'props': {
                        'content': {'kind': 'literal', 'value': dot['id']},
                      },
                    },
                  ],
                },
            ],
          }
        else
          node,
    ];
    return UiDocumentBuilder.bare(nodes);
  }

  final scroller = find.descendant(of: find.byType(Carousel), matching: find.byType(SingleChildScrollView));
  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)))
      .position;

  const detailsText = {'details-0': 'Debit balance', 'details-1': 'Credit limit', 'details-2': 'Open a card'};

  List<String> shownDetails() => [
    for (final entry in detailsText.entries)
      if (find.text(entry.value).evaluate().isNotEmpty) entry.key,
  ];

  /// Moves a finger that holds the row until the scroll stands at [target]: the touch slop eats the first move.
  Future<void> dragTo(WidgetTester tester, TestGesture finger, double target, {bool rtl = false}) async {
    final position = positionOf(tester);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final delta = target - position.pixels;
      if (delta.abs() < 0.01) return;
      await finger.moveBy(Offset(rtl ? delta : -delta, 0));
      await tester.pump();
    }
  }

  group('stopRunCases: a real screen with real fingers', () {
    for (final row in rowsOf('stopRunCases')) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        final log = <List<Object?>>[];
        final actions = <String>[];
        final session = (row['session'] as _Row?) ?? const <String, Object?>{};
        final reduced = row['reducedMotion'] == true;

        Future<void> pump({Map<String, Object?>? data}) => pumpDocument(
          tester,
          documentOf(field: row['field'] != false),
          data: data ?? session,
          theme: theme,
          disableAnimations: reduced,
          onAction: (action, nodeId) => actions.add(action.type),
          onWrite: (path, value) => log.add(['write', path, value]),
        );

        await pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final physics = tester.widget<SingleChildScrollView>(scroller.first).physics! as CarouselPhysics;
        expect(physics.stops(), [for (final stop in layout['stops']! as List<Object?>) (stop! as num).toDouble()]);

        // How the show was made: standing off the first stop on the first frame is "instant".
        final position = positionOf(tester);
        String? behavior = position.pixels == 0 ? null : 'instant';
        TestGesture? finger;
        TestPointer? wheel;
        var wheelPending = false;

        Future<void> hold() async {
          finger = await tester.startGesture(tester.getCenter(scroller.first));
        }

        Future<void> release() async {
          await finger!.up();
          finger = null;
          await tester.pump();
        }

        Future<void> scrollTo(double offset) async {
          if (wheelPending) {
            wheel = TestPointer(7, PointerDeviceKind.mouse);
            await tester.sendEventToBinding(wheel!.hover(tester.getCenter(scroller.first)));
            await tester.sendEventToBinding(wheel!.scroll(Offset(offset - position.pixels, 0)));
            wheelPending = false;
            await tester.pump();
          } else {
            await dragTo(tester, finger!, offset);
          }
        }

        for (final step in (row['steps']! as List<Object?>)) {
          if (step == 'hold') {
            await hold();
          } else if (step == 'release') {
            await release();
          } else if (step == 'wheel') {
            wheelPending = true;
          } else if (step == 'scrollend') {
            // The browser event has no counterpart here: a scroll that ends tells it by its notification.
          } else if (step == 'quiet') {
            await tester.pumpAndSettle();
          } else if (step is Map && step.containsKey('scroll')) {
            await scrollTo((step['scroll']! as num).toDouble());
          } else if (step is Map && step.containsKey('swipe')) {
            await hold();
            for (final offset in (step['swipe']! as List<Object?>)) {
              await dragTo(tester, finger!, (offset! as num).toDouble());
            }
            await release();
            await tester.pumpAndSettle();
          } else if (step is Map && step.containsKey('tap')) {
            final before = position.pixels;
            await tester.tap(find.byKey(ValueKey('sdui-press-${step['tap']}@')).first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
            final early = position.pixels;
            await tester.pumpAndSettle();
            if (position.pixels != before) {
              behavior = early == position.pixels ? 'instant' : 'smooth';
            }
          } else {
            fail('unknown step $step');
          }
        }
        await tester.pumpAndSettle();

        expect(log, row['log']);
        expect(actions, isEmpty, reason: 'onAction is never called');
        expect(position.pixels, closeTo((row['offset']! as num).toDouble(), 0.01));
        expect(behavior, row['behavior']);
        expect(shownDetails(), row['shown']);
      });
    }
  });

  group('beyond the table', () {
    testWidgets('written once per settling, whatever the wheel and the finger do before', (tester) async {
      phone(tester);
      final log = <Object?>[];
      await pumpDocument(tester, documentOf(), theme: theme, onWrite: (path, value) => log.add([path, value]));
      final pointer = TestPointer(3, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(scroller.first)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(280, 0)));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(log, [
        [_path, 1],
      ]);
    });

    testWidgets('a cancelled pointer counts as released: the settled stop is written', (tester) async {
      phone(tester);
      final log = <Object?>[];
      await pumpDocument(tester, documentOf(), theme: theme, onWrite: (path, value) => log.add([path, value]));
      final finger = await tester.startGesture(tester.getCenter(scroller.first));
      await dragTo(tester, finger, 280);
      await finger.cancel();
      await tester.pumpAndSettle();
      expect(log, [
        [_path, 1],
      ]);
      expect(positionOf(tester).pixels, closeTo(280, 0.01));
    });

    testWidgets('right to left the show on stop 2 stands at the logical offset 540', (tester) async {
      phone(tester);
      await pumpDocument(tester, documentOf(), data: const {_path: 2}, theme: theme, locale: 'ar');
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(540, 0.01));
    });

    testWidgets('a write the gate refuses leaves the carousel where the person put it', (tester) async {
      phone(tester);
      final log = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: renderDocument(
              documentOf(),
              theme: theme,
              data: const {},
              writablePaths: const <String>[],
              onWrite: (path, value) => log.add([path, value]),
            ),
          ),
        ),
      );
      final finger = await tester.startGesture(tester.getCenter(scroller.first));
      await dragTo(tester, finger, 280);
      await finger.up();
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(positionOf(tester).pixels, closeTo(280, 0.01));
    });

    testWidgets('the host changing the value moves the carousel; a finger that holds the row wins', (tester) async {
      phone(tester);
      Future<void> pump(Object? value) => pumpDocument(tester, documentOf(), data: {_path: value}, theme: theme);
      await pump(0);
      await tester.pumpAndSettle();
      await pump(2);
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(540, 0.01));

      final finger = await tester.startGesture(tester.getCenter(scroller.first));
      await dragTo(tester, finger, 500);
      await pump(1);
      await tester.pump(const Duration(seconds: 1));
      expect(positionOf(tester).pixels, closeTo(500, 0.01), reason: 'the change under the finger is not applied');
      await finger.up();
      await tester.pumpAndSettle();
    });

    testWidgets('natural card widths: the show stands on the stop once the cards are measured', (tester) async {
      phone(tester);
      final doc = UiDocumentBuilder.bare([
        {
          'id': 'row',
          'type': 'Row',
          'props': {
            'gap': 'md',
            'scrollable': true,
            'carousel': {'indicator': 'none', 'stopPath': _path},
          },
          'children': [
            for (var i = 0; i < 4; i += 1)
              {
                'id': 'c$i',
                'type': 'Container',
                'props': {'direction': 'column', 'gap': 'none'},
                'style': {'width': 200},
                'children': [
                  {
                    'id': 'c$i-t',
                    'type': 'Text',
                    'props': {
                      'content': {'kind': 'literal', 'value': 'card $i'},
                    },
                  },
                ],
              },
          ],
        },
      ]);
      await pumpDocument(tester, doc, data: const {_path: 1}, theme: theme);
      await tester.pumpAndSettle();
      expect(positionOf(tester).pixels, closeTo(212, 0.01));
    });
  });
}
