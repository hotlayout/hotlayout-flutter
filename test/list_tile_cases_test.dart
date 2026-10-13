/// THE PARTS OF A LIST ROW (schema 9.19.0, `x-style.layout.listTileParts` and `partStyle`).
///
/// The shared table (`assets/contract/fixtures/list-tile/list-tile-cases.json`, 91 rows, eight groups) runs row by row:
///
///  1. `lineCases` (10) -- the line limits of the title: the rule, and a real paragraph cut at the limit;
///  2. `tileCases` (13) -- the tile under the leading icon (colour, radius, side) as a function;
///  3. `leadingBoxCases` (8) -- the box of the leading slot and where the glyph stands in it, by the function and by
///     the real row (the glyph of the theme stands where the function says);
///  4. `trailingColumnCases` (5) and `rowCases` (11) -- the trailing column and the three columns of the row, as
///     functions; and a real row at 320 and 393 in both directions, whose measured rectangles are the function's;
///  5. `lookCases` (17) and `leadingColorCases` (6) -- who is drawn in which colour and font: a real row under a
///     card that names a colour or does not, with the data that makes the states hold;
///  6. `documentCases` (21) -- every row of props is read and drawn without a crash.
///
/// The model is the builder's `scripts/list-tile-cases.test.tsx`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/list_tile_parts.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/icon_box.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

final Json _table = jsonDecode(File('assets/contract/fixtures/list-tile/list-tile-cases.json').readAsStringSync()) as Json;
final Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Json;
final RenderTheme _theme = RenderTheme.fallback();

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();

ColorRef _color(Object? raw) => ColorRef.tryParse(raw)!;

Color _resolved(Object? raw) => _theme.resolveColor(_color(raw))!;

void _expectColor(Color? actual, Color expected, String reason) {
  expect(actual, isNotNull, reason: reason);
  expect(actual!.a, closeTo(expected.a, 1e-6), reason: '$reason: alpha');
  expect(actual.r, closeTo(expected.r, 1e-6), reason: '$reason: red');
  expect(actual.g, closeTo(expected.g, 1e-6), reason: '$reason: green');
  expect(actual.b, closeTo(expected.b, 1e-6), reason: '$reason: blue');
}

/// A value that makes a state condition of the table hold.
Object? _satisfying(Json when) {
  final value = when['value'];
  return switch (when['op']) {
    'gt' || 'gte' => (value! as num) + 1,
    'lt' || 'lte' => (value! as num) - 1,
    'isTrue' => true,
    'isFalse' => false,
    'isEmpty' => '',
    'isNotEmpty' => 'x',
    _ => value,
  };
}

/// The data that holds the states of [slot] whose path is in [met].
Map<String, Object?> _dataFor(Json slot, List<String> met) {
  final data = <String, Object?>{};
  for (final key in ['styleWhen', 'captionStyleWhen']) {
    for (final entry in ((slot[key] as List<Object?>?) ?? const []).cast<Json>()) {
      final when = asJson(entry['when']);
      if (met.contains(when['path'])) data[when['path']! as String] = _satisfying(when);
    }
  }
  return data;
}

Json _tile(Json props, {String id = 'tile'}) => {'id': id, 'type': 'ListTile', 'props': props};

/// A card that names a colour (or not) around the row.
Json _inContext(Json tile, Json context) => context['colorNamed'] == true
    ? {
        'id': 'card',
        'type': 'Column',
        'props': {'gap': 'none', 'align': 'start'},
        'style': {'color': context['color']},
        'children': [tile],
      }
    : tile;

TextStyle _typography(Object? raw) => _theme.resolveTypography(TypographyRef.tryParse(raw)!)!;

Json _withParts(Json trailing) => {
  ...trailing,
  'text': trailing['text'] ?? {'kind': 'literal', 'value': '1,200'},
  'caption': trailing['caption'] ?? {'kind': 'literal', 'value': 'Credited'},
};

