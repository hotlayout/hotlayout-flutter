/// SURVEY FORM (schema 9.14.0):
/// "required", a disabled button, a number field, a choice group write.
///
/// The tests read the table ITSELF (`contract/fixtures/inputs/input-cases.json`,
/// twelve 9.14.0 groups, 300 rows) and run the rows twice: with the
/// reader formula (`input_rules.dart`, `form_rules.dart`) and with a REAL widget
/// (`tester.enterText`, `tester.tap`, focus, form state sequences).
/// The expectation in the table is written by hand and does not change.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart' show ButtonAction, TrackEvent;
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/compatibility.dart';
import 'package:hotlayout_flutter/src/model/form_rules.dart';
import 'package:hotlayout_flutter/src/model/input_rules.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/inputs.dart' show InputTextField;
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';

import 'support/fixtures.dart';
import 'support/inputs.dart';

final Json _table = (json.decode(File('assets/contract/fixtures/inputs/input-cases.json').readAsStringSync()) as Map)
    .cast<String, Object?>();
final Json _schema = (json.decode(File('assets/contract/screen-schema.json').readAsStringSync()) as Map)
    .cast<String, Object?>();

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();
Json _obj(Object? value) => (value! as Map).cast<String, Object?>();
String _name(Json row) => (row['name'] ?? row['note'] ?? row.toString()) as String;

const _groups = [
  'numberParseCases',
  'numberReadCases',
  'numberFieldCases',
  'numberInvalidAbout',
  'numberInvalidCases',
  'numberKeyboardCases',
  'filledCases',
  'formCases',
  'pressCases',
  'disabledLookCases',
  'choiceCases',
  'choiceSessionCases',
  'formDocumentCases',
  'formRuleCases',
];

Finder get _field => find.byType(TextField);
EditableText _editable(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText));
String _shown(WidgetTester tester) => _editable(tester).controller.text;

Future<void> _openKeyboard(WidgetTester tester, Finder field) async {
  await tester.showKeyboard(field);
  await tester.pump();
  await tester.showKeyboard(field);
}

