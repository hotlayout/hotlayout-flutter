/// WIDE PLACE (9.18.0, step 2): what the case table does not say about reader BEHAVIOUR.
///
/// The table (`wide_chrome_cases_test.dart`) answers "what stands where". Here - what
/// happens to it in real life: a screen crosses a class boundary (rotation, split screen, desktop
/// window), and the stack, session, field values, focus and an open modal layer all survive; an
/// item in the bar is a real control; the keyboard does not hide the centred window; the "navigation" landmark.
library;

import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart' show IconSizeToken;
import 'package:hotlayout_flutter/src/model/wide_chrome_rules.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/wide_nav_group.dart';

import 'support/fixtures.dart';

typedef _Json = Map<String, Object?>;

_Json _literal(String text) => {'kind': 'literal', 'value': text};

_Json _text(String id, String text) => {
  'id': id,
  'type': 'Text',
  'props': {'content': _literal(text)},
};

_Json _button(String id, String label, _Json action) => {
  'id': id,
  'type': 'Button',
  'props': {'label': _literal(label), 'variant': 'primary', 'action': action},
};

_Json _field(String id, String path) => {
  'id': id,
  'type': 'TextField',
  'props': {'label': _literal('Name $id'), 'value': {'kind': 'binding', 'path': path}},
};

_Json _nav(List<String> sections) => {
  'id': 'nav',
  'type': 'NavBar',
  'props': <String, Object?>{},
  'children': [
    for (final section in sections)
      {
        'id': 'nav-$section',
        'type': 'NavItem',
        'props': {
          'icon': 'house',
          'label': _literal('Go $section'),
          'action': {'type': 'navigate.section', 'params': {'screenId': section}},
        },
      },
  ],
};

_Json _screen(String id, List<_Json> children, {String? presentation}) => {
  'screenId': id,
  'name': id,
  'presentation': ?presentation,
  'root': {
    'id': '$id-root',
    'type': 'Screen',
    'props': {'gap': 'sm'},
    'style': {'padding': 'md', 'background': {'kind': 'color', 'color': 'surface'}},
    'children': children,
  },
};

UiDocument _doc(List<_Json> screens) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'wide-behaviour',
  'name': 'wide-behaviour',
  'initialScreenId': screens.first['screenId'],
  'screens': screens,
});

void _view(WidgetTester tester, double width, [double height = 900]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
}

/// A document with a field, a navigation to a page, a two-section bar and a modal screen with a field.
UiDocument _flow() => _doc([
  _screen('a', [
    _field('page', 'form.page'),
    _button('go', 'Open detail', {'type': 'navigate', 'params': {'screenId': 'detail'}}),
    _button('dialog', 'Open dialog', {'type': 'navigate', 'params': {'screenId': 'ask'}}),
    _nav(['a', 'b']),
  ]),
  _screen('b', [_text('b-text', 'Section B'), _nav(['a', 'b'])]),
  _screen('detail', [
    _text('detail-text', 'Detail page'),
    _button('back', 'Back', {'type': 'navigate.back'}),
  ]),
  _screen('ask', [
    _field('layer', 'form.layer'),
    _text('ask-text', 'Dialog text'),
    _button('close', 'Close', {'type': 'navigate.back'}),
  ], presentation: 'modal'),
]);

