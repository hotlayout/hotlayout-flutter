/// A carousel that advances by time (schema 9.42.0, `x-carouselAutoAdvance`): the `autoAdvance...` groups of the shared
/// table `fixtures/carousel/carousel-cases.json`.
///
/// `autoAdvanceReadCases`, `autoAdvanceNextCases`, `autoAdvanceTickCases`, `autoAdvanceWriteCases` and
/// `autoAdvanceRuleCases` run through the pure rules (`carousel_auto_advance.dart`), the read rows also through node
/// parsing. `autoAdvanceRunCases` run on a REAL screen on the fake clock of the test, in steps of 100 ms (the tick of
/// the reader): the timer, the pauses (a held finger, the background, a layer over the screen), a swipe and "reduce
/// motion"; what is written is read the way a host reads it (`onWrite`), and `onAction` must stay silent.
/// `autoAdvanceDocumentCases` is the table of the builder's validator: this reader validates nothing, so it is not run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/carousel_auto_advance.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/carousel.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

const List<double> _stops = [0, 280, 540];

void main() {
  final table = (jsonDecode(File('assets/contract/fixtures/carousel/carousel-cases.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  final schema = (jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();

  final theme = RenderTheme.fromJson({
    ...(table['theme']! as _Row),
    'id': 'carousel-auto-advance-cases',
    'name': 'Carousel auto-advance cases',
    'brightness': 'light',
  });

  test('the table is read in full', () {
    expect(rowsOf('autoAdvanceReadCases'), hasLength(12));
    expect(rowsOf('autoAdvanceNextCases'), hasLength(7));
    expect(rowsOf('autoAdvanceTickCases'), hasLength(12));
    expect(rowsOf('autoAdvanceWriteCases'), hasLength(5));
    expect(rowsOf('autoAdvanceDocumentCases'), hasLength(12));
    expect(rowsOf('autoAdvanceRunCases'), hasLength(17));
    expect(rowsOf('autoAdvanceRuleCases'), hasLength(10));
  });

  group('the data of the artifact', () {
    test('`x-carouselAutoAdvance` is mirrored whole', () {
      expect(jsonDecode(jsonEncode(kCarouselAutoAdvanceRules)), schema['x-carouselAutoAdvance']);
    });

    test('the blocks it refines do not mention the field', () {
      final layout = ((schema['x-style']! as _Row)['layout']! as _Row);
      expect(jsonEncode(layout['carousel']), isNot(contains('autoAdvance')));
      expect(jsonEncode(schema['x-carouselStop']), isNot(contains('autoAdvance')));
    });

    test('the capability is in the catalog from 9.42.0', () {
      expect(kFeatureCatalog['carouselAutoAdvance'], '9.42.0');
      expect(supportsFeature('carouselAutoAdvance'), isTrue);
      expect(supportsFeature('carouselAutoAdvance', readerVersion: '9.41.0'), isFalse);
    });

    test('the pauses are the list of the artifact, in its order', () {
      expect([for (final pause in AutoAdvancePause.values) pause.name], [
        'held',
        'keyboardFocus',
        'moving',
        'notShown',
        'screenReader',
      ]);
    });

    for (final row in rowsOf('autoAdvanceRuleCases')) {
      test('rule: ${row['name']}', () {
        Object? at = schema['x-carouselAutoAdvance'];
        for (final key in (row['rule']! as String).split('.')) {
          at = (at! as _Row)[key];
        }
        expect(at, row['expect']);
      });
    }
  });

  group('the functions', () {
    for (final row in rowsOf('autoAdvanceReadCases')) {
      test('read: ${row['name']}', () {
        final props = row['props']! as _Row;
        final expected = row['expect'] as _Row?;
        // The field alone is read by its shape; that a node hosts a carousel at all is node parsing's call.
        if (expected != null) {
          final read = carouselAutoAdvanceOf(props['carousel']);
          expect(read?.intervalMs, (expected['intervalMs']! as num).toDouble());
          expect(read?.loop, expected['loop']);
        }
        // Through node parsing: only a carousel host reads the field.
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
        expect(carousel?.autoAdvance?.intervalMs, (expected?['intervalMs'] as num?)?.toDouble());
        expect(carousel?.autoAdvance?.loop, expected?['loop']);
      });
    }

    for (final row in rowsOf('autoAdvanceNextCases')) {
      test('next: ${row['name']}', () {
        expect(carouselAutoAdvanceNext(row['active']! as int, row['stops']! as int, row['loop']! as bool), row['expect']);
      });
    }

    for (final row in rowsOf('autoAdvanceTickCases')) {
      test('tick: ${row['name']}', () {
        final from = row['state']! as _Row;
        final input = row['input']! as _Row;
        final expected = row['expect']! as _Row;
        final tick = carouselAutoAdvanceTick(
          AutoAdvanceState(active: from['active']! as int, elapsed: (from['elapsed']! as num).toDouble()),
          dtMs: (input['dtMs']! as num).toDouble(),
          active: input['active']! as int,
          stopCount: input['stops']! as int,
          paused: input['paused']! as bool,
          intervalMs: (input['intervalMs']! as num).toDouble(),
          loop: input['loop']! as bool,
        );
        final state = expected['state']! as _Row;
        expect(tick.state.active, state['active']);
        expect(tick.state.elapsed, (state['elapsed']! as num).toDouble());
        expect(tick.step, expected['step']);
      });
    }

    for (final row in rowsOf('autoAdvanceWriteCases')) {
      test('write: ${row['name']}', () {
        expect(carouselAutoAdvanceWrite(row['step']! as int, row['current']), row['expect']);
      });
    }
  });

  // ──────────────────────────── a real screen ────────────────────────────

  final runScreen = (table['autoAdvanceRunScreen']! as List<Object?>).cast<_Row>();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The table's screen on the real layout of the stop table: the viewport 320, the start and end padding 16, the gap 12
  /// and the card 268 come from the tokens of the table theme (`lg`, `md`) and a peek of `xl`.
  List<_Row> nodesOf(_Row row) => [
    for (final node in runScreen)
      if (node['id'] == 'row')
        {
          ...node,
          'props': {
            ...(node['props']! as _Row),
            'gap': 'md',
            'carousel': {
              for (final entry in ((node['props']! as _Row)['carousel']! as _Row).entries)
                if (entry.key == 'stopPath'
                    ? row['field'] != 'noPath'
                    : entry.key == 'autoAdvance'
                    ? row['field'] != 'off'
                    : true)
                  entry.key: entry.key == 'autoAdvance' && row['loop'] == true
                      ? {...(entry.value! as _Row), 'loop': true}
                      : entry.value,
              'peek': 'xl',
            },
          },
          'style': {
            'padding': {'start': 'lg', 'end': 'lg'},
          },
        }
      else
        node,
  ];

  UiDocument documentOf(_Row row) {
    final nodes = nodesOf(row);
    if (row['inert'] != true) return UiDocumentBuilder.bare(nodes);
    // A layer over the screen: a button opens it.
    return docWithScreens([
      {
        ...screenEntry('home', const []),
        'root': {
          'id': 'root',
          'type': 'Screen',
          'props': {'gap': 'none'},
          'children': [
            ...nodes,
            buttonNode('Open layer', id: 'open-layer', action: const {'type': 'navigate', 'params': {'screenId': 'layer'}}),
          ],
        },
      },
      screenEntry('layer', [textNode('Layer')], presentation: 'modal'),
    ], initialScreenId: 'home');
  }

  final scroller = find.descendant(of: find.byType(Carousel), matching: find.byType(SingleChildScrollView));
  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(Carousel), matching: find.byType(Scrollable)))
      .position;

  const captions = {'details-0': 'Caption 1', 'details-1': 'Caption 2', 'details-2': 'Caption 3'};

  List<String> shownDetails() => [
    for (final entry in captions.entries)
      if (find.text(entry.value).evaluate().isNotEmpty) entry.key,
  ];

  /// Moves a finger that holds the row until the scroll stands at [target]: the touch slop eats the first move.
  Future<void> dragTo(WidgetTester tester, TestGesture finger, double target) async {
    final position = positionOf(tester);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final delta = target - position.pixels;
      if (delta.abs() < 0.01) return;
      await finger.moveBy(Offset(-delta, 0));
      await tester.pump();
    }
  }

  group('autoAdvanceRunCases: a real screen on the fake clock', () {
    for (final row in rowsOf('autoAdvanceRunCases')) {
      testWidgets(row['name']! as String, (tester) async {
        phone(tester);
        final log = <List<Object?>>[];
        final actions = <String>[];
        final session = (row['session'] as _Row?) ?? const <String, Object?>{};

        await pumpDocument(
          tester,
          documentOf(row),
          data: session,
          theme: theme,
          disableAnimations: row['reducedMotion'] == true,
          onAction: (action, nodeId) => actions.add(action.type),
          onWrite: (path, value) => log.add(['write', path, value]),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final physics = tester.widget<SingleChildScrollView>(scroller.first).physics! as CarouselPhysics;
        expect(physics.stops(), _stops);

        final position = positionOf(tester);
        // How the show was made: standing off the first stop on the first frame is "instant".
        String? behavior = position.pixels == 0 ? null : 'instant';
        var last = position.pixels;
        TestGesture? finger;

        // The time the table waits is lived in frames of 20 ms (the timer ticks every 100 ms on its own): the animation of
        // a step freezes the count while it runs, so a frame as coarse as a tick would stretch every step by its own length.
        // The way a step moves is read from what the scroll did in the first frame after it: a jump lands on a stop, an
        // animation is in between.
        Future<void> wait(int ms) async {
          for (var left = ms; left > 0; left -= 20) {
            await tester.pump(Duration(milliseconds: left < 20 ? left : 20));
            final now = position.pixels;
            if (now != last) {
              behavior ??= _stops.any((stop) => (stop - now).abs() < 0.001) ? 'instant' : 'smooth';
              last = now;
            }
          }
        }

        // Frames until nothing is animating. Not `pumpAndSettle`: it always pumps 100 ms at least, a whole tick of the
        // timer that is being counted.
        Future<void> settle() async {
          for (var frame = 0; frame < 120 && tester.binding.hasScheduledFrame; frame += 1) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        if (row['inert'] == true) {
          await tester.tap(find.text('Open layer'));
          await tester.pumpAndSettle();
        }
        for (final step in (row['steps']! as List<Object?>)) {
          if (step == 'hold') {
            finger = await tester.startGesture(tester.getCenter(scroller.first));
          } else if (step == 'release') {
            await finger!.up();
            finger = null;
            await tester.pump();
          } else if (step is Map && step.containsKey('wait')) {
            await wait((step['wait']! as num).toInt());
          } else if (step is Map && step.containsKey('swipe')) {
            final hand = await tester.startGesture(tester.getCenter(scroller.first));
            for (final offset in (step['swipe']! as List<Object?>)) {
              await dragTo(tester, hand, (offset! as num).toDouble());
            }
            await hand.up();
            await settle();
            last = position.pixels;
          } else if (step is Map && step.containsKey('visibility')) {
            tester.binding.handleAppLifecycleStateChanged(
              step['visibility'] == 'hidden' ? AppLifecycleState.paused : AppLifecycleState.resumed,
            );
            await tester.pump();
          } else {
            fail('unknown step $step');
          }
        }
        // Whatever is left of the animation of a step (it takes no time when nothing moves).
        await settle();

        expect(log, row['log']);
        expect(actions, isEmpty, reason: 'onAction is never called');
        expect(position.pixels, closeTo((row['offset']! as num).toDouble(), 0.01));
        expect(behavior, row['behavior']);
        expect(shownDetails(), row['shown']);
      });
    }
  });
}
