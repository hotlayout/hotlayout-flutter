/// CHOICE FROM PLAIN NODES (schema 9.19.0, `x-choice`): an option, a toggle, a group and the form.
///
/// The shared table (`assets/contract/fixtures/inputs/input-cases.json`) runs row by row:
///
///  1. `choicePlaceCases` (11) -- the place of an option among the shown options of one parent that write one
///     path, by the model function over the parsed nodes. Flutter does not say the place aloud (not promised
///     there); the function is the reference the web reader speaks;
///  2. `choiceControlCases` (15) -- a REAL screen: the semantics of every node (a radio with a checked state, a
///     button with a toggled state, a plain button, a disabled option), the state after real presses, the place
///     the model gives each option;
///  3. `writeFormCases` (6) -- "filled" asks the value under the path, whoever wrote it: a button that needs the
///     form is disabled and enabled as a card, a toggle and a number write and clear the path.
///
/// The model is the builder's `scripts/choice-cases.test.tsx`.
library;

import 'dart:convert';
import 'dart:io';

import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/write_action.dart';

import 'support/fixtures.dart';
import 'support/node_press.dart';

final Json _table = jsonDecode(File('assets/contract/fixtures/inputs/input-cases.json').readAsStringSync()) as Json;
final Json _schema = jsonDecode(File('assets/contract/screen-schema.json').readAsStringSync()) as Json;

List<Json> _rows(String key) => (_table[key]! as List<Object?>).cast<Json>();

List<Json> _nodesOf(Json row, String key) => (row[key]! as List<Object?>).cast<Json>();

UiNode? _find(UiNode node, String id) {
  if (node.id == id) return node;
  for (final child in node.children) {
    final found = _find(child, id);
    if (found != null) return found;
  }
  return null;
}

/// The parent that holds the node with this id.
UiNode? _parentOf(UiNode node, String id) {
  for (final child in node.children) {
    if (child.id == id) return node;
    final found = _parentOf(child, id);
    if (found != null) return found;
  }
  return null;
}

/// What a node is on the finished screen, in the words of the table.
({String? role, bool? checked, bool? pressed, bool disabled}) _seen(SemanticsNode node) {
  final flags = node.flagsCollection;
  final String? role = flags.isChecked != CheckedState.none && flags.isInMutuallyExclusiveGroup
      ? 'radio'
      : flags.isButton
      ? 'button'
      : null;
  return (
    role: role,
    checked: flags.isChecked == CheckedState.none ? null : flags.isChecked == CheckedState.isTrue,
    pressed: flags.isToggled == Tristate.none ? null : flags.isToggled == Tristate.isTrue,
    disabled: flags.isEnabled == Tristate.isFalse,
  );
}

