import 'dart:io';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';

import 'support/fixtures.dart';
import 'support/inputs.dart';
import 'package:hotlayout_flutter/src/model/shown_text.dart';
import 'package:hotlayout_flutter/src/render/wide_nav_group.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

/// Fixes from visually comparing the Flutter reader side by side with React and
/// the canvas. Each group covers one finding.
void main() {
  group('the page under a modal layer', () {
    UiDocument longPage() => docWithScreens(
      [
        screenEntry('home', [
          for (var i = 0; i < 40; i += 1) textNode('Рядок $i', id: 't$i'),
          textFieldNode(id: 'field', label: 'Пошта'),
          buttonNode('Відкрити', id: 'open', action: {
            'type': 'navigate',
            'params': {'screenId': 'gift'},
          }),
        ]),
        screenEntry('gift', [textNode('Ваш подарунок', id: 'gift-text')], presentation: 'modal'),
      ],
      initialScreenId: 'home',
    );

    for (final width in [393.0, 768.0]) {
      testWidgets('scroll, field and focus survive opening and closing the layer ($width)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.reset);
        await pumpDocument(tester, longPage());

        await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText), 'abc');
        await tester.pump();
        final before = tester.getTopLeft(find.text('Відкрити')).dy;
        expect(before, lessThan(800));

        await tester.tap(find.text('Відкрити'));
        await tester.pumpAndSettle();
        expect(find.text('Ваш подарунок'), findsOneWidget);
        // The page under the layer did not jump back to the start.
        expect(tester.getTopLeft(find.text('Відкрити')).dy, before);

        await tester.tapAt(Offset(width / 2, 4));
        await tester.pumpAndSettle();
        expect(find.text('Ваш подарунок'), findsNothing);
        expect(tester.getTopLeft(find.text('Відкрити')).dy, before);
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.controller.text, 'abc');
      });
    }
  });

  group('top item labels', () {
    testWidgets('the natural-width measurement is reset when the fonts change', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);
      final doc = docWithScreens([
        screenEntry('home', [
          {
            'id': 'nav',
            'type': 'NavBar',
            'props': <String, Object?>{},
            'children': [
              for (final id in ['a', 'b'])
                {
                  'id': 'nav-$id',
                  'type': 'NavItem',
                  'props': {
                    'label': {'kind': 'literal', 'value': 'Пункт $id'},
                    'icon': 'house',
                    'action': {'type': 'none'},
                  },
                },
            ],
          },
        ]),
      ], initialScreenId: 'home');
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: renderDocument(doc, theme: RenderTheme.fallback(), data: const {}))),
      );
      final group = tester.renderObject<RenderWideNavGroup>(find.byType(WideNavGroup));
      final first = group.naturalLabelWidths;
      expect(identical(group.naturalLabelWidths, first), isTrue);
      // The fallback font finished loading (web): the engine reports a system font change.
      await tester.binding.handleSystemMessage(<String, dynamic>{'type': 'fontsChange'});
      await tester.pump();
      await tester.pump();
      expect(identical(group.naturalLabelWidths, first), isFalse);
    });
  });

  group('Esc and the modal layer', () {
    UiDocument flow({String? presentation = 'modal'}) => docWithScreens([
      screenEntry('home', [
        textNode('Головний екран', id: 'home-text'),
        buttonNode('Відкрити', id: 'open', action: {
          'type': 'navigate',
          'params': {'screenId': 'gift'},
        }),
      ]),
      screenEntry('gift', [textNode('Ваш подарунок', id: 'gift-text')], presentation: presentation),
    ], initialScreenId: 'home');

    testWidgets('Escape closes the topmost modal layer', (tester) async {
      await pumpDocument(tester, flow());
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();
      expect(find.text('Ваш подарунок'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Ваш подарунок'), findsNothing);
      expect(find.text('Головний екран'), findsOneWidget);
    });

    testWidgets('Escape without a layer does nothing; it does not close a page (non-layer)', (tester) async {
      await pumpDocument(tester, flow(presentation: null));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Головний екран'), findsOneWidget);

      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Ваш подарунок'), findsOneWidget);
    });

    testWidgets('another key does not close the layer', (tester) async {
      await pumpDocument(tester, flow());
      await tester.tap(find.text('Відкрити'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Ваш подарунок'), findsOneWidget);
    });
  });

  group('ring label', () {
    testWidgets('digits are monospaced (tabular-nums as in React)', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'ring',
            'type': 'CircularProgress',
            'props': {
              'value': {'kind': 'literal', 'value': 74},
              'max': {'kind': 'literal', 'value': 119},
              'color': 'primary',
              'size': 'md',
              'labelFormat': 'valueOfMax',
            },
          },
        ]),
      );
      final style = tester.widget<Text>(find.text('74 / 119')).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('whitespace in shown text', () {
    test('collapsing: consecutive whitespace becomes one, edges trimmed, non-breaking space untouched', () {
      expect(collapseShownWhitespace('1  Maya'), '1 Maya');
      expect(collapseShownWhitespace('  a \t b  '), 'a b');
      // A line break is whitespace too: LF, CR and CR LF merge with the whitespace around them.
      expect(collapseShownWhitespace('a  \n  b'), 'a b');
      expect(collapseShownWhitespace('a\r\nb'), 'a b');
      expect(collapseShownWhitespace('\n\tMaya\r\n'), 'Maya');
      expect(collapseShownWhitespace('   '), '');
      expect(collapseShownWhitespace(''), '');
      expect(collapseShownWhitespace('120\u00A0JOD'), '120\u00A0JOD');
      expect(collapseShownWhitespace('a\u00A0\u00A0b'), 'a\u00A0\u00A0b');
      expect(collapseShownWhitespace('a\u202Fb'), 'a\u202Fb');
    });

    testWidgets('Text: literal', (tester) async {
      await pumpDocument(tester, docWith([textNode('  1   Maya \t x ')]));
      expect(find.text('1 Maya x'), findsOneWidget);
    });

    testWidgets('Text: template AFTER substitution (an empty place leaves two spaces)', (tester) async {
      final node = {
        'id': 'row',
        'type': 'Text',
        'props': {
          'content': {
            'kind': 'template',
            'template': '{rank} {name}',
            'values': {
              'rank': {'kind': 'binding', 'path': 'r.rank', 'fallback': ''},
              'name': {'kind': 'binding', 'path': 'r.name', 'fallback': ''},
            },
          },
          'align': 'start',
          'overflow': 'clip',
        },
      };
      await pumpDocument(tester, docWith([node]), data: {'r.rank': '', 'r.name': 'Maya '});
      expect(find.text('Maya'), findsOneWidget);
    });

    testWidgets('composite text: the space at the joint of parts is also one', (tester) async {
      final node = {
        'id': 'row',
        'type': 'Text',
        'props': {
          'content': {
            'kind': 'template',
            'template': ' {a}  {b} ',
            'values': {
              'a': {'kind': 'binding', 'path': 'r.a', 'fallback': ''},
              'b': {'kind': 'binding', 'path': 'r.b', 'fallback': ''},
            },
          },
          'align': 'start',
          'overflow': 'clip',
          'spans': {
            'a': {'typography': 'displayL'},
          },
        },
      };
      await pumpDocument(tester, docWith([node]), data: {'r.a': '1 ', 'r.b': ' Maya'});
      final rich = tester.widget<RichText>(find.byType(RichText).last);
      expect(rich.text.toPlainText(), '1 Maya');
    });

    testWidgets('labels of button, badge, list row, app bar', (tester) async {
      final doc = docWithScreens([
        screenEntry('home', [
          appBarNode('  Мій   екран ', subtitle: ' під  заголовок '),
          buttonNode('  Відкрити   зараз ', action: {'type': 'none'}),
          badgeNode(' Нова   ціль '),
          listTileNode('  Рядок   списку ', subtitle: ' опис  рядка '),
        ]),
      ], initialScreenId: 'home');
      await pumpDocument(tester, doc);
      for (final shown in ['Мій екран', 'під заголовок', 'Відкрити зараз', 'Нова ціль', 'Рядок списку', 'опис рядка']) {
        expect(find.text(shown), findsOneWidget, reason: shown);
      }
    });

    testWidgets('ring label: the spaces are intentional ("3 / 4"), left untouched', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          {
            'id': 'ring',
            'type': 'CircularProgress',
            'props': {
              'value': {'kind': 'literal', 'value': 3},
              'max': {'kind': 'literal', 'value': 4},
              'color': 'primary',
              'size': 'md',
              'labelFormat': 'valueOfMax',
            },
          },
        ]),
      );
      expect(find.text('3 / 4'), findsOneWidget);
    });

    testWidgets('goes to the host as is: action params are not collapsed', (tester) async {
      final actions = <String>[];
      final doc = docWithScreens([
        screenEntry('home', [
          buttonNode('Go', action: {
            'type': 'custom.thing',
            'params': {'note': 'a  b '},
          }),
        ]),
      ], initialScreenId: 'home');
      await pumpDocument(tester, doc, onAction: (action, _) => actions.add('${action.params['note']}'));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(actions, ['a  b ']);
    });

    testWidgets('input field value is not collapsed', (tester) async {
      await pumpDocument(
        tester,
        docWith([textFieldNode(path: 'form.name')]),
        data: {'form.name': ' a  b '},
      );
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, ' a  b ');
    });
  });

  group('navigation items without a hover backing', () {
    testWidgets('item InkWell: hover is transparent, focus is visible', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 800);
      addTearDown(tester.view.reset);
      final doc = docWithScreens([
        screenEntry('home', [
          {
            'id': 'nav',
            'type': 'NavBar',
            'props': <String, Object?>{},
            'children': [
              for (final id in ['a', 'b'])
                {
                  'id': 'nav-$id',
                  'type': 'NavItem',
                  'props': {
                    'label': {'kind': 'literal', 'value': 'Пункт $id'},
                    'icon': 'house',
                    'action': {'type': 'none'},
                  },
                },
            ],
          },
        ]),
      ], initialScreenId: 'home');
      await pumpDocument(tester, doc);
      final ink = tester.widget<InkWell>(find.byKey(const ValueKey('sdui-nav-item-nav-a')));
      expect(ink.splashFactory, NoSplash.splashFactory);
      expect(ink.overlayColor!.resolve({WidgetState.hovered}), Colors.transparent);
      expect(ink.overlayColor!.resolve({WidgetState.pressed}), Colors.transparent);
      expect(ink.overlayColor!.resolve({WidgetState.focused}), isNot(Colors.transparent));
    });
  });

  group('no Material glyphs in the render path', () {
    test('lib/src has no `Icons.` (a host without uses-material-design would see squares)', () {
      final offenders = <String>[];
      for (final file in Directory('lib/src').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          if (RegExp(r'\bIcons\.[a-z_]+').hasMatch(line)) offenders.add('${file.path}:${i + 1}');
        }
      }
      expect(offenders, isEmpty);
    });

    testWidgets('selection mark is a custom painter, without Icon', (tester) async {
      await pumpDocument(
        tester,
        docWith([
          choiceGroupNode(
            [optionNode('Один', optionValue: 'one'), optionNode('Два', optionValue: 'two')],
            value: const {'kind': 'literal', 'value': 'one'},
          ),
        ]),
      );
      expect(find.descendant(of: find.byType(ChoiceOptionMark), matching: find.byType(Icon)), findsNothing);
      expect(find.descendant(of: find.byType(ChoiceOptionMark), matching: find.byType(CustomPaint)), findsNWidgets(2));
    });
  });

  group('data: images (data dictionary samples)', () {
    Map<String, Object?> image(String url) => {
      'id': 'img',
      'type': 'Image',
      'props': {
        'source': {'kind': 'url', 'url': url},
        'alt': 'x',
        'fit': 'cover',
      },
    };

    testWidgets('data:image/png is painted from memory, without the network', (tester) async {
      // A 1x1 transparent PNG.
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAHnOcQAAAAABJRU5ErkJggg==';
      await pumpDocument(tester, docWith([image('data:image/png;base64,$png')]));
      final widget = tester.widget<Image>(find.byType(Image));
      expect(widget.image, isA<ResizeImage>());
      expect(((widget.image as ResizeImage).imageProvider as MemoryImage).bytes, base64.decode(png));
    });

    testWidgets('an unusable data: address is a broken image, not an exception', (tester) async {
      await pumpDocument(tester, docWith([image('data:image/png;base64,%%%')]));
      expect(tester.takeException(), isNull);
      expect(find.text('Image unavailable'), findsOneWidget);
    });
  });
}