void main() {
  test('the table has the promised rows', () {
    final counts = {
      'lineCases': 10,
      'tileCases': 13,
      'leadingBoxCases': 8,
      'trailingColumnCases': 5,
      'rowCases': 11,
      'lookCases': 17,
      'leadingColorCases': 6,
      'documentCases': 21,
    };
    counts.forEach((key, count) => expect(_rows(key), hasLength(count), reason: key));
  });

  group('lineCases: the line limits', () {
    for (final row in _rows('lineCases')) {
      test('${row['name']} (the rule)', () {
        final shown = listTileShownLines(row['natural']! as int, row['limit']);
        expect(shown.lines, asJson(row['expected'])['lines']);
        expect(shown.cut, asJson(row['expected'])['cut']);
      });

      testWidgets('${row['name']} (a real title)', (tester) async {
        final natural = row['natural']! as int;
        final shown = listTileShownLines(natural, row['limit']);
        // A probe row gives the width the title gets; a text of exactly `natural` lines is made for that width.
        await pumpDocument(tester, docWith([_tile({'leading': {'kind': 'none'}, 'title': {'kind': 'literal', 'value': 'probe'}, 'trailing': {'kind': 'none'}})]));
        final width = tester.getSize(find.byType(Expanded).first).width;
        final style = _theme.text(TypographyToken.titleS).copyWith(color: Colors.black);
        var words = 1;
        String build() => List.filled(words, 'word').join(' ');
        int linesOf(String text) {
          final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: width);
          return painter.computeLineMetrics().length;
        }

        while (linesOf(build()) < natural) {
          words += 1;
        }
        final title = build();
        expect(linesOf(title), natural, reason: 'the test text has the natural lines');
        final props = {
          'leading': {'kind': 'none'},
          'title': {'kind': 'literal', 'value': title},
          'trailing': {'kind': 'none'},
          if (row['limit'] != null) 'titleMaxLines': row['limit'],
        };
        await pumpDocument(tester, docWith([_tile(props)]));
        final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
        expect((paragraph.size.height / (style.fontSize! * style.height!)).round(), shown.lines, reason: 'lines drawn');
        expect(paragraph.didExceedMaxLines, shown.cut, reason: 'cut');
        // The ellipsis stands at the logical end of the last line: the paragraph's own rule by the direction.
        expect(tester.widget<Text>(find.text(title)).overflow, listTileLinesOf(row['limit']) == null ? isNull : TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('tileCases: the tile under the leading icon', () {
    for (final row in _rows('tileCases')) {
      test(row['name']! as String, () {
        final tile = leadingTileOf(row['leading']);
        final expected = row['expected'];
        if (expected == null) {
          expect(tile, isNull);
          return;
        }
        final want = asJson(expected);
        expect(tile, isNotNull);
        expect(tile!.color, _color(want['color']));
        final radius = want['radius'];
        expect(tile.radius, radius is String ? ScaleRef.token(radius) : ScaleRef.value((radius! as num).toDouble()));
        expect(tile.size, want['size']);
      });
    }
  });

  group('leadingBoxCases: the box of the leading slot', () {
    for (final row in _rows('leadingBoxCases')) {
      test('${row['name']} (the rule)', () {
        final glyph = asJson(row['glyph']);
        final box = leadingIconBoxOf(
          leadingTileOf(row['leading']),
          (inline: (glyph['inline']! as num).toDouble(), block: (glyph['block']! as num).toDouble()),
        );
        final want = asJson(row['expected']);
        expect(box.inline, (want['inline']! as num).toDouble());
        expect(box.block, (want['block']! as num).toDouble());
        expect(box.glyphInline, (want['glyphInline']! as num).toDouble());
        expect(box.glyphBlock, (want['glyphBlock']! as num).toDouble());
      });

      testWidgets('${row['name']} (the real row: the glyph of the theme stands where the rule says)', (tester) async {
        final props = {
          'leading': row['leading'],
          'title': {'kind': 'literal', 'value': 'Title'},
          'trailing': {'kind': 'none'},
        };
        await pumpDocument(tester, docWith([_tile(props)]));
        final glyph = tester.getRect(find.byType(IconBox).first);
        final tile = leadingTileOf(row['leading']);
        final box = leadingIconBoxOf(tile, (inline: glyph.width, block: glyph.height));
        if (tile == null) {
          expect(glyph.width, box.inline);
          expect(glyph.height, box.block);
          return;
        }
        final tileRect = tester.getRect(find.byType(ClipRRect).first);
        expect(tileRect.width, box.inline, reason: 'the tile is a square of its side');
        expect(tileRect.height, box.block);
        expect(glyph.left - tileRect.left, closeTo(box.glyphInline, 1e-6), reason: 'the glyph is centred');
        expect(glyph.top - tileRect.top, closeTo(box.glyphBlock, 1e-6));
      });
    }
  });

  group('trailingColumnCases: the trailing column', () {
    for (final row in _rows('trailingColumnCases')) {
      test(row['name']! as String, () {
        final caption = row['caption'] == null ? null : asJson(row['caption']);
        final column = trailingColumnOf(
          textInline: (row['textInline']! as num).toDouble(),
          textLine: (row['textLine']! as num).toDouble(),
          caption: caption == null ? null : (inline: (caption['inline']! as num).toDouble(), line: (caption['line']! as num).toDouble()),
        );
        final want = asJson(row['expected']);
        expect(column.inline, (want['inline']! as num).toDouble());
        expect(column.block, (want['block']! as num).toDouble());
        expect(column.textStart, (want['textStart']! as num).toDouble());
        expect(column.captionStart, (want['captionStart'] as num?)?.toDouble());
      });
    }
  });

  group('rowCases: the three columns of the row', () {
    for (final row in _rows('rowCases')) {
      test(row['name']! as String, () {
        ({double inline, double block})? column(Object? raw) =>
            raw == null ? null : (inline: (asJson(raw)['inline']! as num).toDouble(), block: (asJson(raw)['block']! as num).toDouble());
        final rects = listTileRowRects(
          rowInline: (row['rowInline']! as num).toDouble(),
          gap: (row['gap']! as num).toDouble(),
          leading: column(row['leading']),
          trailing: column(row['trailing']),
          bodyBlock: (row['bodyBlock']! as num).toDouble(),
          rtl: row['direction'] == 'rtl',
        );
        final want = asJson(row['expected']);
        expect(rects.block, (want['block']! as num).toDouble());
        void same(RowRect? actual, Object? raw, String name) {
          if (raw == null) {
            expect(actual, isNull, reason: name);
            return;
          }
          final expected = asJson(raw);
          expect(actual, isNotNull, reason: name);
          expect(actual!.x, (expected['x']! as num).toDouble(), reason: '$name x');
          expect(actual.y, (expected['y']! as num).toDouble(), reason: '$name y');
          expect(actual.width, (expected['width']! as num).toDouble(), reason: '$name width');
          expect(actual.height, (expected['height']! as num).toDouble(), reason: '$name height');
        }

        same(rects.leading, want['leading'], 'leading');
        same(rects.body, want['body'], 'body');
        same(rects.trailing, want['trailing'], 'trailing');
      });
    }

    for (final (width, locale) in [(320.0, 'en'), (320.0, 'ar'), (393.0, 'en'), (393.0, 'ar')]) {
      testWidgets('a real row at $width, $locale: its measured columns are the function\'s', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final document = UiDocumentBuilder.bare(
          [
            _tile({
              'leading': {'kind': 'icon', 'icon': 'gift', 'tile': {'color': 'primary'}},
              'title': {'kind': 'literal', 'value': 'Salary'},
              'subtitle': {'kind': 'literal', 'value': 'Northwind'},
              'trailing': _withParts({'kind': 'text'}),
            }),
          ],
        );
        await pumpDocument(tester, document, locale: locale == 'ar' ? 'ar' : null);
        final rtl = Directionality.of(tester.element(find.text('Salary'))) == TextDirection.rtl;
        expect(rtl, locale == 'ar', reason: 'the screen follows the language');
        final row = tester.getRect(find.byType(Expanded).first);
        final leading = tester.getRect(find.byType(ClipRRect).first);
        final trailingText = tester.getRect(find.text('1,200'));
        final caption = tester.getRect(find.text('Credited'));
        final trailing = trailingText.expandToInclude(caption);
        final gap = _theme.space(SpacingToken.sm);
        final rowWidth = leading.width + gap + row.width + gap + trailing.width;
        final left = rtl ? trailing.left : leading.left;
        final rects = listTileRowRects(
          rowInline: rowWidth,
          gap: gap,
          leading: (inline: leading.width, block: leading.height),
          trailing: (inline: trailing.width, block: trailing.height),
          bodyBlock: row.height,
          rtl: rtl,
        );
        expect(leading.left - left, closeTo(rects.leading!.x, 1e-6), reason: 'leading x');
        expect(row.left - left, closeTo(rects.body.x, 1e-6), reason: 'body x');
        expect(trailing.left - left, closeTo(rects.trailing!.x, 1e-6), reason: 'trailing x');
        expect(trailing.height, caption.height + trailingText.height, reason: 'the column is the sum of its lines');
        expect(caption.top, trailingText.bottom, reason: 'no gap between the lines');
        if (rtl) {
          expect(caption.left, closeTo(trailingText.left, 1e-6), reason: 'both lines at the logical end');
        } else {
          expect(caption.right, closeTo(trailingText.right, 1e-6));
        }
      });
    }
  });

  group('lookCases: who is drawn in which colour and font', () {
    for (final row in _rows('lookCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final trailing = _withParts(asJson(row['trailing']));
        final tile = _tile({
          'leading': {'kind': 'none'},
          'title': {'kind': 'literal', 'value': 'Row'},
          'trailing': trailing,
        });
        await pumpDocument(
          tester,
          docWith([_inContext(tile, asJson(row['context']))]),
          data: _dataFor(trailing, (row['met']! as List<Object?>).cast<String>()),
        );
        final expected = asJson(row['expected']);
        for (final (part, text) in [('text', '1,200'), ('caption', 'Credited')]) {
          final want = asJson(expected[part]);
          final style = tester.widget<Text>(find.text(text)).style!;
          _expectColor(style.color, _resolved(want['color']), '$part colour');
          final font = _typography(want['typography']);
          expect(style.fontSize, font.fontSize, reason: '$part size');
          expect(style.fontWeight, font.fontWeight, reason: '$part weight');
          expect(style.height, font.height, reason: '$part line height');
        }
      });
    }
  });

  group('leadingColorCases: the colour of the leading icon', () {
    for (final row in _rows('leadingColorCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final tile = _tile({
          'leading': row['leading'],
          'title': {'kind': 'literal', 'value': 'Row'},
          'trailing': {'kind': 'none'},
        });
        await pumpDocument(tester, docWith([_inContext(tile, asJson(row['context']))]));
        _expectColor(tester.widget<IconBox>(find.byType(IconBox).first).color, _resolved(row['expected']), 'the glyph');
      });
    }
  });

  group('documentCases: every row of props is read and drawn without a crash', () {
    for (final row in _rows('documentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final props = asJson(row['props']);
        await pumpDocument(
          tester,
          docWith([
            _tile({
              'leading': {'kind': 'none'},
              'title': {'kind': 'literal', 'value': 'Row'},
              'trailing': {'kind': 'none'},
              ...props,
            }),
          ]),
          data: const {'account.income': 5, 'user.isPremium': true},
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Row'), findsOneWidget);
      });
    }

    testWidgets('a caption under a chevron and a style under a choice mark are not read', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _tile({
            'leading': {'kind': 'none'},
            'title': {'kind': 'literal', 'value': 'Row'},
            'trailing': {'kind': 'chevron', 'caption': {'kind': 'literal', 'value': 'ghost caption'}},
          }),
        ]),
      );
      expect(find.text('ghost caption'), findsNothing);
    });

    testWidgets('the style of a caption without a caption draws nothing and changes nothing', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _tile({
            'leading': {'kind': 'none'},
            'title': {'kind': 'literal', 'value': 'Row'},
            'trailing': {'kind': 'text', 'text': {'kind': 'literal', 'value': '1'}, 'captionStyle': {'color': 'danger'}},
          }),
        ]),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(Text).evaluate().length, 2, reason: 'the title and the text only');
    });
  });

  test('x-style.layout: the list row blocks of the artifact', () {
    final layout = asJson(asJson(_schema['x-style'])['layout']);
    final parts = asJson(layout['listTileParts']);
    final maxLines = asJson(parts['maxLines']);
    expect(maxLines['min'], kListTileLinesMin);
    expect(maxLines['max'], kListTileLinesMax);
    final size = asJson(asJson(asJson(parts['leading'])['tile'])['size']);
    expect(size['default'], kLeadingTileSize);
    expect(size['min'], kLeadingTileSizeMin);
    expect(size['max'], kLeadingTileSizeMax);
    expect(asJson(asJson(asJson(parts['leading'])['tile'])['radius'])['default'], kLeadingTileRadius.wire);
    final partStyle = asJson(layout['partStyle']);
    expect(partStyle['keys'], ['color', 'typography']);
    expect(asJson(partStyle['states'])['max'], 4);
  });
}