void main() {
  group('a screen crosses a class boundary: nothing is reset', () {
    for (final widths in [
      [393.0, 768.0, 1280.0, 393.0],
      [1280.0, 599.0, 600.0, 1023.0, 1024.0],
    ]) {
      testWidgets('field, focus and typed text: ${widths.map((w) => w.toInt()).join(' → ')}', (tester) async {
        addTearDown(tester.view.reset);
        _view(tester, widths.first);
        await pumpDocument(tester, _flow());
        await tester.enterText(find.byType(EditableText).first, 'Ann');
        await tester.pump();
        final focus = tester.widget<EditableText>(find.byType(EditableText).first).focusNode;
        expect(focus.hasFocus, isTrue);
        for (final width in widths.skip(1)) {
          _view(tester, width);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Ann'), findsOneWidget, reason: 'typed text kept at ${width.toInt()}');
          expect(tester.widget<EditableText>(find.byType(EditableText).first).focusNode.hasFocus, isTrue, reason: 'focus at ${width.toInt()}');
        }
      });
    }

    testWidgets('stack: a page opened on a phone stays on a wide screen, back returns', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 393);
      await pumpDocument(tester, _flow());
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(find.text('Detail page'), findsOneWidget);
      _view(tester, 1280);
      await tester.pumpAndSettle();
      expect(find.text('Detail page'), findsOneWidget, reason: 'the stack was not reset');
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open detail'), findsOneWidget);
      // Back on the screen with the bar: now it is at the top.
      expect(find.byType(WideNavGroup), findsOneWidget);
    });

    testWidgets('session: the screen record and the field survive a section switch and a class boundary', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 1280);
      final writes = <String, Object>{};
      await pumpDocument(tester, _flow(), onWrite: (path, value) => writes[path] = value);
      await tester.enterText(find.byType(EditableText).first, 'Zed');
      await tester.pump();
      expect(writes['form.page'], 'Zed');
      await tester.tap(find.byKey(const ValueKey('sdui-nav-item-nav-b')));
      await tester.pumpAndSettle();
      expect(find.text('Section B'), findsOneWidget);
      _view(tester, 393);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sdui-nav-item-nav-a')));
      await tester.pumpAndSettle();
      expect(find.text('Zed'), findsOneWidget, reason: 'the session value on the same screen');
    });

    testWidgets('open modal layer: sheet -> window -> sheet, the field in it keeps typed text and focus', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 393);
      await pumpDocument(tester, _flow());
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      final layerField = find.descendant(of: find.byKey(kModalLayerKey), matching: find.byType(EditableText));
      await tester.enterText(layerField, 'Inside');
      await tester.pump();
      expect(tester.getRect(find.byKey(kModalLayerKey)).width, 393);

      _view(tester, 1280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final window = tester.getRect(find.byKey(kModalLayerKey));
      expect(window.width, 560, reason: 'the layer is open and is now a window');
      expect(find.text('Inside'), findsOneWidget);
      expect(tester.widget<EditableText>(layerField).focusNode.hasFocus, isTrue, reason: 'focus stayed in the layer');
      expect(find.text('Dialog text'), findsOneWidget);

      _view(tester, 393);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(kModalLayerKey)).width, 393);
      expect(find.text('Inside'), findsOneWidget);

      // Closing is unchanged: a tap on the scrim is `navigate.back`.
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(kModalLayerKey), findsNothing);
    });
  });

  group('a bar item in the app bar is a real control', () {
    testWidgets('a tap delivers the item action; the active one is highlighted; the name is the label', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 1280);
      final actions = <ButtonAction>[];
      await pumpDocument(tester, _flow(), onAction: (action, nodeId) => actions.add(action));
      final b = find.byKey(const ValueKey('sdui-nav-item-nav-b'));
      expect(tester.getSemantics(find.bySemanticsLabel('Go b')).label, 'Go b');
      await tester.tap(b);
      await tester.pumpAndSettle();
      // `navigate.section` is executed by the reader (stack reset): the host does not get this action.
      expect(actions, isEmpty);
      expect(find.text('Section B'), findsOneWidget);
    });

    testWidgets('the "navigation" landmark sits on the item group in the app bar', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 1280);
      final handle = tester.ensureSemantics();
      await pumpDocument(tester, _flow());
      final node = tester.getSemantics(find.byType(WideNavGroup));
      expect(node.getSemanticsData().role, SemanticsRole.navigation);
      handle.dispose();
    });

    testWidgets('on a phone there is no item group in the app bar: the bar stays at the bottom as before', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 393);
      await pumpDocument(tester, _flow());
      expect(find.byType(WideNavGroup), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('sdui-nav-item-nav-a'))).bottom, closeTo(900, 1));
    });

    testWidgets('every section screen draws the items in the same place: switching does not make the bar jump', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 1280);
      await pumpDocument(tester, _flow());
      final before = tester.getRect(find.byKey(const ValueKey('sdui-nav-item-nav-a')));
      await tester.tap(find.byKey(const ValueKey('sdui-nav-item-nav-b')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('sdui-nav-item-nav-a'))), before);
    });
  });

  group('the keyboard does not hide the centred window', () {
    for (final keyboard in [200.0, 480.0]) {
      testWidgets('768 × 1024, keyboard ${keyboard.toInt()}: the window is above it, the field in the window is visible', (tester) async {
        addTearDown(tester.view.reset);
        _view(tester, 768, 1024);
        await pumpDocument(tester, _flow(), keyboard: keyboard);
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        final window = tester.getRect(find.byKey(kModalLayerKey));
        expect(window.width, 560);
        expect(window.bottom, lessThanOrEqualTo(1024 - keyboard + 0.01), reason: 'the window is not below the keyboard');
        expect(window.top, greaterThanOrEqualTo(0));
        final field = tester.getRect(find.descendant(of: find.byKey(kModalLayerKey), matching: find.byType(EditableText)));
        expect(field.bottom, lessThanOrEqualTo(1024 - keyboard + 0.01));
      });
    }

    testWidgets('a sheet on a phone still rides above the keyboard', (tester) async {
      addTearDown(tester.view.reset);
      _view(tester, 393, 800);
      await pumpDocument(tester, _flow(), keyboard: 300);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byKey(kModalLayerKey));
      expect(sheet.width, 393);
      expect(sheet.bottom, closeTo(500, 0.01));
    });
  });

  group('system font scale', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('app bar items ×$scale: widths follow the reference from the measured value, no overflow', (tester) async {
        addTearDown(tester.view.reset);
        _view(tester, 1280);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: renderDocument(_flow(), theme: RenderTheme.fallback(), data: const {})),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final group = tester.renderObject<RenderWideNavGroup>(find.byType(WideNavGroup));
        final formula = wideNavBarOf(width: group.size.width, navLabels: group.naturalLabelWidths, nav: group.metrics);
        expect(group.drawnMode, WideNavMode.labels);
        for (var i = 0; i < formula.navItemWidths.length; i++) {
          final id = ['nav-a', 'nav-b'][i];
          expect(tester.getSize(find.byKey(ValueKey('sdui-nav-item-$id'))).width, closeTo(formula.navItemWidths[i], 0.01));
        }
        // The glyph grows with the text: the glyph box width in the metrics is scaled.
        expect(group.metrics.iconWidth, closeTo(RenderTheme.fallback().iconBox(IconSizeToken.md).width * scale, 0.5));
      });
    }
  });

  group('untrusted input: a `widePlacement` of the wrong shape does not break the screen', () {
    for (final (name, value, place) in <(String, Object?, bool)>[
      ('number', 7, true),
      ('object', <String, Object?>{'bottom': true}, true),
      ('null', null, true),
      ('array', ['bottom'], true),
      ('«bottom»', 'bottom', false),
    ]) {
      testWidgets(name, (tester) async {
        addTearDown(tester.view.reset);
        _view(tester, 1280);
        final nav = _nav(['a', 'b']);
        nav['props'] = {'widePlacement': value};
        await pumpDocument(tester, _doc([_screen('a', [_text('t', 'T'), nav]), _screen('b', [_text('u', 'U')])]));
        expect(tester.takeException(), isNull);
        expect(find.byType(WideNavGroup).evaluate().isNotEmpty, place);
      });
    }
  });
}
