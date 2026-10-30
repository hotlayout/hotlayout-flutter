/// THE LAYOUT IS HELD BY THE FINAL VALUE (`x-valueLayout`).
///
/// The `layoutCases` group of the shared table `fixtures/value-transition/value-transition-cases.json`, every row
/// run through the rule, and the mechanism through REAL widgets: a text below a number that runs keeps its height
/// on the first, a middle and the last frame, the painted number lies over the place of the final one, and the
/// screen reader still hears the final text.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/value_layout.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/value-transition/value-transition-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

_Json _template(String text, {bool appear = false, bool changes = false, int? maxLines, String align = 'start'}) => {
  'id': 'line',
  'type': 'Text',
  'props': {
    'content': {
      'kind': 'template',
      'template': text,
      'values': {
        'n': {'kind': 'binding', 'path': 'user.rank', 'fallback': '0'},
      },
    },
    'animateIn': ?(appear ? true : null),
    'animateChanges': ?(changes ? true : null),
    'maxLines': ?maxLines,
    'align': align,
  },
  'style': {'width': 150},
};

_Json _bar(String path, {bool changes = true}) => {
  'id': 'bar',
  'type': 'ProgressBar',
  'props': {
    'value': {'kind': 'binding', 'path': path, 'fallback': 0},
    'max': {'kind': 'literal', 'value': 100},
    'color': 'primary',
    'labelFormat': 'valueOfMax',
    'animateChanges': ?(changes ? true : null),
  },
};

// In a box of 150 the text fits one line with a one-digit number and wraps with a two-digit one.
const String _sentence = 'ahead of {n}';

