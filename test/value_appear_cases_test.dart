/// A VALUE THAT GROWS WHEN SHOWN (schema 9.24.0, `animateIn`).
///
/// The `appear…` groups of the shared table `fixtures/value-transition/value-transition-cases.json`: every row is
/// run through the rule, and the mechanism through REAL widgets and a real frame clock -- the number of a text and
/// the fill of a scale are read at moments of the appearance. Around the table: the mirror of the artifact block
/// `x-valueAppear`, and what the field does not do (a change of data on a shown node, reduced motion, a value that
/// is not a number, a value of zero, a node without the field).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/value_transition.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/value-transition/value-transition-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

double _num(Object? value) => (value! as num).toDouble();

_Json _text(Object content, {bool changes = false, bool appear = true, Object? visibleIf}) => {
  'id': 'pts',
  'type': 'Text',
  'props': {'content': content, 'animateIn': ?(appear ? true : null), 'animateChanges': ?(changes ? true : null)},
  'visibleIf': ?visibleIf,
};

_Json _binding(String path, {String? format, String? currency}) => {
  'kind': 'binding',
  'path': path,
  'fallback': '0',
  'format': ?format,
  'currency': ?currency,
};

_Json _scale(String type, {Object? value, bool changes = false, bool appear = true, String labelFormat = 'none'}) => {
  'id': 'scale',
  'type': type,
  'props': {
    'value': value ?? {'kind': 'binding', 'path': 'task.progress', 'fallback': 0},
    'max': {'kind': 'literal', 'value': 100},
    'color': 'primary',
    if (type == 'CircularProgress') 'size': 'md',
    'labelFormat': labelFormat,
    'animateIn': ?(appear ? true : null),
    'animateChanges': ?(changes ? true : null),
  },
};