void _view(WidgetTester tester, {double width = 320, double height = 568}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// A document with screens "identifier -> root children"; the first screen is the start one.
UiDocument _docOf(Map<String, List<Json>> screens) => UiDocument.fromJson({
  'schemaVersion': kSupportedSchemaVersion,
  'documentId': 'form',
  'name': 'form',
  'initialScreenId': screens.keys.first,
  'screens': [
    for (final entry in screens.entries)
      {
        'screenId': entry.key,
        'name': entry.key,
        'root': {
          'id': '${entry.key}-root',
          'type': 'Screen',
          'props': {'gap': 'none'},
          'children': entry.value,
        },
      },
  ],
});

Map<String, List<Json>> _screensOf(Json row) => {
  for (final entry in _obj(row['screens']).entries) entry.key: (entry.value! as List<Object?>).cast<Json>(),
};

Map<String, Object?>? _layer(Json layers, String name) => (layers[name] as Map?)?.cast<String, Object?>();

ScreenData _dataOf(Json layers) => ScreenData.scoped(
  document: _layer(layers, 'data') ?? const {},
  record: _layer(layers, 'record'),
  session: _layer(layers, 'session') ?? const {},
  scope: _layer(layers, 'host') ?? const {},
);

UiNode? _nodeById(UiNode node, String id) {
  if (node.id == id) return node;
  for (final child in node.children) {
    final found = _nodeById(child, id);
    if (found != null) return found;
  }
  return null;
}

Json? _jsonById(List<Object?> nodes, String id) {
  for (final raw in nodes) {
    final node = raw! as Json;
    if (node['id'] == id) return node;
    final found = _jsonById((node['children'] as List<Object?>?) ?? const [], id);
    if (found != null) return found;
  }
  return null;
}

/// A Material button by LABEL: the button text or the accessible name of an icon button.
Finder _buttonLabelled(String label) => find.ancestor(
  of: find.descendant(
    of: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    matching: find.byWidgetPredicate(
      (w) => (w is Text && w.data == label) || (w is Semantics && w.properties.label == label),
    ),
  ),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _disabledButton(WidgetTester tester, String label, {int index = 0}) =>
    tester.widget<ButtonStyleButton>(_buttonLabelled(label).at(index)).onPressed == null;

/// Double identity of a button in the table: labels repeat ("Next"), so
/// a button is its label plus the NUMBER of earlier buttons on the screen with the same label.
int _sameLabelBefore(List<Object?> nodes, String id, String label) {
  var seen = 0;
  var found = -1;
  void walk(List<Object?> list) {
    for (final raw in list) {
      final node = raw! as Json;
      if (found >= 0) return;
      if (node['type'] == 'Button' || node['type'] == 'IconButton') {
        final text = (((node['props']! as Json)['label']) as Json?)?['value'];
        if (text == label) {
          if (node['id'] == id) {
            found = seen;
            return;
          }
          seen += 1;
        }
      }
      walk((node['children'] as List<Object?>?) ?? const []);
    }
  }

  walk(nodes);
  return found;
}


/// The button focus node: a disabled Material button takes no focus, the reader
/// wrapper ABOVE it supplies it; for an enabled one it is inside.
FocusNode _focusOf(WidgetTester tester, Finder button) {
  final widget = tester.widget<ButtonStyleButton>(button.first);
  if (widget.onPressed == null) return Focus.of(tester.element(button.first), scopeOk: false);
  final inner = find.descendant(of: button, matching: find.byType(Padding)).first;
  return Focus.of(tester.element(inner), scopeOk: false);
}

Json _button(String id, {String label = 'Next', bool requiresFilled = true, Object? disabledIf, Json? action}) => {
  'id': id,
  'type': 'Button',
  'props': {
    'label': literal(label),
    'variant': 'primary',
    'action': action ?? {'type': 'navigate', 'params': {'screenId': 'next'}},
    'fullWidth': true,
    if (requiresFilled) 'requiresFilled': true,
    'disabledIf': ?disabledIf,
  },
};

void main() {
  test('table 9.14.0: thirteen groups (and a note), 315 rows, 68 form states', () {
    final keys = _table.keys.toList();
    final after = keys.sublist(keys.indexOf('formAbout') + 1);
    // The groups of schema 9.19.0 (choice controls, the write action, parts of a field, emptiness) come
    // after the 9.14.0 ones and are run by their own files (`choice_controls_cases_test.dart`,
    // `input_parts_cases_test.dart`, `emptiness_cases_test.dart`); they are named here and left out of the
    // count below.
    const groupsOfOtherFiles = [
      'choiceNote', 'choicePlaceCases', 'choiceControlCases', 'writeFormCases', 'inputPartsNote',
      'fieldBoxCases', 'affixRowCases', 'counterCases', 'noteRowCases', 'partsDocumentCases',
      'emptinessNote', 'emptinessCases', 'emptinessDocumentCases',
      // 9.23.0: a comparison with the value of another path (`value_path_cases_test.dart`).
      'valuePathNote', 'valuePathCases', //
    ];
    expect(after, [..._groups, ...groupsOfOtherFiles]);
    after.removeWhere(groupsOfOtherFiles.contains);
    // `numberInvalidAbout` is a note (a string), not a group of rows.
    expect(after.where((key) => _table[key] is List).fold<int>(0, (sum, key) => sum + _rows(key).length), 315);
    expect(_rows('numberInvalidCases'), hasLength(11));
    expect(_rows('formCases').fold<int>(0, (sum, row) => sum + (row['states']! as List<Object?>).length), 68);
  });

  // ───────────────────────────── numberParseCases ─────────────────────────────

  group('numberParseCases: typed text -> number or "not a number"', () {
    for (final row in _rows('numberParseCases')) {
      test(_name(row), () {
        final got = parseInputNumber(row['text']! as String);
        expect(got, row['number']);
        if (got != null) {
          // An integer is an `int`: `12` is written, not `12.0`.
          expect(got is int, (row['number'] as num) == (row['number'] as num).truncate() ? isTrue : isFalse, reason: '$got');
        }
      });
    }
  });

  // ───────────────────────────── numberReadCases ─────────────────────────────

  group('numberReadCases: what the field reads from the layer value and how it shows it', () {
    for (final row in _rows('numberReadCases')) {
      test(_name(row), () {
        final value = row['value'];
        expect(readInputNumber(value), row['number']);
        expect(numberInputText(value), row['text']);
      });
    }
  });

  // ───────────────────────────── numberFieldCases ─────────────────────────────

  group('numberFieldCases: event sequences of the number field', () {
    TextInputEvent? eventOf(Json step) => switch (step['type']) {
      'focus' => const FocusEvent(),
      'blur' => const BlurEvent(),
      'input' => InputEvent(step['text']! as String),
      'compositionStart' => const CompositionStartEvent(),
      'compositionEnd' => CompositionEndEvent(step['text']! as String),
      'platformFill' => PlatformFillEvent(step['text']! as String),
      _ => null,
    };

    for (final row in _rows('numberFieldCases')) {
      final steps = (row['steps']! as List<Object?>).cast<Json>();
      final disabled = row['disabled'] == true;
      final hasPath = row['hasPath'] != false;
      final maxLength = row['maxLength'];

      test('formula: ${_name(row)}', () {
        Object? bound = row['bound'];
        var state = kInitialTextInput;
        final writes = <Object?>[];
        for (final step in steps) {
          if (step['type'] == 'data') {
            bound = step['bound'];
            continue;
          }
          final result = stepNumberInput(state, eventOf(step)!, bound, maxLength: maxLength, disabled: disabled, hasPath: hasPath);
          state = result.state;
          if (result.write != null) writes.add(result.write);
        }
        expect(writes, row['writes']);
        expect(shownNumberInput(state, bound), row['shown']);
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final harness = InputHarness(
          [
            textFieldNode(
              value: hasPath ? defaultValue : absentValue,
              valueType: 'number',
              maxLength: maxLength,
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
        final written = [for (final (_, value) in harness.writes) value];
        expect(written, row['writes'], reason: 'host writes');
        // An integer is written as an integer, not `12.0`: a JSON number without a fractional part.
        for (final value in written) {
          if (value is num && value == value.truncate()) expect(value, isA<int>(), reason: '$value');
        }
        expect([for (final (path, _) in harness.writes) path], everyElement('form.field'));
        expect(_shown(tester), row['shown'], reason: 'what is shown in the field');
      });
    }
  });

  // ───────────────────────────── numberInvalidCases ─────────────────────────────

  group('numberInvalidCases: a non-number in a number field - error state', () {
    for (final row in _rows('numberInvalidCases')) {
      final steps = (row['steps']! as List<Object?>).cast<Json>();
      final states = (row['states']! as List<Object?>).cast<bool>();
      final disabled = row['disabled'] == true;

      test('formula: ${_name(row)}', () {
        expect(states, hasLength(steps.length));
        Object? bound = row['bound'];
        var state = kInitialTextInput;
        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          switch (step['type']) {
            case 'data':
              bound = step['bound'];
            case 'focus':
              state = stepNumberInput(state, const FocusEvent(), bound, disabled: disabled).state;
            case 'blur':
              state = stepNumberInput(state, const BlurEvent(), bound, disabled: disabled).state;
            case 'input':
              state = stepNumberInput(state, InputEvent(step['text']! as String), bound, disabled: disabled).state;
          }
          expect(numberInputInvalid(state, bound), states[i], reason: 'after step $i: $step');
        }
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = InputHarness(
          [
            textFieldNode(
              value: defaultValue,
              valueType: 'number',
              helper: literal('Digits only'),
              disabledIf: disabled ? const {'path': 'flags.off', 'op': 'isEmpty'} : null,
            ),
          ],
          session: {'form.field': row['bound']},
        );
        await harness.pump(tester);
        final danger = RenderTheme.fallback().color(ColorToken.danger);
        Color borderColor() {
          final box = tester.widget<Container>(
            find.descendant(of: find.byType(InputTextField), matching: find.byType(Container)).first,
          );
          return ((box.decoration! as BoxDecoration).border! as Border).top.color;
        }

        for (var i = 0; i < steps.length; i++) {
          final step = steps[i];
          switch (step['type']) {
            case 'data':
              await harness.setSession(tester, {'form.field': step['bound']});
            case 'focus':
              await _openKeyboard(tester, _field);
              await tester.pump();
            case 'blur':
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pump();
              // A focus change reaches the listener as a microtask: the rebuild comes on the next frame.
              await tester.pump();
            case 'input':
              await tester.enterText(_field, step['text']! as String);
              await tester.pump();
          }
          final expected = states[i];
          expect(borderColor() == danger, expected, reason: 'border after step $i: $step');
          final data = tester.getSemantics(find.bySemanticsLabel('Email')).getSemanticsData();
          expect(
            data.validationResult,
            expected ? SemanticsValidationResult.invalid : SemanticsValidationResult.none,
            reason: 'semantics after step $i',
          );
          // The reader adds no text: the hint is in place, there is no second text.
          expect(find.text('Digits only'), findsOneWidget, reason: 'step $i');
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  });

  // ───────────────────────────── numberKeyboardCases ─────────────────────────────

  group('numberKeyboardCases: keyboard, lines, direction', () {
    for (final row in _rows('numberKeyboardCases')) {
      final given = row['given'] == null ? const <String, Object?>{} : _obj(row['given']);
      final numeric = isNumberValueType(row['valueType']);

      test('formula: ${_name(row)}', () {
        final effective = effectiveInputKeyboardOf(given['keyboard'], given['lines'], numeric: numeric);
        expect(effective?.wire ?? 'multiline', row['keyboard']);
        expect(effectiveInputLinesOf(given['lines'], numeric: numeric), row['lines']);
        expect(inputContentIsLeftToRight(given['keyboard'], given['lines'], numeric: numeric), row['content'] == 'left-to-right');
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final harness = InputHarness([
          textFieldNode(valueType: row['valueType'], keyboard: given['keyboard'], lines: given['lines']),
        ]);
        await harness.pump(tester, settle: true);
        final editable = _editable(tester);
        expect(editable.maxLines, row['lines']);
        final want = switch (row['keyboard']) {
          'multiline' => TextInputType.multiline,
          'number' => const TextInputType.numberWithOptions(decimal: true),
          'email' => TextInputType.emailAddress,
          'phone' => TextInputType.phone,
          _ => TextInputType.text,
        };
        expect(editable.keyboardType, want);
        expect(editable.textDirection, row['content'] == 'left-to-right' ? TextDirection.ltr : isNull);
        // Number field: no autofill hints, no autocorrect.
        if (row['keyboard'] == 'number') {
          expect(editable.autofillHints ?? const <String>[], isEmpty);
          expect(editable.autocorrect, isFalse);
        }
      });
    }
  });

  // ───────────────────────────── filledCases ─────────────────────────────

  group('filledCases: "filled" for text, number, checkbox, choice', () {
    for (final row in _rows('filledCases')) {
      test('${row['kind']}: ${_name(row)}', () {
        final kind = FilledKind.values.byName(row['kind']! as String);
        expect(isFilledValue(kind, row['value']), row['filled']);
      });
    }
  });

  // ───────────────────────────── formCases ─────────────────────────────

  group('formCases: screen form - by formula and by a real widget', () {
    for (final row in _rows('formCases')) {
      final screens = _screensOf(row);
      final doc = _docOf(screens);
      for (final state in (row['states']! as List<Object?>).cast<Json>()) {
        final layers = _obj(state['layers']);
        final filled = _obj(state['filled']);
        final disabled = _obj(state['disabled']);

        test('formula: ${_name(row)} - ${_name(state)}', () {
          final data = _dataOf(layers);
          for (final entry in filled.entries) {
            final screen = doc.screens.firstWhere((s) => s.screenId == entry.key);
            expect(isFormFilled(screen.root, data), entry.value, reason: 'form of screen ${entry.key}');
          }
          for (final entry in disabled.entries) {
            final node = [for (final s in doc.screens) _nodeById(s.root, entry.key)].whereType<UiNode>().first;
            final screenOf = doc.screens.firstWhere((s) => _nodeById(s.root, entry.key) != null);
            final got = switch (node) {
              ButtonNode(:final requiresFilled, :final disabledIf) ||
              IconButtonNode(:final requiresFilled, :final disabledIf) => isPressDisabled(
                requiresFilled: requiresFilled,
                disabledIf: disabledIf,
                data: data,
                formFilled: () => isFormFilled(screenOf.root, data),
              ),
              _ => false, // a list row and a navigation item are not disabled
            };
            expect(got, entry.value, reason: 'node ${entry.key}');
          }
        });

        testWidgets('widget: ${_name(row)} - ${_name(state)}', (tester) async {
          _view(tester);
          final actions = <String>[];
          for (final screen in doc.screens) {
            final here = {
              for (final entry in disabled.entries)
                if (_nodeById(screen.root, entry.key) != null) entry.key: entry.value as bool,
            };
            if (here.isEmpty) continue;
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: renderScreen(
                    screen,
                    theme: RenderTheme.fallback(),
                    data: _layer(layers, 'data') ?? const {},
                    record: _layer(layers, 'record'),
                    session: _layer(layers, 'session') ?? const {},
                    scopeFor: (_) => _layer(layers, 'host') ?? const {},
                    onAction: (action, id) => actions.add(id),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            for (final entry in here.entries) {
              final json = _jsonById(screens[screen.screenId]!, entry.key)!;
              if (json['type'] == 'ListTile') {
                // A list row: it has no disabled fields - the tap works.
                await tester.tap(find.text('Open'));
                await tester.pump();
                expect(actions, contains(entry.key), reason: 'a list row is not disabled');
                continue;
              }
              final label = ((json['props']! as Json)['label']! as Json)['value']! as String;
              final index = _sameLabelBefore(screens[screen.screenId]!, entry.key, label);
              expect(_disabledButton(tester, label, index: index), entry.value, reason: 'button ${entry.key} of screen ${screen.screenId}');
            }
          }
        });
      }
    }
  });

  // ───────────────────────────── pressCases ─────────────────────────────

  group('pressCases: pressing a disabled button does nothing', () {
    for (final row in _rows('pressCases')) {
      testWidgets(_name(row), (tester) async {
        _view(tester);
        final disabled = row['disabled'] == true;
        final isIcon = row['widget'] == 'IconButton';
        final tracks = <TrackEvent>[];
        final handed = <ButtonAction>[];
        final action = {
          'type': 'openUrl',
          'params': {'url': 'https://example.com/promo'},
          'track': {'event': 'promo_open'},
        };
        final key = switch (row['press']) {
          'enter' || 'enter-held' => LogicalKeyboardKey.enter,
          'space' => LogicalKeyboardKey.space,
          _ => null,
        };
        final children = <Json>[
          if (isIcon)
            {
              'id': 'bar',
              'type': 'AppBar',
              'props': {'title': literal('Form'), 'showBack': false},
              'children': [
                {
                  'id': 'done',
                  'type': 'IconButton',
                  'props': {
                    'icon': 'check',
                    'label': literal('Done'),
                    'variant': 'ghost',
                    'size': 'md',
                    'action': action,
                    if (disabled) 'requiresFilled': true,
                  },
                },
              ],
            },
          // A required field nobody filled in: the form is not filled, and the only button left enabled
          // is the one without `requiresFilled`. The field takes focus no earlier than the button.
          if (disabled) textFieldNode(required: true, path: 'survey.name'),
          if (!isIcon) _button('go', label: 'Go', requiresFilled: disabled, action: action),
        ];
        await pumpDocument(
          tester,
          docWith(children),
          onTrack: (event, nodeId, record) => tracks.add(event),
          onAction: (a, nodeId) => handed.add(a),
        );
        final label = isIcon ? 'Done' : 'Go';
        final button = _buttonLabelled(label);
        expect(button, findsOneWidget);

        Future<void> focusButton() async {
          _focusOf(tester, button).requestFocus();
          await tester.pump();
        }

        switch (row['press']) {
          case 'tap':
            await tester.tap(button, warnIfMissed: false);
            await tester.pump();
          case 'double-tap':
            await tester.tap(button, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 40));
            await tester.tap(button, warnIfMissed: false);
            await tester.pump();
          case 'enter' || 'space':
            await focusButton();
            await tester.sendKeyEvent(key!);
            await tester.pump();
          case 'enter-held':
            await focusButton();
            await tester.sendKeyDownEvent(key!);
            for (var i = 0; i < 5; i += 1) {
              await tester.sendKeyRepeatEvent(key);
            }
            await tester.sendKeyUpEvent(key);
            await tester.pump();
        }
        expect(handed.length, row['action'], reason: 'actions the host received');
        expect(tracks.length, row['track'], reason: 'analytics events');
      });
    }
  });

  // ───────────────────────────── disabledLookCases ─────────────────────────────

  group('disabledLookCases: look and semantics of a disabled button', () {
    for (final row in _rows('disabledLookCases')) {
      testWidgets(_name(row), (tester) async {
        final semantics = tester.ensureSemantics();
        _view(tester);
        final disabled = row['disabled'] == true;
        final isIcon = row['widget'] == 'IconButton';
        final variant = (row['variant'] as String?) ?? (isIcon ? 'ghost' : 'primary');
        final style = row['styleOpacity'] == null ? null : {'opacity': row['styleOpacity']};
        final button = isIcon
            ? {
                'id': 'ib',
                'type': 'IconButton',
                'props': {
                  'icon': 'check',
                  'label': literal('Done'),
                  'variant': variant,
                  'size': 'md',
                  'action': {'type': 'navigate', 'params': {'screenId': 'next'}},
                  if (disabled) 'requiresFilled': true,
                },
                'style': ?style,
              }
            : {
                ..._button('b', label: 'Go', requiresFilled: disabled),
                'style': ?style,
              };
        await pumpDocument(
          tester,
          docWith([if (disabled) textFieldNode(required: true, path: 'survey.name'), button]),
          onAction: (a, id) {},
        );
        final label = isIcon ? 'Done' : 'Go';
        final found = _buttonLabelled(label);
        expect(found, findsOneWidget);
        // Opacity of the WHOLE widget: the product of all `Opacity` above the button (the own
        // `style.opacity` multiplies with the disabled opacity).
        final opacities = tester.widgetList<Opacity>(find.ancestor(of: found, matching: find.byType(Opacity)));
        final product = opacities.fold<double>(1, (a, o) => a * o.opacity);
        expect(product, closeTo((row['opacity']! as num).toDouble(), 1e-9));

        // The theme role is the same: the colours of a disabled button are those of an enabled one.
        final styleButton = tester.widget<ButtonStyleButton>(found.first);
        final enabledColor = styleButton.style?.backgroundColor?.resolve(<WidgetState>{});
        final disabledColor = styleButton.style?.backgroundColor?.resolve(<WidgetState>{WidgetState.disabled});
        expect(disabledColor, enabledColor, reason: 'the theme has no disabled group - the colours are the same');
        final fg = styleButton.style?.foregroundColor;
        expect(fg?.resolve(<WidgetState>{WidgetState.disabled}), fg?.resolve(<WidgetState>{}));

        final want = _obj(row['semantics']);
        final node = tester.getSemantics(found.first);
        expect(
          node.flagsCollection.isEnabled == Tristate.isFalse,
          want['disabled'],
          reason: 'semantics enabled: false',
        );
        // The node is in the tree (not ExcludeSemantics) and focusable: the button can be found and heard.
        expect(node.flagsCollection.isButton, isTrue);
        // Keyboard focus: a disabled button stays in the focus order.
        final focus = _focusOf(tester, found);
        expect(focus.canRequestFocus, want['focusable']);
        focus.requestFocus();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(focus), reason: 'focus reached the button');
        semantics.dispose();
      });
    }
  });

  // ───────────────────────────── choiceCases ─────────────────────────────

  Json options() => choiceGroupNode(
    [
      optionNode('Gold', optionValue: 'gold'),
      optionNode('Silver', optionValue: 'silver'),
      optionNode('Curious', optionValue: 'curious'),
    ],
  );
  Json groupWith(Object? value) => {...options(), 'props': {..._obj(options()['props']), 'value': value}};
  String titleOf(Object? option) => {'gold': 'Gold', 'silver': 'Silver', 'curious': 'Curious'}[option]!;

  group('choiceCases: what a group choice writes and where', () {
    for (final row in _rows('choiceCases')) {
      test('formula: ${_name(row)}', () {
        final write = choiceWriteOf(inputPathOf(row['value']), row['pick']! as String, row['shown'] as String?);
        final want = row['write'] as Json?;
        if (want == null) {
          expect(write, isNull);
        } else {
          expect(write?.path, want['path']);
          expect(write?.value, want['value']);
        }
      });

      testWidgets('widget: ${_name(row)}', (tester) async {
        final shown = row['shown']! as String;
        final fallback = fallbackOfBinding(row['value']);
        // What is shown as chosen lives in the session, except when it is shown by
        // the binding fallback text: then there is no data at all.
        final fromFallback = shown.isNotEmpty && shown == fallback;
        final harness = InputHarness(
          [groupWith(row['value'])],
          session: {if (shown.isNotEmpty && !fromFallback) 'survey.goal': shown},
        );
        await harness.pump(tester);
        await tester.tap(find.text(titleOf(row['pick'])));
        await tester.pump();
        final want = row['write'] as Json?;
        expect(harness.writes, want == null ? isEmpty : [(want['path'], want['value'])]);
      });
    }
  });

  group('choiceSessionCases: a choice is immediately visible to conditions of the same screen', () {
    for (final row in _rows('choiceSessionCases')) {
      testWidgets(_name(row), (tester) async {
        _view(tester);
        final writes = <(String, Object)>[];
        await pumpDocument(
          tester,
          docWith([
            groupWith(row['value']),
            {
              'id': 'marker',
              'type': 'Text',
              'props': {'content': literal('Marker')},
              'visibleIf': row['condition'],
            },
          ]),
          onWrite: (path, value) => writes.add((path, value)),
        );
        expect(find.text('Marker').evaluate().isNotEmpty, row['before'], reason: 'before the choice');
        if (row['pickFirst'] != null) {
          await tester.tap(find.text(titleOf(row['pickFirst'])));
          await tester.pump();
        }
        await tester.tap(find.text(titleOf(row['pick'])));
        await tester.pump();
        expect(find.text('Marker').evaluate().isNotEmpty, row['after'], reason: 'after the choice');
        // The reader session and the host see the same: the write reached the host.
        final literalGroup = inputPathOf(row['value']) == null;
        expect(writes.isNotEmpty, !literalGroup);
      });
    }
  });

  // ───────────────────────────── formDocumentCases ─────────────────────────────

  group('formDocumentCases: the reader paints what it read and does not crash', () {
    for (final row in _rows('formDocumentCases')) {
      testWidgets(_name(row), (tester) async {
        _view(tester);
        final node = _obj(row['node']);
        await pumpDocument(tester, docWith([node]), onAction: (a, id) {});
        expect(tester.takeException(), isNull);
        // What a document has no right to say the reader does not execute: `required` that is not
        // the literal `true`, and `requiresFilled` likewise.
        final parsed = _nodeById(docWith([node]).initialScreen.root, node['id']! as String);
        final props = _obj(node['props']);
        switch (parsed) {
          case TextFieldNode():
            expect(parsed.required, props['required'] == true);
            expect(parsed.numeric, props['valueType'] == 'number');
          case CheckboxNode():
            expect(parsed.required, props['required'] == true);
          case ChoiceGroupNode():
            expect(parsed.required, props['required'] == true);
          case ButtonNode():
            expect(parsed.requiresFilled, props['requiresFilled'] == true);
          case IconButtonNode():
            expect(parsed.requiresFilled, props['requiresFilled'] == true);
          default:
            break;
        }
      });
    }
  });

  // ───────────────────────────── formRuleCases ─────────────────────────────

  group('formRuleCases: rules as data - the artifact and the code mirror', () {
    final form = _obj(_obj(_obj(_schema['x-style'])['layout'])['form']);

    Object? at(Object? node, String path) {
      var current = node;
      for (final key in path.split('.')) {
        current = (current as Map)[key];
      }
      return current;
    }

    // Numbers and words the reader keeps in its OWN mirror.
    final mirror = <String, Object?>{
      'required.mark.text': kRequiredMarkText,
      'button.look': {'opacity': kInputDisabledOpacity},
      'number.parse.trimmed': kNumberInputTrimmed,
      'number.parse.minus': kNumberInputMinus,
      'number.parse.digitZeros': kNumberInputDigitZeros,
      'number.parse.separators': kNumberInputSeparators,
      'number.parse.maxDigits': kNumberInputMaxDigits,
      'number.keyboard': kNumberInputKeyboard.wire,
      'number.default': 'string',
    };
    // `numberInvalid.*` are state visibility rules; they are held by the `numberInvalidCases` group
    // (formula and widget) and the guard below, not by a separate number in code.

    for (final row in _rows('formRuleCases')) {
      final path = row['at']! as String;
      test(path, () {
        expect(at(form, path), row['expect']);
        final dart = mirror[path];
        if (dart != null) {
          final expected = row['expect'];
          if (expected is Map) {
            for (final entry in (dart as Map).entries) {
              expect(expected[entry.key], entry.value, reason: '$path.${entry.key}');
            }
          } else {
            expect(dart, expected, reason: 'mirror in code');
          }
        }
      });
    }

    test('the reader knows every key of the form block (a new key is a new decision)', () {
      expect(form.keys.toSet(), {'required', 'filled', 'button', 'number', 'numberInvalid', 'choice', 'cases'});
    });

    test('the 9.13.0 inputs block did not change: the reader knows the same keys', () {
      final inputs = _obj(_obj(_obj(_schema['x-style'])['layout'])['inputs']);
      expect(inputs.keys.toSet(), {'rules', 'textField', 'switch', 'checkbox', 'cases'});
    });

    test('fourteen policy rows of 9.14.0: the mirror matches the artifact and stands at the end', () {
      final compatibility = _obj(_schema['x-compatibility']);
      final policy = _obj(compatibility['policy']);
      expect(kFormPolicy, hasLength(14));
      for (final entry in kFormPolicy.entries) {
        expect(policy[entry.key], entry.value, reason: entry.key);
      }
      expect(policy.keys.toList().sublist(policy.length - kFormPolicy.length), kFormPolicy.keys.toList());
      final features = _obj(compatibility['features']);
      for (final feature in ['inputRequired', 'pressDisabled', 'numberInput']) {
        expect(features[feature], '9.14.0', reason: feature);
        expect(kFeatureCatalog[feature], '9.14.0', reason: feature);
        expect(supportsFeature(feature), isTrue, reason: feature);
        expect(supportsFeature(feature, readerVersion: '9.13.0'), isFalse, reason: feature);
      }
      // The reader moved on (9.15.0-9.17.0); this test asks what 9.14.0 can do.
      expect(
        SchemaVersion.tryParse(kSupportedSchemaVersion)!.compareTo(const SchemaVersion(9, 14, 0)),
        greaterThanOrEqualTo(0),
      );
    });
  });

  // ───────────────────────────── policy: one test per row ─────────────────────────────

  group('9.14.0 policy rows - one named test each', () {
    test('unreadableRequired: required that is not the literal true - not required', () {
      for (final value in <Object?>[false, 'true', 'yes', 1, null, const {'a': 1}]) {
        final doc = docWith([textFieldNode(required: value)]);
        final node = doc.initialScreen.root.children.single as TextFieldNode;
        expect(node.required, isFalse, reason: '$value');
        expect(requiredFieldsOf(doc.initialScreen.root), isEmpty);
      }
      final node = docWith([textFieldNode(required: true)]).initialScreen.root.children.single as TextFieldNode;
      expect(node.required, isTrue);
    });

    test('requiredHiddenOrDisabled: a hidden or disabled field is not counted', () {
      final data = ScreenData.scoped(session: const {'flag.on': true});
      final hidden = docWith([
        textFieldNode(required: true, path: 'a', visibleIf: const {'path': 'flag.on', 'op': 'isFalse'}),
        {
          'id': 'box',
          'type': 'Container',
          'props': {'direction': 'column'},
          'visibleIf': const {'path': 'flag.on', 'op': 'isFalse'},
          'children': [textFieldNode(id: 'inner', required: true, path: 'b')],
        },
        textFieldNode(id: 'off', required: true, path: 'c', disabledIf: const {'path': 'flag.on', 'op': 'isTrue'}),
      ]);
      expect(isFormFilled(hidden.initialScreen.root, data), isTrue);
      expect(isFormFilled(hidden.initialScreen.root, const ScreenData.scoped()), isFalse, reason: 'conditions not met - the fields are shown');
    });

    test('requiredWithoutPath: a field without a path is never filled', () {
      final doc = docWith([textFieldNode(required: true, value: absentValue)]);
      final data = ScreenData.scoped(session: const {'form.field': 'хоч би що'});
      expect(isFormFilled(doc.initialScreen.root, data), isFalse);
    });

    test('requiredInInactiveTab: a field in a tab that is not open is counted', () {
      final doc = docWith([
        {
          'id': 'tabs',
          'type': 'Tabs',
          'props': {},
          'children': [
            {'id': 'a', 'type': 'Tab', 'props': {'title': literal('A')}, 'children': <Json>[]},
            {
              'id': 'b',
              'type': 'Tab',
              'props': {'title': literal('B')},
              'children': [textFieldNode(required: true, path: 'form.b')],
            },
          ],
        },
      ]);
      expect(isFormFilled(doc.initialScreen.root, const ScreenData.scoped()), isFalse);
      expect(isFormFilled(doc.initialScreen.root, const ScreenData.scoped(session: {'form.b': 'x'})), isTrue);
    });

    testWidgets('requiredMessage: the field does not write "fill in" and does not go into error', (tester) async {
      _view(tester);
      final semantics = tester.ensureSemantics();
      await pumpDocument(tester, docWith([textFieldNode(required: true, path: 'survey.name')]), onAction: (a, id) {});
      // Only the label and the asterisk: no other text on screen.
      final texts = tester.widgetList<RichText>(find.byType(RichText)).map((w) => w.text.toPlainText()).where((t) => t.isNotEmpty).toList();
      expect(texts.where((t) => !t.startsWith('Email')), isEmpty, reason: '$texts');
      final node = tester.getSemantics(find.bySemanticsLabel('Email'));
      expect(node.validationResult, SemanticsValidationResult.none);
      // After trying to press the button too: there is no error state from emptiness.
      semantics.dispose();
    });

    test('unreadableRequiresFilled: requiresFilled that is not the literal true - not read', () {
      final doc = docWith([
        textFieldNode(required: true, path: 'a'),
        {
          ..._button('b'),
          'props': {..._obj(_button('b')['props']), 'requiresFilled': 'true'},
        },
      ]);
      final button = doc.initialScreen.root.children.last as ButtonNode;
      expect(button.requiresFilled, isFalse);
    });

    test('requiresFilledWithoutRequired: no required fields - the button is enabled', () {
      final doc = docWith([textFieldNode(path: 'a'), _button('b')]);
      expect(isFormFilled(doc.initialScreen.root, const ScreenData.scoped()), isTrue);
    });

    testWidgets('disabledPress: neither action nor track, focus stays', (tester) async {
      _view(tester);
      final tracks = <TrackEvent>[];
      final handed = <ButtonAction>[];
      await pumpDocument(
        tester,
        docWith([
          textFieldNode(required: true, path: 'survey.name'),
          _button('go', label: 'Go', action: {'type': 'openUrl', 'params': {'url': 'https://example.com'}, 'track': {'event': 'go'}}),
        ]),
        onTrack: (e, id, r) => tracks.add(e),
        onAction: (a, id) => handed.add(a),
      );
      await tester.tap(_buttonLabelled('Go'), warnIfMissed: false);
      await tester.pump();
      expect(handed, isEmpty);
      expect(tracks, isEmpty);
      final focus = _focusOf(tester, _buttonLabelled('Go'))..requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(focus));
    });

    test('unknownInputValueType: an unfamiliar word - a string field', () {
      for (final value in <Object?>['string', 'date', 7, null, const {'a': 1}]) {
        expect(isNumberValueType(value), isFalse, reason: '$value');
      }
      expect(isNumberValueType('number'), isTrue);
    });

    test('numberInputText: a number or an empty string, typed text stays', () {
      var state = kInitialTextInput;
      final first = stepNumberInput(state, const FocusEvent(), null);
      state = first.state;
      final typed = stepNumberInput(state, const InputEvent('12'), null);
      expect(typed.write, 12);
      final bad = stepNumberInput(typed.state, const InputEvent('12a'), 12);
      expect(bad.write, '');
      expect(bad.state.held?.text, '12a');
    });

    test('numberInputValueOfOtherType: a string under a number path - an empty field', () {
      expect(numberInputText('12'), '');
      expect(numberInputText(true), '');
      expect(numberInputText(null), '');
    });

    test('numberInputOptions: the number field reads neither keyboard nor lines', () {
      expect(effectiveInputKeyboardOf('email', 4, numeric: true), InputKeyboard.number);
      expect(effectiveInputLinesOf(4, numeric: true), 1);
    });

    testWidgets('choiceWrite: the group writes to the session and the host at the same moment', (tester) async {
      _view(tester);
      final writes = <(String, Object)>[];
      await pumpDocument(
        tester,
        docWith([groupWith({'kind': 'binding', 'path': 'survey.goal', 'fallback': ''})]),
        onWrite: (p, v) => writes.add((p, v)),
      );
      await tester.tap(find.text('Gold'));
      await tester.pump();
      expect(writes, [('survey.goal', 'gold')]);
      await tester.tap(find.text('Gold'));
      await tester.pump();
      expect(writes, hasLength(1), reason: 'the same option is not written twice');
    });

    testWidgets('nonStringActionParam: a number and a checkbox do not become an action parameter', (tester) async {
      _view(tester);
      final handed = <ButtonAction>[];
      for (final value in <Object>[12, true, '']) {
        await pumpDocument(
          tester,
          docWith([
            _button(
              'go',
              label: 'Go',
              requiresFilled: false,
              action: {
                'type': 'openUrl',
                'params': {'url': 'https://example.com/literal'},
                'paramBindings': {'url': 'survey.age'},
              },
            ),
          ]),
          data: {'survey.age': value},
          onAction: (a, id) => handed.add(a),
        );
        await tester.tap(find.text('Go'));
        await tester.pump();
      }
      expect(handed, hasLength(3));
      expect([for (final a in handed) a.params['url']], everyElement('https://example.com/literal'));
    });
  });

  // ───────────────────────────── end-to-end behaviour ─────────────────────────────

  group('form end to end: I type - the button enables, focus and controller stay the same', () {
    testWidgets('letter by letter: the button enables with the first, focus in the field, same controller', (tester) async {
      _view(tester);
      final writes = <(String, Object)>[];
      await pumpDocument(
        tester,
        docWith([
          textFieldNode(required: true, path: 'survey.name'),
          _button('go', label: 'Go'),
        ]),
        onAction: (a, id) {},
        onWrite: (p, v) => writes.add((p, v)),
      );
      expect(_disabledButton(tester, 'Go'), isTrue);
      await _openKeyboard(tester, _field);
      final controller = _editable(tester).controller;
      final focusNode = _editable(tester).focusNode;
      expect(focusNode.hasFocus, isTrue);

      await tester.enterText(_field, 'O');
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isFalse, reason: 'the first letter enables the button without delay');
      for (final typed in ['Ol', 'Ole', 'Olen', 'Olena']) {
        await tester.enterText(_field, typed);
        await tester.pump();
        expect(_disabledButton(tester, 'Go'), isFalse);
        expect(identical(_editable(tester).controller, controller), isTrue, reason: 'same controller');
        expect(_editable(tester).focusNode.hasFocus, isTrue, reason: 'focus stays in the field');
        expect(_editable(tester).controller.text, typed);
      }
      // Erased - the button is disabled again; the field lives on.
      await tester.enterText(_field, '');
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isTrue);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      expect(writes.last, ('survey.name', ''));
    });

    testWidgets('number: "12a" does not enable the button, "12" does, the consent checkbox enables the next', (tester) async {
      _view(tester);
      final writes = <(String, Object)>[];
      await pumpDocument(
        tester,
        docWith([
          textFieldNode(id: 'age', required: true, path: 'survey.age', valueType: 'number'),
          toggleNode('Checkbox', id: 'agree', label: 'Agree', path: 'survey.agreed', required: true),
          _button('go', label: 'Go'),
        ]),
        onAction: (a, id) {},
        onWrite: (p, v) => writes.add((p, v)),
      );
      await _openKeyboard(tester, _field);
      await tester.enterText(_field, '12a');
      await tester.pump();
      expect(writes, isEmpty, reason: 'there was no number and there is none - no write');
      expect(_disabledButton(tester, 'Go'), isTrue);
      await tester.enterText(_field, '12');
      await tester.pump();
      expect(writes.last, ('survey.age', 12));
      expect(writes.last.$2, isA<int>());
      expect(_disabledButton(tester, 'Go'), isTrue, reason: 'consent not given yet');
      await tester.enterText(_field, '12a');
      await tester.pump();
      expect(writes.last, ('survey.age', ''), reason: 'the number became a non-number: an empty string, not silence');
      expect(_shown(tester), '12a');
      expect(_disabledButton(tester, 'Go'), isTrue);
      await tester.enterText(_field, '12');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sdui-checkbox-box')));
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isFalse);
      // A number with zero is not empty: "0" is filled.
      await tester.enterText(_field, '0');
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isFalse);
    });

    testWidgets('required group: a choice enables the button', (tester) async {
      _view(tester);
      final group = groupWith({'kind': 'binding', 'path': 'survey.goal', 'fallback': ''});
      await pumpDocument(
        tester,
        docWith([
          {...group, 'props': {..._obj(group['props']), 'required': true}},
          _button('go', label: 'Go'),
        ]),
        onAction: (a, id) {},
      );
      expect(_disabledButton(tester, 'Go'), isTrue);
      await tester.tap(find.text('Silver'));
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isFalse);
    });

    testWidgets('disabledIf: a session condition disables the button while it holds', (tester) async {
      _view(tester);
      await pumpDocument(
        tester,
        docWith([
          textFieldNode(id: 'age', path: 'survey.age', valueType: 'number'),
          _button('go', label: 'Go', requiresFilled: false, disabledIf: const {'path': 'survey.age', 'op': 'lt', 'value': 16}),
        ]),
        onAction: (a, id) {},
      );
      expect(_disabledButton(tester, 'Go'), isFalse, reason: 'no value - lt is silent: the button is enabled');
      await _openKeyboard(tester, _field);
      await tester.enterText(_field, '12');
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isTrue);
      await tester.enterText(_field, '18');
      await tester.pump();
      expect(_disabledButton(tester, 'Go'), isFalse);
    });

    testWidgets('asterisk: danger, after the label, not part of the accessible name, isRequired in semantics', (tester) async {
      _view(tester);
      final semantics = tester.ensureSemantics();
      await pumpDocument(
        tester,
        docWith([
          textFieldNode(required: true, label: 'Name', path: 'survey.name'),
          toggleNode('Checkbox', label: 'Agree', path: 'survey.agreed', required: true),
          toggleNode('Switch', id: 'sw', label: 'Push', path: 'settings.push', required: true),
        ]),
        onAction: (a, id) {},
      );
      final label = tester.widgetList<RichText>(find.byType(RichText)).map((w) => w.text.toPlainText()).toList();
      expect(label, contains('Name\u{FFFC}*'));
      expect(label, contains('Agree\u{FFFC}*'));
      expect(label, isNot(contains('Push\u{FFFC}*')), reason: 'a switch is never required');
      final danger = RenderTheme.fallback().color(ColorToken.danger);
      final star = tester.widgetList<RichText>(find.byType(RichText)).firstWhere((w) => w.text.toPlainText().startsWith('Name'));
      final spans = <TextSpan>[];
      star.text.visitChildren((span) {
        if (span is TextSpan) spans.add(span);
        return true;
      });
      expect(spans.last.text, '*');
      expect(spans.last.style?.color, danger);
      final named = tester.getSemantics(find.bySemanticsLabel('Name'));
      expect(named.label, 'Name', reason: 'the asterisk is not part of the name');
      expect(named.flagsCollection.isRequired, Tristate.isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('Agree')).flagsCollection.isRequired, Tristate.isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('Push')).flagsCollection.isRequired, isNot(Tristate.isTrue));
      semantics.dispose();
    });
  });
}
