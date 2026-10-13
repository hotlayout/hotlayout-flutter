import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/style_values.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/render/progress_paint.dart';

import 'support/fixtures.dart';

/// Node STATES (8.9.0): `styleWhen` - a list of "condition -> style".
///
/// The main thing checked here is not the picture but the RULE: the first state whose
/// condition is met applies, and it is laid over the base style rather than replacing
/// it. The same rule is implemented by the builder `resolveNodeStyle`, and they have
/// nowhere to diverge: otherwise a locked card would be grey on the web and branded on the phone.
///
/// Since 9.0.0 a state has the same shape as the base style (all fifteen fields),
/// is laid over BY TOP-LEVEL FIELDS, and the style is inherited AFTER the merge -
/// so a state that paints a card paints the captions in it too.
void main() {
  Map<String, Object?> styledText({
    Map<String, Object?>? style,
    List<Map<String, Object?>>? styleWhen,
  }) => {
    'id': 'txt',
    'type': 'Text',
    'props': {
      'content': {'kind': 'literal', 'value': 'Підпис'},
      'align': 'start',
      'overflow': 'clip',
    },
    'style': ?style,
    'styleWhen': ?styleWhen,
  };

  Map<String, Object?> caseOf(String op, Map<String, Object?> style) => {
    'when': {'path': 'task.completed', 'op': op},
    'style': style,
  };

  TextStyle textStyle(WidgetTester tester) => tester.widget<Text>(find.text('Підпис')).style!;

  group('model', () {
    test('states are parsed in document order', () {
      final node = flattenDocument(
        docWith([
          styledText(styleWhen: [caseOf('isTrue', {'color': 'success'}), caseOf('isFalse', {'color': 'muted'})]),
        ]),
      ).whereType<TextNode>().single;

      expect(node.styleWhen, hasLength(2));
      expect(node.styleWhen.first.style.color, const ColorRef.token('success'));
    });

    test('a state without a style or without a condition is skipped, not failing the node', () {
      // The schema never emits such, but the document arrives from the network.
      final node = flattenDocument(
        docWith([
          styledText(styleWhen: [
            {'when': null, 'style': {'color': 'success'}},
            {'when': {'path': 'task.completed', 'op': 'isTrue'}, 'style': {}},
            caseOf('isFalse', {'color': 'muted'}),
          ]),
        ]),
      ).whereType<TextNode>().single;

      expect(node.styleWhen, hasLength(1));
    });

    test('the feature is declared in the catalog - an old reader knows what it skips', () {
      expect(kFeatureCatalog['nodeStyleCases'], '8.9.0');
      expect(supportsFeature('nodeStyleCases'), isTrue);
      expect(supportsFeature('nodeStyleCases', readerVersion: '8.8.0'), isFalse);
    });
  });

  group('render', () {
    testWidgets('the first state whose condition is met applies', (tester) async {
      // Both conditions are phrased so that exactly the second one is met.
      await pumpDocument(
        tester,
        docWith([
          styledText(styleWhen: [caseOf('isTrue', {'color': 'success'}), caseOf('isFalse', {'color': 'muted'})]),
        ]),
        data: const {'task.completed': false},
      );

      expect(textStyle(tester).color, RenderTheme.fallback().color(ColorToken.muted));
    });

    testWidgets('a state is laid over the base style, not replacing it', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          styledText(
            style: {'typography': 'titleM'},
            styleWhen: [caseOf('isFalse', {'color': 'muted'})],
          ),
        ]),
        data: const {'task.completed': false},
      );

      final theme = RenderTheme.fallback();
      // Colour - from the state, size - from the base style: replacement would force
      // repeating the shared fields in every state.
      expect(textStyle(tester).color, theme.color(ColorToken.muted));
      expect(textStyle(tester).fontSize, theme.text(TypographyToken.titleM).fontSize);
    });

    testWidgets('no state met - we draw the base style', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          styledText(style: {'color': 'accent'}, styleWhen: [caseOf('isTrue', {'color': 'success'})]),
        ]),
        data: const {'task.completed': false},
      );

      expect(textStyle(tester).color, RenderTheme.fallback().color(ColorToken.accent));
    });

    testWidgets('the same data changed - the state changed too, without re-reading the document', (tester) async {
      // The main reason a state cannot be applied at parse time: data
      // changes without a new document - another screen, other `params`, another
      // repeater record.
      final document = docWith([
        styledText(styleWhen: [caseOf('isTrue', {'color': 'success'}), caseOf('isFalse', {'color': 'muted'})]),
      ]);
      final theme = RenderTheme.fallback();

      await pumpDocument(tester, document, data: const {'task.completed': false});
      expect(textStyle(tester).color, theme.color(ColorToken.muted));

      await pumpDocument(tester, document, data: const {'task.completed': true});
      expect(textStyle(tester).color, theme.color(ColorToken.success));
    });

    testWidgets('a state changes the node BACKGROUND too, not just the foreground', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          styledText(styleWhen: [
            caseOf('isFalse', {'background': {'kind': 'color', 'color': 'secondary'}}),
          ]),
        ]),
        data: const {'task.completed': false},
      );

      expect(
        nodeDecoration(tester, 'Підпис').color,
        RenderTheme.fallback().color(ColorToken.secondary),
      );
    });

    testWidgets('a state exists on the SCREEN too: the root is the same node with a style', (tester) async {
      final theme = RenderTheme.fallback();
      final document = UiDocument.fromJson({
        'schemaVersion': UiDocument.supportedSchemaVersion,
        'documentId': 'inline',
        'name': 'Екран зі станом',
        'initialScreenId': 'inline',
        'screens': [
          {
            'screenId': 'inline',
            'name': 'inline',
            'root': {
              'id': 'root',
              'type': 'Screen',
              'props': <String, Object?>{},
              'style': {'background': colorBackground('surface')},
              'styleWhen': [
                caseOf('isTrue', {'background': colorBackground('secondary'), 'color': 'success'}),
              ],
              'children': [styledText()],
            },
          },
        ],
      });

      await pumpDocument(tester, document, data: const {'task.completed': false}, theme: theme);
      expect(screenDecoration(tester).color, theme.color(ColorToken.surface));
      expect(textStyle(tester).color, theme.color(ColorToken.onSurface));

      await pumpDocument(tester, document, data: const {'task.completed': true}, theme: theme);
      expect(screenDecoration(tester).color, theme.color(ColorToken.secondary));
      // The screen state colour was inherited by the captions on it.
      expect(textStyle(tester).color, theme.color(ColorToken.success));
    });

    testWidgets('style is inherited AFTER the state merge', (tester) async {
      // `x-style.inheritance: 'after-case-merge'`. A card in the "locked" state
      // repaints the captions inside it - without duplicating the subtree per state.
      final theme = RenderTheme.fallback();
      final document = docWith([
        {
          'id': 'card',
          'type': 'Container',
          'props': {'gap': 'none'},
          'style': {'color': 'primary'},
          'styleWhen': [
            caseOf('isFalse', {'color': 'locked'}),
          ],
          'children': [styledText()],
        },
      ]);

      await pumpDocument(tester, document, data: const {'task.completed': true}, theme: theme);
      expect(textStyle(tester).color, theme.color(ColorToken.primary));

      await pumpDocument(tester, document, data: const {'task.completed': false}, theme: theme);
      expect(textStyle(tester).color, theme.color(ColorToken.locked));
    });

    testWidgets('a state with padding replaces the base padding WHOLE', (tester) async {
      // `x-style.caseMerge: 'top-level-fields'`: a side the state did not name
      // becomes ZERO, not the base one.
      final document = docWith([
        styledText(
          style: {
            'padding': {'top': 'sm', 'start': 'lg', 'end': 'lg', 'bottom': 'sm'},
          },
          styleWhen: [
            caseOf('isTrue', {
              'padding': {'top': 'xl'},
            }),
          ],
        ),
      ]);

      await pumpDocument(tester, document, data: const {'task.completed': false});
      expect(nodePadding(tester, 'Підпис'), const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8));

      await pumpDocument(tester, document, data: const {'task.completed': true});
      expect(nodePadding(tester, 'Підпис'), const EdgeInsetsDirectional.only(top: 24));
    });

    testWidgets('a state does NOT repaint a widget part: the bar colour lives in props', (tester) async {
      // Before 9.0.0 `styleWhen.color` on a progress bar changed the fill ("style beats
      // props"). Now the part colour is in `props`, and states change only
      // `style`; the bar does not read the inherited colour at all.
      final theme = RenderTheme.fallback();
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'bar',
            'type': 'ProgressBar',
            'props': {
              'value': {'kind': 'literal', 'value': 40},
              'max': {'kind': 'literal', 'value': 100},
              'color': 'primary',
              'labelFormat': 'none',
            },
            'style': {'color': 'danger'},
            'styleWhen': [
              caseOf('isFalse', {'color': 'success'}),
            ],
          },
        ]),
        data: const {'task.completed': false},
        theme: theme,
      );

      final indicator = tester.widget<ProgressTrack>(find.byType(ProgressTrack));
      expect(indicator.fill.color, theme.color(ColorToken.primary));
    });
  });
}
