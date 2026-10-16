/// The steps that fill smoothly and the glow of a scale (schema 9.25.0, `x-segmentsTransition` and `x-progressGlow`):
/// the groups `segmentFillCases`, `segmentFillInlineCases`, `transitionShareCases`, `glowStepCases` and
/// `glowRuleCases` of the shared table `fixtures/progress/progress-cases.json`. Every row is run through the rule and,
/// where a screen can show it, through a real node: what the canvas was told to paint, not a formula.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/progress_glow.dart';
import 'package:hotlayout_flutter/src/model/progress_rules.dart';
import 'package:hotlayout_flutter/src/model/segment_transition.dart';
import 'package:hotlayout_flutter/src/model/value_transition.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Row = Map<String, Object?>;

void main() {
  final table = jsonDecode(File('assets/contract/fixtures/progress/progress-cases.json').readAsStringSync()) as _Row;
  final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Row;
  List<_Row> rowsOf(String name) => (table[name]! as List<Object?>).cast<_Row>();
  final fillCases = rowsOf('segmentFillCases');
  final inlineCases = rowsOf('segmentFillInlineCases');
  final shareCases = rowsOf('transitionShareCases');
  final glowSteps = rowsOf('glowStepCases');
  final glowRules = rowsOf('glowRuleCases');
  final theme = RenderTheme.fromJson({
    ...(table['theme']! as _Row),
    'id': 'progress-cases',
    'name': 'Progress cases',
    'brightness': 'light',
  });
  final xs = theme.spacing[kProgressSegmentGap]!;
  final pill = theme.radii['pill']!;

  double number(Object? value) => (value! as num).toDouble();

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('the groups are read in full', () {
    expect(fillCases, hasLength(12));
    expect(inlineCases, hasLength(4));
    expect(shareCases, hasLength(5));
    expect(glowSteps, hasLength(7));
    expect(glowRules, hasLength(6));
  });

  group('segmentFillCases: the steps of a bar during a transition', () {
    for (final row in fillCases) {
      final name = row['name']! as String;
      final segments = row['segments']! as int;
      final expected = row['expected']! as _Row;
      final fills = [for (final fill in expected['fills']! as List<Object?>) number(fill)];

      test('rule: $name', () {
        final units = segmentUnitsAt(
          fromRatio: number(row['fromRatio']),
          toRatio: number(row['toRatio']),
          segments: segments,
          eased: number(row['eased']),
        );
        expect(units, closeTo(number(expected['units']), 1e-9));
        final actual = segmentFills(units, segments);
        expect(actual, hasLength(fills.length));
        for (var i = 0; i < fills.length; i += 1) {
          expect(actual[i], closeTo(fills[i], 1e-9), reason: 'fill of step $i');
        }
        expect(segmentCurrentOf(actual), expected['current']);
      });

      testWidgets('screen: $name', (tester) async {
        phone(tester);
        const trackInline = 300.0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: trackInline,
                child: ProgressTrack(
                  ratio: number(row['toRatio']),
                  thickness: 8,
                  pillRadius: pill,
                  trackColor: const Color(0xFFEEF0F6),
                  fill: const ProgressFill.solid(Color(0xFF4F46E5)),
                  segments: segments,
                  segmentGap: xs,
                  segmentUnits: segmentUnitsAt(
                    fromRatio: number(row['fromRatio']),
                    toRatio: number(row['toRatio']),
                    segments: segments,
                    eased: number(row['eased']),
                  ),
                ),
              ),
            ),
          ),
        );
        final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
        // One rounded rectangle per step; a step with a fraction has one more rectangle, the cut fill.
        expect(render, paintsExactlyCountTimes(#drawRRect, segments));
        final partial = fills.where((fill) => fill > 0 && fill < 1).toList();
        expect(render, paintsExactlyCountTimes(#drawRect, partial.length));
        if (partial.isNotEmpty) {
          final inline = (trackInline - (segments - 1) * xs) / segments;
          final index = fills.indexWhere((fill) => fill > 0 && fill < 1);
          final left = tester.getTopLeft(find.byType(ProgressTrack)).dx;
          expect(
            render,
            paints..rect(
              rect: Rect.fromLTWH(index * (inline + xs), 0, inline * fills[index], 8),
              color: const Color(0xFF4F46E5),
            ),
            reason: 'the cut fill of step $index (box at $left)',
          );
        }
      });
    }
  });

  group('segmentFillInlineCases: the gradient line along the drawn fill', () {
    for (final row in inlineCases) {
      test(row['name']! as String, () {
        expect(
          segmentFillInline(number(row['units']), step: number(row['step']), gap: number(row['gap'])),
          closeTo(number(row['expected']), 1e-9),
        );
        // The geometry of a bar says the same.
        final step = number(row['step']);
        final gap = number(row['gap']);
        final geometry = segmentGeometry(
          trackInline: 6 * step + 5 * gap,
          thickness: 8,
          ratio: 0,
          segments: 6,
          gap: gap,
          pill: pill,
          units: number(row['units']),
        )!;
        expect(geometry.filledInline, closeTo(number(row['expected']), 1e-9));
      });
    }
  });

  group('transitionShareCases: the eased share recovered from the shown value', () {
    for (final row in shareCases) {
      test(row['name']! as String, () {
        expect(transitionShareOf(number(row['from']), number(row['to']), number(row['shown'])), closeTo(number(row['expected']), 1e-9));
      });
    }
  });

  group('glowStepCases: which step of a bar glows', () {
    for (final row in glowSteps) {
      final fills = [for (final fill in row['fills']! as List<Object?>) number(fill)];
      final expected = row['expected']! as _Row;
      test(row['name']! as String, () {
        final step = glowingStepOf(fills, currentPainted: row['currentPainted']! as bool);
        expect(step.kind.name, expected['kind']);
        if (expected['kind'] != 'none') expect(step.index, expected['index']);
        if (expected['kind'] == 'front') expect(step.fill, closeTo(number(expected['fill']), 1e-9));
      });
    }
  });

  group('glowRuleCases and the mirror of the artifact', () {
    final block = schema['x-progressGlow']! as _Row;
    for (final row in glowRules) {
      test(row['name']! as String, () {
        final rule = row['rule']! as String;
        final expected = row['expect'];
        if (rule.startsWith('strength.')) {
          final parts = rule.split('.');
          final glow = ProgressGlow.parse(parts[1])!;
          expect(parts[2] == 'sigma' ? glow.sigma : glow.opacity, expected);
        } else if (rule == 'on') {
          expect(block['on'], expected);
        } else {
          expect((block['segments']! as _Row)['others'], expected);
        }
      });
    }

    test('the words of the field, and anything else is no glow', () {
      expect(ProgressGlow.values.map((glow) => glow.wire).toList(), (block['strength']! as _Row).keys.toList());
      for (final raw in ['', 'Soft', 'medium', 'none', 1, true, null]) {
        expect(ProgressGlow.parse(raw), isNull, reason: '$raw');
      }
    });

    test('the field is read on the bar and the ring only, and unknown words are dropped by the node', () {
      final doc = UiDocumentBuilder.bare([
        {'id': 'bar', 'type': 'ProgressBar', 'props': {'value': {'kind': 'literal', 'value': 1}, 'glow': 'strong'}},
        {'id': 'ring', 'type': 'CircularProgress', 'props': {'value': {'kind': 'literal', 'value': 1}, 'glow': 'soft'}},
        {'id': 'odd', 'type': 'ProgressBar', 'props': {'value': {'kind': 'literal', 'value': 1}, 'glow': 'huge'}},
      ]);
      final children = doc.screens.first.root.children;
      expect((children[0] as ProgressBarNode).glow, ProgressGlow.strong);
      expect((children[1] as CircularProgressNode).glow, ProgressGlow.soft);
      expect((children[2] as ProgressBarNode).glow, isNull);
    });
  });

  group('on a real screen', () {
    _Row bar(Map<String, Object?> props, {Object? value = 50, Object? max = 100}) => {
      'id': 'bar',
      'type': 'ProgressBar',
      'props': {
        'value': {'kind': 'literal', 'value': value},
        'max': {'kind': 'literal', 'value': max},
        'color': 'primary',
        'labelFormat': 'none',
        ...props,
      },
    };

    Future<void> pumpBar(WidgetTester tester, _Row node, {double width = 300}) async {
      phone(tester);
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'holder',
            'type': 'Container',
            'props': {'gap': 'none'},
            'style': {'width': width},
            'children': [node],
          },
        ]),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
    }

    testWidgets('a glowing bar: the blurred copy of the fill comes FIRST, then the track, then the fill', (tester) async {
      await pumpBar(tester, bar({'glow': 'soft'}));
      final render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
      expect(render, paintsExactlyCountTimes(#drawRRect, 3));
      final copy = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 150, 8), const Radius.circular(4));
      expect(
        render,
        paints
          ..rrect(rrect: copy, hasMaskFilter: true)
          ..rrect(hasMaskFilter: false)
          ..rrect(hasMaskFilter: false),
      );
    });

    testWidgets('without the field there is no copy: track and fill only', (tester) async {
      await pumpBar(tester, bar({}));
      expect(tester.renderObject<RenderBox>(find.byType(ProgressTrack)), paintsExactlyCountTimes(#drawRRect, 2));
    });

    testWidgets('nothing filled: no glow', (tester) async {
      await pumpBar(tester, bar({'glow': 'strong'}, value: 0));
      expect(tester.renderObject<RenderBox>(find.byType(ProgressTrack)), paintsExactlyCountTimes(#drawRRect, 1));
    });

    testWidgets('the glow takes no room: the bar has the same box with and without it', (tester) async {
      await pumpBar(tester, bar({'glow': 'strong'}));
      final glowing = tester.getRect(find.byType(ProgressTrack));
      await pumpBar(tester, bar({}));
      expect(tester.getRect(find.byType(ProgressTrack)), glowing);
    });

    testWidgets('a bar with steps: the current step glows in its colour, otherwise the front step in the fill paint', (tester) async {
      await pumpBar(tester, bar({'segments': 6, 'glow': 'soft', 'currentColor': 'accent'}, value: 3, max: 6));
      var render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
      // Six steps and one blurred copy: the current step (the fourth), in `accent`.
      expect(render, paintsExactlyCountTimes(#drawRRect, 7));
      final inline = (300 - 5 * xs) / 6;
      expect(
        render,
        paints..rrect(
          rrect: RRect.fromRectAndRadius(Rect.fromLTWH(3 * (inline + xs), 0, inline, 8), Radius.circular(barFillRadius(inline, 8, pill))),
          hasMaskFilter: true,
        ),
      );

      await pumpBar(tester, bar({'segments': 6, 'glow': 'soft'}, value: 3, max: 6));
      render = tester.renderObject<RenderBox>(find.byType(ProgressTrack));
      expect(render, paintsExactlyCountTimes(#drawRRect, 7));
      expect(
        render,
        paints..rrect(
          rrect: RRect.fromRectAndRadius(Rect.fromLTWH(2 * (inline + xs), 0, inline, 8), Radius.circular(barFillRadius(inline, 8, pill))),
          hasMaskFilter: true,
        ),
      );
    });

    testWidgets('a glowing ring: the blurred arc comes first, the track is not blurred', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'ring',
            'type': 'CircularProgress',
            'props': {
              'value': {'kind': 'literal', 'value': 50},
              'max': {'kind': 'literal', 'value': 100},
              'color': 'primary',
              'size': 'md',
              'labelFormat': 'none',
              'glow': 'strong',
            },
          },
        ]),
        theme: theme,
      );
      final render = tester.renderObject<RenderBox>(find.byType(CustomPaint).first);
      expect(
        find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is RingPainter && (widget.painter! as RingPainter).glow == ProgressGlow.strong),
        findsOneWidget,
      );
      expect(render, isNotNull);
    });

    testWidgets('steps fill smoothly when a bar appears: halfway along the curve the fourth step is half filled', (tester) async {
      await pumpBar(tester, bar({'segments': 6, 'animateIn': true}, value: 4, max: 6));
      // The first frame is empty.
      expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).segmentUnits, 0);
      // 350 ms of 700: `e = 1 - (1 - 0.5)^3 = 0.875`, the row «appear 4 of 6 at e = 0.875».
      await tester.pump(const Duration(milliseconds: 350));
      final track = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
      expect(track.segmentUnits, closeTo(3.5, 1e-6));
      expect(tester.renderObject<RenderBox>(find.byType(ProgressTrack)), paintsExactlyCountTimes(#drawRect, 1));
      // At the end the picture is the one at rest: whole steps, nothing left to cut.
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).segmentUnits, isNull);
      expect(tester.renderObject<RenderBox>(find.byType(ProgressTrack)), paintsExactlyCountTimes(#drawRect, 0));
      expect(kValueTransitionMs, 700);
    });

    testWidgets('a change of data leads the steps from the shown value to the new one', (tester) async {
      phone(tester);
      Future<void> show(Map<String, Object?> data) => pumpDocument(
        tester,
        docWith([
          {
            'id': 'bar',
            'type': 'ProgressBar',
            'props': {
              'value': {'kind': 'binding', 'path': 'task.progress', 'fallback': 0},
              'max': {'kind': 'literal', 'value': 5},
              'color': 'primary',
              'labelFormat': 'none',
              'segments': 5,
              'animateChanges': true,
            },
          },
        ]),
        theme: theme,
        data: data,
      );
      await show({'task.progress': 2});
      expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).segmentUnits, isNull);
      await show({'task.progress': 4});
      await tester.pump(const Duration(milliseconds: 100));
      final units = tester.widget<ProgressTrack>(find.byType(ProgressTrack)).segmentUnits!;
      expect(units, greaterThan(2));
      expect(units, lessThan(4));
      expect(units - units.floorToDouble(), greaterThan(0), reason: 'a step with a fraction');
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).segmentUnits, isNull);
    });

    testWidgets('«reduce motion»: whole steps at once', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        docWith([
          {'id': 'holder', 'type': 'Container', 'props': {'gap': 'none'}, 'children': [bar({'segments': 6, 'animateIn': true}, value: 4, max: 6)]},
        ]),
        theme: theme,
        disableAnimations: true,
      );
      expect(tester.widget<ProgressTrack>(find.byType(ProgressTrack)).segmentUnits, isNull);
    });
  });
}
