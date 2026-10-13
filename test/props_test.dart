import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/bindable.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

Map<String, Object?> _spacer(String orientation) => {
  'id': 'sp',
  'type': 'Spacer',
  'props': {'size': 'xl', 'orientation': orientation},
};

Map<String, Object?> _divider(String orientation, {String color = 'border'}) => {
  'id': 'dv',
  'type': 'Divider',
  'props': {'color': color, 'spacing': 'sm', 'orientation': orientation},
};

/// A card with an explicit direction (8.1.0). Before it, the parent axis was determined by the
/// node type; now the document names it, which is why the mirrored axis tests below
/// go over ALL parent forms, not just `Row`.
Map<String, Object?> _container({
  required String direction,
  required List<Map<String, Object?>> children,
}) => {
  'id': 'card-$direction',
  'type': 'Container',
  'props': {
    'direction': direction,
    'gap': 'none',
  },
  'style': {
    'radius': 'md',
    'background': {'kind': 'color', 'color': 'surface'},
  },
  'children': children,
};

Map<String, Object?> _row({required bool wrap, required List<Map<String, Object?>> children}) => {
  'id': 'row',
  'type': 'Row',
  'props': {
    'gap': 'sm',
    'align': 'center',
    'justify': 'start',
    'wrap': wrap,
  },
  'children': children,
};

Map<String, Object?> _progress({
  Object? value = const {'kind': 'literal', 'value': 75},
  Object? max = const {'kind': 'literal', 'value': 100},
  String labelFormat = 'valueOfMax',
}) => {
  'id': 'pb',
  'type': 'ProgressBar',
  'props': {'value': value, 'max': max, 'color': 'primary', 'labelFormat': labelFormat},
};

/// All `SizedBox`es in the tree — easier than catching a specific node through
/// the renderer wrappers.
Iterable<SizedBox> _boxes(WidgetTester tester) =>
    tester.widgetList<SizedBox>(find.byType(SizedBox));

