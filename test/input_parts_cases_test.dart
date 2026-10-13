/// THE PARTS OF A TEXT FIELD (schema 9.19.0, `x-style.layout.inputParts`): the box, the marks, the counter and
/// the row under the box.
///
/// The shared table (`assets/contract/fixtures/inputs/input-cases.json`, five new groups) runs row by row:
///
///  1. `fieldBoxCases` (16) -- the height of the box: by the function, and a real field of the same props measured;
///  2. `affixRowCases` (7) -- where the marks and the text stand in the row inside the box: by the function (the
///     left edges in a right-to-left screen included), and real marks measured in both directions;
///  3. `counterCases` (16) -- the text of the counter: by the function, and a real field shows it (or does not);
///  4. `noteRowCases` (4) -- the row under the box: by the function, and a real note beside a real counter;
///  5. `partsDocumentCases` (20) -- every row of props is read and drawn without a crash; what a document may say
///     and the reader does not read is not read.
///
/// The model is the builder's `scripts/input-parts-cases.test.tsx`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/input_parts.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/icon_box.dart';
import 'package:hotlayout_flutter/src/render/inputs.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

final Json _table = jsonDecode(File('assets/contract/fixtures/inputs/input-cases.json').readAsStringSync()) as Json;
final Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Json;
final RenderTheme _theme = RenderTheme.fallback();

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();

double _n(Object? value) => (value! as num).toDouble();

Json _field(Json extra, {String path = 'form.note'}) => {
  'id': 'field',
  'type': 'TextField',
  'props': {
    'label': {'kind': 'literal', 'value': 'Amount'},
    'value': {'kind': 'binding', 'path': path},
    ...extra,
  },
};

/// The decorated box of the field.
Finder get _box => find.descendant(
  of: find.byType(InputTextField),
  matching: find.byWidgetPredicate((widget) => widget is Container && widget.decoration is BoxDecoration && (widget.decoration! as BoxDecoration).border != null),
);

TextStyle get _fieldFont => _theme.text(TypographyToken.bodyM);

double get _fieldLine => _fieldFont.fontSize! * _fieldFont.height!;

