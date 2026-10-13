import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';

/// Compatibility-policy rows of contract 9 that readers
/// used to answer differently. The row values are checked against the artifact by
/// `schema_version_test.dart`; here is the BEHAVIOR of each, rendered.
void main() {
  final theme = RenderTheme.fallback();
  const surface = {'kind': 'color', 'color': 'surface'};

  Future<void> pump(WidgetTester tester, List<Map<String, Object?>> children, {String? locale}) =>
      pumpDocument(tester, UiDocumentBuilder.bare(children), theme: theme, locale: locale);

  Rect boxRect(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first,
  );

  Map<String, Object?> button({Map<String, Object?>? style, bool fullWidth = false}) => {
    'id': 'btn',
    'type': 'Button',
    'props': {
      'label': {'kind': 'literal', 'value': 'Довгий підпис кнопки'},
      'variant': 'primary',
      'action': {'type': 'noop'},
      'fullWidth': fullWidth,
    },
    'style': ?style,
  };

  group('literalOutOfRange: clamp (AE)', () {
    testWidgets('negative padding is zero, oversized is the schema limit, opacity 1.5 is one', (
      tester,
    ) async {
      await pump(tester, [
        textNode('А', id: 'a', style: {'padding': -8, 'background': surface}),
        textNode('Б', id: 'b', style: {'padding': 9999, 'background': surface}),
        textNode('В', id: 'c', style: {'opacity': 1.5}),
      ]);

      expect(tester.takeException(), isNull);
      // Zero: no padding around the label.
      expect(tester.getTopLeft(find.text('А')), Offset.zero);
      // 128 is the `SpacingRef` limit; an oversized value is clamped, not rejected.
      expect(tester.getTopLeft(find.text('Б')).dx, 128);
      // 1.5 is clamped to 1, and opacity 1 wraps nothing.
      expect(find.byType(Opacity), findsNothing);
    });
  });

  group('unknownBoxToken: omit-field versus unknownSideToken: side-is-zero', () {
    Future<double> buttonWidth(WidgetTester tester, Map<String, Object?>? style) async {
      await pump(tester, [
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'none', 'align': 'center', 'justify': 'start', 'wrap': false, 'scrollable': false},
          'children': [button(style: style)],
        },
      ]);
      return tester.getSize(find.byWidgetPredicate((widget) => widget is ButtonStyleButton)).width;
    }

    testWidgets('one value with an unknown token: the button padding stays built-in', (
      tester,
    ) async {
      final builtIn = await buttonWidth(tester, null);
      final unknownSingle = await buttonWidth(tester, {'padding': 'tokenFromFuture'});
      expect(unknownSingle, builtIn);
    });

    testWidgets('the per-side form is ALWAYS applied: all unknown means zeros, a narrower button', (
      tester,
    ) async {
      final builtIn = await buttonWidth(tester, null);
      final allUnknown = await buttonWidth(tester, {
        'padding': {'top': 'tokenFromFuture', 'start': 'tokenFromFuture'},
      });
      expect(allUnknown, lessThan(builtIn), reason: 'zero REMOVES the built-in padding');
    });
  });

  group('screenBoxFields: ignore (AG)', () {
    testWidgets('margin and the six size fields on the screen root have no effect', (tester) async {
      await pumpDocument(
        tester,
        UiDocumentBuilder.bare(
          [textNode('Вміст')],
          style: {
            'margin': 'xl',
            'width': 100,
            'height': 100,
            'minWidth': 50,
            'maxWidth': 60,
            'minHeight': 10,
            'maxHeight': 20,
            'background': surface,
          },
        ),
        theme: theme,
      );

      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Вміст')), Offset.zero);
      expect(tester.getSize(find.byType(DecoratedBox).last), const Size(800, 600));
    });
  });

  group('allLayersFilled: ignore-fill (AI)', () {
    testWidgets('a stack without unstretched layers paints layers at their own size', (tester) async {
      await pump(tester, [
        {
          'id': 'stack',
          'type': 'Stack',
          'props': {'alignHorizontal': 'start', 'alignVertical': 'start'},
          'children': [
            {
              ...textNode('Перший', id: 'a', style: {'width': 50, 'height': 30, 'background': surface}),
              'fill': true,
            },
            {
              ...textNode('Другий', id: 'b', style: {'width': 20, 'height': 10, 'background': surface}),
              'fill': true,
            },
          ],
        },
      ]);

      expect(tester.takeException(), isNull);
      expect(boxRect(tester, 'Перший').size, const Size(50, 30));
      expect(boxRect(tester, 'Другий').size, const Size(20, 10));
    });
  });

  group('scrollableRowChildWidth: row-viewport (AJ)', () {
    Map<String, Object?> scrollRow(List<Map<String, Object?>> children) => {
      'id': 'row',
      'type': 'Row',
      'props': {'gap': 'none', 'align': 'center', 'justify': 'start', 'wrap': false, 'scrollable': true},
      'children': children,
    };

    testWidgets('a fullWidth button in a scrollable row takes the row width, no exception', (tester) async {
      await pump(tester, [
        scrollRow([button(fullWidth: true, style: {'background': surface})]),
      ]);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byWidgetPredicate((widget) => widget is ButtonStyleButton)).width, 800);
    });

    testWidgets('a child that names its own width may be wider than the row', (tester) async {
      await pump(tester, [
        scrollRow([
          textNode('Широка', id: 'wide', style: {'width': 1000, 'background': surface}),
        ]),
      ]);

      expect(tester.takeException(), isNull);
      expect(boxRect(tester, 'Широка').width, 1000);
    });
  });

  group('sizedChildInTightSlot: start-top (AL)', () {
    testWidgets('a node with width in a grid cell sits at the start and top, at the right in RTL', (tester) async {
      final grid = {
        'id': 'grid',
        'type': 'Grid',
        'props': {'columns': 2, 'gap': 'none'},
        'children': [
          textNode('Вузька', id: 'a', style: {'width': 100, 'height': 20, 'background': surface}),
          textNode('Висока', id: 'b', style: {'height': 90, 'background': surface}),
        ],
      };

      await pump(tester, [grid]);
      expect(boxRect(tester, 'Вузька').topLeft, Offset.zero);

      await pump(tester, [grid], locale: 'ar');
      final rect = boxRect(tester, 'Вузька');
      expect(rect.top, 0);
      expect(rect.right, 800);
    });
  });

  group('state (`styleWhen`) on Tab', () {
    Map<String, Object?> tab(String id, String title, {Object? styleWhen, Map<String, Object?>? style}) => {
      'id': id,
      'type': 'Tab',
      'props': {
        'title': {'kind': 'literal', 'value': title},
      },
      'style': ?style,
      'styleWhen': ?styleWhen,
      'children': [textNode('Панель $title', id: '$id-body')],
    };

    Map<String, Object?> when(String op, Map<String, Object?> style) => {
      'when': {'path': 'user.vip', 'op': op},
      'style': style,
    };

    Map<String, Object?> tabs(List<Map<String, Object?>> children) => {
      'id': 'tabs',
      'type': 'Tabs',
      'props': {'initialTab': 0},
      'children': children,
    };

    // Panel padding is the distance from the box edge to the label. The panel
    // sits inside an `AnimatedSwitcher`, so an absolute coordinate says nothing.
    double panelInset(WidgetTester tester) =>
        tester.getTopLeft(find.text('Панель Перша')).dx -
        tester
            .getRect(find.ancestor(of: find.text('Панель Перша'), matching: find.byType(Padding)).first)
            .left;

    TextStyle titleStyle(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!;

    testWidgets('state changes the title color (open and closed) and the panel box', (
      tester,
    ) async {
      final document = UiDocumentBuilder.bare([
        tabs([
          tab(
            'a',
            'Перша',
            style: {'padding': 'sm'},
            styleWhen: [
              when('isTrue', {
                'color': 'danger',
                'padding': 'xl',
                'background': {'kind': 'color', 'color': 'accent'},
              }),
            ],
          ),
          tab('b', 'Друга', styleWhen: [
            when('isTrue', {'color': 'danger'}),
          ]),
        ]),
      ]);

      await pumpDocument(tester, document, theme: theme, data: const {'user.vip': false});
      // Condition not met: built-in colors and the base box.
      expect(titleStyle(tester, 'Перша').color, theme.color(ColorToken.primary));
      expect(panelInset(tester), theme.space(SpacingToken.sm));

      await pumpDocument(tester, document, theme: theme, data: const {'user.vip': true});
      final danger = theme.color(ColorToken.danger);
      // The open tab gets the named color as is; the closed one is x 0.6.
      expect(titleStyle(tester, 'Перша').color, danger);
      expect(titleStyle(tester, 'Друга').color!.a, closeTo(danger.a * 0.6, 1e-6));
      // Panel box: the state REPLACED padding entirely and added a background.
      expect(panelInset(tester), theme.space(SpacingToken.xl));
      final panel = tester.widget<DecoratedBox>(
        find.ancestor(of: find.text('Панель Перша'), matching: find.byType(DecoratedBox)).first,
      );
      expect((panel.decoration as BoxDecoration).color, theme.color(ColorToken.accent));
    });
  });
}
