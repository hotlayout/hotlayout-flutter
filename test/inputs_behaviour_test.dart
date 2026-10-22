/// INPUT FIELDS (schema 9.13.0) - behaviour the case table does not express:
/// screen flow and host, focus and keyboard, disabled state, keyboard
/// switching, autofill, semantics, each of the twenty policy rows
/// with its own test.
///
/// `input_cases_test.dart` runs the table ITSELF; here is a real screen flow
/// (`renderDocument`) in which a write goes to the reader session and to the host at the same moment.
library;

import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/inputs.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/render/screen_zones.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/inputs.dart';

EditableText _editableAt(WidgetTester tester, [int index = 0]) =>
    tester.widgetList<EditableText>(find.byType(EditableText)).elementAt(index);

/// Focus and the on-screen keyboard (the platform connection in a test opens
/// with a second call after the frame).
Future<void> _focus(WidgetTester tester, Finder editable) async {
  await tester.showKeyboard(editable);
  await tester.pump();
  await tester.showKeyboard(editable);
}

Json _screen(String id, List<Json> children, {Json? style, String gap = 'none'}) => {
  'screenId': id,
  'name': id,
  'root': {'id': '$id-root', 'type': 'Screen', 'props': {'gap': gap}, 'style': ?style, 'children': children},
};

UiDocument _flow(List<Json> screens) => UiDocument.fromJson({
  'schemaVersion': UiDocument.supportedSchemaVersion,
  'documentId': 'inputs-flow',
  'name': 'inputs-flow',
  'initialScreenId': screens.first['screenId'],
  'screens': screens,
});

Json _button(String id, String label, Json action) => {
  'id': id,
  'type': 'Button',
  'props': {'label': literal(label), 'variant': 'primary', 'action': action},
};