void main() {
  test('layoutCases: the group is read in full and every field of it is known', () {
    final rows = _rows('layoutCases');
    expect(rows, hasLength(13));
    expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length));
    for (final row in rows) {
      expect(row.keys.toSet().difference({'name', 'from', 'changes', 't', 'digits', 'reducedMotion', 'expected'}), isEmpty);
    }
  });

  test('x-valueLayout: the artifact block refines both transition blocks and names the table', () {
    final block = _schema['x-valueLayout']! as _Json;
    expect(block['refines'], ['x-valueTransition.shown', 'x-valueAppear.shown']);
    expect(block['cases'], 'contract/fixtures/value-transition/value-transition-cases.json (layoutCases)');
  });

  group('layoutCases: what the node measures and what it paints', () {
    for (final row in _rows('layoutCases')) {
      test(row['name']! as String, () {
        final frame = valueLayoutAt(
          from: row['from']! as num,
          changes: [
            for (final change in (row['changes']! as List<Object?>).cast<_Json>())
              ValueLayoutChange(at: change['at']! as num, to: change['to']! as num),
          ],
          t: row['t']! as num,
          digits: row['digits'] as int?,
          reducedMotion: row['reducedMotion'] == true,
        );
        final expected = row['expected']! as _Json;
        expect(frame.layout, closeTo((expected['layout']! as num).toDouble(), 1e-9));
        expect(frame.shown, closeTo((expected['shown']! as num).toDouble(), 1e-9));
        expect(frame.held, expected['held']);
      });
    }
  });

  group('through real widgets', () {
    Future<double> heightAfter(WidgetTester tester, _Json node, Map<String, Object?> data, {int ms = 0}) async {
      await pumpDocument(tester, docWith([node, _below()]), data: data);
      if (ms > 0) await tester.pump(Duration(milliseconds: ms));
      return tester.getRect(find.text('below')).top;
    }

    // The node under the text is a witness: its top is the height of everything above it.
    testWidgets('the height under a text that appears is the same on the first, a middle and the last frame', (tester) async {
      final node = _template(_sentence, appear: true);
      final tops = <double>[];
      await pumpDocument(tester, docWith([node, _below()]), data: {'user.rank': 78});
      for (final ms in [0, 175, 350, 525, 700, 100]) {
        if (ms > 0) await tester.pump(Duration(milliseconds: ms));
        tops.add(tester.getRect(find.text('below')).top);
      }
      expect(tops.toSet(), hasLength(1), reason: 'the layout changes once, never on a frame of the motion: $tops');
      final plain = await heightAfter(tester, _template(_sentence), {'user.rank': 78});
      expect(tops.first, plain, reason: 'the place is that of the final text');
    });

    testWidgets('the place is not that of the first value: the scene is one where the final text wraps', (tester) async {
      // A guard against a test that proves nothing: the same text measured with 0 and with 78 differs in height.
      final zero = await heightAfter(tester, _template(_sentence), {'user.rank': 0});
      final final78 = await heightAfter(tester, _template(_sentence), {'user.rank': 78});
      expect(zero, isNot(final78));
    });

    testWidgets('a change of data under a shown text keeps the height of the final text on every frame', (tester) async {
      final node = _template(_sentence, changes: true);
      await pumpDocument(tester, docWith([node, _below()]), data: {'user.rank': 0});
      final before = tester.getRect(find.text('below')).top;
      await pumpDocument(tester, docWith([node, _below()]), data: {'user.rank': 78});
      final tops = <double>[tester.getRect(find.text('below')).top];
      for (final ms in [175, 175, 350, 100]) {
        await tester.pump(Duration(milliseconds: ms));
        tops.add(tester.getRect(find.text('below')).top);
      }
      expect(tops.toSet(), hasLength(1), reason: '$tops');
      final plain = await heightAfter(tester, _template(_sentence), {'user.rank': 78});
      expect(tops.first, plain);
      expect(before, isNot(plain), reason: 'the layout did change, once, when the data changed');
    });

    testWidgets('the painted number lies over the place of the final text, in figures of equal width', (tester) async {
      await pumpDocument(tester, docWith([_template(_sentence, appear: true)]), data: {'user.rank': 78});
      await tester.pump(const Duration(milliseconds: 175));
      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts, hasLength(2));
      final held = tester.getRect(find.byWidget(texts.first));
      final painted = tester.getRect(find.byWidget(texts.last));
      expect(painted, held, reason: 'same start, same width, same height');
      expect(tester.widget<Opacity>(find.ancestor(of: find.byWidget(texts.first), matching: find.byType(Opacity)).first).opacity, 0);
      final context = tester.element(find.byWidget(texts.last));
      expect(DefaultTextStyle.of(context).style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(texts.first.data, contains('78'));
      expect(texts.last.data, isNot(contains('78')));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byType(Text), findsNWidgets(1), reason: 'at the end the final text stands in its own place alone');
    });

    testWidgets('centred text: the painted number is centred in the box of the final text', (tester) async {
      await pumpDocument(tester, docWith([_template('{n}', appear: true, align: 'center')]), data: {'user.rank': 1000});
      await tester.pump(const Duration(milliseconds: 175));
      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(tester.getRect(find.byWidget(texts.first)), tester.getRect(find.byWidget(texts.last)));
      expect(tester.widget<Text>(find.byWidget(texts.last)).textAlign, TextAlign.center);
    });

    testWidgets('the screen reader hears the final text only, once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, docWith([_template('{n} points', appear: true)]), data: {'user.rank': 78});
      await tester.pump(const Duration(milliseconds: 175));
      expect(find.bySemanticsLabel('78 points'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^\d+ points$')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a bar label holds the place of the final label while the value runs', (tester) async {
      // In a row of natural width the track is as wide as its label.
      final node = {
        'id': 'row',
        'type': 'Row',
        'props': {'gap': 'none', 'align': 'start', 'justify': 'start', 'wrap': false},
        'children': [
          {
            'id': 'chip',
            'type': 'Container',
            'props': {'direction': 'row', 'gap': 'none'},
            'children': [_bar('task.done')],
          },
          _below(),
        ],
      };
      await pumpDocument(tester, docWith([node]), data: {'task.done': 5});
      final width = (await _barWidth(tester));
      await pumpDocument(tester, docWith([node]), data: {'task.done': 100});
      final widths = <double>[await _barWidth(tester)];
      for (final ms in [175, 175, 350, 100]) {
        await tester.pump(Duration(milliseconds: ms));
        widths.add(await _barWidth(tester));
      }
      expect(widths.toSet(), hasLength(1), reason: '$widths');
      expect(widths.first, greaterThan(width), reason: 'the final label "100 / 100" is wider than "5 / 100"');
    });
  });
}

_Json _below() => {
  'id': 'below',
  'type': 'Text',
  'props': {'content': {'kind': 'literal', 'value': 'below'}},
};

Future<double> _barWidth(WidgetTester tester) async => tester.getRect(find.byType(ProgressTrack)).width;
