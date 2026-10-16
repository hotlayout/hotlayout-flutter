/// A VALUE THAT LEADS TO ITS NEW VALUE (schema 9.21.0, `animateChanges`).
///
/// The five groups of the shared table `fixtures/value-transition/value-transition-cases.json`, every row run
/// through the rule, and the mechanism through REAL widgets: the number of a text and the fill of a scale are
/// read at the quarters of the duration, with a real frame clock, after the data under a shown node changed.
/// Around the table: the mirror of the artifact block `x-valueTransition`, and everything the field does NOT do
/// (the first show, a changed language, reduced motion, a value that is not a number, a new record of a list,
/// a node without the field), an interrupted transition, and what the screen reader hears.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/binding_format.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/model/value_transition.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/value-transition/value-transition-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

double _num(Object? value) => (value! as num).toDouble();

BindingFormat? _format(Object? wire) => wire == null ? null : BindingFormat.parse(wire);

_Json _text(Object content, {bool animate = true, String id = 'pts'}) => {
  'id': id,
  'type': 'Text',
  'props': {'content': content, 'animateChanges': ?(animate ? true : null)},
};

_Json _binding(String path, {String? format, String? currency, String fallback = '0'}) => {
  'kind': 'binding',
  'path': path,
  'fallback': fallback,
  'format': ?format,
  'currency': ?currency,
};

_Json _scale(String type, {String id = 'scale', String labelFormat = 'none', bool animate = true, Object? max}) => {
  'id': id,
  'type': type,
  'props': {
    'value': {'kind': 'binding', 'path': 'task.progress', 'fallback': 0},
    'max': max ?? {'kind': 'literal', 'value': 100},
    'color': 'primary',
    if (type == 'CircularProgress') 'size': 'md',
    'labelFormat': labelFormat,
    'animateChanges': ?(animate ? true : null),
  },
};