void main() {
  test('the appearance groups are read in full', () {
    expect(_rows('appearStepCases'), hasLength(9));
    expect(_rows('appearDecisionCases'), hasLength(8));
    expect(_rows('appearTargetCases'), hasLength(4));
    expect(_rows('appearFlowCases'), hasLength(9));
    const known = {
      'appearStepCases': {'name', 'to', 't', 'digits', 'expected'},
      'appearDecisionCases': {'name', 'input', 'expected'},
      'appearTargetCases': {'name', 'props', 'expected'},
      'appearFlowCases': {'name', 'moment', 'expected'},
    };
    for (final entry in known.entries) {
      final rows = _rows(entry.key);
      expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: '${entry.key}: names are unique');
      for (final row in rows) {
        expect(row.keys.toSet().difference(entry.value), isEmpty, reason: '${entry.key}/${row['name']}');
      }
    }
  });

  test('x-valueAppear: the mirror against the artifact', () {
    final block = _schema['x-valueAppear']! as _Json;
    expect(block['prop'], 'animateIn');
    expect(block['from'], kValueAppearFrom);
    expect(block['durationMs'], kValueTransitionMs);
    expect(block['on'], ['Text', 'ProgressBar', 'CircularProgress']);
    expect((block['whenNoAppear']! as _Json)['order'], kNoAppearOrder);
    expect(NoAppear.values.map((reason) => reason.name), kNoAppearOrder);
    expect(block['refines'], ['x-valueTransition.whenNoTransition.firstShow']);
    expect(block['stagger'], contains('none'));
    expect(block['cases'], 'contract/fixtures/value-transition/value-transition-cases.json');
  });

  group('appearStepCases: the value shown at t milliseconds after the show', () {
    for (final row in _rows('appearStepCases')) {
      test(row['name']! as String, () {
        final shown = appearValueAt(to: _num(row['to']), t: _num(row['t']), digits: row['digits'] as int?);
        expect(shown, closeTo(_num(row['expected']), 1e-9));
      });
    }
  });

  group('appearDecisionCases: whether the show gives an appearance', () {
    for (final row in _rows('appearDecisionCases')) {
      test(row['name']! as String, () {
        final input = row['input']! as _Json;
        final reason = noAppearBecause(
          animates: input['animates']! as bool,
          to: input['to'],
          reducedMotion: input['reducedMotion'] == true,
        );
        expect(reason?.name ?? true, row['expected']);
      });
    }
  });

  group('appearTargetCases: which numbers of a node appear', () {
    for (final row in _rows('appearTargetCases')) {
      test(row['name']! as String, () {
        final props = row['props']! as _Json;
        final isScale = props.containsKey('value');
        final node = (docWith([
          {'id': 'n', 'type': isScale ? 'ProgressBar' : 'Text', 'props': props},
        ]).initialScreen.root as ScreenNode).children.single;
        final targets = appearTargetsOf(node);
        final expected = (row['expected']! as List<Object?>).cast<_Json>();
        expect(targets.map((target) => target.path), expected.map((entry) => entry['path']));
        expect(targets.map((target) => target.scale), expected.map((entry) => entry['scale']));
        expect(targets.map((target) => target.format?.wire), expected.map((entry) => entry['format']));
      });
    }
  });

  group('appearFlowCases: what a moment of a flow does', () {
    const moments = {
      'firstShow': AppearMoment.firstShow,
      'forward': AppearMoment.forward,
      'back': AppearMoment.back,
      'switch': AppearMoment.switchSection,
      'modalClosed': AppearMoment.modalClosed,
      'conditionMet': AppearMoment.conditionMet,
      'dataChanged': AppearMoment.dataChanged,
      'dataChangedDuringAppearWithAnimateChanges': AppearMoment.dataChangedDuringAppearWithAnimateChanges,
      'dataChangedDuringAppear': AppearMoment.dataChangedDuringAppear,
    };
    for (final row in _rows('appearFlowCases')) {
      test(row['name']! as String, () => expect(appearOnMoment(moments[row['moment']]!).name, row['expected']));
    }
  });

  group('a number of a text, through real frames', () {
    String shownText(WidgetTester tester) => tester.widget<Text>(find.byType(Text).last).data!;

    Future<void> at(WidgetTester tester, int ms) => tester.pump(Duration(milliseconds: ms));

    for (final row in _rows('appearStepCases').where((row) => row['digits'] == 0)) {
      testWidgets('the show: ${row['name']}', (tester) async {
        final to = row['to']! as int;
        await pumpDocument(tester, docWith([_text(_binding('user.points'))]), data: {'user.points': to});
        expect(shownText(tester), '0', reason: 'the first frame of the show is zero');
        final t = (row['t']! as num).toInt();
        if (t > 0) await at(tester, t);
        expect(shownText(tester), '${row['expected']}');
        await at(tester, 5000);
        expect(shownText(tester), '$to', reason: 'the end is exactly the value');
      });
    }

    testWidgets('money: two digits of the currency, written by the same format as the final value', (tester) async {
      await pumpDocument(
        tester,
        docWith([_text(_binding('user.balance', format: 'currency', currency: 'USD'))]),
        data: {'user.balance': 87.5},
      );
      expect(shownText(tester), '0\u00A0USD');
      await at(tester, 350);
      expect(shownText(tester), '76.56\u00A0USD');
      await at(tester, 5000);
      expect(shownText(tester), '87.50\u00A0USD');
    });

    testWidgets('no field: the value is there at once', (tester) async {
      await pumpDocument(tester, docWith([_text(_binding('user.points'), appear: false)]), data: {'user.points': 500});
      expect(shownText(tester), '500');
    });

    testWidgets('reduced motion, no data, zero: the value at once', (tester) async {
      await pumpDocument(tester, docWith([_text(_binding('user.points'))]), data: {'user.points': 500}, disableAnimations: true);
      expect(shownText(tester), '500');
      await pumpDocument(tester, docWith([_text(_binding('user.points'))]));
      expect(shownText(tester), '0', reason: 'the fallback');
      await pumpDocument(tester, docWith([_text(_binding('user.points'))]), data: {'user.points': 0});
      expect(shownText(tester), '0');
      await pumpDocument(tester, docWith([_text(_binding('user.points'))]), data: {'user.points': '87'});
      expect(shownText(tester), '87', reason: 'a string is not a number');
    });

    testWidgets('a change of data on a shown node is not a show', (tester) async {
      final children = [_text(_binding('user.points'))];
      await pumpDocument(tester, docWith(children), data: {'user.points': 500});
      await at(tester, 5000);
      await pumpDocument(tester, docWith(children), data: {'user.points': 900});
      expect(shownText(tester), '900', reason: 'no animateChanges: the new value at once');
      await at(tester, 100);
      expect(shownText(tester), '900');
    });

    testWidgets('without animateChanges a change during the appearance shows the new value at once and ends it', (tester) async {
      final children = [_text(_binding('user.points'))];
      await pumpDocument(tester, docWith(children), data: {'user.points': 500});
      await at(tester, 200);
      await pumpDocument(tester, docWith(children), data: {'user.points': 900});
      expect(shownText(tester), '900');
      await at(tester, 100);
      expect(shownText(tester), '900');
    });

    testWidgets('with animateChanges a change during the appearance leads from the value shown at that moment', (tester) async {
      final children = [_text(_binding('user.points'), changes: true)];
      await pumpDocument(tester, docWith(children), data: {'user.points': 1000});
      await at(tester, 175);
      final mid = int.parse(shownText(tester));
      expect(mid, inInclusiveRange(1, 999));
      await pumpDocument(tester, docWith(children), data: {'user.points': 2000});
      expect(shownText(tester), '$mid', reason: 'the frame of the change keeps the shown value');
      await at(tester, 700);
      expect(shownText(tester), '2000');
    });

    testWidgets('a node that appears by a condition grows', (tester) async {
      final shown = {'path': 'user.vip', 'op': 'isTrue'};
      final children = [_text(_binding('user.points'), visibleIf: shown)];
      await pumpDocument(tester, docWith(children), data: {'user.points': 500, 'user.vip': false});
      expect(find.byType(Text), findsNothing);
      await pumpDocument(tester, docWith(children), data: {'user.points': 500, 'user.vip': true});
      expect(shownText(tester), '0');
      await at(tester, 5000);
      expect(shownText(tester), '500');
    });

    testWidgets('the screen reader hears the final value, not the numbers in between', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, docWith([_text(_binding('user.points'))]), data: {'user.points': 500});
      await at(tester, 100);
      expect(find.bySemanticsLabel('500'), findsOneWidget);
      handle.dispose();
    });
  });

  group('a scale, through real frames', () {
    double barRatio(WidgetTester tester) => tester.widget<ProgressTrack>(find.byType(ProgressTrack)).ratio;

    double ringRatio(WidgetTester tester) =>
        (tester.widget<CustomPaint>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)).first).painter! as RingPainter).ratio;

    testWidgets('the fill grows from empty without a step', (tester) async {
      await pumpDocument(tester, docWith([_scale('ProgressBar')]), data: {'task.progress': 87});
      expect(barRatio(tester), 0);
      await tester.pump(const Duration(milliseconds: 175));
      expect(barRatio(tester), closeTo(0.50296875, 1e-9));
      await tester.pump(const Duration(milliseconds: 175));
      expect(barRatio(tester), closeTo(0.76125, 1e-9));
      await tester.pump(const Duration(seconds: 1));
      expect(barRatio(tester), closeTo(0.87, 1e-9));
    });

    testWidgets('the ring grows from empty too', (tester) async {
      await pumpDocument(tester, docWith([_scale('CircularProgress')]), data: {'task.progress': 100});
      expect(ringRatio(tester), 0);
      await tester.pump(const Duration(milliseconds: 350));
      expect(ringRatio(tester), closeTo(0.875, 1e-9));
      await tester.pump(const Duration(seconds: 1));
      expect(ringRatio(tester), 1);
    });

    testWidgets('a literal value grows too', (tester) async {
      await pumpDocument(tester, docWith([_scale('ProgressBar', value: {'kind': 'literal', 'value': 60})]));
      expect(barRatio(tester), 0);
      await tester.pump(const Duration(milliseconds: 350));
      expect(barRatio(tester), closeTo(0.525, 1e-9));
      await tester.pump(const Duration(seconds: 1));
      expect(barRatio(tester), closeTo(0.6, 1e-9));
    });

    testWidgets('reduced motion, zero and a node without the field: the value at once', (tester) async {
      await pumpDocument(tester, docWith([_scale('ProgressBar')]), data: {'task.progress': 40}, disableAnimations: true);
      expect(barRatio(tester), closeTo(0.4, 1e-9));
      await pumpDocument(tester, docWith([_scale('ProgressBar')]), data: {'task.progress': 0});
      expect(barRatio(tester), 0);
      await pumpDocument(tester, docWith([_scale('ProgressBar', appear: false)]), data: {'task.progress': 40});
      expect(barRatio(tester), closeTo(0.4, 1e-9));
    });

    testWidgets('the label of the scale writes the shown value in steps', (tester) async {
      await pumpDocument(tester, docWith([_scale('ProgressBar', labelFormat: 'percent')]), data: {'task.progress': 80});
      expect(find.text('0%'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('80%'), findsOneWidget);
    });
  });

  test('the format of the appearance step is the one of the text', () {
    expect(appearDigitsOf(12480, null, null), 0);
    expect(appearDigitsOf(87.5, BindingFormat.currency, 'USD'), 2);
    expect(appearDigitsOf(0.5, BindingFormat.number, null), kNumberFormatMaxFractionDigits);
  });
}
