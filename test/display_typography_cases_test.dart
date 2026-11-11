/// DISPLAY TYPOGRAPHY (schema 9.35.0): the shared table
/// `assets/contract/fixtures/display-typography/display-typography-cases.json`, every row run, and the frame
/// `display-typography-screens` at the system text scales 1, 1.3 and 2.
///
///  * `scaleCases` -- the effective font size after the system text scale, through the pure rule and through the
///    scaler the screen hands to everything under it;
///  * `trackingCases` -- the letter spacing in pixels, through the rule and through a real `Text`;
///  * `lineCases` -- the height of one line of a real `Text`;
///  * `documentCases` -- how the reader reads each override.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
import 'package:hotlayout_flutter/src/model/display_typography.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/render/display_text_scaler.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

final _Json _table =
    jsonDecode(File('assets/contract/fixtures/display-typography/display-typography-cases.json').readAsStringSync())
        as _Json;

List<_Json> _rows(String key) => (_table[key]! as List<Object?>).cast<_Json>();

double _n(Object? value) => (value! as num).toDouble();

/// A screen on a view wide enough for the test font (every glyph is one em wide), drawn at the system text scale
/// [scale].
Future<void> _pump(
  WidgetTester tester,
  UiDocument doc,
  double scale, {
  RenderTheme? theme,
  Map<String, Object?> data = const {},
}) async {
  tester.view
    ..physicalSize = const Size(1000, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(1000, 1600), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: renderDocument(doc, theme: theme ?? RenderTheme.fallback(), data: data),
        ),
      ),
    ),
  );
  await tester.pump();
}

Map<String, Object?> _textWith(Object typography, {String value = '8', String id = 'n'}) =>
    textNode(value, id: id, style: {'typography': typography, 'color': 'onSurface'});

