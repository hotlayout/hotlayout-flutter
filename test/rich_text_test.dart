/// Composed text (9.6.0) as a SCREEN: what the case table cannot see, because it answers
/// about text, chunks and the strut, not about pixels.
///
///  * one line pitch per paragraph - by SIZE: a two-line paragraph with one `displayL`
///    part is exactly 2 x its line tall, not "28 + 20";
///  * a part the line of this language does not mention still holds the pitch
///    (`unusedSpan: not-drawn-still-measured`);
///  * without `spans` - the same `Text` as before 9.6.0 (no `Text.rich`);
///  * the `rich-text-screens` fixture in three languages: what is drawn, what the
///    screen reader hears, a paragraph in Arabic.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/demo_data.dart';
import 'support/fixtures.dart';

UiDocument _doc(Map<String, Object?> text, {Map<String, Object?>? localization}) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'rich',
  'name': 'rich',
  'initialScreenId': 'rich',
  'screens': [
    {
      'screenId': 'rich',
      'name': 'rich',
      'root': {
        'id': 'root',
        'type': 'Screen',
        'props': {'gap': 'none'},
        'children': [
          {'id': 'row', 'type': 'Text', 'props': text},
        ],
      },
    },
  ],
  'localization': ?localization,
});

Map<String, Object?> _balance({Map<String, Object?>? spans}) => {
  'content': {
    'kind': 'template',
    'template': '{amount} {unit} {amount} {unit}',
    'values': {
      'amount': {'kind': 'binding', 'path': 'user.points', 'fallback': '0', 'format': 'number'},
      'unit': {
        'kind': 'plural',
        'of': 'amount',
        'forms': {'one': 'Point', 'other': 'Points'},
      },
    },
  },
  'align': 'start',
  'overflow': 'clip',
  'spans': ?spans,
};

Future<void> _pump(WidgetTester tester, UiDocument doc, {double width = 200, String? locale}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(
            width: width,
            child: renderDocument(
              doc,
              theme: RenderTheme.fallback(),
              data: const {'user.points': 1850},
              locale: locale,
            ),
          ),
        ),
      ),
    ),
  );
}

/// How many lines the paragraph took (left-to-right): a new line starts where the next
/// selection rectangle lies to the left of the previous one.
int _lines(RenderParagraph paragraph) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: paragraph.text.toPlainText().length),
  );
  var lines = 1;
  for (var i = 1; i < boxes.length; i++) {
    if (boxes[i].left < boxes[i - 1].left) lines++;
  }
  return lines;
}

