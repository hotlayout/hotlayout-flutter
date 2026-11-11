/// THE CHART (schema 9.37.0, `x-chart`): the shared table `assets/contract/fixtures/chart/chart-cases.json`, every
/// row run, the widget through real frames, and the frame `chart-screens`.
///
///  * `pointCases`, `highlightCases`, `barCases`, `lineCases`, `smoothCases`, `labelCases`, `plotHeightCases` -- the
///    numbers of `chart_rules.dart` against the table, to 1e-6;
///  * the widget -- what a real chart draws, its labels, its name for a screen reader, the right-to-left mirror, the
///    appearance, and a broken field that does not take the screen down;
///  * the frame -- four charts on one screen, from literals and from a collection.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/chart_rules.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/chart_paint.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/chart/chart-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

double _n(Object? value) => (value! as num).toDouble();

List<double> _numbers(Object? value) => [for (final item in value! as List<Object?>) _n(item)];

const double _tol = 1e-6;

/// The week of the frame: seven days of spending.
const List<Map<String, Object?>> _spending = [
  {'spend.day': 'Mon', 'spend.amount': 420},
  {'spend.day': 'Tue', 'spend.amount': 260},
  {'spend.day': 'Wed', 'spend.amount': 580},
  {'spend.day': 'Thu', 'spend.amount': 310},
  {'spend.day': 'Fri', 'spend.amount': 760},
  {'spend.day': 'Sat', 'spend.amount': 540},
  {'spend.day': 'Sun', 'spend.amount': 690},
];

UiDocument _chartDoc(Map<String, Object?> props, {Map<String, Object?>? style}) {
  return UiDocument.fromJson({
    'schemaVersion': UiDocument.supportedSchemaVersion,
    'documentId': 'chart-test',
    'name': 'Chart',
    'initialScreenId': 'main',
    'screens': [
      {
        'screenId': 'main',
        'name': 'Main',
        'root': {
          'id': 'root',
          'type': 'Screen',
          'props': {'gap': 'md'},
          'children': [
            {
              'id': 'chart',
              'type': 'Chart',
              'props': props,
              'style': ?style,
            },
          ],
        },
      },
    ],
  });
}

Map<String, Object?> _bars({Map<String, Object?>? extra}) => {
  'variant': 'bars',
  'data': {
    'kind': 'literal',
    'points': [
      {'value': 30, 'label': 'Mon'},
      {'value': 60, 'label': 'Tue'},
      {'value': 45, 'label': 'Wed'},
    ],
  },
  'color': 'primary',
  ...?extra,
};

List<ChartPainter> _painters(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.painter is ChartPainter) paint.painter! as ChartPainter,
];