void main() {
  test('the table has its groups, every row with a unique name', () {
    expect(_rows('scaleCases'), hasLength(44));
    expect(_rows('trackingCases'), hasLength(10));
    expect(_rows('lineCases'), hasLength(6));
    expect(_rows('documentCases'), hasLength(12));
    for (final key in ['scaleCases', 'trackingCases', 'lineCases', 'documentCases']) {
      expect(_rows(key).map((row) => row['name']).toSet(), hasLength(_rows(key).length), reason: key);
    }
  });

  group('scaleCases -- the effective font size', () {
    for (final row in _rows('scaleCases')) {
      test(row['name']! as String, () {
        final size = _n(row['fontSize']);
        final scale = _n(row['scale']);
        final want = _n(row['effective']);
        expect(scaledFontSize(size, scale), closeTo(want, 1e-6));
        // The scaler a screen gives to everything under it follows the same rule.
        expect(DisplayTextScaler(TextScaler.linear(scale)).scale(size), closeTo(want, 1e-6));
      });
    }

    test('the function is continuous at the ceiling and never below its own size above scale one', () {
      for (final scale in [1.0, 1.15, 1.3, 2.0, 3.0]) {
        expect(scaledFontSize(96, scale), closeTo(96 * scale, 1e-9));
        expect(scaledFontSize(96.0001, scale), closeTo(96 * scale, 1e-3));
        expect(scaledFontSize(400, scale), greaterThanOrEqualTo(400));
      }
    });

    test('a scaler is not wrapped twice, and a clamp keeps the rule', () {
      final once = DisplayTextScaler(const TextScaler.linear(2));
      expect(identical(DisplayTextScaler(once), once), isTrue);
      expect(once.clamp(maxScaleFactor: 1.3).scale(240), 240);
      expect(once.clamp(maxScaleFactor: 1.3).scale(50), closeTo(65, 1e-9));
    });
  });

  group('trackingCases -- the letter spacing in pixels', () {
    for (final row in _rows('trackingCases')) {
      test(row['name']! as String, () {
        final size = _n(row['fontSize']);
        final scale = _n(row['scale']);
        final effective = scaledFontSize(size, scale);
        expect(effective, closeTo(_n(row['effective']), 1e-6));
        final em = row['letterSpacingEm'] == null ? null : _n(row['letterSpacingEm']);
        final px = row['letterSpacing'] == null ? null : _n(row['letterSpacing']);
        expect(
          trackingPx(letterSpacing: px, letterSpacingEm: em, effectiveFontSize: effective),
          closeTo(_n(row['trackingPx']), 1e-6),
        );

        // The same through the theme: the override resolved against the scaler the screen uses.
        final theme = RenderTheme.fallback();
        final style = theme.resolveTypography(
          TypographyRef('bodyM', fontSize: size, letterSpacing: px, letterSpacingEm: em),
          textScaler: DisplayTextScaler(TextScaler.linear(scale)),
        )!;
        if (em != null || px != null) expect(style.letterSpacing, closeTo(_n(row['trackingPx']), 1e-6));
      });
    }

    testWidgets('a real Text carries the tracking of its effective size', (tester) async {
      for (final row in _rows('trackingCases')) {
        final em = row['letterSpacingEm'];
        final px = row['letterSpacing'];
        if (em == null && px == null) continue;
        final override = {'token': 'bodyM', 'fontSize': row['fontSize'], 'letterSpacingEm': ?em, 'letterSpacing': ?px};
        await _pump(tester, docWith([_textWith(override)]), _n(row['scale']));
        expect(
          tester.widget<Text>(find.text('8')).style!.letterSpacing,
          closeTo(_n(row['trackingPx']), 1e-6),
          reason: row['name']! as String,
        );
      }
    });
  });

  group('lineCases -- the height of one line', () {
    for (final row in _rows('lineCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await _pump(
          tester,
          docWith([
            _textWith({'token': 'bodyM', 'fontSize': row['fontSize'], 'lineHeight': row['lineHeight']}),
          ]),
          _n(row['scale']),
        );
        // The engine lays a line out in whole pixels: within one pixel of the block of the table.
        expect(tester.getSize(find.text('8')).height, closeTo(_n(row['lineBlock']), 1));
      });
    }
  });

  group('documentCases -- how an override is read', () {
    for (final row in _rows('documentCases')) {
      final name = row['name']! as String;
      test(name, () {
        final raw = row['typography']! as _Json;
        final ref = TypographyRef.tryParse(raw)!;
        final size = raw['fontSize'];
        if (size is num) expect(ref.fontSize, size.toDouble().clamp(kMinFontSizePx, kMaxFontSizePx));
        final em = raw['letterSpacingEm'];
        if (em is num) expect(ref.letterSpacingEm, em.toDouble().clamp(kMinLetterSpacingEm, kMaxLetterSpacingEm));
        // A share that is not a number is the lower bound, like any literal.
        if (em is String) expect(ref.letterSpacingEm, kMinLetterSpacingEm);
        // Both fields at once do not publish; a reader that gets them takes the share.
        if (raw['letterSpacing'] != null && em != null) {
          expect(ref.letterSpacing, isNull);
          expect(ref.letterSpacingEm, isNotNull);
        }
      });
    }

    test('the bound of a size in a node override is the schema one, not the theme one', () {
      final schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as _Json;
      final override = ((schema[r'$defs']! as _Json)['TypographyOverride']! as _Json)['properties']! as _Json;
      expect((override['fontSize']! as _Json)['maximum'], kMaxFontSizePx);
      // A theme token keeps 96: a larger size in a theme is clamped.
      final theme = RenderTheme.fromJsonRaw({...(jsonDecode(readThemeContract()) as _Json)['contract']! as _Json});
      expect(theme, isNotNull);
    });
  });

  group('the frame display-typography-screens', () {
    const id = 'display-typography-screens';

    Future<Map<String, Size>> sizes(WidgetTester tester, double scale) async {
      await _pump(tester, loadFixture(id), scale, theme: fixtureTheme(id));
      expect(tester.takeException(), isNull);
      return {
        'figure': tester.getSize(find.text('50')),
        'title': tester.getSize(find.text('Sale')),
        'note': tester.getSize(find.textContaining('Percent off')),
      };
    }

    testWidgets('scale 1: the figure is 240 high and the title 128, the tracking is -14.4 px', (tester) async {
      final at = await sizes(tester, 1);
      expect(at['figure']!.height, closeTo(240, 1e-6));
      expect(at['title']!.height, closeTo(128, 1e-6));
      expect(tester.widget<Text>(find.text('50')).style!.letterSpacing, closeTo(-14.4, 1e-9));
      // The engine applies it: in the test font a glyph is one em wide, so two glyphs are 2 x (240 - 14.4) wide.
      final natural = tester.renderObject<RenderParagraph>(find.text('50')).getMaxIntrinsicWidth(double.infinity);
      expect(natural, closeTo(2 * (240 - 14.4), 1e-3));
    });

    testWidgets('scale 1.3: the figure and the title do not grow, the line under the banner does', (tester) async {
      final one = await sizes(tester, 1);
      final at = await sizes(tester, 1.3);
      expect(at['figure']!.height, closeTo(240, 1e-6));
      expect(at['title']!.height, closeTo(128, 1e-6));
      expect(at['note']!.height, greaterThan(one['note']!.height));
    });

    testWidgets('scale 2: the figure is 240 and the title is 192; the figure is not clipped', (tester) async {
      final at = await sizes(tester, 2);
      expect(at['figure']!.height, closeTo(240, 1e-6));
      expect(at['title']!.height, closeTo(192, 1e-6));
      final banner = tester.getRect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  (widget.decoration as BoxDecoration).color != null &&
                  tester.getSize(find.byWidget(widget)).height > 300,
            )
            .first,
      );
      expect(banner.bottom, greaterThanOrEqualTo(tester.getRect(find.text('Sale')).bottom));
    });
  });

  group('figureCases -- figures of equal width', () {
    final value =
        jsonDecode(File('assets/contract/fixtures/value-transition/value-transition-cases.json').readAsStringSync())
            as _Json;
    final rows = (value['figureCases']! as List<Object?>).cast<_Json>();

    test('the group is read in full', () {
      expect(rows, hasLength(8));
      for (final row in rows) {
        expect(row.keys.toSet().difference({'name', 'type', 'props', 'expected'}), isEmpty);
      }
    });

    for (final row in rows) {
      testWidgets(row['name']! as String, (tester) async {
        final type = row['type']! as String;
        final props = row['props']! as _Json;
        final Map<String, Object?> node = type == 'Text'
            ? {
                ...textNode('1 250 pts'),
                'props': {...(textNode('1 250 pts')['props']! as _Json), ...props},
              }
            : {
                'id': 'bar',
                'type': 'ProgressBar',
                'props': {
                  'value': {'kind': 'literal', 'value': 40},
                  'max': {'kind': 'literal', 'value': 100},
                  'color': 'primary',
                  'labelFormat': 'valueOfMax',
                  ...props,
                },
              };
        await pumpDocument(tester, docWith([node]));
        final tabular = (row['expected']! as _Json)['tabular'] == true;
        final label = type == 'Text' ? find.text('1 250 pts') : find.textContaining('40');
        expect(label, findsWidgets);
        for (final text in tester.widgetList<Text>(label)) {
          final features = text.style?.fontFeatures ?? const <FontFeature>[];
          expect(features.contains(const FontFeature.tabularFigures()), tabular, reason: row['name']! as String);
        }
      });
    }

    testWidgets('the parts of a text that runs its numbers are in figures of equal width too', (tester) async {
      final node = {
        'id': 'p',
        'type': 'Text',
        'props': {
          'content': {
            'kind': 'template',
            'template': '{n} pts',
            'values': {
              'n': {'kind': 'text', 'text': '1 250'},
            },
          },
          'align': 'start',
          'overflow': 'clip',
          'animateIn': true,
          'spans': {
            'n': {'typography': 'titleM'},
          },
        },
      };
      await pumpDocument(tester, docWith([node]));
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final spans = <TextSpan>[];
      (rich.text as TextSpan).visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      expect(spans, isNotEmpty);
      for (final span in spans) {
        expect(
          (span.style ?? rich.text.style)?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: '"${span.text}"',
        );
      }
    });

    testWidgets('a text with a data number that runs holds its place in the same figures at every moment', (
      tester,
    ) async {
      final node = {
        ...textNode('x'),
        'props': {
          'content': {
            'kind': 'template',
            'template': '{n} pts',
            'values': {
              'n': {'kind': 'binding', 'path': 'user.points', 'fallback': '0'},
            },
          },
          'align': 'start',
          'overflow': 'clip',
          'animateIn': true,
        },
      };
      await pumpDocument(tester, docWith([node]), data: {'user.points': 1250});
      for (final ms in [0, 175, 350, 700]) {
        if (ms > 0) await tester.pump(Duration(milliseconds: ms));
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.style?.fontFeatures, contains(const FontFeature.tabularFigures()), reason: 'at $ms ms');
        }
      }
    });
  });
}
