/// The frame of 9.40.0 (`fixtures/motion-turn-screens.json`): a glow of two tiles that spin in opposite directions, a
/// trophy that rises, a bell that sways from its top edge and a gift from its bottom edge, a heading that fades in and three
/// cards that rise in a cascade (the last one also floats).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/motion_rules.dart';
import 'package:hotlayout_flutter/src/model/node_appear.dart';
import 'package:hotlayout_flutter/src/render/node_appear.dart';
import 'package:hotlayout_flutter/src/render/node_motion.dart';

import 'support/fixtures.dart';

void main() {
  const id = 'motion-turn-screens';

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> open(WidgetTester tester, {bool reduced = false}) async {
    phone(tester);
    await pumpDocument(tester, loadFixture(id), theme: fixtureTheme(id), disableAnimations: reduced);
    await tester.pump();
  }

  /// The turn each `NodeMotionBox` of kind spin or sway paints, in degrees.
  List<double> turns(WidgetTester tester) => [
    for (final box in tester.widgetList<NodeMotionBox>(find.byType(NodeMotionBox)))
      if (box.motion is SpinMotion || box.motion is SwayMotion)
        () {
          final transform = tester.widget<Transform>(
            find.descendant(of: find.byWidget(box), matching: find.byType(Transform)).first,
          );
          final m = transform.transform;
          return math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
        }(),
  ];

  List<NodeMotion> turningMotions(WidgetTester tester) => [
    for (final box in tester.widgetList<NodeMotionBox>(find.byType(NodeMotionBox)))
      if (box.motion is SpinMotion || box.motion is SwayMotion) box.motion,
  ];

  bool sameTurn(double a, double b) =>
      (math.sin(a * math.pi / 180) - math.sin(b * math.pi / 180)).abs() < 1e-6 &&
      (math.cos(a * math.pi / 180) - math.cos(b * math.pi / 180)).abs() < 1e-6;

  test('the frame is registered and carries the new kinds and the field', () {
    expect(fixtureIds, contains(id));
    final doc = loadFixture(id);
    expect(doc.schemaVersion, '9.42.0');
    final raw = readFixture(id);
    for (final word in ['"spin"', '"sway"', '"appear"', '"rise"', '"pivot": "top"', '"pivot": "bottom"']) {
      expect(raw, contains(word));
    }
  });

  testWidgets('the tiles of the glow spin in opposite directions, the bell and the gift sway', (tester) async {
    await open(tester);
    expect(turningMotions(tester), hasLength(4));
    await tester.pump(const Duration(milliseconds: 1000));
    final motions = turningMotions(tester);
    final painted = turns(tester);
    expect(motions.whereType<SpinMotion>().map((m) => m.direction), [SpinDirection.clockwise, SpinDirection.counterclockwise]);
    for (var i = 0; i < motions.length; i += 1) {
      final expected = motionPoseAt(motions[i], 1000).rotate;
      expect(sameTurn(painted[i], expected), isTrue, reason: 'motion $i: painted ${painted[i]}, formula $expected');
    }
    expect(sameTurn(painted[0], 30), isTrue, reason: 'a twelfth of 12 s clockwise');
    expect(sameTurn(painted[1], -22.5), isTrue, reason: 'a sixteenth of 16 s counterclockwise');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cards appear one after another and not before their own delay', (tester) async {
    await open(tester);
    final boxes = tester.widgetList<NodeAppearBox>(find.byType(NodeAppearBox)).toList();
    expect(boxes, hasLength(5));
    expect([for (final box in boxes) box.appear.kind], [
      AppearKind.fade,
      AppearKind.rise,
      AppearKind.rise,
      AppearKind.rise,
      AppearKind.rise,
    ]);
    List<double> opacities() => [
      for (final box in boxes)
        tester.widget<Opacity>(find.descendant(of: find.byWidget(box), matching: find.byType(Opacity)).first).opacity,
    ];
    expect(opacities(), everyElement(0), reason: 'everything stands in the start pose at the show');
    await tester.pump(const Duration(milliseconds: 200));
    final at200 = opacities();
    for (var i = 0; i < boxes.length; i += 1) {
      expect(at200[i], closeTo(appearPoseAt(boxes[i].appear, 200).opacity, 1e-6), reason: 'node $i at 200 ms');
    }
    expect(at200.last, 0, reason: 'the last card has not started: its delay is 240 ms');
    expect(at200[4], lessThan(at200[3]), reason: 'a cascade: each card a little later than the one before');
    // The glow and the bell never stop, so the screen never settles: past the longest appearance (240 + 400 ms) all stand whole.
    await tester.pump(const Duration(seconds: 2));
    expect(opacities(), everyElement(1));
  });

  testWidgets('"reduce motion": everything stands at rest and nothing is invisible', (tester) async {
    await open(tester, reduced: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(turns(tester), everyElement(0));
    for (final box in tester.widgetList<NodeAppearBox>(find.byType(NodeAppearBox))) {
      final fade = find.descendant(of: find.byWidget(box), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(fade.first).opacity, 1);
    }
  });
}