Future<void> _pump(
  WidgetTester tester,
  UiDocument doc, {
  RenderTheme? theme,
  Map<String, Object?> data = const {},
  bool disableAnimations = false,
  String? locale,
}) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 900), disableAnimations: disableAnimations),
        child: Scaffold(
          body: renderDocument(doc, theme: theme ?? RenderTheme.fallback(), data: data, locale: locale),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('table: structure', () {
    test('the seven groups and the numbers of the artifact block', () {
      expect(_rows('pointCases'), hasLength(7));
      expect(_rows('highlightCases'), hasLength(6));
      expect(_rows('barCases'), hasLength(5));
      expect(_rows('lineCases'), hasLength(3));
      expect(_rows('smoothCases'), hasLength(4));
      expect(_rows('labelCases'), hasLength(3));
      expect(_rows('plotHeightCases'), hasLength(3));
      final rules = (_schema['x-chart']! as _Json);
      final points = rules['points']! as _Json;
      expect(points['min'], kChartPointsMin);
      expect(points['max'], kChartPointsMax);
      expect((rules['box']! as _Json)['defaultHeight'], kChartDefaultHeight);
      final lineWidth = rules['lineWidth']! as _Json;
      expect(lineWidth['min'], kChartLineWidthMin);
      expect(lineWidth['max'], kChartLineWidthMax);
      expect((rules['defaults']! as _Json)['lineWidth'], kChartDefaultLineWidth);
      expect((rules['area']! as _Json)['topOpacity'], kChartAreaTopOpacity);
      expect((rules['highlight']! as _Json)['dotExtra'], kChartDotExtra);
      expect((rules['labels']! as _Json)['minWidth'], kChartLabelMinWidth);
      final defaults = rules['defaults']! as _Json;
      expect(defaults['highlightColor'], kChartDefaultHighlightColor);
      expect(defaults['barRadius'], kChartDefaultBarRadius);
      expect(defaults['barGap'], kChartDefaultBarGap);
      final labels = rules['labels']! as _Json;
      expect(labels['typography'], kChartLabelTypography);
      expect(labels['color'], kChartLabelColor);
      expect(labels['labelGap'], kChartLabelGap);
    });

    test('the props of the schema are the ones the reader reads', () {
      final props = ((_schema[r'$defs']! as _Json)['ChartProps']! as _Json)['properties']! as _Json;
      expect(props.keys, containsAll(['variant', 'data', 'color', 'labels', 'highlight', 'highlightColor']));
      expect((props['lineWidth']! as _Json)['minimum'], kChartLineWidthMin);
      expect((props['lineWidth']! as _Json)['maximum'], kChartLineWidthMax);
    });
  });

  group('pointCases -- how a record becomes a point', () {
    for (final row in _rows('pointCases')) {
      test(row['name']! as String, () {
        final collections = (row['collections']! as _Json).map((key, value) => MapEntry(key, value as List<Object?>));
        final points = chartPointsOf(row['data'], (source) => collections[source]);
        final expected = [
          for (final point in (row['expect']! as List<Object?>).cast<_Json>())
            ChartPoint(_n(point['value']), point['label']! as String),
        ];
        expect(points, expected);
      });
    }
  });

  group('highlightCases -- the shares and the highlighted point', () {
    for (final row in _rows('highlightCases')) {
      test('${row['highlight']} over ${row['values']}', () {
        final values = _numbers(row['values']);
        expect(chartHighlightIndex(values, row['highlight']), row['expect']);
        final ratios = chartRatios(values);
        final expected = _numbers(row['ratios']);
        expect(ratios, hasLength(expected.length));
        for (var i = 0; i < ratios.length; i += 1) {
          expect(ratios[i], closeTo(expected[i], _tol));
        }
      });
    }
  });

  group('barCases -- the bars', () {
    for (final row in _rows('barCases')) {
      test(row['name']! as String, () {
        final values = _numbers(row['values']);
        final bars = chartBars(
          ratios: chartRatios(values, _n(row['shown'])),
          width: _n(row['width']),
          height: _n(row['height']),
          gap: _n(row['gap']),
          radius: _n(row['radius']),
          highlight: chartHighlightIndex(values, row['highlight']),
        );
        final expected = (row['expect']! as List<Object?>).cast<_Json>();
        expect(bars, hasLength(expected.length));
        for (var i = 0; i < bars.length; i += 1) {
          expect(bars[i].x, closeTo(_n(expected[i]['x']), _tol), reason: 'x of $i');
          expect(bars[i].y, closeTo(_n(expected[i]['y']), _tol), reason: 'y of $i');
          expect(bars[i].width, closeTo(_n(expected[i]['width']), _tol), reason: 'width of $i');
          expect(bars[i].height, closeTo(_n(expected[i]['height']), _tol), reason: 'height of $i');
          expect(bars[i].radius, closeTo(_n(expected[i]['radius']), _tol), reason: 'radius of $i');
          expect(bars[i].highlighted, expected[i]['highlighted'], reason: 'highlighted of $i');
        }
      });
    }
  });

  group('lineCases -- the line from edge to edge', () {
    for (final row in _rows('lineCases')) {
      test(row['name']! as String, () {
        final values = _numbers(row['values']);
        final line = chartLine(
          ratios: chartRatios(values),
          width: _n(row['width']),
          height: _n(row['height']),
          lineWidth: _n(row['lineWidth']),
          highlight: chartHighlightIndex(values, row['highlight']),
        );
        final expected = row['expect']! as _Json;
        final points = (expected['points']! as List<Object?>).cast<_Json>();
        expect(line.points, hasLength(points.length));
        for (var i = 0; i < points.length; i += 1) {
          expect(line.points[i].x, closeTo(_n(points[i]['x']), _tol), reason: 'x of $i');
          expect(line.points[i].y, closeTo(_n(points[i]['y']), _tol), reason: 'y of $i');
        }
        expect(line.inset, closeTo(_n(expected['inset']), _tol));
        expect(line.baseline, closeTo(_n(expected['baseline']), _tol));
        final dot = expected['dot'] as _Json?;
        if (dot == null) {
          expect(line.dot, isNull);
        } else {
          expect(line.dot, isNotNull);
          expect(line.dot!.x, closeTo(_n(dot['x']), _tol));
          expect(line.dot!.y, closeTo(_n(dot['y']), _tol));
          expect(line.dot!.radius, closeTo(_n(dot['radius']), _tol));
        }
      });
    }
  });

  group('smoothCases -- the monotone curve', () {
    for (final row in _rows('smoothCases')) {
      test(row['name']! as String, () {
        final points = [
          for (final point in (row['points']! as List<Object?>).cast<_Json>()) ChartXY(_n(point['x']), _n(point['y'])),
        ];
        final tangents = monotoneTangents(points);
        final expected = _numbers(row['expectTangents']);
        expect(tangents, hasLength(expected.length));
        for (var i = 0; i < tangents.length; i += 1) {
          expect(tangents[i], closeTo(expected[i], _tol), reason: 'tangent of $i');
        }
        // The segments are the Bezier pairs of the tangents; a monotone curve never leaves the values of its neighbours.
        final segments = smoothSegments(points);
        expect(segments, hasLength(points.length - 1));
        for (var i = 0; i < segments.length; i += 1) {
          final low = points[i].y < points[i + 1].y ? points[i].y : points[i + 1].y;
          final high = points[i].y < points[i + 1].y ? points[i + 1].y : points[i].y;
          expect(segments[i].c1.y, inInclusiveRange(low - _tol, high + _tol), reason: 'c1 of $i stays between the points');
          expect(segments[i].c2.y, inInclusiveRange(low - _tol, high + _tol), reason: 'c2 of $i stays between the points');
        }
      });
    }
  });

  group('labelCases -- the label boxes', () {
    for (final row in _rows('labelCases')) {
      test(row['name']! as String, () {
        final boxes = chartLabelBoxes(centers: _numbers(row['centers']), width: _n(row['width']));
        final expected = (row['expect']! as List<Object?>).cast<_Json>();
        expect(boxes, hasLength(expected.length));
        for (var i = 0; i < boxes.length; i += 1) {
          expect(boxes[i].index, expected[i]['index']);
          expect(boxes[i].left, closeTo(_n(expected[i]['left']), _tol), reason: 'left of $i');
          expect(boxes[i].width, closeTo(_n(expected[i]['width']), _tol), reason: 'width of $i');
        }
      });
    }
  });

  group('plotHeightCases', () {
    for (final row in _rows('plotHeightCases')) {
      test('height ${row['height']}, labels ${row['labels']}', () {
        expect(
          chartPlotHeight(
            height: _n(row['height']),
            labels: row['labels']! as bool,
            labelLine: _n(row['labelLine']),
            labelGap: _n(row['labelGap']),
          ),
          closeTo(_n(row['expect']), _tol),
        );
      });
    }
  });

  group('fields of the node', () {
    test('a value that is not a number is zero in its place, a negative one is zero', () {
      expect(chartValueOf('7'), 0);
      expect(chartValueOf(double.infinity), 0);
      expect(chartValueOf(double.nan), 0);
      expect(chartValueOf(null), 0);
      expect(chartValueOf(-3), 0);
      expect(chartValueOf(4), 4);
    });

    test('the stroke is clamped to 1..8 and a non-number is 2; an unknown highlight word is none', () {
      expect(readChartLineWidth(0), 1);
      expect(readChartLineWidth(20), 8);
      expect(readChartLineWidth('3'), 2);
      expect(readChartLineWidth(null), 2);
      expect(readChartLineWidth(double.nan), 2);
      expect(readChartHighlight('today'), 'none');
      expect(readChartHighlight('last'), 'last');
      expect(readChartSmooth('smooth'), isTrue);
      expect(readChartSmooth('curved'), isFalse);
    });
  });

  group('the widget', () {
    testWidgets('bars: three bars on the plot area, the highest is full, the box is 120 high without style.height', (
      tester,
    ) async {
      await _pump(tester, _chartDoc(_bars()));
      expect(tester.takeException(), isNull);
      final painter = _painters(tester).single;
      expect(painter.bars, hasLength(3));
      expect(painter.line, isNull);
      expect(painter.bars![1].height, closeTo(120, 1e-6));
      expect(painter.bars![1].y, closeTo(0, 1e-6));
      expect(tester.getSize(find.byType(ChartFrame)).height, 120);
      expect(tester.getSize(find.byType(ChartFrame)).width, closeTo(400, 1e-6));
    });

    testWidgets('style.height sets the box, and the labels live INSIDE it', (tester) async {
      await _pump(tester, _chartDoc(_bars(extra: {'labels': true}), style: {'height': 140}));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ChartFrame)).height, 140);
      final plot = tester.getSize(find.byType(CustomPaint).last);
      expect(plot.height, lessThan(140));
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      // The band is a line of the label font under the plot area and the gap.
      final labelBottom = tester.getBottomLeft(find.text('Mon')).dy;
      final frameBottom = tester.getBottomLeft(find.byType(ChartFrame)).dy;
      expect(labelBottom, lessThanOrEqualTo(frameBottom + 1e-6));
    });

    testWidgets('no labels without the flag: no band, the plot takes the whole box', (tester) async {
      await _pump(tester, _chartDoc(_bars(extra: {'labels': 1}), style: {'height': 100}));
      expect(find.text('Mon'), findsNothing);
      expect(tester.getSize(find.byType(CustomPaint).last).height, 100);
    });

    testWidgets('a line with area, curve and highlight draws its points, a dot and no bars', (tester) async {
      await _pump(
        tester,
        _chartDoc({
          'variant': 'line',
          'data': {
            'kind': 'literal',
            'points': [
              {'value': 2},
              {'value': 6},
              {'value': 4},
            ],
          },
          'color': 'accent',
          'curve': 'smooth',
          'area': true,
          'highlight': 'max',
          'lineWidth': 3,
        }),
      );
      expect(tester.takeException(), isNull);
      final painter = _painters(tester).single;
      expect(painter.bars, isNull);
      expect(painter.line!.points, hasLength(3));
      expect(painter.smooth, isTrue);
      expect(painter.area, isTrue);
      expect(painter.lineWidth, 3);
      expect(painter.line!.dot, isNotNull);
      expect(painter.line!.dot!.radius, 5);
    });

    testWidgets('fewer than two points: nothing is drawn and the box stays', (tester) async {
      await _pump(
        tester,
        _chartDoc({
          'variant': 'bars',
          'data': {
            'kind': 'literal',
            'points': [
              {'value': 1},
            ],
          },
          'color': 'primary',
        }),
      );
      expect(tester.takeException(), isNull);
      final painter = _painters(tester).single;
      expect(painter.bars, isNull);
      expect(painter.line, isNull);
      expect(tester.getSize(find.byType(ChartFrame)).height, 120);
    });

    testWidgets('a broken data field and broken props do not take the screen down', (tester) async {
      for (final props in <Map<String, Object?>>[
        {'variant': 'bars', 'data': null, 'color': 'primary'},
        {'variant': 'pie', 'data': 7, 'color': 3},
        {'variant': 'line', 'data': {'kind': 'collection'}, 'color': 'primary', 'lineWidth': 'thick', 'barRadius': {}},
        {'variant': 'bars', 'data': {'kind': 'literal', 'points': 'many'}, 'color': 'nonsense', 'highlight': 5},
      ]) {
        await _pump(tester, _chartDoc(props));
        expect(tester.takeException(), isNull, reason: '$props');
        expect(find.byType(ChartFrame), findsOneWidget);
      }
    });

    testWidgets('a name is one picture for a screen reader; without a name the chart is hidden', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _chartDoc(_bars(extra: {'alt': 'Active minutes', 'labels': true})));
      expect(find.bySemanticsLabel('Active minutes'), findsOneWidget);
      expect(find.bySemanticsLabel('Mon'), findsNothing);
      final named = tester.getSemantics(find.bySemanticsLabel('Active minutes'));
      expect(named.flagsCollection.isImage, isTrue);

      await _pump(tester, _chartDoc(_bars(extra: {'labels': true})));
      expect(find.bySemanticsLabel('Mon'), findsNothing);
      handle.dispose();
    });

    testWidgets('right-to-left mirrors the drawing and puts the first label at the start', (tester) async {
      await _pump(
        tester,
        _chartDoc(_bars(extra: {'labels': true})),
        locale: 'ar',
      );
      expect(_painters(tester).single.mirrored, isTrue);
      expect(tester.getTopLeft(find.text('Mon')).dx, greaterThan(tester.getTopLeft(find.text('Wed')).dx));
      await _pump(tester, _chartDoc(_bars(extra: {'labels': true})));
      expect(_painters(tester).single.mirrored, isFalse);
      expect(tester.getTopLeft(find.text('Mon')).dx, lessThan(tester.getTopLeft(find.text('Wed')).dx));
    });

    testWidgets('a collection gives one point per record and the labels from labelField', (tester) async {
      await _pump(
        tester,
        _chartDoc({
          'variant': 'bars',
          'data': {
            'kind': 'collection',
            'source': 'spending',
            'item': 'spend',
            'valueField': 'spend.amount',
            'labelField': 'spend.day',
          },
          'color': 'primary',
          'labels': true,
          'highlight': 'max',
        }),
        data: {'spending': _spending},
      );
      final painter = _painters(tester).single;
      expect(painter.bars, hasLength(7));
      expect(painter.bars!.where((bar) => bar.highlighted), hasLength(1));
      expect(painter.bars![4].highlighted, isTrue);
      expect(find.text('Fri'), findsOneWidget);
    });

    testWidgets('animateIn grows the values from zero over 700 ms, the top of the scale stands at once', (tester) async {
      await _pump(tester, _chartDoc(_bars(extra: {'animateIn': true})));
      expect(_painters(tester).single.bars!.every((bar) => bar.height == 0), isTrue);
      await tester.pump(const Duration(milliseconds: 350));
      final halfway = _painters(tester).single.bars!;
      expect(halfway[1].height, greaterThan(0));
      expect(halfway[1].height, lessThan(120));
      // The highest bar is the top of the scale: its share is the eased share, never more than the whole.
      expect(halfway[0].height / halfway[1].height, closeTo(0.5, 1e-6));
      await tester.pump(const Duration(milliseconds: 400));
      final done = _painters(tester).single.bars!;
      expect(done[1].height, closeTo(120, 1e-6));
      expect(done[0].height, closeTo(60, 1e-6));
    });

    testWidgets('"disable animations" gives the final chart at once', (tester) async {
      await _pump(tester, _chartDoc(_bars(extra: {'animateIn': true})), disableAnimations: true);
      expect(_painters(tester).single.bars![1].height, closeTo(120, 1e-6));
    });

    testWidgets('without the flag the chart stands at once, and only the literal true counts', (tester) async {
      await _pump(tester, _chartDoc(_bars(extra: {'animateIn': 'true'})));
      expect(_painters(tester).single.bars![1].height, closeTo(120, 1e-6));
    });

    testWidgets('in a row it takes the width it is given and does not crash in a natural-width row', (tester) async {
      final doc = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'chart-row',
        'name': 'Row',
        'initialScreenId': 'main',
        'screens': [
          {
            'screenId': 'main',
            'name': 'Main',
            'root': {
              'id': 'root',
              'type': 'Screen',
              'props': {},
              'children': [
                {
                  'id': 'row',
                  'type': 'Row',
                  'props': {'gap': 'sm'},
                  'children': [
                    {'id': 'chart', 'type': 'Chart', 'props': _bars(), 'weight': 1},
                    {
                      'id': 'label',
                      'type': 'Text',
                      'props': {
                        'content': {'kind': 'literal', 'value': 'Tue'},
                      },
                    },
                  ],
                },
              ],
            },
          },
        ],
      });
      await _pump(tester, doc);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ChartFrame)).width, greaterThan(0));
    });
  });

  group('the frame chart-screens', () {
    const id = 'chart-screens';

    testWidgets('four charts, from literals and from a collection, in both languages', (tester) async {
      final doc = loadFixture(id);
      await _pump(tester, doc, theme: fixtureTheme(id), data: {'spending': _spending});
      expect(tester.takeException(), isNull);
      final painters = _painters(tester);
      expect(painters, hasLength(4));
      // The week: seven bars, the last one (today) highlighted.
      expect(painters[0].bars, hasLength(7));
      expect(painters[0].bars!.last.highlighted, isTrue);
      // Spending: a smooth line with area, the highest day marked with a dot.
      expect(painters[1].line!.points, hasLength(7));
      expect(painters[1].smooth, isTrue);
      expect(painters[1].area, isTrue);
      expect(painters[1].line!.dot, isNotNull);
      // Steps: a straight line of five points with no highlight.
      expect(painters[2].line!.points, hasLength(5));
      expect(painters[2].smooth, isFalse);
      expect(painters[2].line!.dot, isNull);
      // Spending by day: bars from the collection.
      expect(painters[3].bars, hasLength(7));
      expect(find.text('Mon'), findsWidgets);
    });

    testWidgets('the names of the charts come from the language of the screen', (tester) async {
      final handle = tester.ensureSemantics();
      final strings = (((jsonDecode(readFixture(id)) as _Json)['localization']! as _Json)['strings']! as _Json)['uk']! as _Json;
      await _pump(tester, loadFixture(id), data: {'spending': _spending}, locale: 'uk');
      expect(find.bySemanticsLabel(strings['charts/week-bars/alt']! as String), findsOneWidget);
      expect(find.bySemanticsLabel('Active minutes this week'), findsNothing);
      await _pump(tester, loadFixture(id), data: {'spending': _spending}, locale: 'en');
      expect(find.bySemanticsLabel('Active minutes this week'), findsOneWidget);
      handle.dispose();
    });
  });
}