void main() {
  group('orientation (the axis is now in the document)', () {
    testWidgets('Spacer: horizontal gives height, vertical — width', (tester) async {
      await pumpDocument(tester, docWith([_spacer('horizontal')]));
      expect(_boxes(tester).any((b) => b.height == 24 && b.width == null), isTrue);

      await pumpDocument(tester, docWith([_spacer('vertical')]));
      expect(_boxes(tester).any((b) => b.width == 24 && b.height == null), isTrue);
    });

    testWidgets('Divider: horizontal — full-width strip, vertical — line', (tester) async {
      await pumpDocument(tester, docWith([_divider('horizontal')]));
      expect(
        _boxes(tester).any((b) => b.height == 1 && b.width == double.infinity),
        isTrue,
      );

      await pumpDocument(tester, docWith([_divider('vertical')]));
      expect(_boxes(tester).any((b) => b.width == 1 && b.height == 20), isTrue);
    });

    testWidgets('Divider: the `border` colour (7.3.0) reaches the pixels as is', (tester) async {
      // The token was added precisely for dividers, and it must be checked on the
      // painted result: before 7.3.0 the renderer dimmed the line to 40% alpha, i.e.
      // painted a colour the theme does not have. Now no arithmetic — exactly the
      // theme value.
      final theme = RenderTheme.fallback();
      await pumpDocument(tester, docWith([_divider('horizontal')]), theme: theme);

      final line = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((box) => box.color)
          .toList();

      expect(line, contains(theme.color(ColorToken.border)));
      // The main point for display: `border` is lighter than `muted`, which is why
      // dividers on the phone looked darker than in the builder.
      expect(theme.color(ColorToken.border), isNot(theme.color(ColorToken.muted)));

      // The same node with the old token is painted with the old colour: the renderer
      // does not "improve" a document that asks for `muted`.
      await pumpDocument(
        tester,
        docWith([_divider('horizontal', color: 'muted')]),
        theme: theme,
      );
      expect(
        tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((box) => box.color),
        contains(theme.color(ColorToken.muted)),
      );
    });

    test('the axis does not depend on the parent — in any of its forms', () {
      // Since 8.1.0 the "parent axis" no longer follows from the node TYPE: `Container`
      // itself says how it lays out content, so there are now two horizontal parents.
      // The builder validator computes `axis_mismatch` by direction —
      // while the renderer parse does not compute it at all, and this is checked on all
      // parent forms at once so a new form is not forgotten.
      final parents = <String, Map<String, Object?>>{
        'Row': _row(wrap: false, children: [_divider('horizontal')]),
        'Container{row}': _container(
          direction: 'row',
          children: [_divider('horizontal')],
        ),
        'Container{column}': _container(
          direction: 'column',
          children: [_divider('horizontal')],
        ),
      };

      for (final entry in parents.entries) {
        final divider = flatten(rootOf(docWith([entry.value])))
            .whereType<DividerNode>()
            .single;
        expect(divider.orientation, OrientationToken.horizontal, reason: entry.key);
      }
    });

    testWidgets('the renderer does NOT fix an axis mismatch with the parent', (tester) async {
      // `Spacer{horizontal}` inside a horizontal parent is zero pixels along
      // that parent's axis. The builder validator catches it; the renderer
      // stays literal, because a "fix" would mean the screen differs from
      // the document (rule 2).
      //
      // Both horizontal parents are checked together: since 8.1.0 there are two, and
      // if the renderer ever started "helping", it would do so in one of
      // them — so not only platforms but two places in one would diverge.
      final parents = <String, Map<String, Object?>>{
        'Row': _row(wrap: false, children: [_spacer('horizontal')]),
        'Container{row}': _container(
          direction: 'row',
          children: [_spacer('horizontal')],
        ),
      };

      for (final entry in parents.entries) {
        await pumpDocument(tester, docWith([entry.value]));

        expect(
          _boxes(tester).any((b) => b.height == 24 && b.width == null),
          isTrue,
          reason: entry.key,
        );
        expect(_boxes(tester).any((b) => b.width == 24), isFalse, reason: entry.key);
      }
    });
  });

  group('Row.wrap', () {
    testWidgets('wrap: true → Wrap instead of Row', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _row(
            wrap: true,
            children: [textNode('раз', id: 't1'), textNode('два', id: 't2')],
          ),
        ]),
      );

      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.spacing, 8);
      expect(wrap.runSpacing, 8);
      expect(wrap.alignment, WrapAlignment.start);
      expect(wrap.crossAxisAlignment, WrapCrossAlignment.center);
      expect(find.bySubtype<Row>(), findsNothing);
      expect(find.byType(RowLayout), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // This used to count `Flexible`: a child without weight sat in `Flexible(loose)`,
    // and two children got at most half a row each. Now the document row is
    // `RowLayout`, where a child without weight takes its natural width; the arithmetic
    // itself is guarded by `row_natural_width_test`.
    testWidgets('wrap: false → document row, both children in it', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _row(
            wrap: false,
            children: [textNode('раз', id: 't1'), textNode('два', id: 't2')],
          ),
        ]),
      );

      expect(find.byType(Wrap), findsNothing);
      expect(find.byType(RowLayout), findsOneWidget);
      expect(find.byType(RowSlot), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long text in a wrap row does not overflow', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _row(
            wrap: true,
            children: [
              textNode('Дуже довгий заголовок задачі, який точно не влізе', id: 't1'),
              textNode('і сусід поруч', id: 't2'),
            ],
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Container.gap', () {
    testWidgets('a gap appears between children', (tester) async {
      Map<String, Object?> card(String gap) => {
        'id': 'card',
        'type': 'Container',
        'props': {'gap': gap},
        'style': {
          'padding': 'md',
          'radius': 'md',
          'background': {'kind': 'color', 'color': 'surface'},
        },
        'children': [textNode('перший', id: 'a'), textNode('другий', id: 'b')],
      };

      await pumpDocument(tester, docWith([card('none')]));
      expect(_boxes(tester).any((b) => b.height == 24), isFalse);

      await pumpDocument(tester, docWith([card('xl')]));
      expect(_boxes(tester).any((b) => b.height == 24 && b.width == null), isTrue);
    });

    test('gap defaults to none, as in the schema', () {
      final doc = docWith([
        {
          'id': 'card',
          'type': 'Container',
          'props': <String, Object?>{},
          'children': [textNode('один')],
        },
      ]);
      // Since 9.0.0 the gap is a reference ("token or number") together with the default of
      // its field; without the field in the document both say `none`.
      final gap = flatten(rootOf(doc)).whereType<ContainerNode>().single.gap;
      expect(gap.fieldDefault, SpacingToken.none);
      expect(gap.ref, const ScaleRef.token('none'));
    });
  });

  group('Text.maxLines / overflow', () {
    testWidgets('both props reach Flutter directly', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          textNode('Довгий текст', extra: const {'maxLines': 2, 'overflow': 'clip'}),
        ]),
      );

      final text = tester.widget<Text>(find.text('Довгий текст'));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.clip);
    });

    testWidgets('without maxLines lines are unbounded — and `overflow` has no effect', (tester) async {
      // In Flutter `ellipsis` without `maxLines` collapses the paragraph to one line, on the web
      // the same combination does nothing. The contract describes the props as
      // independent, so the contract wins: no line limit — no overflow.
      await pumpDocument(tester, docWith([textNode('Текст')]));

      final text = tester.widget<Text>(find.text('Текст'));
      expect(text.maxLines, isNull);
      expect(text.overflow, TextOverflow.clip);
    });

    testWidgets('long text without maxLines wraps instead of being cut off', (tester) async {
      // Regression from a real screen: a promo description in the document has `overflow:
      // ellipsis` and no `maxLines`, and in the app only one line of it remained —
      // half of the condition disappeared.
      const long = 'Оплатите покупки на 200 000 тенге картой Visa через Apple / '
          'Google / Samsung / Garmin Pay до 25 числа';
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await pumpDocument(
        tester,
        docWith([textNode('Коротко', id: 'short'), textNode(long, id: 'long')]),
      );
      final oneLine = tester.getSize(find.text('Коротко'));

      expect(
        tester.getSize(find.textContaining('Оплатите покупки')).height,
        greaterThan(oneLine.height * 2),
        reason: 'the text must take several lines',
      );
    });

    test('maxLines outside the schema range is clamped, a non-number — the lower bound', () {
      // Flipped: previously an out-of-range field was ignored
      // (`maxLines == null`, i.e. "unbounded"). The contract says otherwise:
      // a number out of range is clamped (`literalOutOfRange`), a NON-number is the lower bound
      // (`nonNumericLiteral`), and the schema gives 1…20.
      final doc = docWith([
        textNode('Текст', extra: const {'maxLines': 0}),
        textNode('Інший', id: 'txt2', extra: const {'maxLines': 'багато'}),
        textNode('Третій', id: 'txt3', extra: const {'maxLines': 999}),
        textNode('Без', id: 'txt4'),
      ]);
      final lines = flatten(rootOf(doc)).whereType<TextNode>().map((n) => n.maxLines).toList();
      expect(lines, [1, 1, 20, null]);
    });
  });

  group('8.0.0: long text is a valid document, not an error', () {
    // Major 8.0.0 removed `maxLength` from text that a human reads. The assertions here
    // are FLIPPED, not added: before 8.0.0 the builder simply would not let one build a
    // 300-character button title, so the renderer never saw such a document.
    // Now it will, and the policy `overlongText: 'render-as-is'`
    // says what to do: nothing. Do not cut by your own number, do not add an
    // ellipsis — show exactly what arrived.

    testWidgets('a button title of several hundred characters reaches Flutter whole', (
      tester,
    ) async {
      // No trailing space: shown text has no edges (`shown_text.dart`).
      final long = ('Оформити картку та отримати додаткові бали за кожну покупку ' * 6).trim();
      expect(long.length, greaterThan(300));

      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await pumpDocument(
        tester,
        docWith([
          buttonNode(long, action: const {'type': 'navigate.back'}),
        ]),
      );

      final label = tester.widget<Text>(find.text(long));
      expect(
        label.data!.length,
        long.length,
        reason: 'the renderer must not shorten what the document did not ask to shorten',
      );
      expect(label.data, isNot(contains('…')), reason: 'an ellipsis is the document\'s decision, not the reader\'s');
      expect(label.maxLines, isNull);
      expect(tester.takeException(), isNull);
    });

    test('long text does not make the document unreadable', () {
      // The main consequence of the major: a document with such a string is VALID. A 7.x
      // reader would reject it entirely — which is why this is a major, not a minor.
      final long = 'а' * 5000;
      final doc = docWith([
        textNode(long, id: 'long'),
        {
          'id': 'img',
          'type': 'Image',
          'props': {
            'source': {'kind': 'asset', 'asset': 'banner'},
            'aspectRatio': '16:9',
            // `alt` lost its limit in 8.0.0 too — and it is the one most often long,
            // because it describes the image with a sentence.
            'alt': long,
          },
        },
      ]);

      expect(doc.isSupportedVersion, isTrue);
      final text = flatten(rootOf(doc)).whereType<TextNode>().single;
      expect(text.content.resolve(const ScreenData({})), long);
      expect(flatten(rootOf(doc)).whereType<ImageNode>().single.alt!.resolve(const ScreenData({})), long);
    });

    testWidgets('no widget with text breaks the layout with a long string', (tester) async {
      // The costliest risk of 8.0.0 for the renderer, and it is not about validity but
      // about LAYOUT. Before, the schema itself guarded against label overflow:
      // `Button.label` physically could not exceed 24 characters. Now it can be
      // any length, while `maxLines`/`overflow` exist ONLY in `Text` — i.e. exactly
      // where the `render-as-is` policy hands the decision to the document, the document
      // has none (a gap found while mirroring the contract). So we must check what used to
      // be impossible: that being unable to say "cut" does not cost an exception.
      const long = 'Умови акції та порядок нарахування балів учаснику програми ';
      final text = long * 5;

      Future<void> probe(String what, Map<String, Object?> node) async {
        await pumpDocument(tester, docWith([node]));
        expect(tester.takeException(), isNull, reason: '$what broke on long text');
      }

      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await probe('AppBar', appBarNode(text, subtitle: text));
      await probe('Badge', badgeNode(text));
      await probe(
        'ListTile',
        listTileNode(text, subtitle: text, trailing: const {'kind': 'chevron'}),
      );
      await probe('Button', buttonNode(text, action: const {'type': 'navigate.back'}));
      await probe('Accordion', {
        'id': 'acc',
        'type': 'Accordion',
        'props': {
          'title': {'kind': 'literal', 'value': text},
          'initiallyExpanded': true,
        },
        'children': [textNode('вміст')],
      });
      // Worst case: a line without wraps, i.e. an axis along which space
      // will not appear from nowhere.
      await probe('Row', {
        'id': 'row',
        'type': 'Row',
        'props': {
          'gap': 'sm',
          'align': 'center',
          'justify': 'start',
          'wrap': false,
        },
        'children': [badgeNode(text), textNode('поруч', id: 'near')],
      });
    });

    testWidgets('the document still controls overflow itself: maxLines + ellipsis work', (
      tester,
    ) async {
      // The second half of `render-as-is`: "do not cut on your own" does not mean "never
      // cut". When the document ASKED for a line limit, it applies as before.
      final long = ('Дуже довгий опис умови акції, ' * 20).trim();
      await pumpDocument(
        tester,
        docWith([
          textNode(long, id: 'clipped', extra: const {'maxLines': 2, 'overflow': 'ellipsis'}),
        ]),
      );

      final text = tester.widget<Text>(find.text(long));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.data, long, reason: 'it truncates the display, not the data');
    });
  });

  group('alt → semantics', () {
    testWidgets('Image and Icon pass alt into the accessibility tree', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'img',
            'type': 'Image',
            'props': {
              'source': {'kind': 'asset', 'asset': 'banner'},
              'aspectRatio': '16:9',
              'alt': 'Банер кампанії',
            },
          },
          {
            'id': 'ic',
            'type': 'Icon',
            'props': {'name': 'trophy', 'size': 'md', 'alt': 'Кубок'},
            'style': {'color': 'primary'},
          },
        ]),
      );

      expect(find.bySemanticsLabel('Банер кампанії'), findsOneWidget);
      expect(find.bySemanticsLabel('Кубок'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('without alt the node stays decorative', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'ic',
            'type': 'Icon',
            'props': {'name': 'trophy', 'size': 'md'},
          },
        ]),
      );

      expect(find.bySemanticsLabel('Кубок'), findsNothing);
      handle.dispose();
    });
  });

  group('ProgressBar max and data', () {
    testWidgets('max is a binding: the target comes from data', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _progress(
            value: const {'kind': 'binding', 'path': 'task.progress', 'fallback': 0},
            max: const {'kind': 'binding', 'path': 'task.target', 'fallback': 100},
          ),
        ]),
        data: const {'task.progress': 150000, 'task.target': 200000},
      );

      final bar = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
      expect(bar.ratio, closeTo(0.75, 1e-9));
      expect(find.text('150000 / 200000'), findsOneWidget);
    });

    testWidgets('without data for max the document fallback is used', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _progress(
            value: const {'kind': 'literal', 'value': 5},
            max: const {'kind': 'binding', 'path': 'task.target', 'fallback': 10},
          ),
        ]),
      );

      final bar = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
      expect(bar.ratio, closeTo(0.5, 1e-9));
    });

    test('max defaults to the literal 100', () {
      final doc = docWith([
        {
          'id': 'pb',
          'type': 'ProgressBar',
          'props': {
            'value': {'kind': 'literal', 'value': 1},
          },
        },
      ]);
      final node = flatten(rootOf(doc)).whereType<ProgressBarNode>().single;
      expect(node.max, isA<LiteralNumber>());
      expect((node.max as LiteralNumber).value, 100);
    });

    testWidgets('labelFormat: valueOfMax / percent / none', (tester) async {
      await pumpDocument(tester, docWith([_progress()]));
      expect(find.text('75 / 100'), findsOneWidget);

      await pumpDocument(tester, docWith([_progress(labelFormat: 'percent')]));
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('75 / 100'), findsNothing);

      await pumpDocument(tester, docWith([_progress(labelFormat: 'none')]));
      expect(find.text('75 / 100'), findsNothing);
      expect(find.text('75%'), findsNothing);
      expect(find.byType(ProgressTrack), findsOneWidget);
    });

    testWidgets('max <= 0 from data does not divide by zero', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          _progress(
            value: const {'kind': 'literal', 'value': 5},
            max: const {'kind': 'binding', 'path': 'task.target', 'fallback': 0},
          ),
        ]),
        data: const {'task.target': 0},
      );

      expect(tester.takeException(), isNull);
      final bar = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
      // A bound that is not a positive number is NOT a scale (9.7.0, `nonPositiveMax`):
      // before 9.7.0 this was 1.0, because `max` was silently replaced with 1, and a bar with
      // target 0 came out full.
      expect(bar.ratio, 0.0);
    });
  });

  group('Button.action as a structure', () {
    test('type is a free string, params parse into Map<String, String>', () {
      final action = ButtonAction.parse({
        'type': 'navigate',
        'params': {'screenId': 'task-42', 'source': 'banner'},
      });

      expect(action.type, 'navigate');
      expect(action.params, {'screenId': 'task-42', 'source': 'banner'});
      // `navigate.next`/`navigate.details` disappeared in 5.0.0: the transition target is now
      // in a parameter, and the renderer reads it from there.
      expect(action.navigationTarget, 'task-42');
    });

    test('an unknown type degrades gently — it is simply passed on', () {
      final action = ButtonAction.parse({'type': 'openArSelfieBooth'});
      expect(action.type, 'openArSelfieBooth');
      expect(action.params, isEmpty);
    });

    test('the transition target is read only in the `navigate` action', () {
      expect(ButtonAction.parse({'type': 'navigate'}).navigationTarget, isNull);
      expect(
        ButtonAction.parse({'type': 'navigate', 'params': {'screenId': ''}}).navigationTarget,
        isNull,
      );
      expect(
        ButtonAction.parse({
          'type': 'navigate.back',
          'params': {'screenId': 'task-42'},
        }).navigationTarget,
        isNull,
      );
    });

    test('a corrupted action yields the default `none`', () {
      expect(ButtonAction.parse(null).type, 'none');
      expect(ButtonAction.parse('submit').type, 'none');
      expect(ButtonAction.parse({'type': 42}).type, 'none');
      expect(ButtonAction.parse({'type': 'x', 'params': 'ні'}).params, isEmpty);
    });

    testWidgets('the button passes the structure with params to the callback', (tester) async {
      ButtonAction? fired;
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'cta',
            'type': 'Button',
            'props': {
              'label': {'kind': 'literal', 'value': 'Деталі'},
              'variant': 'primary',
              'action': {
                'type': 'share',
                'params': {'target': 'telegram'},
              },
              'fullWidth': true,
            },
          },
        ]),
        onAction: (action, _) => fired = action,
      );

      await tester.tap(find.text('Деталі'));
      // An action the renderer does not understand it does not interpret — it hands it to the host as is.
      expect(fired?.type, 'share');
      expect(fired?.params['target'], 'telegram');
      expect(fired?.navigationTarget, isNull);
    });
  });

  group('tree structure', () {
    test('Screen inside Screen is no longer a screen node', () {
      final doc = docWith([
        {
          'id': 'nested',
          'type': 'Screen',
          'props': <String, Object?>{},
          'style': {
            'background': {'kind': 'color', 'color': 'surface'},
            'padding': 'md',
          },
          'children': [textNode('усередині вкладеного')],
        },
      ]);

      expect(flatten(rootOf(doc)).whereType<ScreenNode>(), hasLength(1));
      final unknown = flatten(rootOf(doc)).whereType<UnknownNode>().single;
      expect(unknown.type, 'Screen');
    });

    testWidgets('a child of a leaf node is ignored, not rendered', (tester) async {
      final doc = docWith([
        {
          'id': 'txt',
          'type': 'Text',
          'props': {
            'content': {'kind': 'literal', 'value': 'Листок'},
            'align': 'start',
            'overflow': 'ellipsis',
          },
          'children': [textNode('дитина листка', id: 'inner')],
        },
      ]);

      final text = flatten(rootOf(doc)).whereType<TextNode>().single;
      expect(text.children, isEmpty);

      await pumpDocument(tester, doc);
      expect(find.text('Листок'), findsOneWidget);
      expect(find.text('дитина листка'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