void main() {
  final theme = RenderTheme.fallback();
  final displayL = theme.typography['displayL']!;
  final bodyM = theme.typography['bodyM']!;
  // The line of the tallest style: size x multiplier.
  final pitch = displayL.fontSize! * displayL.height!;

  RenderParagraph paragraphOf(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(find.byType(RichText).first);

  group('line pitch', () {
    testWidgets('a two-line paragraph with a big part is exactly 2 x its line tall', (tester) async {
      await _pump(
        tester,
        _doc(_balance(spans: {'amount': {'typography': 'displayL'}})),
        width: 220,
      );
      final paragraph = paragraphOf(tester);
      expect(_lines(paragraph), 2, reason: 'the paragraph must wrap to two lines');
      expect(paragraph.size.height, closeTo(2 * pitch, 0.5));
      // "28 + 20" is what a line without a strut would give: the first line with the big
      // part, the second with plain text only.
      expect(paragraph.size.height, isNot(closeTo(pitch + bodyM.fontSize! * bodyM.height!, 1)));
    });

    testWidgets('the pitch is held also by a part the line of this language does not mention (unusedSpan)', (tester) async {
      const place = 'rich/row/content';
      final spans = {'amount': {'typography': 'displayL'}};
      final text = {
        'content': {
          'kind': 'template',
          'template': '{amount} {unit}',
          'values': {
            'amount': {'kind': 'binding', 'path': 'user.points', 'fallback': '0'},
            'unit': {'kind': 'text', 'text': 'pts'},
          },
        },
        'align': 'start',
        'overflow': 'clip',
        'spans': spans,
      };
      final localization = {
        'defaultLocale': 'en',
        'locales': ['en', 'uk'],
        'strings': {
          'uk': {'$place.template': 'Баланс: {unit}'},
        },
      };
      await _pump(tester, _doc(text, localization: localization), width: 400, locale: 'uk');
      final paragraph = paragraphOf(tester);
      expect(paragraph.text.toPlainText(), 'Баланс: pts');
      // There is no big part in the line, yet the pitch is its.
      expect(paragraph.size.height, closeTo(pitch, 0.5));

      // The same line without spans - the pitch of plain text.
      await _pump(tester, _doc({...text}..remove('spans'), localization: localization), width: 400, locale: 'uk');
      expect(paragraphOf(tester).size.height, closeTo(bodyM.fontSize! * bodyM.height!, 0.5));
    });
  });

  group('node shape on screen', () {
    testWidgets('without spans - a plain Text, as before 9.6.0', (tester) async {
      await _pump(tester, _doc(_balance()));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan, isNull);
      expect(text.data, '1,850 Points 1,850 Points');
      expect(text.strutStyle, isNull);
    });

    testWidgets('a style for a name the template does not declare - a plain Text (spanWithoutPlace)', (tester) async {
      await _pump(tester, _doc(_balance(spans: {'ghost': {'color': 'danger'}})));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan, isNull);
      expect(text.data, '1,850 Points 1,850 Points');
    });

    testWidgets('spans on a literal text have no effect', (tester) async {
      await _pump(
        tester,
        _doc({
          'content': {'kind': 'literal', 'value': 'Hello'},
          'align': 'start',
          'overflow': 'clip',
          'spans': {'word': {'color': 'danger'}},
        }),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan, isNull);
      expect(text.data, 'Hello');
    });

    testWidgets('maxLines and overflow work as in text without parts', (tester) async {
      final props = _balance(spans: {'amount': {'typography': 'displayL'}})
        ..['maxLines'] = 1
        ..['overflow'] = 'ellipsis';
      await _pump(tester, _doc(props), width: 220);
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final paragraph = paragraphOf(tester);
      expect(_lines(paragraph), 1);
      expect(paragraph.size.height, closeTo(pitch, 0.5));
    });
  });

  group('fixture rich-text-screens', () {
    final doc = loadFixture('rich-text-screens');

    testWidgets('is read whole, no unknown node and no exception', (tester) async {
      expect(doc.schemaVersion, '9.6.0');
      await pumpDocument(tester, doc, data: sampleScreenData, now: DateTime.parse(kSampleNow));
      expect(tester.takeException(), isNull);
      // There are at least five composed paragraphs on the screen - they differ from
      // plain texts by `Text.rich`.
      final rich = tester.widgetList<Text>(find.byType(Text)).where((text) => text.textSpan != null);
      expect(rich.length, greaterThanOrEqualTo(5));
    });

    for (final locale in ['en', 'uk', 'ar']) {
      testWidgets('in $locale: each composed paragraph is one semantics node with the whole line', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDocument(
          tester,
          doc,
          data: sampleScreenData,
          locale: locale,
          now: DateTime.parse(kSampleNow),
        );
        expect(tester.takeException(), isNull);
        for (final text in tester.widgetList<Text>(find.byType(Text)).where((text) => text.textSpan != null)) {
          final whole = text.textSpan!.toPlainText();
          expect(find.bySemanticsLabel(whole), findsOneWidget, reason: '«$whole» is one node');
          expect(whole, isNot(contains('{')), reason: 'the place was not substituted: $whole');
        }
        handle.dispose();
      });
    }

    // Base chunks of a paragraph with a highlighted word must carry the NODE FONT
    // (`style.typography: titleS` -> 16 / 500), not the default one. The highlighted
    // word overrides only its own fields (weight 700, colour).
    testWidgets('node offer: base chunks carry the titleS font (16 / 500), the word its own weight 700', (tester) async {
      await pumpDocument(tester, doc, data: sampleScreenData, locale: 'en', now: DateTime.parse(kSampleNow));
      final offer = find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null && widget.textSpan!.toPlainText() == 'Earn double points this weekend',
      );
      expect(offer, findsOneWidget);
      final text = tester.widget<Text>(offer);
      final root = text.textSpan! as TextSpan;
      // The style each chunk is drawn in: the default style on top of the root style.
      final context = tester.element(offer);
      final inherited = DefaultTextStyle.of(context).style.merge(text.style).merge(root.style);
      final chunks = root.children!.cast<TextSpan>();
      expect(chunks.map((chunk) => chunk.text), ['Earn ', 'double', ' points this weekend']);
      for (final index in [0, 2]) {
        final style = inherited.merge(chunks[index].style);
        expect(style.fontSize, 16, reason: 'base chunk $index: titleS size');
        expect(style.fontWeight, FontWeight.w500, reason: 'base chunk $index: titleS weight');
      }
      final word = inherited.merge(chunks[1].style);
      expect(word.fontSize, 16);
      expect(word.fontWeight, FontWeight.w700);
    });

    testWidgets('in Arabic the paragraph runs right to left, and the source language text left to right', (tester) async {
      await pumpDocument(tester, doc, data: sampleScreenData, locale: 'ar', now: DateTime.parse(kSampleNow));
      final rich = find.byWidgetPredicate((widget) => widget is Text && widget.textSpan != null);
      expect(Directionality.of(tester.element(rich.first)), TextDirection.rtl);
      await pumpDocument(tester, doc, data: sampleScreenData, locale: 'en', now: DateTime.parse(kSampleNow));
      expect(Directionality.of(tester.element(rich.first)), TextDirection.ltr);
    });
  });
}