void main() {
  test('the table has the promised rows', () {
    expect(_rows('fieldBoxCases'), hasLength(16));
    expect(_rows('affixRowCases'), hasLength(7));
    expect(_rows('counterCases'), hasLength(16));
    expect(_rows('noteRowCases'), hasLength(4));
    expect(_rows('partsDocumentCases'), hasLength(20));
  });

  group('fieldBoxCases: the height of the box', () {
    for (final row in _rows('fieldBoxCases')) {
      final metrics = asJson(row['metrics']);
      test('${row['name']} (the rule)', () {
        final height = fieldBoxHeightOf(
          textLine: _n(metrics['textLine']),
          paddingBlock: _n(metrics['paddingBlock']),
          lines: row['lines']! as int,
          height: row['height'],
          borderWidth: row['borderWidth'],
        );
        expect(height, _n(row['expect']));
      });

      testWidgets('${row['name']} (a real field)', (tester) async {
        final lines = row['lines']! as int;
        await pumpDocument(
          tester,
          docWith([
            _field({'lines': lines, 'fieldHeight': ?row['height'], 'fieldBorderWidth': ?row['borderWidth']}),
          ]),
        );
        // The same rule with the metrics of the real field: its line and its padding.
        final expected = fieldBoxHeightOf(
          textLine: _fieldLine,
          paddingBlock: _theme.space(SpacingToken.md),
          lines: lines,
          height: row['height'],
          borderWidth: row['borderWidth'],
        );
        expect(tester.getSize(_box).height, closeTo(expected, 1e-2));
      });
    }
  });

  group('affixRowCases: the row inside the box', () {
    for (final row in _rows('affixRowCases')) {
      test('${row['name']} (the rule)', () {
        final laid = affixRowOf(
          boxInline: _n(row['boxInline']),
          border: _n(row['border']),
          paddingInline: _n(row['paddingInline']),
          gap: _n(row['gap']),
          prefix: row['prefix'] == null ? null : _n(row['prefix']),
          suffix: row['suffix'] == null ? null : _n(row['suffix']),
        );
        final want = asJson(row['expect']);
        expect(laid.prefixStart, (want['prefixStart'] as num?)?.toDouble());
        expect(laid.textStart, _n(want['textStart']));
        expect(laid.textInline, _n(want['textInline']));
        expect(laid.suffixStart, (want['suffixStart'] as num?)?.toDouble());
        // A right-to-left screen: the left edge is `box - start - width`.
        final rtl = row['rtl'];
        if (rtl != null) {
          final box = _n(row['boxInline']);
          final edges = asJson(rtl);
          expect(box - laid.prefixStart! - _n(row['prefix']), _n(edges['prefixX']));
          expect(box - laid.textStart - laid.textInline, _n(edges['textX']));
          expect(box - laid.suffixStart! - _n(row['suffix']), _n(edges['suffixX']));
        }
      });
    }

    for (final (width, locale) in [(320.0, 'en'), (320.0, 'ar'), (393.0, 'en'), (393.0, 'ar')]) {
      testWidgets('real marks at $width, $locale: measured, they stand where the rule says', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpDocument(
          tester,
          docWith([
            _field({
              'prefix': {'kind': 'icon', 'icon': 'mail'},
              'suffix': {'kind': 'text', 'text': {'kind': 'literal', 'value': 'kg'}},
              'valueType': 'number',
            }),
          ]),
          locale: locale == 'ar' ? 'ar' : null,
        );
        final rtl = Directionality.of(tester.element(find.byType(InputTextField))) == TextDirection.rtl;
        expect(rtl, locale == 'ar');
        final box = tester.getRect(_box);
        final prefix = tester.getRect(find.byType(IconBox));
        final suffix = tester.getRect(find.text('kg'));
        final text = tester.getRect(find.byType(TextField));
        final border = 1.0;
        final pad = _theme.space(SpacingToken.md);
        final laid = affixRowOf(
          boxInline: box.width,
          border: border,
          paddingInline: pad,
          gap: _theme.space(SpacingToken.sm),
          prefix: prefix.width,
          suffix: suffix.width,
        );
        double fromStart(Rect rect) => rtl ? box.right - rect.right : rect.left - box.left;
        expect(fromStart(prefix), closeTo(laid.prefixStart!, 1e-6), reason: 'the first mark is at the logical start');
        expect(fromStart(text), closeTo(laid.textStart, 1e-6), reason: 'the text follows it');
        expect(text.width, closeTo(laid.textInline, 1e-6), reason: 'the text takes the rest');
        expect(fromStart(suffix), closeTo(laid.suffixStart!, 1e-6), reason: 'the second mark is at the logical end');
      });
    }
  });

  group('counterCases: the text of the counter', () {
    for (final row in _rows('counterCases')) {
      test('${row['name']} (the rule)', () {
        final props = asJson(row['props']);
        expect(
          inputCounterText(counter: props['counter'], maxLength: props['maxLength'], shown: row['shown']! as String),
          row['expect'],
        );
      });

      testWidgets('${row['name']} (a real field)', (tester) async {
        final props = asJson(row['props']);
        await pumpDocument(tester, docWith([_field(props)]), data: {'form.note': row['shown']});
        final expected = row['expect'] as String?;
        if (expected == null) {
          expect(find.textContaining(' / '), findsNothing);
        } else {
          expect(find.text(expected), findsOneWidget);
        }
      });
    }

    testWidgets('typing changes the counter at once, and it is not announced', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDocument(tester, docWith([_field({'counter': true, 'maxLength': 10})]));
      expect(find.text('0 / 10'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'héllo');
      await tester.pump();
      expect(find.text('5 / 10'), findsOneWidget);
      final data = tester.getSemantics(find.bySemanticsLabel('Amount')).getSemanticsData();
      expect(data.hint, contains('5 / 10'), reason: 'part of the description of the field');
      final counterNode = tester.getSemantics(find.text('5 / 10'));
      expect(counterNode.flagsCollection.isLiveRegion, isFalse, reason: 'not a live region');
      semantics.dispose();
    });
  });

  group('noteRowCases: the row under the box', () {
    for (final row in _rows('noteRowCases')) {
      test('${row['name']} (the rule)', () {
        final laid = noteRowOf(
          rowInline: _n(row['rowInline']),
          gap: _n(row['gap']),
          counter: row['counter'] == null ? null : _n(row['counter']),
        );
        final want = asJson(row['expect']);
        expect(laid.noteInline, _n(want['noteInline']));
        expect(laid.counterStart, (want['counterStart'] as num?)?.toDouble());
        final rtl = row['rtl'];
        if (rtl != null) expect(_n(row['rowInline']) - laid.counterStart! - _n(row['counter']), _n(asJson(rtl)['counterX']));
      });
    }

    for (final (width, locale) in [(320.0, 'en'), (320.0, 'ar'), (393.0, 'en'), (393.0, 'ar')]) {
      testWidgets('a real note and counter at $width, $locale', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpDocument(
          tester,
          docWith([
            _field({'counter': true, 'maxLength': 280, 'helper': {'kind': 'literal', 'value': 'Shown on your card'}}),
          ]),
          locale: locale == 'ar' ? 'ar' : null,
        );
        final rtl = locale == 'ar';
        final box = tester.getRect(_box);
        final counter = tester.getRect(find.text('0 / 280'));
        final note = tester.getRect(find.text('Shown on your card'));
        final laid = noteRowOf(rowInline: box.width, gap: _theme.space(SpacingToken.sm), counter: counter.width);
        double fromStart(Rect rect) => rtl ? box.right - rect.right : rect.left - box.left;
        expect(fromStart(counter), closeTo(laid.counterStart!, 1e-6), reason: 'the counter is at the logical end');
        expect(fromStart(note), closeTo(0, 1e-6), reason: 'the note is from the start');
        expect(note.width, lessThanOrEqualTo(laid.noteInline + 1e-6), reason: 'the note takes at most the rest');
      });
    }

    testWidgets('a counter without a note holds the row alone, at the end', (tester) async {
      await pumpDocument(tester, docWith([_field({'counter': true, 'maxLength': 5})]));
      final box = tester.getRect(_box);
      final counter = tester.getRect(find.text('0 / 5'));
      expect(counter.right, closeTo(box.right, 1e-6));
    });
  });

  group('partsDocumentCases: every row of props is read and drawn without a crash', () {
    for (final row in _rows('partsDocumentCases')) {
      testWidgets(row['name']! as String, (tester) async {
        await pumpDocument(tester, docWith([_field(asJson(row['props']))]), data: const {'user.firstName': 'Alex'});
        expect(tester.takeException(), isNull);
        expect(find.byType(InputTextField), findsOneWidget);
      });
    }

    testWidgets('a mark of nine characters is drawn with the first eight (code points, no split pair)', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _field({
            'prefix': {'kind': 'text', 'text': {'kind': 'literal', 'value': '12345678\u{1F600}'}},
            'suffix': {'kind': 'text', 'text': {'kind': 'literal', 'value': 'abcdefg\u{1F600}x'}},
          }),
        ]),
      );
      expect(find.text('12345678'), findsOneWidget);
      expect(find.text('abcdefg\u{1F600}'), findsOneWidget, reason: 'eight code points, the pair is whole');
    });

    testWidgets('a bound mark: data, the fallback, the translation key of the field', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _field({
            'suffix': {'kind': 'text', 'text': {'kind': 'binding', 'path': 'account.currency', 'fallback': '₴'}},
          }),
        ]),
      );
      expect(find.text('₴'), findsOneWidget);
      await pumpDocument(
        tester,
        docWith([
          _field({
            'suffix': {'kind': 'text', 'text': {'kind': 'binding', 'path': 'account.currency', 'fallback': '₴'}},
          }),
        ]),
        data: const {'account.currency': 'USD'},
      );
      expect(find.text('USD'), findsOneWidget);
    });

    testWidgets('an empty mark is no mark and no gap; the icon of an unknown name is an empty box with the gap', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _field({
            'prefix': {'kind': 'text', 'text': {'kind': 'literal', 'value': ''}},
            'suffix': {'kind': 'icon', 'icon': 'no-such-icon'},
          }),
        ]),
      );
      final box = tester.getRect(_box);
      final text = tester.getRect(find.byType(TextField));
      final mark = tester.getRect(find.byType(IconBox));
      expect(text.left - box.left, closeTo(1 + _theme.space(SpacingToken.md), 1e-6), reason: 'no start mark, no gap');
      expect(mark.width, greaterThan(0), reason: 'the empty box has its size');
      expect(text.right + _theme.space(kFieldAffixGap), closeTo(mark.left, 1e-6), reason: 'the gap stays');
    });

    testWidgets('a mark is not part of the value: it is never written, and a press on it focuses the field', (tester) async {
      final writes = <String>[];
      await pumpDocument(
        tester,
        docWith([
          _field({'suffix': {'kind': 'text', 'text': {'kind': 'literal', 'value': '₴'}}}),
        ]),
        onWrite: (path, value) => writes.add('$path=$value'),
      );
      await tester.tap(find.text('₴'));
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      expect(writes, ['form.note=12'], reason: 'the mark is not in the value');
    });

    testWidgets('the text of a mark is read with the field; an icon is not', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDocument(
        tester,
        docWith([
          _field({
            'prefix': {'kind': 'icon', 'icon': 'mail'},
            'suffix': {'kind': 'text', 'text': {'kind': 'literal', 'value': '₴'}},
            'helper': {'kind': 'literal', 'value': 'Per month'},
          }),
        ]),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Amount')).getSemanticsData();
      expect(node.hint, contains('₴'));
      expect(node.hint, contains('Per month'));
      expect(node.label, contains('Amount'), reason: 'the accessible name stays the label');
      semantics.dispose();
    });

    testWidgets('the sides of a mark are logical by the screen; the content of a number field stays left to right', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _field({'suffix': {'kind': 'text', 'text': {'kind': 'literal', 'value': '₴'}}, 'valueType': 'number'}),
        ]),
        locale: 'ar',
      );
      final box = tester.getRect(_box);
      expect(tester.getRect(find.text('₴')).left, lessThan(box.center.dx), reason: 'the suffix is on the left in a right-to-left screen');
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.textDirection, TextDirection.ltr, reason: 'a number is read left to right');
    });

    testWidgets('the look of the box: radius, background, border colour and width; focus and error replace the colour only', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _field({
            'fieldRadius': 16,
            'fieldBackground': {'token': 'primary', 'opacity': 0.1},
            'fieldBorderColor': 'success',
            'fieldBorderWidth': 3,
          }),
        ]),
      );
      BoxDecoration decoration() => tester.widget<Container>(_box).decoration! as BoxDecoration;
      var border = decoration().border! as Border;
      expect(decoration().borderRadius, BorderRadius.circular(16));
      expect(decoration().color, _theme.resolveColor(ColorRef.tryParse({'token': 'primary', 'opacity': 0.1})!));
      expect(border.top.color, _theme.color(ColorToken.success));
      expect(border.top.width, 3);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      border = decoration().border! as Border;
      expect(border.top.color, _theme.color(ColorToken.primary), reason: 'focus replaces the colour');
      expect(border.top.width, 3, reason: 'the width is the same in every state');
    });

    testWidgets('a token the theme does not know is the built-in value; out-of-range numbers are the built-in ones', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _field({'fieldRadius': 'roundNope', 'fieldBackground': 'paperNope', 'fieldBorderColor': 'inkNope', 'fieldBorderWidth': 9}),
        ]),
      );
      final decoration = tester.widget<Container>(_box).decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(decoration.borderRadius, BorderRadius.circular(_theme.radius(RadiusToken.sm)));
      expect(decoration.color, _theme.color(ColorToken.surface));
      expect(border.top.color, _theme.color(ColorToken.border));
      expect(border.top.width, 1);
    });

    testWidgets('style of the node is still the box of the whole widget, not of the field', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            ..._field({}),
            'style': {'background': {'kind': 'color', 'color': 'primary'}, 'padding': 'md'},
          },
        ]),
      );
      final decoration = tester.widget<Container>(_box).decoration! as BoxDecoration;
      expect(decoration.color, _theme.color(ColorToken.surface), reason: 'the field keeps its own background');
    });
  });

  test('x-style.layout.inputParts: the blocks of the artifact', () {
    final parts = asJson(asJson(asJson(_schema['x-style'])['layout'])['inputParts']);
    final field = asJson(parts['field']);
    expect(asJson(field['borderWidth'])['min'], kFieldBorderWidthMin);
    expect(asJson(field['borderWidth'])['max'], kFieldBorderWidthMax);
    expect(asJson(field['height'])['min'], kFieldHeightMin);
    expect(asJson(field['height'])['max'], kFieldHeightMax);
    expect(asJson(field['radius'])['default'], kFieldRadiusToken.wire);
    expect(asJson(field['background'])['default'], kFieldBackgroundToken.wire);
    expect(asJson(field['borderColor'])['default'], kFieldBorderToken.wire);
    final affix = asJson(parts['affix']);
    expect(asJson(affix['text'])['maxLength'], kFieldAffixTextMax);
    expect(affix['gap'], kFieldAffixGap.wire);
    expect(asJson(parts['counter'])['separator'], kFieldCounterSeparator);
  });
}
