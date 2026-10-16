/// THE APP BAR AFTER SCROLLING (schema 9.21.0): `styleScrolled` and `titleShown: 'scrolled'`.
///
/// The three `scrolled…` groups of the shared table `fixtures/media-chrome/media-chrome-cases.json`, every row
/// run through the rule; the threshold also through a REAL scroll of a REAL body (the bar changes when the body
/// passes the number, not before), and the documents through the reader. Around the table: the mirror of the
/// artifact block `x-style.layout.appBarScrolled`, which bar the field acts on, and what a bar that cannot be
/// scrolled does.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/scrolled_bar.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table = jsonDecode(File('assets/contract/fixtures/media-chrome/media-chrome-cases.json').readAsStringSync()) as _Json;
final _Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

double _num(Object? value) => (value! as num).toDouble();

const _Json _opaque = {'kind': 'color', 'color': 'surface'};

_Json _bar({_Json? scrolled, Object? titleShown, _Json? style, List<_Json>? styleWhen}) => {
  'id': 'bar',
  'type': 'AppBar',
  'props': {
    'title': {'kind': 'literal', 'value': 'Mission'},
    'showBack': false,
    'titleShown': ?titleShown,
  },
  'style': ?style,
  'styleWhen': ?styleWhen,
  'styleScrolled': ?scrolled,
};

_Json _tall(String id) => {
  'id': id,
  'type': 'Container',
  'props': {'gap': 'none'},
  'style': {'height': 2000},
  'children': <Object?>[],
};

UiDocument _screen(List<_Json> children, {Object? bodyTop}) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'scrolled',
  'name': 'scrolled',
  'initialScreenId': 'main',
  'screens': [
    {
      'screenId': 'main',
      'name': 'main',
      'root': {
        'id': 'root',
        'type': 'Screen',
        'props': {'gap': 'none', 'bodyTop': ?bodyTop},
        'style': {'background': colorBackground()},
        'children': children,
      },
    },
  ],
});

