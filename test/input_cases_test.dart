/// INPUT FIELDS (schema 9.13.0): `TextField`,
/// `Switch`, `Checkbox`.
///
/// The tests read the table ITSELF (`contract/fixtures/inputs/input-cases.json`, all
/// fourteen groups, 250 rows) and run the rows twice: with the reader formula
/// (`input_rules.dart`) and with a REAL widget (`tester.enterText`, `tester.tap`,
/// focus, write sequences). The expectation in the table is written by hand, not
/// taken from a call to the reference, and does not change.
///
/// The reader does not execute the `documentCases` group (it does not need the
/// validator sentences): here it is checked differently - the reader PAINTS every
/// table document without crashing, and paints what it read.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/render/inputs.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/inputs.dart';

final Json _table = (json.decode(File('assets/contract/fixtures/inputs/input-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();
Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
String _name(Json row) => (row['name'] ?? row['note'] ?? row.toString()) as String;

Finder get _field => find.byType(TextField);

/// A person touched the field: focus and the on-screen keyboard. The test connection to the
/// platform needs a second call after the frame, otherwise nobody is there to accept the keyboard
/// action and value.
Future<void> _openKeyboard(WidgetTester tester, Finder field) async {
  await tester.showKeyboard(field);
  await tester.pump();
  await tester.showKeyboard(field);
}
EditableText _editable(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText));
String _shown(WidgetTester tester) => _editable(tester).controller.text;

void main() {
  test('table 9.13.0: exactly fourteen groups and 250 rows (the 9.14.0 groups are in form_cases_test)', () {
    // The 9.13.0 groups stand before `formAbout`; the twelve 9.14.0 groups come after it.
    final keys = _table.keys.toList();
    final groups = keys.sublist(0, keys.indexOf('formAbout')).where((key) => key != 'about').toList();
    expect(groups, hasLength(14));
    expect(groups.fold<int>(0, (sum, key) => sum + _rows(key).length), 250);
  });

  // ───────────────────────────── pathCases ─────────────────────────────

  group('pathCases: the path as the reader sees it', () {
    for (final row in _rows('pathCases')) {
      test(_name(row), () => expect(inputPathOf(row['value']), row['path']));
    }
  });

  // ───────────────────────────── readCases ─────────────────────────────

  group('readCases: what is read from the data layers', () {
    ScreenData layersOf(Json row) {
      final layers = _obj(row['layers']);
      return ScreenData.scoped(
        document: (layers['data'] as Map?)?.cast<String, Object?>() ?? const {},
        record: (layers['record'] as Map?)?.cast<String, Object?>(),
        session: (layers['session'] as Map?)?.cast<String, Object?>() ?? const {},
        scope: (layers['host'] as Map?)?.cast<String, Object?>() ?? const {},
      );
    }

    for (final row in _rows('readCases')) {
      final isText = row['type'] == 'string';
      test('formula: ${_name(row)}', () {
        final value = layersOf(row).lookup(row['path']! as String);
        if (isText) {
          expect(readInputText(value), row['text']);
        } else {
          expect(readInputFlag(value), row['on']);
        }
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final semantics = isText ? null : tester.ensureSemantics();
        final layers = _obj(row['layers']);
        final path = row['path']! as String;
        final record = (layers['record'] as Map?)?.cast<String, Object?>();
        final host = (layers['host'] as Map?)?.cast<String, Object?>() ?? const {};
        final doc = inputDoc([
          isText
              ? textFieldNode(path: path)
              : toggleNode('Switch', path: path),
        ]);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: renderScreen(
                doc.initialScreen,
                theme: RenderTheme.fallback(),
                data: (layers['data'] as Map?)?.cast<String, Object?>() ?? const {},
                record: record,
                session: (layers['session'] as Map?)?.cast<String, Object?>() ?? const {},
                scopeFor: (_) => host,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (isText) {
          expect(_shown(tester), row['text']);
        } else {
          expect(
            tester.getSemantics(find.bySemanticsLabel('Push')).flagsCollection.isToggled,
            row['on'] == true ? Tristate.isTrue : Tristate.isFalse,
          );
        }
        semantics?.dispose();
      });
    }
  });

  // ───────────────────────────── textCases ─────────────────────────────

  group('textCases: event sequences of the text field', () {
    TextInputEvent? eventOf(Json step) => switch (step['type']) {
      'focus' => const FocusEvent(),
      'blur' => const BlurEvent(),
      'input' => InputEvent(step['text']! as String),
      'compositionStart' => const CompositionStartEvent(),
      'compositionEnd' => CompositionEndEvent(step['text']! as String),
      'platformFill' => PlatformFillEvent(step['text']! as String),
      _ => null, // `data` is a layer event, not a field one
    };

    for (final row in _rows('textCases')) {
      final steps = (row['steps']! as List<Object?>).cast<Json>();
      final disabled = row['disabled'] == true;
      final hasPath = row['hasPath'] != false;
      final maxLength = row['maxLength'];

      test('formula: ${_name(row)}', () {
        var bound = row['bound']! as String;
        var state = kInitialTextInput;
        final writes = <String>[];
        for (final step in steps) {
          if (step['type'] == 'data') {
            bound = step['bound']! as String;
            state = syncTextInput(state, bound);
            continue;
          }
          final result = stepTextInput(state, eventOf(step)!, bound, maxLength: maxLength, disabled: disabled, hasPath: hasPath);
          state = result.state;
          if (result.write != null) writes.add(result.write!);
        }
        expect(writes, row['writes']);
        expect(shownInputText(state, bound), row['shown']);
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final harness = InputHarness(
          [
            textFieldNode(
              value: hasPath ? defaultValue : absentValue,
              maxLength: maxLength,
              lines: (row['name']! as String).startsWith('multi-line') ? 3 : null,
              disabledIf: disabled ? const {'path': 'flags.off', 'op': 'isEmpty'} : null,
            ),
          ],
          session: {'form.field': row['bound']},
        );
        await harness.pump(tester);
        var composing = false;
        for (final step in steps) {
          switch (step['type']) {
            case 'data':
              await harness.setSession(tester, {'form.field': step['bound']});
            case 'focus':
              // A person touched the field: focus and the on-screen keyboard (the connection to the
              // platform opens exactly this way).
              await _openKeyboard(tester, _field);
              await tester.pump();
            case 'blur':
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pump();
            case 'compositionStart':
              composing = true;
            case 'input':
              final text = step['text']! as String;
              if (composing) {
                await tester.showKeyboard(_field);
                tester.testTextInput.updateEditingValue(
                  TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length), composing: TextRange(start: 0, end: text.length)),
                );
                await tester.idle();
              } else {
                await tester.enterText(_field, text);
              }
              await tester.pump();
            case 'compositionEnd':
              composing = false;
              final text = step['text']! as String;
              await tester.showKeyboard(_field);
              tester.testTextInput.updateEditingValue(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));
              await tester.idle();
              await tester.pump();
            case 'platformFill':
              final text = step['text']! as String;
              final value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
              final focused = _editable(tester).focusNode.hasFocus;
              if (focused) {
                await tester.showKeyboard(_field);
                tester.testTextInput.updateEditingValue(value);
                await tester.idle();
              } else {
                tester.state<EditableTextState>(find.byType(EditableText)).updateEditingValue(value);
              }
              await tester.pump();
          }
        }
        expect(tester.takeException(), isNull);
        expect([for (final (_, value) in harness.writes) value], row['writes'], reason: 'host writes');
        expect([for (final (path, _) in harness.writes) path], everyElement('form.field'), reason: 'writes only by the field path');
        expect(_shown(tester), row['shown'], reason: 'what is shown in the field');
      });
    }
  });

  // ───────────────────────────── toggleCases ─────────────────────────────

  group('toggleCases: switch and checkbox', () {
    for (final row in _rows('toggleCases')) {
      final steps = row['steps']! as List<Object?>;
      final disabled = row['disabled'] == true;
      final hasPath = row['hasPath'] != false;

      test('formula: ${_name(row)}', () {
        var bound = row['bound']! as bool;
        var state = kInitialToggle;
        final writes = <bool>[];
        for (final step in steps) {
          if (step is Map) {
            bound = step['data']! as bool;
            state = syncToggle(state, bound);
            continue;
          }
          final result = pressToggle(state, bound, disabled: disabled, hasPath: hasPath);
          state = result.state;
          if (result.write != null) writes.add(result.write!);
        }
        expect(writes, row['writes']);
        expect(shownToggle(state, bound), row['shown']);
      });

      for (final type in ['Switch', 'Checkbox']) {
        testWidgets('widget $type: ${_name(row)}', (tester) async {
          final semantics = tester.ensureSemantics();
          final harness = InputHarness(
            [
              toggleNode(
                type,
                value: hasPath ? defaultValue : absentValue,
                disabledIf: disabled ? const {'path': 'flags.off', 'op': 'isEmpty'} : null,
              ),
            ],
            session: {'form.flag': row['bound']},
          );
          await harness.pump(tester);
          for (final step in steps) {
            if (step is Map) {
              await harness.setSession(tester, {'form.flag': step['data']});
            } else {
              await tester.tap(find.text('Push'), warnIfMissed: false);
              await tester.pump();
            }
          }
          expect(tester.takeException(), isNull);
          expect([for (final (_, value) in harness.writes) value], row['writes']);
          final flags = tester.getSemantics(find.bySemanticsLabel('Push')).flagsCollection;
          final on = type == 'Switch' ? flags.isToggled == Tristate.isTrue : flags.isChecked == CheckedState.isTrue;
          expect(on, row['shown']);
          semantics.dispose();
        });
      }
    }
  });

  // ───────────────────────────── clampCases, linesCases ─────────────────────────────

  group('clampCases: length limit in code points', () {
    for (final row in _rows('clampCases')) {
      test('${row['text']} / ${row['maxLength']}${row['note'] == null ? '' : ' — ${row['note']}'}', () {
        expect(clampInputText(row['text']! as String, row['maxLength']), row['expect']);
      });
    }
  });

  group('linesCases: number of lines', () {
    for (final row in _rows('linesCases')) {
      test('${row['lines']}${row['note'] == null ? '' : ' — ${row['note']}'}', () {
        expect(inputLinesOf(row['lines']), row['expect']);
      });
    }
  });

  // ───────────────────────────── keyboardCases ─────────────────────────────

  group('keyboardCases: intent and platform equivalents', () {
    // A code-independent list: artifact words -> Flutter types.
    final types = <String, TextInputType>{
      'text': TextInputType.text,
      'emailAddress': TextInputType.emailAddress,
      'numberWithOptions(decimal: true)': const TextInputType.numberWithOptions(decimal: true),
      'phone': TextInputType.phone,
      'url': TextInputType.url,
    };

    for (final row in _rows('keyboardCases')) {
      final label = '${row['keyboard']} / lines ${row['lines']}${row['note'] == null ? '' : ' — ${row['note']}'}';

      test('formula: $label', () {
        final effective = effectiveInputKeyboardOf(row['keyboard'], row['lines']);
        expect(effective?.wire ?? 'multiline', row['expect']);
      });

      final flutter = row['flutter'] == null ? null : _obj(row['flutter']);
      if (flutter != null) {
        test('the platform table in code matches the row: $label', () {
          final platform = kInputKeyboardFlutter[inputKeyboardOf(row['keyboard'])]!;
          expect(platform.keyboardType, flutter['keyboardType']);
          expect(platform.autofillHints, flutter['autofillHints']);
        });
      }

      testWidgets('widget: $label', (tester) async {
        final harness = InputHarness([textFieldNode(keyboard: row['keyboard'], lines: row['lines'])]);
        await harness.pump(tester, settle: true);
        final editable = _editable(tester);
        if (row['expect'] == 'multiline') {
          expect(editable.keyboardType, TextInputType.multiline);
          expect(editable.autofillHints, anyOf(isNull, isEmpty), reason: 'a multi-line field reads no intents');
          return;
        }
        // A row without `flutter` (a note about an unfamiliar word, `lines: 1`) states only the intent:
        // the equivalents come from the test own list - from the platform table of the contract's input rules.
        const byIntent = <String, Json>{
          'text': {'keyboardType': 'text', 'autofillHints': <String>[]},
          'email': {'keyboardType': 'emailAddress', 'autofillHints': ['email']},
          'number': {'keyboardType': 'numberWithOptions(decimal: true)', 'autofillHints': <String>[]},
          'phone': {'keyboardType': 'phone', 'autofillHints': ['telephoneNumber']},
          'url': {'keyboardType': 'url', 'autofillHints': ['url']},
        };
        final want = flutter ?? byIntent[row['expect']]!;
        expect(editable.keyboardType, types[want['keyboardType']]);
        expect(editable.autofillHints ?? const <String>[], want['autofillHints']);
        // Capitals and spelling - only in `text`; off in the rest.
        final isText = row['expect'] == 'text';
        expect(editable.textCapitalization, isText ? TextCapitalization.sentences : TextCapitalization.none);
        expect(editable.autocorrect, isText);
        // There is no password: the field is never hidden.
        expect(editable.obscureText, isFalse);
      });
    }
  });

  // ───────────────────────────── keyActionCases ─────────────────────────────

  group('keyActionCases: keyboard button', () {
    for (final row in _rows('keyActionCases')) {
      final fields = (row['fields']! as List<Object?>).cast<Json>();
      final index = row['index']! as int;

      test('formula: ${_name(row)}', () {
        final list = [for (final f in fields) (multiline: f['multiline']! as bool, reachable: f['reachable']! as bool)];
        expect(inputKeyActionOf(list, index).name, row['expect']);
        expect(nextInputIndexOf(list, index), row['next']);
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        var actions = 0;
        final harness = InputHarness(
          [
            for (var i = 0; i < fields.length; i += 1)
              textFieldNode(
                id: 'f$i',
                label: 'Field $i',
                path: 'form.f$i',
                lines: fields[i]['multiline']! as bool ? 3 : null,
                // "Unreachable" means disabled: the same as hidden, for the traversal order.
                disabledIf: fields[i]['reachable']! as bool ? null : const {'path': 'flags.off', 'op': 'isEmpty'},
              ),
            {
              'id': 'go',
              'type': 'Button',
              'props': {'label': literal('Go'), 'variant': 'primary', 'action': {'type': 'openUrl', 'params': {'url': 'https://example.com'}}},
            },
          ],
          onAction: (_, _) => actions += 1,
        );
        await harness.pump(tester, settle: true);
        final field = find.byType(TextField).at(index);
        await _openKeyboard(tester, find.descendant(of: field, matching: find.byType(EditableText)));
        await tester.pumpAndSettle();
        final editable = tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)));
        expect(
          editable.textInputAction,
          switch (row['expect']) {
            'newline' => TextInputAction.newline,
            'next' => TextInputAction.next,
            _ => TextInputAction.done,
          },
        );

        // The keyboard button was pressed.
        await tester.testTextInput.receiveAction(editable.textInputAction!);
        await tester.pumpAndSettle();
        expect(actions, 0, reason: 'the keyboard button never executes an action (inputKeyAction)');
        final next = row['next'];
        final focused = FocusManager.instance.primaryFocus;
        switch (row['expect']) {
          case 'next':
            final target = find.descendant(of: find.byType(TextField).at(next! as int), matching: find.byType(EditableText));
            expect(tester.widget<EditableText>(target).focusNode.hasFocus, isTrue, reason: 'focus on the next field');
          case 'done':
            expect(editable.focusNode.hasFocus, isFalse, reason: 'done: focus dropped');
            expect(focused?.debugLabel, isNot('sdui-input'));
          case 'newline':
            expect(editable.focusNode.hasFocus, isTrue, reason: 'new line: focus stays');
        }
      });
    }
  });

  // ───────────────────────────── errorCases ─────────────────────────────

  group('errorCases: error state', () {
    for (final row in _rows('errorCases')) {
      test('formula: ${_name(row)}', () => expect(inputErrorOf(row['error'] as String?), row['expect']));

      testWidgets('widget: ${_name(row)}', (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = InputHarness([
          textFieldNode(
            helper: literal('We send the receipt here'),
            error: row.containsKey('error') ? literal(row['error']! as String) : null,
          ),
        ]);
        await harness.pump(tester);
        final expected = row['expect'] as String?;
        if (expected == null) {
          expect(find.text('We send the receipt here'), findsOneWidget, reason: 'no error - the hint is in place');
        } else {
          // The table itself says what is SHOWN: on screen stands exactly `expect`.
          expect(find.text(expected), findsOneWidget);
          expect(find.text('We send the receipt here'), findsNothing, reason: 'the error is in place of the hint');
        }
        final data = tester.getSemantics(find.bySemanticsLabel('Email')).getSemanticsData();
        expect(data.validationResult, expected == null ? SemanticsValidationResult.none : SemanticsValidationResult.invalid);
        semantics.dispose();
      });
    }
  });

  // ───────────────────────────── geometryCases ─────────────────────────────

  group('geometryCases: numbers on the built-in theme', () {
    // The number of lines comes from the WIDTH, not from a break in the text (`\n` in shown text is a space):
    // n words, each taking almost the whole width of the place, so one fits per line.
    // The test font (Ahem) is squares as wide as the font size, so a word of `floor(width / size)`
    // characters fits a line exactly and never fits twice.
    String lines(int n, double width, double fontSize) {
      final word = 'W' * math.max(1, (width / fontSize).floor());
      return List.filled(n, word).join(' ');
    }

    RenderTheme themeWithBodyLine(double line) {
      final raw = (json.decode(File('assets/contract/theme.json').readAsStringSync()) as Map).cast<String, Object?>();
      final light = _obj(_obj(_obj(raw['contract'])['themes'])['light']);
      final typography = _obj(light['typography']);
      final bodyM = _obj(typography['bodyM']);
      bodyM['lineHeight'] = line / (bodyM['fontSize']! as num);
      return RenderTheme.fromJson(light);
    }

    // A field on a 320 screen with root padding `lg` (16): 288; the label and note are `bodyS` (12).
    const fieldContentWidth = 288.0;
    const fieldNoteFont = 12.0;

    final padding = {
      'padding': {'top': 'lg', 'bottom': 'lg', 'start': 'lg', 'end': 'lg'},
    };

    for (final row in _rows('geometryCases')) {
      final widget = row['widget'] as String;

      if (widget == 'TextField') {
        const metrics = (labelLine: 16.0, textLine: 20.0, noteLine: 16.0, gap: 4.0, paddingBlock: 12.0, border: 1.0);
        test('formula: ${_name(row)}', () {
          expect(textFieldBoxHeightOf(metrics, row['lines']), row['box']);
          expect(
            textFieldHeightOf(metrics, lines: row['lines'], labelLines: row['labelLines']! as int, noteLines: row['noteLines']! as int),
            row['height'],
          );
        });
        testWidgets('widget: ${_name(row)}', (tester) async {
          final noteLines = row['noteLines']! as int;
          final harness = InputHarness(
            [
              textFieldNode(
                label: lines(row['labelLines']! as int, fieldContentWidth, fieldNoteFont),
                helper: noteLines == 0 ? null : literal(lines(noteLines, fieldContentWidth, fieldNoteFont)),
                lines: row['lines'],
              ),
            ],
            rootStyle: padding,
          );
          await harness.pump(tester);
          expect(tester.takeException(), isNull);
          expect(tester.getSize(find.byType(InputTextField)).height, closeTo((row['height']! as num).toDouble(), 0.01));
          // The field box is exactly the given height.
          final box = find.descendant(of: find.byType(InputTextField), matching: find.byType(Container)).first;
          expect(tester.getSize(box).height, closeTo((row['box']! as num).toDouble(), 0.01));
        });
        continue;
      }

      if (row.containsKey('thumbOffset')) {
        testWidgets('widget: ${_name(row)}', (tester) async {
          final harness = InputHarness([toggleNode('Switch')], session: {'form.flag': row['on']}, rootStyle: padding);
          await harness.pump(tester);
          final track = tester.getTopLeft(find.byKey(const ValueKey('sdui-switch-track')));
          final thumb = tester.getTopLeft(find.byKey(const ValueKey('sdui-switch-thumb')));
          expect(thumb.dx - track.dx, row['thumbOffset']);
        });
        test('formula: ${_name(row)}', () => expect(switchThumbOffsetOf(row['on']! as bool), row['thumbOffset']));
        continue;
      }

      final rowWidth = (row['rowWidth']! as num).toDouble();
      final labelLines = row['labelLines']! as int;
      final labelLine = (row['labelLine'] as num?)?.toDouble() ?? 20;
      final isSwitch = widget == 'Switch';
      final gap = isSwitch ? 12.0 : 8.0;

      test('formula: ${_name(row)}', () {
        if (isSwitch) {
          expect(switchLabelWidthOf(rowWidth, gap), row['labelWidth']);
          expect(switchHeightOf(labelLine, labelLines), row['height']);
        } else {
          expect(checkboxLabelWidthOf(rowWidth, gap), row['labelWidth']);
          expect(checkboxHeightOf(labelLine, labelLines), row['height']);
          expect(checkboxBoxOffsetOf(labelLine), row['boxOffset']);
        }
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final harness = InputHarness(
          [toggleNode(widget, label: lines(labelLines, (row['labelWidth']! as num).toDouble(), 14))],
          rootStyle: padding,
          theme: labelLine == 20 ? null : themeWithBodyLine(labelLine),
        );
        await harness.pump(tester, width: rowWidth + 32);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(InputToggle)).height, closeTo((row['height']! as num).toDouble(), 0.01));
        expect(tester.getSize(find.byType(InputToggle)).width, rowWidth);
        if (row['labelWidth'] == 0) {
          // A label without width is not painted (at zero it would wrap by letter).
          expect(find.text(lines(labelLines, (row['labelWidth']! as num).toDouble(), 14)), findsNothing);
          return;
        }
        final label = tester.getSize(find.text(lines(labelLines, (row['labelWidth']! as num).toDouble(), 14)));
        expect(label.width, closeTo((row['labelWidth']! as num).toDouble(), 0.01));
        if (!isSwitch) {
          final box = tester.getTopLeft(find.byKey(const ValueKey('sdui-checkbox-box')));
          final text = tester.getTopLeft(find.text(lines(labelLines, (row['labelWidth']! as num).toDouble(), 14)));
          expect(box.dy - text.dy, closeTo((row['boxOffset']! as num).toDouble(), 0.01));
        }
      });
    }
  });

  // ───────────────────────────── directionCases ─────────────────────────────

  group('directionCases: right-to-left writing', () {
    for (final row in _rows('directionCases')) {
      final widget = row['widget'] as String;
      final rtl = row['direction'] == 'rtl';

      testWidgets(_name(row), (tester) async {
        if (widget == 'TextField') {
          final harness = InputHarness([
            textFieldNode(placeholder: literal('Hint'), keyboard: row['keyboard'], lines: row['lines']),
          ]);
          await harness.pump(tester, direction: rtl ? TextDirection.rtl : TextDirection.ltr);
          final editable = _editable(tester);
          expect(editable.textAlign, row['textAlign'] == 'right' ? TextAlign.right : TextAlign.left, reason: 'alignment from the SCREEN start');
          expect(editable.textDirection, row['content'] == 'left-to-right' ? TextDirection.ltr : isNull, reason: 'content direction');
          // The placeholder stands near the screen start.
          final box = tester.getRect(find.byType(EditableText));
          final hint = tester.getRect(find.text('Hint'));
          if (rtl) {
            expect(box.right - hint.right, lessThan(1), reason: 'placeholder from the right edge');
          } else {
            expect(hint.left - box.left, lessThan(1), reason: 'placeholder from the left edge');
          }
          return;
        }
        final harness = InputHarness([toggleNode(widget)], session: {'form.flag': true});
        await harness.pump(tester, direction: rtl ? TextDirection.rtl : TextDirection.ltr);
        final row0 = tester.getRect(find.byType(InputToggle));
        final control = widget == 'Switch'
            ? tester.getRect(find.byKey(const ValueKey('sdui-switch-track')))
            : tester.getRect(find.byKey(const ValueKey('sdui-checkbox-box')));
        expect(control.center.dx < row0.center.dx ? 'left' : 'right', row['controlSide']);
        if (widget == 'Switch') {
          final thumb = tester.getRect(find.byKey(const ValueKey('sdui-switch-thumb')));
          expect(thumb.center.dx < control.center.dx ? 'left' : 'right', row['thumbOnSide']);
        }
      });
    }

    testWidgets('the checkbox tick is not mirrored in RTL (it is not in x-mirroredIcons)', (tester) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        final harness = InputHarness([toggleNode('Checkbox')], session: {'form.flag': true});
        await harness.pump(tester, direction: direction);
        final painter = tester.widget<CustomPaint>(
          find.descendant(of: find.byKey(const ValueKey('sdui-checkbox-box')), matching: find.byType(CustomPaint)),
        );
        expect((painter.painter! as dynamic).mirrored, isFalse, reason: '$direction');
      }
    });
  });

  // ───────────────────────────── documentCases ─────────────────────────────

  group('documentCases: the reader paints what it read and does not crash', () {
    for (final row in _rows('documentCases')) {
      testWidgets(_name(row), (tester) async {
        final node = _obj(row['node']);
        if (row['pin'] != null) node['pin'] = row['pin'];
        final inRepeater = row['inRepeater'] == true;
        final harness = InputHarness(
          [
            inRepeater
                ? {
                    'id': 'list',
                    'type': 'Repeater',
                    'props': {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'},
                    'children': [node],
                  }
                : node,
          ],
          data: {
            'items': [
              {'id': 'a'},
              {'id': 'b'},
            ],
            // So that `visibleIf` on the field shows it.
            'form.agreed': true,
          },
        );
        await harness.pump(tester);
        expect(tester.takeException(), isNull);
        final type = node['type'] as String;
        final finder = type == 'TextField' ? find.byType(InputTextField) : find.byType(InputToggle);
        expect(finder, inRepeater ? findsNWidgets(2) : findsOneWidget, reason: 'the node is painted');

        final props = _obj(node['props']);
        if (type == 'TextField') {
          final editable = tester.widgetList<EditableText>(find.byType(EditableText)).first;
          expect(editable.obscureText, isFalse, reason: '${props['keyboard']}: there is no password');
          // A bound the reader does not understand (0) means no bounds.
          if (props['maxLength'] == 0) {
            await tester.enterText(_field.first, 'x' * 50);
            expect(tester.widgetList<EditableText>(find.byType(EditableText)).first.controller.text.length, 50);
          }
          // `lines` outside bounds or a fraction - one line.
          if (props.containsKey('lines')) expect(editable.maxLines, 1);
        }
      });
    }
  });

  // ───────────────────────────── placementCases ─────────────────────────────

  group('placementCases: a field in the wrong place does not break the screen', () {
    Json parentWith(String type, Json child) => switch (type) {
      'Screen' => child,
      'Column' => {'id': 'p', 'type': 'Column', 'props': {'gap': 'none'}, 'children': [child]},
      'Row' => {'id': 'p', 'type': 'Row', 'props': {'gap': 'none'}, 'children': [child]},
      'Container' => {'id': 'p', 'type': 'Container', 'props': {'direction': 'column'}, 'children': [child]},
      'Tab' => {
        'id': 'p',
        'type': 'Tabs',
        'props': {'initialTab': 0},
        'children': [
          {'id': 't', 'type': 'Tab', 'props': {'title': literal('One')}, 'children': [child]},
        ],
      },
      'Repeater' => {
        'id': 'p',
        'type': 'Repeater',
        'props': {'source': 'items', 'item': 'item', 'direction': 'column', 'gap': 'none'},
        'children': [child],
      },
      'Grid' => {'id': 'p', 'type': 'Grid', 'props': {'columns': 2, 'gap': 'none'}, 'children': [child]},
      'Stack' => {'id': 'p', 'type': 'Stack', 'props': {}, 'children': [child]},
      'Accordion' => {
        'id': 'p',
        'type': 'Accordion',
        'props': {'title': literal('Title'), 'initiallyExpanded': true},
        'children': [child],
      },
      'ChoiceGroup' => {'id': 'p', 'type': 'ChoiceGroup', 'props': {'value': literal('x'), 'gap': 'none'}, 'children': [child]},
      'AppBar' => {'id': 'p', 'type': 'AppBar', 'props': {'title': literal('Bar'), 'showBack': false}, 'children': [child]},
      'NavBar' => {'id': 'p', 'type': 'NavBar', 'props': {}, 'children': [child]},
      _ => throw StateError(type),
    };

    for (final row in _rows('placementCases')) {
      final parent = row['parent']! as String;
      for (final kind in ['TextField', 'Switch', 'Checkbox']) {
        testWidgets('$kind in $parent (${row['accepts'] == true ? 'legal' : 'the contract rejects it'})', (tester) async {
          final child = kind == 'TextField' ? textFieldNode() : toggleNode(kind);
          final harness = InputHarness([parentWith(parent, child)], data: {
            'items': [
              {'id': 'a'},
            ],
          });
          await harness.pump(tester, settle: true);
          expect(tester.takeException(), isNull);
          final finder = kind == 'TextField' ? find.byType(InputTextField) : find.byType(InputToggle);
          if (parent == 'AppBar' || parent == 'NavBar') {
            // A bar paints only icon buttons, a nav bar only items: foreign nodes are not painted.
            expect(finder, findsNothing);
          } else {
            expect(finder, findsOneWidget);
          }
        });
      }
    }
  });

  // ───────────────────────────── ruleCases ─────────────────────────────

  group('ruleCases: rules as data - the artifact and the code mirror', () {
    final inputs = _obj(_obj(_obj(_schema['x-style'])['layout'])['inputs']);

    Object? at(Object? node, String path) {
      var current = node;
      for (final key in path.split('.')) {
        current = (current as Map)[key];
      }
      return current;
    }

    // Numbers and words the reader keeps in its OWN mirror.
    final mirror = <String, Object?>{
      'rules.disabled.look.opacity': kInputDisabledOpacity,
      'textField.lines.max': kTextFieldMaxLines,
      'textField.box.border': {'width': kTextFieldBorderWidth, 'color': 'border'},
      'switch.thumb.size': kSwitchThumbSize,
      'switch.thumb.inset': kSwitchThumbInset,
      'switch.track': {'width': kSwitchTrackWidth, 'height': kSwitchTrackHeight, 'radius': 'pill'},
      'checkbox.box': {'size': kCheckboxBoxSize, 'radius': kCheckboxBoxRadius, 'border': {'width': kCheckboxBorderWidth}},
      'checkbox.mark': {'icon': 'check', 'size': kCheckboxMarkSize, 'shown': 'when-on'},
    };

    for (final row in _rows('ruleCases')) {
      final path = row['at']! as String;
      test(path, () {
        final found = at(inputs, path);
        final expected = row['expect'];
        if (expected is Map) {
          expect(found, expected);
        } else {
          expect(found, expected);
        }
        final dart = mirror[path];
        if (dart != null) {
          if (expected is Map) {
            for (final entry in (dart as Map).entries) {
              final want = expected[entry.key];
              if (want is Map) {
                for (final inner in (entry.value as Map).entries) {
                  expect((want)[inner.key], inner.value, reason: '$path.${entry.key}.${inner.key}');
                }
              } else {
                expect(want, entry.value, reason: '$path.${entry.key}');
              }
            }
          } else {
            expect(dart, expected, reason: 'mirror in code');
          }
        }
      });
    }

    test('the reader knows every key of the inputs block (a new key is a new decision)', () {
      expect(inputs.keys.toSet(), {'rules', 'textField', 'switch', 'checkbox', 'cases'});
      expect(_obj(inputs['rules']).keys.toSet(), {'value', 'write', 'shown', 'disabled', 'focus', 'keyAction', 'autofill', 'password'});
    });

    test('keyboard equivalents in code are exactly those in the artifact', () {
      final keyboards = _obj(_obj(inputs['textField'])['keyboards']);
      expect(keyboards.keys.toSet(), InputKeyboard.values.map((k) => k.wire).toSet());
      for (final keyboard in InputKeyboard.values) {
        final flutter = _obj(_obj(keyboards[keyboard.wire])['flutter']);
        final mine = kInputKeyboardFlutter[keyboard]!;
        expect(mine.keyboardType, flutter['keyboardType'], reason: keyboard.wire);
        expect(mine.autofillHints, flutter['autofillHints'], reason: keyboard.wire);
        expect(mine.textCapitalization, flutter['textCapitalization'], reason: keyboard.wire);
        expect(mine.autocorrect, flutter['autocorrect'], reason: keyboard.wire);
      }
    });

    test('twenty policy rows of 9.13.0: the mirror matches the artifact and stands at the end', () {
      final compatibility = _obj(_schema['x-compatibility']);
      final policy = _obj(compatibility['policy']);
      expect(kInputsPolicy, hasLength(20));
      for (final entry in kInputsPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      // Next come fourteen 9.14.0 rows (`kFormPolicy`).
      expect(
        policy.keys.toList().sublist(policy.length - kFormPolicy.length - kInputsPolicy.length, policy.length - kFormPolicy.length),
        kInputsPolicy.keys.toList(),
      );

      final features = _obj(compatibility['features']);
      for (final feature in ['textField', 'toggles', 'inputDisabledIf']) {
        expect(features[feature], '9.13.0', reason: feature);
        expect(kFeatureCatalog[feature], '9.13.0', reason: feature);
        expect(supportsFeature(feature), isTrue, reason: feature);
        expect(supportsFeature(feature, readerVersion: '9.12.0'), isFalse, reason: feature);
      }
      final widgets = _obj(compatibility['widgets']);
      for (final widget in ['TextField', 'Switch', 'Checkbox']) {
        expect(widgets[widget], '9.13.0');
        expect(kWidgetCatalog[widget], '9.13.0');
        expect(widgetOriginOf(widget), WidgetOrigin.contractual);
        expect(widgetOriginOf(widget, readerVersion: '9.12.0'), isNot(WidgetOrigin.contractual));
      }
    });
  });
}