void main() {
  test('the table is read in full, and every field of it is known to this test', () {
    expect(_table.keys.toSet(), {
      'description', 'durationMs', 'curveCases', 'stepCases', 'digitsCases', 'decisionCases', 'targetCases',
      // 9.24.0: the appearance, run by `value_appear_cases_test.dart`.
      'appearNote', 'appearStepCases', 'appearDecisionCases', 'appearTargetCases', 'appearFlowCases',
    });
    expect(_table['durationMs'], kValueTransitionMs);
    expect(_rows('curveCases'), hasLength(7));
    expect(_rows('stepCases'), hasLength(16));
    expect(_rows('digitsCases'), hasLength(7));
    expect(_rows('decisionCases'), hasLength(12));
    expect(_rows('targetCases'), hasLength(7));
    const known = {
      'curveCases': {'name', 'p', 'e'},
      'stepCases': {'name', 'from', 'to', 't', 'digits', 'expected'},
      'digitsCases': {'name', 'from', 'to', 'format', 'currency', 'expected'},
      'decisionCases': {'name', 'change', 'expected'},
      'targetCases': {'name', 'props', 'expected'},
    };
    for (final entry in known.entries) {
      final rows = _rows(entry.key);
      expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: '${entry.key}: names are unique');
      for (final row in rows) {
        expect(row.keys.toSet().difference(entry.value), isEmpty, reason: '${entry.key}/${row['name']}');
      }
    }
  });

  test('x-valueTransition: the mirror against the artifact', () {
    final block = _schema['x-valueTransition']! as _Json;
    expect(block['prop'], kValueTransitionRules['prop']);
    expect(block['durationMs'], kValueTransitionRules['durationMs']);
    expect((block['text']! as _Json)['step'], containsPair('precision', kValueTransitionPrecision));
    expect(block['interrupted'], kValueTransitionRules['interrupted']);
    expect(block['semantics'], kValueTransitionRules['semantics']);
    expect(block['on'], ['Text', 'ProgressBar', 'CircularProgress']);
    expect((block['whenNoTransition']! as _Json)['order'], kNoTransitionOrder);
    expect(NoTransition.values.map((reason) => reason.name), kNoTransitionOrder);
    expect(block['cases'], 'contract/fixtures/value-transition/value-transition-cases.json');
  });

  group('curveCases: e = 1 - (1 - p)^3', () {
    for (final row in _rows('curveCases')) {
      test(row['name']! as String, () => expect(valueTransitionEase(_num(row['p'])), closeTo(_num(row['e']), 1e-9)));
    }
  });

  group('stepCases: the value shown at t milliseconds', () {
    for (final row in _rows('stepCases')) {
      test(row['name']! as String, () {
        final shown = transitionValueAt(
          from: _num(row['from']),
          to: _num(row['to']),
          t: _num(row['t']),
          digits: row['digits'] as int?,
        );
        expect(shown, closeTo(_num(row['expected']), 1e-9));
      });
    }
  });

  group('digitsCases: the step of a number in a text', () {
    for (final row in _rows('digitsCases')) {
      test(row['name']! as String, () {
        expect(
          transitionDigitsOf(_num(row['from']), _num(row['to']), _format(row['format']), row['currency'] as String?),
          row['expected'],
        );
      });
    }
  });

  group('decisionCases: whether a change leads, and if not why', () {
    for (final row in _rows('decisionCases')) {
      test(row['name']! as String, () {
        final change = row['change']! as _Json;
        final reason = noTransitionBecause(
          TransitionChange(
            animates: change['animates']! as bool,
            shownBefore: change['shownBefore']! as bool,
            from: change['from'],
            to: change['to'],
            localeChanged: change['localeChanged'] == true,
            reducedMotion: change['reducedMotion'] == true,
          ),
        );
        expect(reason?.name ?? true, row['expected']);
      });
    }
  });

  group('targetCases: which numbers of a node lead', () {
    for (final row in _rows('targetCases')) {
      test(row['name']! as String, () {
        final props = row['props']! as _Json;
        final isScale = props.containsKey('value');
        final node = (docWith([
          {'id': 'n', 'type': isScale ? 'ProgressBar' : 'Text', 'props': props},
        ]).initialScreen.root as ScreenNode).children.single;
        final targets = transitionTargetsOf(node);
        final expected = (row['expected']! as List<Object?>).cast<_Json>();
        expect(targets.map((target) => target.path), expected.map((entry) => entry['path']));
        expect(targets.map((target) => target.scale), expected.map((entry) => entry['scale']));
        expect(targets.map((target) => target.format?.wire), expected.map((entry) => entry['format']));
        expect(targets.map((target) => target.currency), expected.map((entry) => entry['currency']));
      });
    }
  });

  group('a number of a text, through real frames', () {
    Future<void> change(WidgetTester tester, List<_Json> children, Map<String, Object?> data, {bool reduced = false, String? locale}) =>
        pumpDocument(tester, docWith(children), data: data, disableAnimations: reduced, locale: locale);

    String shownText(WidgetTester tester) => tester.widget<Text>(find.byType(Text).first).data!;

    Future<void> at(WidgetTester tester, int ms) => tester.pump(Duration(milliseconds: ms));

    for (final row in _rows('stepCases').where((row) => row['digits'] == 0 && row['from'] is int && row['to'] is int)) {
      testWidgets('the quarters: ${row['name']}', (tester) async {
        final from = row['from']! as int;
        final to = row['to']! as int;
        final children = [_text(_binding('user.points'))];
        await change(tester, children, {'user.points': from});
        expect(shownText(tester), '$from', reason: 'the first show is the value itself');
        await change(tester, children, {'user.points': to});
        // The frame of the change: the old value stays, the new one is not shown ahead of the lead.
        expect(shownText(tester), '$from');
        final t = (row['t']! as num).toInt();
        if (t > 0) await at(tester, t);
        expect(shownText(tester), '${row['expected']}');
        await at(tester, 5000);
        expect(shownText(tester), '$to', reason: 'the end is exactly the new value');
      });
    }

    testWidgets('money: two digits of the currency, written by the same format as the final value', (tester) async {
      final children = [_text(_binding('user.balance', format: 'currency', currency: 'USD'))];
      await change(tester, children, {'user.balance': 10.5});
      expect(shownText(tester), '10.50 USD');
      await change(tester, children, {'user.balance': 20.25});
      await at(tester, 350);
      expect(shownText(tester), '19.03 USD');
      await at(tester, 350);
      expect(shownText(tester), '20.25 USD');
    });

    testWidgets('a template value leads and the plural word follows the shown number', (tester) async {
      final content = {
        'kind': 'template',
        'template': '{n} {w}',
        'values': {
          'n': _binding('user.points'),
          'w': {'kind': 'plural', 'of': 'n', 'forms': {'one': 'point', 'other': 'points'}},
        },
      };
      final children = [_text(content)];
      Future<void> inEnglish(num points) => pumpDocument(
        tester,
        UiDocument.fromJson({
          'schemaVersion': UiDocument.supportedSchemaVersion,
          'documentId': 'plural',
          'name': 'plural',
          'initialScreenId': 'inline',
          'screens': [screenEntry('inline', children)],
          'localization': {'defaultLocale': 'en', 'locales': ['en'], 'strings': <String, Object?>{}},
        }),
        data: {'user.points': points},
        locale: 'en',
      );
      await inEnglish(1);
      expect(shownText(tester), '1 point');
      await inEnglish(3);
      expect(shownText(tester), '1 point');
      await at(tester, 350);
      expect(shownText(tester), '2 points', reason: 'whole steps: 1 + trunc(2 * 0.875) = 2, and the word agrees with it');
      await at(tester, 700);
      expect(shownText(tester), '3 points');
    });

    testWidgets('a change DURING a transition starts from the value shown at that moment, for the full duration', (tester) async {
      final children = [_text(_binding('user.points'))];
      await change(tester, children, {'user.points': 0});
      await change(tester, children, {'user.points': 1000});
      await at(tester, 175);
      final midway = int.parse(shownText(tester));
      expect(midway, closeTo(578, 1), reason: 'a quarter of the time is more than half of the way');
      await change(tester, children, {'user.points': 0});
      expect(int.parse(shownText(tester)), midway, reason: 'it starts from what is shown');
      await at(tester, 350);
      final half = int.parse(shownText(tester));
      expect(half, lessThan(midway));
      expect(half, greaterThan(0), reason: 'the full duration is ahead, not what was left of the first one');
      await at(tester, 350);
      expect(shownText(tester), '0');
    });

    testWidgets('going down leads too, and the step is cut towards the old value', (tester) async {
      final children = [_text(_binding('user.points'))];
      await change(tester, children, {'user.points': 1580});
      await change(tester, children, {'user.points': 1240});
      await at(tester, 350);
      expect(shownText(tester), '1283');
    });

    testWidgets('the first show is the value itself, and a node without the field changes at once', (tester) async {
      final plain = [_text(_binding('user.points'), animate: false)];
      await change(tester, plain, {'user.points': 10});
      await change(tester, plain, {'user.points': 99});
      expect(shownText(tester), '99');
    });

    testWidgets('reduce motion: the new value at once', (tester) async {
      final children = [_text(_binding('user.points'))];
      await change(tester, children, {'user.points': 10}, reduced: true);
      await change(tester, children, {'user.points': 99}, reduced: true);
      expect(shownText(tester), '99');
    });

    testWidgets('a changed language moves the number without a transition', (tester) async {
      final children = [_text(_binding('user.points', format: 'number'))];
      await change(tester, children, {'user.points': 1000}, locale: 'en');
      await change(tester, children, {'user.points': 5000}, locale: 'de');
      expect(shownText(tester), '5.000', reason: 'the language changed in the same step');
    });

    testWidgets('no data on either side: the fallback and the value appear at once', (tester) async {
      final children = [_text(_binding('user.points', fallback: 'none yet'))];
      await change(tester, children, {});
      expect(shownText(tester), 'none yet');
      await change(tester, children, {'user.points': 700});
      expect(shownText(tester), '700', reason: 'no data before: not a number');
      await change(tester, children, {});
      expect(shownText(tester), 'none yet', reason: 'no data after: not a number');
    });

    testWidgets('a string from the data is not a number', (tester) async {
      final children = [_text(_binding('user.points'))];
      await change(tester, children, {'user.points': 10});
      await change(tester, children, {'user.points': '99'});
      expect(shownText(tester), '99');
    });

    testWidgets('the same value leads nowhere', (tester) async {
      final children = [_text(_binding('user.points'))];
      await change(tester, children, {'user.points': 10});
      await change(tester, children, {'user.points': 10, 'other.thing': 1});
      expect(shownText(tester), '10');
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a date and a countdown part are not led', (tester) async {
      final children = [_text(_binding('offer.endsAt', format: 'date'))];
      await change(tester, children, {'offer.endsAt': '2026-10-12T12:00:00.000Z'});
      final before = shownText(tester);
      await change(tester, children, {'offer.endsAt': '2027-01-20T12:00:00.000Z'});
      expect(shownText(tester), isNot(before));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a document with another binding is another document: its value stands at once', (tester) async {
      await change(tester, [_text(_binding('user.points'))], {'user.points': 10, 'user.coins': 500});
      await change(tester, [_text(_binding('user.coins'))], {'user.points': 10, 'user.coins': 500});
      expect(shownText(tester), '500');
    });

    testWidgets('the screen reader hears the FINAL value, the shown one is out of the semantics', (tester) async {
      final handle = tester.ensureSemantics();
      final children = [_text(_binding('user.points'))];
      await change(tester, children, {'user.points': 0});
      await change(tester, children, {'user.points': 1000});
      await at(tester, 175);
      expect(int.parse(shownText(tester)), greaterThan(0));
      expect(find.bySemanticsLabel('1000'), findsOneWidget);
      expect(find.bySemanticsLabel(shownText(tester)), findsNothing);
      await at(tester, 700);
      expect(find.bySemanticsLabel('1000'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a new record of a list is a first show; the others lead', (tester) async {
      final list = {
        'id': 'list',
        'type': 'Repeater',
        'props': {'source': 'items', 'item': 'item', 'gap': 'none'},
        'children': [
          _text(_binding('item.points'), id: 'row'),
        ],
      };
      List<Object?> items(Iterable<(String, num)> rows) => [
        for (final (id, points) in rows) {'id': id, 'points': points},
      ];
      await change(tester, [list], {'items': items([('a', 100), ('b', 200)])});
      expect(find.text('100'), findsOneWidget);
      // `a` changes, `n` is new at the head: `n` shows its value at once, `a` (now second) leads.
      await change(tester, [list], {'items': items([('n', 900), ('a', 300), ('b', 200)])});
      expect(find.text('900'), findsOneWidget, reason: 'a new record is a first show');
      expect(find.text('100'), findsOneWidget, reason: '`a` leads from 100, not from the record that stood before it');
      expect(find.text('200'), findsOneWidget);
      await at(tester, 700);
      expect(find.text('300'), findsOneWidget);
    });
  });

  group('a scale, through real frames', () {
    Future<void> change(WidgetTester tester, List<_Json> children, num progress, {bool reduced = false}) =>
        pumpDocument(tester, docWith(children), data: {'task.progress': progress}, disableAnimations: reduced);

    double barRatio(WidgetTester tester) => tester.widget<ProgressTrack>(find.byType(ProgressTrack)).ratio;

    double ringRatio(WidgetTester tester) =>
        (tester.widget<CustomPaint>(find.descendant(of: find.byType(RingPlacement), matching: find.byType(CustomPaint)).first).painter! as RingPainter).ratio;

    testWidgets('the fill grows without a step, by the contract curve', (tester) async {
      final children = [_scale('ProgressBar')];
      await change(tester, children, 30);
      expect(barRatio(tester), closeTo(0.3, 1e-9));
      await change(tester, children, 90);
      expect(barRatio(tester), closeTo(0.3, 1e-9), reason: 'the first frame is the old value');
      await tester.pump(const Duration(milliseconds: 350));
      expect(barRatio(tester), closeTo(0.825, 1e-9), reason: '30 + 60 * 0.875, with no step');
      await tester.pump(const Duration(milliseconds: 350));
      expect(barRatio(tester), closeTo(0.9, 1e-9));
    });

    testWidgets('the ring grows too', (tester) async {
      final children = [_scale('CircularProgress')];
      await change(tester, children, 20);
      await change(tester, children, 100);
      await tester.pump(const Duration(milliseconds: 175));
      expect(ringRatio(tester), closeTo(0.2 + 0.8 * 0.578125, 1e-9));
      await tester.pump(const Duration(seconds: 1));
      expect(ringRatio(tester), 1);
    });

    testWidgets('the label `valueOfMax` writes the numbers in steps', (tester) async {
      final steps = [_scale('ProgressBar', labelFormat: 'valueOfMax')];
      await change(tester, steps, 30);
      await change(tester, steps, 90);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('82 / 100'), findsOneWidget, reason: 'whole ends: whole steps, 30 + trunc(52.5)');
    });

    testWidgets('the label `percent` is the shown ratio', (tester) async {
      final percent = [_scale('ProgressBar', labelFormat: 'percent')];
      await change(tester, percent, 30);
      await change(tester, percent, 90);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('83%'), findsOneWidget, reason: 'the shown ratio 0.825 rounds to 83');
    });

    testWidgets('the max leads on its own transition', (tester) async {
      final children = [_scale('ProgressBar', max: {'kind': 'binding', 'path': 'task.target', 'fallback': 5})];
      Future<void> data(num progress, num target) =>
          pumpDocument(tester, docWith(children), data: {'task.progress': progress, 'task.target': target});
      await data(5, 10);
      expect(barRatio(tester), 0.5);
      await data(5, 20);
      await tester.pump(const Duration(milliseconds: 350));
      // The max went 10 -> 17.5 (0.875 of the way): the ratio is 5 / 18.75.
      expect(barRatio(tester), closeTo(5 / 18.75, 1e-9));
      await tester.pump(const Duration(seconds: 1));
      expect(barRatio(tester), closeTo(0.25, 1e-9));
    });

    testWidgets('reduce motion: the scale changes at once', (tester) async {
      final children = [_scale('ProgressBar')];
      await change(tester, children, 30, reduced: true);
      await change(tester, children, 90, reduced: true);
      expect(barRatio(tester), closeTo(0.9, 1e-9));
    });

    testWidgets('a scale without the field jumps', (tester) async {
      final children = [_scale('ProgressBar', animate: false)];
      await change(tester, children, 30);
      await change(tester, children, 90);
      expect(barRatio(tester), closeTo(0.9, 1e-9));
    });

    testWidgets('the screen reader hears the final value of the scale', (tester) async {
      final handle = tester.ensureSemantics();
      final children = [_scale('ProgressBar')];
      await change(tester, children, 30);
      await change(tester, children, 90);
      await tester.pump(const Duration(milliseconds: 175));
      expect(_semanticValues(tester), ['90'], reason: 'the final value, not the one between');
      await tester.pump(const Duration(seconds: 1));
      expect(_semanticValues(tester), ['90']);
      handle.dispose();
    });
  });
}

/// The values of every node of the semantics tree that has one.
List<String> _semanticValues(WidgetTester tester) {
  final values = <String>[];
  void visit(SemanticsNode node) {
    if (node.value.isNotEmpty) values.add(node.value);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return values;
}