void main() {
  // ───────────────────────────── flow and host ─────────────────────────────

  group('a write goes to the reader session and the host at the same moment', () {
    testWidgets('text: a dependent node of the same screen updates under the finger, the host gets the string on every change', (tester) async {
      final writes = <(String, Object?)>[];
      final doc = _flow([
        _screen('a', [
          textFieldNode(path: 'form.name', label: 'Name'),
          {
            ...plainText('hello', 'Hello!'),
            'visibleIf': {'path': 'form.name', 'op': 'isNotEmpty'},
          },
        ]),
      ]);
      await pumpDocument(tester, doc, onWrite: (path, value) => writes.add((path, value)));
      expect(find.text('Hello!'), findsNothing);

      await tester.enterText(find.byType(TextField), 'A');
      await tester.pump();
      expect(find.text('Hello!'), findsOneWidget, reason: 'the reader session is a data layer: the condition fired at the same moment');
      await tester.enterText(find.byType(TextField), 'Al');
      await tester.pump();
      expect(writes, [('form.name', 'A'), ('form.name', 'Al')]);
      expect(writes.every((w) => w.$2 is String), isTrue);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(writes.last, ('form.name', ''), reason: 'everything erased - an empty string, not "no value"');
      expect(find.text('Hello!'), findsNothing);
    });

    testWidgets('switch and checkbox: the host gets a bool; a text binding to the same path writes true / false', (tester) async {
      final writes = <(String, Object?)>[];
      final doc = _flow([
        _screen('a', [
          toggleNode('Switch', path: 'settings.push', label: 'Push'),
          toggleNode('Checkbox', id: 'agree', path: 'form.agreed', label: 'Agree'),
          {
            'id': 'show',
            'type': 'Text',
            'props': {'content': binding('form.agreed')},
          },
        ]),
      ]);
      await pumpDocument(tester, doc, onWrite: (path, value) => writes.add((path, value)));
      await tester.tap(find.text('Push'));
      await tester.tap(find.text('Agree'));
      await tester.pump();
      expect(writes, [('settings.push', true), ('form.agreed', true)]);
      expect(writes.every((w) => w.$2 is bool), isTrue);
      expect(find.text('true'), findsOneWidget, reason: 'a boolean on screen is true / false, as on the phone');
      await tester.tap(find.text('Agree'));
      await tester.pump();
      expect(writes.last, ('form.agreed', false));
      expect(find.text('false'), findsOneWidget);
    });

    testWidgets('the write reaches the host BEFORE an action pressed after the change: the action sees the typed text (inputWrite)', (tester) async {
      final log = <String>[];
      final doc = _flow([
        _screen('a', [
          textFieldNode(path: 'form.name'),
          toggleNode('Switch', path: 'settings.push'),
          _button('send', 'Send', {
            'type': 'custom.send',
            'params': {'static': 'x'},
            'paramBindings': {'name': 'form.name', 'push': 'settings.push'},
          }),
        ]),
      ]);
      await pumpDocument(
        tester,
        doc,
        onWrite: (path, value) => log.add('write $path=$value'),
        onAction: (action, nodeId) => log.add('action ${action.type} ${action.params}'),
      );
      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pump();
      await tester.tap(find.text('Push'));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(log, [
        'write form.name=Alex',
        'write settings.push=true',
        // The field value in a parameter is whole (inputValueInActionParam). A switch
        // boolean does NOT become a parameter: `x-actions.paramBinding` accepts only a
        // non-empty string (9.8.0), so the `params` literal applies. The contract text says "the string
        // true / false" - a contradiction, reported separately (the contract is silent).
        'action custom.send {static: x, name: Alex}',
      ]);
    });

    testWidgets('the value survives a move to another screen and back (session layer)', (tester) async {
      final doc = _flow([
        _screen('a', [
          textFieldNode(path: 'form.name'),
          _button('go', 'Next', {'type': 'navigate', 'params': {'screenId': 'b'}}),
        ]),
        _screen('b', [
          _button('back', 'Back', {'type': 'navigate.back'}),
          plainText('echo', 'Second'),
        ]),
      ]);
      await pumpDocument(tester, doc);
      await tester.enterText(find.byType(TextField), 'Alex');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(_editableAt(tester).controller.text, 'Alex');
    });
  });

  // ───────────────────────────── inputFocusOnScreenChange ─────────────────────────────

  group('focus (inputFocusOnScreenChange)', () {
    testWidgets('moving between screens drops focus', (tester) async {
      final doc = _flow([
        _screen('a', [
          textFieldNode(path: 'form.name'),
          _button('go', 'Next', {'type': 'navigate', 'params': {'screenId': 'b'}}),
        ]),
        _screen('b', [textFieldNode(id: 'other', path: 'form.other'), plainText('t', 'Second')]),
      ]);
      await pumpDocument(tester, doc);
      await _focus(tester, find.byType(EditableText));
      expect(_editableAt(tester).focusNode.hasFocus, isTrue);
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      expect(_editableAt(tester).focusNode.hasFocus, isFalse, reason: 'there is no focus on the new screen');
    });

    testWidgets('a tap beside the field drops focus; a tap on the field itself does not', (tester) async {
      final harness = InputHarness([textFieldNode(), plainText('plain', 'Plain text')]);
      await harness.pump(tester);
      await _focus(tester, find.byType(EditableText));
      await tester.pump();
      expect(_editableAt(tester).focusNode.hasFocus, isTrue);
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(_editableAt(tester).focusNode.hasFocus, isTrue, reason: 'a repeated tap on the field does not drop focus');
      await tester.tap(find.text('Plain text'));
      await tester.pump();
      expect(_editableAt(tester).focusNode.hasFocus, isFalse);
    });

    testWidgets('switch and checkbox are traversal stops: space toggles, Enter only on the switch', (tester) async {
      final harness = InputHarness([
        toggleNode('Switch', id: 'sw', path: 'form.sw', label: 'Sw'),
        toggleNode('Checkbox', id: 'cb', path: 'form.cb', label: 'Cb'),
      ]);
      await harness.pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.writes, [('form.sw', true), ('form.sw', false)], reason: 'switch: space and Enter');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.writes, hasLength(2), reason: 'the checkbox is not toggled by Enter');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(harness.writes.last, ('form.cb', true));
    });

    for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
      testWidgets('a held ${key.keyLabel.isEmpty ? 'Space' : key.keyLabel} key toggles once', (tester) async {
        final harness = InputHarness([toggleNode('Switch', path: 'form.sw', label: 'Sw')]);
        await harness.pump(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyDownEvent(key);
        for (var i = 0; i < 6; i += 1) {
          await tester.sendKeyRepeatEvent(key);
        }
        await tester.sendKeyUpEvent(key);
        await tester.pump();
        expect(harness.writes, [('form.sw', true)], reason: 'key auto-repeat is not a press');
      });
    }
  });

  // ───────────────────────────── "A -> B -> A" ─────────────────────────────

  group('inputHeldValue: a layer value changed - that is an event, not a comparison', () {
    testWidgets('text: A -> B -> A drops the typed text even though the initial and final values match', (tester) async {
      final harness = InputHarness([textFieldNode()], session: {'form.field': 'A'});
      await harness.pump(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_editableAt(tester).controller.text, 'typed', reason: 'the layer value did not change - the typed text stays');
      await harness.setSession(tester, {'form.field': 'B'});
      expect(_editableAt(tester).controller.text, 'B');
      await harness.setSession(tester, {'form.field': 'A'});
      expect(_editableAt(tester).controller.text, 'A', reason: 'the same "A" came back - but the typed text was already dropped by the "B" event');
    });

    testWidgets('in focus: the "value changed" event marks a reset on focus loss', (tester) async {
      final harness = InputHarness([textFieldNode()], session: {'form.field': 'A'});
      await harness.pump(tester);
      await _focus(tester, find.byType(EditableText));
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();
      await harness.setSession(tester, {'form.field': 'B'});
      await harness.setSession(tester, {'form.field': 'A'});
      expect(_editableAt(tester).controller.text, 'typed', reason: 'in focus the typed text stays, whatever the data do');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_editableAt(tester).controller.text, 'A', reason: 'on focus loss - the layer value: it did change');
    });
  });

  // ───────────────────────────── disabledIf ─────────────────────────────

  group('disabledIf: inputDisabled, unknownDisabledOp, missingDisabledValue', () {
    const off = {'path': 'flags.off', 'op': 'isTrue'};

    testWidgets('condition met: the field takes no focus, writes nothing; opacity 0.5 on the WHOLE widget; "disabled" semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = InputHarness(
        [
          textFieldNode(helper: literal('Note'), disabledIf: off),
          toggleNode('Switch', disabledIf: off),
        ],
        session: {'flags.off': true},
      );
      await harness.pump(tester);
      await tester.tap(find.byType(TextField), warnIfMissed: false);
      await tester.pump();
      expect(_editableAt(tester).focusNode.hasFocus, isFalse);
      await tester.tap(find.text('Push'));
      await tester.pump();
      expect(harness.writes, isEmpty);
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).where((o) => o.opacity == 0.5).length;
      expect(opacities, 2, reason: 'both widgets are whole, with the label and the row under the field');
      expect(tester.getSemantics(find.bySemanticsLabel('Email')).flagsCollection.isEnabled, Tristate.isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Push')).flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets('a field that lost focus through disabling drops the held value', (tester) async {
      final harness = InputHarness([textFieldNode(disabledIf: off)], session: {'form.field': 'Alex', 'flags.off': false});
      await harness.pump(tester);
      await _focus(tester, find.byType(EditableText));
      await tester.enterText(find.byType(TextField), 'Alexa');
      await tester.pump();
      await harness.setSession(tester, {'form.field': 'Olena', 'flags.off': true});
      expect(_editableAt(tester).focusNode.hasFocus, isFalse);
      expect(_editableAt(tester).controller.text, 'Olena', reason: 'held value dropped - the field follows the layers');
    });

    testWidgets('unknown operator - the field is NOT disabled (unknownDisabledOp)', (tester) async {
      final harness = InputHarness([textFieldNode(disabledIf: const {'path': 'flags.off', 'op': 'between'})]);
      await harness.pump(tester);
      await tester.enterText(find.byType(TextField), 'x');
      expect(harness.writes, [('form.field', 'x')]);
    });

    testWidgets('no condition value, isEmpty - holds: the field is disabled (missingDisabledValue)', (tester) async {
      final harness = InputHarness([textFieldNode(disabledIf: const {'path': 'flags.none', 'op': 'isEmpty'})]);
      await harness.pump(tester);
      await tester.enterText(find.byType(TextField), 'x');
      expect(harness.writes, isEmpty);
    });

    testWidgets('no condition value, isTrue - silent: the field is enabled (missingDisabledValue)', (tester) async {
      final harness = InputHarness([textFieldNode(disabledIf: const {'path': 'flags.none', 'op': 'isTrue'})]);
      await harness.pump(tester);
      await tester.enterText(find.byType(TextField), 'x');
      expect(harness.writes, [('form.field', 'x')]);
    });

    testWidgets('a condition of broken shape - the field is enabled (the reader does not crash)', (tester) async {
      final harness = InputHarness([textFieldNode(disabledIf: 'yes')]);
      await harness.pump(tester);
      await tester.enterText(find.byType(TextField), 'x');
      expect(harness.writes, [('form.field', 'x')]);
    });
  });

  // ───────────────────────────── autofill ─────────────────────────────

  group('autofill (inputAutofill)', () {
    testWidgets('by default - hints from the keyboard intent', (tester) async {
      final harness = InputHarness([
        textFieldNode(id: 'e', path: 'form.e', keyboard: 'email'),
        textFieldNode(id: 'p', path: 'form.p', keyboard: 'phone'),
        textFieldNode(id: 'u', path: 'form.u', keyboard: 'url'),
        textFieldNode(id: 'n', path: 'form.n', keyboard: 'number'),
        textFieldNode(id: 't', path: 'form.t'),
      ]);
      await harness.pump(tester);
      expect([for (var i = 0; i < 5; i += 1) _editableAt(tester, i).autofillHints ?? const <String>[]], [
        [AutofillHints.email],
        [AutofillHints.telephoneNumber],
        [AutofillHints.url],
        isEmpty,
        isEmpty,
      ]);
    });

    testWidgets('autofill: false - no hint at all, on no field', (tester) async {
      final harness = InputHarness(
        [
          textFieldNode(id: 'e', path: 'form.e', keyboard: 'email'),
          textFieldNode(id: 'p', path: 'form.p', keyboard: 'phone'),
          textFieldNode(id: 'u', path: 'form.u', keyboard: 'url'),
        ],
        autofill: false,
      );
      await harness.pump(tester);
      for (var i = 0; i < 3; i += 1) {
        expect(_editableAt(tester, i).autofillHints ?? const <String>[], isEmpty);
      }
    });

    testWidgets('the reader never asks for credentials, card, address or SMS code (document words are ignored)', (tester) async {
      const forbidden = [
        AutofillHints.password,
        AutofillHints.username,
        AutofillHints.newPassword,
        AutofillHints.creditCardNumber,
        AutofillHints.postalCode,
        AutofillHints.fullStreetAddress,
        AutofillHints.oneTimeCode,
      ];
      final harness = InputHarness([
        for (final word in ['password', 'username', 'creditCard', 'postalCode', 'oneTimeCode', 'address'])
          textFieldNode(id: word, path: 'form.$word', keyboard: word),
      ]);
      await harness.pump(tester);
      for (var i = 0; i < 6; i += 1) {
        final hints = _editableAt(tester, i).autofillHints ?? const <String>[];
        expect(hints, isEmpty, reason: 'unfamiliar intent - text, no hints');
        expect(hints.where(forbidden.contains), isEmpty);
        expect(_editableAt(tester, i).obscureText, isFalse);
      }
    });
  });

  // ───────────────────────────── on-screen keyboard ─────────────────────────────

  group('keyboard and the bottom zone (bottomZone.keyboard)', () {
    Json pinnedButton() => {
      'id': 'save',
      'type': 'Button',
      'props': {'label': literal('Save'), 'variant': 'primary', 'fullWidth': true, 'action': {'type': 'none'}},
      'pin': 'bottom',
    };

    Json navBar() => {
      'id': 'nav',
      'type': 'NavBar',
      'props': <String, Object?>{},
      'children': [
        {
          'id': 'i1',
          'type': 'NavItem',
          'props': {'icon': 'house', 'label': literal('Home'), 'action': {'type': 'navigate.section', 'params': {'screenId': 'main'}}},
        },
      ],
    };

    testWidgets('a focused field with a row under it stays above the keyboard (the host does not shrink the screen)', (tester) async {
      final fields = [
        for (var i = 0; i < 12; i += 1) textFieldNode(id: 'f$i', path: 'form.f$i', label: 'Field $i', helper: literal('Note $i')),
      ];
      final harness = InputHarness(fields, rootStyle: const {'padding': {'top': 'lg', 'bottom': 'lg', 'start': 'lg', 'end': 'lg'}});
      await harness.pump(tester, keyboard: 300);
      final last = find.byType(EditableText).last;
      await tester.ensureVisible(find.text('Field 0'));
      await _focus(tester, last);
      await tester.pumpAndSettle();
      final block = tester.getRect(find.byType(InputTextField).last);
      expect(block.bottom, lessThanOrEqualTo(568 - 300 + 0.5), reason: 'the field with its hint is above the keyboard');
      expect(find.text('Note 11'), findsOneWidget);
    });

    testWidgets('the keyboard rises AFTER the focus (as on a device): the scroll follows the inset, the field with its note ends above the pinned block', (tester) async {
      final fields = [
        for (var i = 0; i < 12; i += 1) textFieldNode(id: 'f$i', path: 'form.f$i', label: 'Field $i', helper: literal('Note $i')),
      ];
      final harness = InputHarness([...fields, pinnedButton(), navBar()], rootStyle: const {'padding': {'top': 'lg', 'bottom': 'lg', 'start': 'lg', 'end': 'lg'}});
      // No keyboard yet: focus a field that is far down the body, scrolled into view by hand.
      await harness.pump(tester, safeBottom: 34, settle: true);
      final last = find.byType(EditableText).last;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      await _focus(tester, last);
      await tester.pumpAndSettle();
      // The keyboard slides in over several frames, the way the platform reports it.
      for (final height in [80.0, 160.0, 240.0, 300.0]) {
        await harness.pump(tester, keyboard: height, safeBottom: 34);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      final block = tester.getRect(find.byType(InputTextField).last);
      final pinned = tester.getRect(find.text('Save'));
      expect(pinned.bottom, lessThanOrEqualTo(568 - 300 + 0.5), reason: 'the pinned block rides above the keyboard');
      expect(block.bottom, lessThanOrEqualTo(pinned.top + 0.5), reason: 'the field with its note is in the body area, above the pinned block');
      expect(block.top, greaterThanOrEqualTo(0), reason: 'and is not pushed out through the top');
    });

    // The focused block keeps the tail of the body under it (`rules.focus.visible`).
    List<Json> formFields() => [
      for (var i = 0; i < 12; i += 1) textFieldNode(id: 'f$i', path: 'form.f$i', label: 'Field $i', helper: literal('Note $i')),
    ];

    Future<void> focusLast(WidgetTester tester, List<Json> children, {Json? rootStyle, String gap = 'md'}) async {
      final harness = InputHarness(children, rootStyle: rootStyle, gap: gap);
      await harness.pump(tester, settle: true);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      await _focus(tester, find.byType(EditableText).last);
      await tester.pumpAndSettle();
      await harness.pump(tester, keyboard: 300);
      await tester.pumpAndSettle();
    }

    testWidgets('with a pinned block: the field with its note ends one screen gap above the block', (tester) async {
      await focusLast(tester, [...formFields(), pinnedButton()], rootStyle: const {'padding': {'top': 'lg', 'bottom': 'lg', 'start': 'lg', 'end': 'lg'}});
      final block = tester.getRect(find.byType(InputTextField).last);
      final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
      final body = zones.firstChild!;
      final bodyBottom = (body.localToGlobal(Offset.zero) & body.size).bottom;
      final gap = RenderTheme.fallback().space(SpacingToken.md);
      expect(gap, greaterThan(0));
      expect(bodyBottom - block.bottom, closeTo(gap, 1), reason: 'the screen gap stays under the note');
    });

    testWidgets('without a pinned block: the field with its note ends one root bottom padding above the keyboard', (tester) async {
      await focusLast(tester, formFields(), gap: 'none', rootStyle: const {'padding': {'top': 'lg', 'bottom': 'xl', 'start': 'lg', 'end': 'lg'}});
      final block = tester.getRect(find.byType(InputTextField).last);
      final padding = RenderTheme.fallback().space(SpacingToken.xl);
      expect(padding, greaterThan(0));
      expect((568 - 300) - block.bottom, closeTo(padding, 1));
    });

    testWidgets('a block already visible together with its tail does not scroll', (tester) async {
      final harness = InputHarness([...formFields().take(3), pinnedButton()], gap: 'md');
      await harness.pump(tester, settle: true);
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final before = position.pixels;
      await _focus(tester, find.byType(EditableText).first);
      await tester.pumpAndSettle();
      expect(position.pixels, before);
    });

    testWidgets('the pinned block rides ABOVE the keyboard, the bar stays under it, there is no safe inset above the keyboard', (tester) async {
      Future<(Rect, Rect, Rect)> measure(double keyboard) async {
        final harness = InputHarness([textFieldNode(), pinnedButton(), navBar()]);
        await harness.pump(tester, keyboard: keyboard, safeBottom: 34, settle: true);
        final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
        final body = zones.firstChild!;
        final pinned = zones.childAfter(body)!;
        Rect rect(RenderBox box) => box.localToGlobal(Offset.zero) & box.size;
        return (rect(body), rect(pinned), rect(zones.lastChild!));
      }

      final closed = await measure(0);
      final open = await measure(300);
      // Keyboard closed: the block above the bar, the bar down to the screen bottom.
      expect(closed.$3.bottom, 568);
      expect(closed.$2.bottom, closed.$3.top);
      // Open: the block above the keyboard - its bottom exactly at the keyboard top; the bar under it.
      expect(open.$2.bottom, 568 - 300, reason: 'the block stands on the keyboard');
      expect(open.$3.top, 568 - 300, reason: 'the bar is under the keyboard');
      expect(open.$1.bottom, open.$2.top, reason: 'the body ends above the block');
    });

    testWidgets('the host already shrank the screen (resizeToAvoidBottomInset): zero in the reader context, nothing is subtracted twice', (tester) async {
      final fields = [for (var i = 0; i < 3; i += 1) textFieldNode(id: 'f$i', path: 'form.f$i', label: 'Field $i')];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      final doc = inputDoc([...fields, pinnedButton()]);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
            child: Scaffold(
              // Scaffold shrinks the body and REMOVES the inset from the body MediaQuery.
              resizeToAvoidBottomInset: true,
              body: Builder(
                builder: (context) {
                  expect(MediaQuery.viewInsetsOf(context).bottom, 0, reason: 'an inset the host already accounted for does not reach the reader');
                  return renderDocument(doc, theme: RenderTheme.fallback(), data: const {});
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pinned = tester.getRect(find.text('Save'));
      expect(pinned.bottom, lessThanOrEqualTo(568 - 300 + 0.5), reason: 'the block is above the keyboard once');
      expect(pinned.bottom, greaterThan(568 - 300 - 80), reason: 'and not lifted a second time');
    });

    testWidgets('a screen without a bottom zone: the body ends above the keyboard', (tester) async {
      final harness = InputHarness([textFieldNode()]);
      await harness.pump(tester, keyboard: 300, settle: true);
      final zones = tester.renderObject<RenderScreenZones>(find.byType(ScreenZones).last);
      final body = zones.firstChild!;
      expect((body.localToGlobal(Offset.zero) & body.size).bottom, 568 - 300);
    });
  });

  // ───────────────────────────── field state across rebuilds ─────────────────────────────

  group('field state does not move across rebuilds', () {
    testWidgets('a field that appeared above another does not hand it the typed text (state by node key)', (tester) async {
      final doc = _flow([
        _screen('a', [
          {...textFieldNode(id: 'first', path: 'form.first', label: 'First'), 'visibleIf': {'path': 'flags.show', 'op': 'isTrue'}},
          textFieldNode(id: 'second', path: 'form.second', label: 'Second'),
          toggleNode('Switch', path: 'flags.show', label: 'Show'),
        ]),
      ]);
      await pumpDocument(tester, doc);
      await tester.enterText(find.byType(TextField), 'typed in second');
      await tester.pump();
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(_editableAt(tester, 0).controller.text, '', reason: 'the new field on top is empty');
      expect(_editableAt(tester, 1).controller.text, 'typed in second');
    });
  });

  // ───────────────────────────── field in a list ─────────────────────────────

  group('inputInsideRepeater: the field is painted in every instance and writes by its own path', () {
    testWidgets('two instances - one path; the write does not invent a path from the instance record', (tester) async {
      final harness = InputHarness(
        [
          {
            'id': 'list',
            'type': 'Repeater',
            'props': {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'},
            'children': [textFieldNode(path: 'form.field')],
          },
        ],
        data: {
          'items': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        },
      );
      await harness.pump(tester);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).last, 'x');
      expect(harness.writes, [('form.field', 'x')]);
    });
  });

  // ───────────────────────────── untrusted input ─────────────────────────────

  group('a field in a place with infinite width', () {
    testWidgets('a sideways-scrolling row: field, switch and checkbox paint, the screen does not crash', (tester) async {
      final harness = InputHarness([
        {
          'id': 'row',
          'type': 'Row',
          'props': {'gap': 'sm', 'scrollable': true},
          'children': [textFieldNode(), toggleNode('Switch'), toggleNode('Checkbox', id: 'cb', label: 'Cb')],
        },
      ]);
      await harness.pump(tester, settle: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(InputTextField), findsOneWidget);
      expect(find.byType(InputToggle), findsNWidgets(2));
    });
  });

  group('untrusted input', () {
    testWidgets('a value from data is text: markup in it stays as letters', (tester) async {
      const hostile = '<script>alert(1)</script> \u202eurl(https://evil.example)';
      final harness = InputHarness([textFieldNode()], session: {'form.field': hostile});
      await harness.pump(tester);
      expect(_editableAt(tester).controller.text, hostile);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard with the wrong word, lines 1000, negative maxLength, value as a literal, a path of the wrong type - no crash', (tester) async {
      final harness = InputHarness([
        textFieldNode(id: 'a', path: 'form.a', keyboard: 'pass word'),
        textFieldNode(id: 'b', path: 'form.b', lines: 1000),
        textFieldNode(id: 'c', path: 'form.c', maxLength: -5),
        textFieldNode(id: 'd', value: literal('Alex')),
        textFieldNode(id: 'e', path: 'user.points'),
        toggleNode('Switch', id: 'f', label: 'Literal', value: literal('true')),
        toggleNode('Checkbox', id: 'g', label: 'Mismatch', path: 'form.email'),
      ], session: {'user.points': 1250, 'form.email': 'a@b.c'});
      await harness.pump(tester);
      expect(tester.takeException(), isNull);
      expect(_editableAt(tester, 4).controller.text, '', reason: 'a number under a text path - an empty field');
      await tester.enterText(find.byType(TextField).at(2), 'x' * 30);
      expect(_editableAt(tester, 2).controller.text, 'x' * 30, reason: 'a negative limit - no limits');
      await tester.tap(find.text('Mismatch'));
      await tester.tap(find.text('Literal'));
      await tester.pump();
      // A checkbox on a string path reads as disabled and writes a bool by its own path;
      // a switch with a literal is local only.
      expect([for (final w in harness.writes) if (w.$1 == 'form.email') w.$2], [true]);
    });

    testWidgets('style.color and style.typography are not read on fields - neither named nor inherited', (tester) async {
      final harness = InputHarness(
        [
          {
            'id': 'card',
            'type': 'Container',
            'props': {'direction': 'column'},
            'style': {'color': 'danger', 'typography': {'token': 'titleL'}},
            'children': [
              textFieldNode(
                helper: literal('Help'),
                style: {'color': 'danger', 'typography': {'token': 'titleL'}},
              ),
              toggleNode('Switch', style: {'color': 'danger'}),
            ],
          },
        ],
      );
      await harness.pump(tester);
      final plain = InputHarness([textFieldNode(helper: literal('Help')), toggleNode('Switch')]);
      TextStyle styleOf(String text) => tester.widget<Text>(find.text(text)).style!;
      final styled = (styleOf('Help'), styleOf('Push'), _editableAt(tester).style);
      await plain.pump(tester);
      expect(styleOf('Help'), styled.$1);
      expect(styleOf('Push'), styled.$2);
      expect(_editableAt(tester).style, styled.$3);
    });

    testWidgets('node style is the box of the whole widget: margin, size, background', (tester) async {
      final harness = InputHarness([
        textFieldNode(style: const {'margin': {'top': 8, 'start': 8}, 'width': 240, 'background': {'kind': 'color', 'color': 'secondary'}}),
      ]);
      await harness.pump(tester);
      final rect = tester.getRect(find.byType(InputTextField));
      expect(rect.left, 8);
      expect(rect.top, 8);
      expect(rect.width, 240);
    });
  });

  // ───────────────────────────── semantics ─────────────────────────────

  group('semantics', () {
    testWidgets('text field: the name is the label, the description is the hint, the placeholder does not become the name', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = InputHarness([textFieldNode(helper: literal('We send the receipt here'), placeholder: literal('you@example.com'))]);
      await harness.pump(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Email'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isTextField, isTrue);
      expect(data.label, contains('Email'));
      expect(data.label, isNot(contains('you@example.com')));
      expect(data.hint, contains('We send the receipt here'));
      semantics.dispose();
    });

    testWidgets('error: the field is invalid, the error line is announced politely (liveRegion)', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = InputHarness([textFieldNode(error: literal('Enter a valid email'))]);
      await harness.pump(tester);
      final data = tester.getSemantics(find.bySemanticsLabel('Email')).getSemanticsData();
      expect(data.validationResult, SemanticsValidationResult.invalid);
      expect(data.hint, contains('Enter a valid email'));
      final live = tester.getSemantics(find.text('Enter a valid email'));
      expect(live.flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });

    testWidgets('switch: switch role and state; checkbox: checked / not, with no "indeterminate"', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = InputHarness([
        toggleNode('Switch', id: 's', path: 'form.s', label: 'Sw'),
        toggleNode('Checkbox', id: 'c', path: 'form.c', label: 'Cb'),
      ], session: {'form.s': true, 'form.c': false});
      await harness.pump(tester);
      final sw = tester.getSemantics(find.bySemanticsLabel('Sw'));
      expect(sw.flagsCollection.isToggled, Tristate.isTrue);
      expect(sw.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final cb = tester.getSemantics(find.bySemanticsLabel('Cb'));
      expect(cb.flagsCollection.isChecked, CheckedState.isFalse);
      semantics.dispose();
    });

    testWidgets('empty label (a document built by someone else): a nameless field paints, the placeholder does not become the name', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = InputHarness([textFieldNode(label: '', placeholder: literal('Hint'))]);
      await harness.pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      final data = tester.getSemantics(find.byType(TextField)).getSemanticsData();
      expect(data.label, isNot(contains('Hint')));
      semantics.dispose();
    });
  });

  // ───────────────────────────── visual states ─────────────────────────────

  group('field states: the box size does not change', () {
    testWidgets('focus: primary border + inner ring; error is stronger; same size', (tester) async {
      final harness = InputHarness([textFieldNode(error: literal('Bad'))], session: const {});
      final plain = InputHarness([textFieldNode()]);
      await plain.pump(tester);
      final before = tester.getSize(find.byType(InputTextField));
      Container box() => tester.widget<Container>(find.descendant(of: find.byType(InputTextField), matching: find.byType(Container)).first);
      Color borderColor() => ((box().decoration! as BoxDecoration).border! as Border).top.color;
      final idleColor = borderColor();
      await _focus(tester, find.byType(EditableText));
      await tester.pump();
      expect(borderColor(), isNot(idleColor), reason: 'in focus - the primary border');
      expect(tester.getSize(find.byType(InputTextField)), before, reason: 'the box size does not change in focus');
      final ring = tester.widgetList<Container>(find.descendant(of: find.byType(InputTextField), matching: find.byType(Container))).where((c) => c.foregroundDecoration != null);
      expect(ring, hasLength(1), reason: 'the ring exists only in focus');

      await harness.pump(tester);
      final errorColor = borderColor();
      await _focus(tester, find.byType(EditableText));
      await tester.pump();
      expect(borderColor(), errorColor, reason: 'error is stronger than focus: the border stays danger');
    });
  });
}