void main() {
  test('the table has the promised rows', () {
    expect(_rows('choicePlaceCases'), hasLength(11));
    expect(_rows('choiceControlCases'), hasLength(15));
    expect(_rows('writeFormCases'), hasLength(6));
  });

  group('choicePlaceCases: the place in the group', () {
    for (final row in _rows('choicePlaceCases')) {
      test(row['name']! as String, () {
        final siblings = _nodesOf(row, 'siblings');
        final screen = UiNode.parse({'id': 'root', 'type': 'Screen', 'props': {}, 'children': siblings}) as ScreenNode;
        final hidden = ((row['hidden'] as List<Object?>?) ?? const []).cast<String>();
        final places = asJson(row['places']);
        expect(places.keys, siblings.map((node) => node['id']), reason: 'one answer per sibling');
        for (final entry in places.entries) {
          final node = screen.children.firstWhere((candidate) => candidate.id == entry.key);
          final place = choicePlaceOf(screen.children, node, isShown: (sibling) => !hidden.contains(sibling.id));
          final want = (entry.value as List<Object?>?)?.cast<int>();
          expect(place == null ? null : [place.position, place.size], want, reason: entry.key);
        }
      });
    }
  });

  group('choiceControlCases: the semantics and the state of a real screen', () {
    for (final row in _rows('choiceControlCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final semantics = tester.ensureSemantics();
        final nodes = _nodesOf(row, 'nodes');
        final document = docWith(nodes);
        final session = asJson(row['session']);
        await pumpDocument(tester, document, data: session);
        final root = document.initialScreen.root;
        final written = <String, Object?>{...session};

        Future<void> expectState(Json states, String when) async {
          for (final entry in states.entries) {
            final json = findNodeJson(nodes, entry.key)!;
            final want = entry.value;
            if (want == 'absent') {
              expect(find.text(_labelOf(json)), findsNothing, reason: '$when: ${entry.key} is not on the screen');
              continue;
            }
            final expected = asJson(want);
            final role = expected['role'] as String?;
            if (role == null) {
              // A text or a row that is not a control: it is no control of its own. (A text inside a control is
              // merged into the control's node, which is the control's.)
              expect(find.byKey(ValueKey('sdui-press-${entry.key}@')), findsNothing, reason: '$when: ${entry.key} is not a card');
              continue;
            }
            final finder = finderOfNodeJson(json);
            expect(finder, findsWidgets, reason: '$when: ${entry.key}');
            final seen = _seen(tester.getSemantics(finder));
            expect(seen.role, role, reason: '$when: ${entry.key} role');
            if (role == 'radio') expect(seen.checked, expected['checked'], reason: '$when: ${entry.key} checked');
            if (role == 'button' && expected.containsKey('pressed')) {
              expect(seen.pressed, expected['pressed'], reason: '$when: ${entry.key} pressed');
            }
            if (role == 'button' && !expected.containsKey('pressed')) {
              expect(seen.pressed, isNull, reason: '$when: ${entry.key} is a plain button, no state');
              expect(seen.checked, isNull);
            }
            expect(seen.disabled, expected['disabled'] == true, reason: '$when: ${entry.key} disabled');
            // The place: the model says it, Flutter does not speak it.
            if (expected.containsKey('position') || role == 'radio') {
              final parent = _parentOf(root, entry.key);
              final node = _find(root, entry.key);
              if (parent != null && node != null && !expected.containsKey('disabled')) {
                final place = choicePlaceOf(
                  parent.children,
                  node,
                  isShown: (sibling) => sibling is! ChildNode || sibling.isVisible(ScreenData(written)),
                );
                expect(place?.position, expected['position'], reason: '$when: ${entry.key} position');
                expect(place?.size, expected['size'], reason: '$when: ${entry.key} size');
              }
            }
          }
        }

        await expectState(asJson(row['expect']), 'before');
        for (final id in ((row['presses'] as List<Object?>?) ?? const []).cast<String>()) {
          await tester.tap(finderOfNodeJson(findNodeJson(nodes, id)!), warnIfMissed: false);
          await tester.pump();
          // Track what the last write left, for the visibility of the nodes the model asks about.
        }
        final after = row['after'];
        if (after != null) {
          // The data shown to the model is the host data plus what was written: read it back from the screen.
          written.clear();
          written.addAll(session);
          await expectState(asJson(after), 'after');
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  });

  group('writeFormCases: "filled" asks the value under the path, whoever wrote it', () {
    for (final row in _rows('writeFormCases')) {
      testWidgets(row['name']! as String, (tester) async {
        final semantics = tester.ensureSemantics();
        final nodes = _nodesOf(row, 'nodes');
        await pumpDocument(tester, docWith(nodes));
        final disabled = asJson(row['disabled']);
        bool isDisabled(String id) => _seen(tester.getSemantics(finderOfNodeJson(findNodeJson(nodes, id)!))).disabled;

        final presses = (row['presses']! as List<Object?>).cast<String>();
        for (var step = 0; step <= presses.length; step += 1) {
          for (final entry in disabled.entries) {
            expect(isDisabled(entry.key), (entry.value! as List<Object?>)[step], reason: '${entry.key} after $step presses');
          }
          if (step == presses.length) break;
          await tester.tap(finderOfNodeJson(findNodeJson(nodes, presses[step])!), warnIfMissed: false);
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  });

  test('x-choice: the semantics and the group words of the artifact', () {
    final choice = asJson(_schema['x-choice']);
    expect(asJson(asJson(choice['semantics'])['option'])['flutter'], 'Semantics-inMutuallyExclusiveGroup-checked');
    expect(asJson(asJson(choice['semantics'])['toggle'])['flutter'], 'Semantics-button-toggled');
    expect(asJson(asJson(choice['semantics'])['position'])['flutter'], 'not-promised');
    expect(asJson(choice['semantics'])['groupRole'], 'none');
    expect(asJson(choice['keyboard'])['arrows'], 'not-promised');
    expect(asJson(choice['option'])['pressSelected'], 'writes-nothing-the-option-cannot-be-unselected-by-pressing-it');
  });
}

/// The visible label of a node: what to look for to see whether it is on the screen.
String _labelOf(Json node) {
  final props = asJson(node['props'] ?? const <String, Object?>{});
  final value = props['label'] ?? props['title'] ?? props['content'];
  return asJson(value)['value']! as String;
}