void main() {
  final theme = RenderTheme.fallback();

  test('the three groups are read in full: 9 + 4 + 7 rows, names unique, only known fields', () {
    expect(_rows('scrolledThresholdCases'), hasLength(9));
    expect(_rows('scrolledLayerCases'), hasLength(4));
    expect(_rows('scrolledDocumentCases'), hasLength(7));
    const known = {
      'scrolledThresholdCases': {'name', 'scrollTop', 'barBottom', 'bodyTop', 'threshold', 'expected'},
      'scrolledLayerCases': {'name', 'base', 'state', 'scrolled', 'expected'},
      'scrolledDocumentCases': {'name', 'node', 'valid'},
    };
    for (final entry in known.entries) {
      final rows = _rows(entry.key);
      expect(rows.map((row) => row['name']).toSet(), hasLength(rows.length), reason: '${entry.key}: names are unique');
      for (final row in rows) {
        expect(row.keys.toSet().difference(entry.value), isEmpty, reason: '${entry.key}/${row['name']}');
      }
    }
  });

  test('x-style.layout.appBarScrolled: the mirror against the artifact', () {
    final block = ((_schema['x-style']! as _Json)['layout']! as _Json)['appBarScrolled']! as _Json;
    expect(block['prop'], kAppBarScrolledRules['prop']);
    expect(block['titleProp'], kAppBarScrolledRules['titleProp']);
    expect(block['keys'], kScrolledStyleKeys.toList());
    expect(block['transition'], kAppBarScrolledRules['transition']);
    expect(block['unknownToken'], kAppBarScrolledRules['unknownToken']);
    expect((block['threshold']! as _Json)['strict'], isTrue);
    expect(((block['titleShown']! as _Json)['scrolled']), isA<String>());
    expect(block['cases'], 'contract/fixtures/media-chrome/media-chrome-cases.json#scrolledThresholdCases');
  });

  group('scrolledThresholdCases: scrolled <=> scrollTop > max(0, barBottom - bodyTop)', () {
    for (final row in _rows('scrolledThresholdCases')) {
      test(row['name']! as String, () {
        final barBottom = _num(row['barBottom']);
        final bodyTop = _num(row['bodyTop']);
        expect(scrolledThreshold(barBottom: barBottom, bodyTop: bodyTop), _num(row['threshold']));
        expect(isBarScrolled(_num(row['scrollTop']), barBottom: barBottom, bodyTop: bodyTop), row['expected']);
      });
    }

    test('a scroll that is not a number is rest', () {
      expect(isBarScrolled(double.nan, barBottom: 0, bodyTop: 0), isFalse);
      expect(isBarScrolled(double.infinity, barBottom: 0, bodyTop: 0), isFalse);
    });
  });

  group('scrolledLayerCases: the layer lies last', () {
    for (final row in _rows('scrolledLayerCases')) {
      test(row['name']! as String, () {
        final base = NodeStyle.parse(row['base']);
        final state = row.containsKey('state') ? NodeStyle.parse(row['state']) : null;
        // The first state whose condition holds: `isEmpty` over empty data.
        final cases = state == null
            ? const <StyleCase>[]
            : StyleCase.parseList([
                {'when': {'path': 'none.at.all', 'op': 'isEmpty'}, 'style': row['state']},
              ]);
        final resolved = resolveNodeStyle(base, cases, ScreenData.empty);
        final shown = withScrolledLayer(resolved, readScrolledStyle(row['scrolled']));
        final expected = NodeStyle.parse(row['expected'])!;
        expect(shown, isNotNull);
        for (final (name, actual, wanted) in <(String, Object?, Object?)>[
          ('color', shown!.color, expected.color),
          ('background', shown.background, expected.background),
          ('shadow', shown.shadow, expected.shadow),
          ('padding', shown.padding, expected.padding),
          ('backdropBlur', shown.backdropBlur, expected.backdropBlur),
        ]) {
          expect(actual, wanted, reason: name);
        }
      });
    }

    test('without a layer the style is returned as it is', () {
      const base = NodeStyle(opacity: 0.5);
      expect(withScrolledLayer(base, null), same(base));
      expect(withScrolledLayer(null, null), isNull);
    });
  });

  group('scrolledDocumentCases: what the reader makes of the document', () {
    for (final row in _rows('scrolledDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final node = Map<String, Object?>.of(row['node']! as _Json);
        await pumpDocument(tester, _screen([node, _tall('body')]), theme: theme);
        expect(tester.takeException(), isNull);
        final doc = _screen([node, _tall('body')]);
        final first = (doc.initialScreen.root as ScreenNode).children.first;
        if (first is AppBarNode) {
          final props = node['props']! as _Json;
          expect(first.titleShown, props['titleShown'] == 'scrolled' ? TitleShown.scrolled : isNull);
          final scrolled = first.styleScrolled;
          if (row['valid'] == true && node.containsKey('styleScrolled')) {
            expect(scrolled, isNotNull);
          } else if (node.containsKey('styleScrolled')) {
            // A refused layer: nothing of a box field (`padding`, `height`) and nothing of an empty object is read.
            expect(scrolled?.padding, isNull);
            expect(scrolled?.height, isNull);
            expect(scrolled, isNull);
          }
        } else {
          // «no other node has the field»: a container with the field is drawn and the field is not read.
          expect(first, isA<ContainerNode>());
        }
      });
    }
  });

  group('a real scroll of a real body', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    final Finder zoneBar = find.byKey(const ValueKey('hl-zone-bar'));
    final Finder body = find.byType(SingleChildScrollView);

    double titleOpacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.descendant(of: zoneBar, matching: find.byType(Opacity)).first).opacity;

    Color? barColor(WidgetTester tester) {
      final colored = tester.widgetList<DecoratedBox>(find.descendant(of: zoneBar, matching: find.byType(DecoratedBox)));
      for (final box in colored) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.color != null) return decoration.color;
      }
      return null;
    }

    Future<void> scrollTo(WidgetTester tester, double offset) async {
      final controller = tester.widget<SingleChildScrollView>(body.first).controller!;
      controller.jumpTo(offset);
      await tester.pump();
    }

    testWidgets('without screenTop: any scroll counts, rest does not', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        _screen([_bar(scrolled: {'background': _opaque}, titleShown: 'scrolled'), _tall('body')]),
        theme: theme,
      );
      expect(titleOpacity(tester), 0, reason: 'the title waits for the scroll');
      expect(barColor(tester), isNull, reason: 'the bar has no background at rest');
      await scrollTo(tester, 1);
      expect(titleOpacity(tester), 1);
      expect(barColor(tester), isNotNull);
      await scrollTo(tester, 0);
      expect(titleOpacity(tester), 0, reason: 'back at rest');
      expect(barColor(tester), isNull);
    });

    testWidgets('at rest the title keeps its place and its meaning for the screen reader', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, _screen([_bar(titleShown: 'scrolled'), _tall('body')]), theme: theme);
      expect(find.text('Mission'), findsOneWidget);
      expect(tester.getSemantics(find.text('Mission')).label, 'Mission');
      expect(tester.getSize(find.text('Mission')).height, greaterThan(0), reason: 'the block keeps its place');
      handle.dispose();
    });

    testWidgets('with screenTop: the threshold is the bar zone, strictly greater', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        _screen([_bar(scrolled: {'background': _opaque}, titleShown: 'scrolled'), _tall('body')], bodyTop: 'screenTop'),
        theme: theme,
      );
      final zone = tester.getSize(zoneBar).height;
      expect(zone, greaterThan(0));
      await scrollTo(tester, zone / 2);
      expect(titleOpacity(tester), 0, reason: 'half of the bar zone is not enough');
      await scrollTo(tester, zone);
      expect(titleOpacity(tester), 0, reason: 'exactly the bar zone is not yet scrolled');
      await scrollTo(tester, zone + 1);
      expect(titleOpacity(tester), 1);
      expect(barColor(tester), isNotNull);
    });

    testWidgets('a pulled first child: the overlap is the threshold', (tester) async {
      phone(tester);
      // `pull: lg` over `gap: none` -- the body area is raised by the whole `lg`.
      final pulled = _tall('first')..['pull'] = 'lg';
      await pumpDocument(
        tester,
        _screen([_bar(scrolled: {'background': _opaque}, titleShown: 'scrolled'), pulled]),
        theme: theme,
      );
      final lift = theme.spacing['lg']!;
      await scrollTo(tester, lift);
      expect(titleOpacity(tester), 0, reason: 'exactly the overlap');
      await scrollTo(tester, lift + 1);
      expect(titleOpacity(tester), 1);
    });

    testWidgets('the layer lies over the state of styleWhen', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        _screen([
          _bar(
            style: {'background': _opaque},
            styleWhen: [
              {
                'when': {'path': 'x.y', 'op': 'isEmpty'},
                'style': {'background': {'kind': 'color', 'color': 'primary'}},
              },
            ],
            scrolled: {'background': {'kind': 'color', 'color': 'accent'}},
          ),
          _tall('body'),
        ]),
        theme: theme,
      );
      expect(barColor(tester), theme.color(ColorToken.primary));
      await scrollTo(tester, 10);
      expect(barColor(tester), theme.color(ColorToken.accent));
    });

    testWidgets('a token the theme does not know: the field is dropped, the field under it stays', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        _screen([
          _bar(
            style: {'background': _opaque},
            scrolled: {'background': {'kind': 'color', 'color': 'noSuchToken'}, 'shadow': 'low'},
          ),
          _tall('body'),
        ]),
        theme: theme,
      );
      await scrollTo(tester, 10);
      expect(barColor(tester), theme.color(ColorToken.surface), reason: 'the unknown colour leaves the base');
    });

    testWidgets('a bar that is not the zone of the screen does not change and shows its title', (tester) async {
      phone(tester);
      await pumpDocument(
        tester,
        _screen([_tall('first'), _bar(scrolled: {'background': _opaque}, titleShown: 'scrolled')]),
        theme: theme,
      );
      expect(find.text('Mission'), findsOneWidget);
      expect(find.descendant(of: find.text('Mission'), matching: find.byType(Opacity)), findsNothing);
      expect(find.ancestor(of: find.text('Mission'), matching: find.byType(Opacity)), findsNothing, reason: 'always shown');
    });

    testWidgets('a bar hidden by a condition has no zone and nothing follows the scroll', (tester) async {
      phone(tester);
      final hidden = _bar(scrolled: {'background': _opaque}, titleShown: 'scrolled')..['visibleIf'] = {'path': 'x.y', 'op': 'isNotEmpty'};
      await pumpDocument(tester, _screen([hidden, _tall('body')]), theme: theme);
      expect(find.text('Mission'), findsNothing);
      await scrollTo(tester, 100);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a document without the fields: the scroll changes nothing about the bar', (tester) async {
      phone(tester);
      await pumpDocument(tester, _screen([_bar(), _tall('body')]), theme: theme);
      expect(find.descendant(of: zoneBar, matching: find.byType(Opacity)), findsNothing);
      await scrollTo(tester, 300);
      expect(find.descendant(of: zoneBar, matching: find.byType(Opacity)), findsNothing);
      expect(find.text('Mission'), findsOneWidget);
    });

    testWidgets('a nested scrolling row does not make the bar scrolled', (tester) async {
      phone(tester);
      final row = {
        'id': 'row',
        'type': 'Row',
        'props': {'gap': 'sm', 'scrollable': true},
        'children': [
          {'id': 'wide', 'type': 'Container', 'props': {'gap': 'none'}, 'style': {'width': 900, 'height': 20}, 'children': <Object?>[]},
        ],
      };
      await pumpDocument(
        tester,
        _screen([_bar(scrolled: {'background': _opaque}, titleShown: 'scrolled'), row, _tall('body')]),
        theme: theme,
      );
      final rowScroll = tester.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView)).firstWhere((view) => view.scrollDirection == Axis.horizontal);
      rowScroll.controller?.jumpTo(100);
      await tester.drag(find.byWidget(rowScroll), const Offset(-150, 0));
      await tester.pump();
      expect(titleOpacity(tester), 0, reason: 'only the body of the screen counts');
    });
  });
}
