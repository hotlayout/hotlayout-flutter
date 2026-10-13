/// The pressable container as a person and a keyboard meet it (schema 9.19.0): focus order, Enter and
/// Space, a held key, the analytics event, and that the reader opens nothing itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/src/render/widgets/pressable.dart';

import 'support/fixtures.dart';

Map<String, Object?> _card({Map<String, Object?> action = const {'type': 'submit'}, List<Map<String, Object?>>? inside}) => {
  'id': 'card',
  'type': 'Container',
  'props': {'action': action, 'label': {'kind': 'literal', 'value': 'Open the quest'}},
  'children': inside ?? [textNode('Morning quest')],
};

Map<String, Object?> _button(String id, String label) => {
  'id': id,
  'type': 'Button',
  'props': {
    'label': {'kind': 'literal', 'value': label},
    'action': {'type': 'share'},
  },
};

void main() {
  testWidgets('Tab goes to the card first, then to the control inside it', (tester) async {
    final ran = <String>[];
    await pumpDocument(
      tester,
      docWith([
        _card(inside: [textNode('Morning quest'), _button('go', 'Start')]),
      ]),
      onAction: (action, nodeId) => ran.add(nodeId),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // The first stop is the card: Enter runs the card's action.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(ran, ['card']);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    // The second stop is the button; the card does not hear a key that a control inside took.
    expect(ran, ['card', 'go']);
  });

  testWidgets('Space presses the card too', (tester) async {
    final ran = <String>[];
    await pumpDocument(tester, docWith([_card()]), onAction: (action, nodeId) => ran.add(nodeId));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ran, ['card']);
  });

  testWidgets('a held key is one press: auto-repeat does not run the action again', (tester) async {
    final ran = <String>[];
    await pumpDocument(tester, docWith([_card()]), onAction: (action, nodeId) => ran.add(nodeId));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    for (var repeat = 0; repeat < 5; repeat += 1) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(ran, ['card']);
  });

  testWidgets('the card is a button with the label first; the control inside is a separate node', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDocument(
      tester,
      docWith([
        _card(inside: [textNode('Morning quest'), _button('go', 'Start')]),
      ]),
    );
    final card = tester.getSemantics(find.byType(PressableCard));
    expect(card.flagsCollection.isButton, isTrue);
    expect(card.label, startsWith('Open the quest'));
    expect(card.label, contains('Morning quest'));
    expect(card.label, isNot(contains('Start')), reason: 'a control inside is not merged into the card');
    final button = tester.getSemantics(find.text('Start'));
    expect(button.flagsCollection.isButton, isTrue);
    expect(button.label, 'Start');
    semantics.dispose();
  });

  testWidgets('an action `none` that carries an event: the event goes once, the host gets no action', (tester) async {
    final events = <String>[];
    final actions = <String>[];
    await pumpDocument(
      tester,
      docWith([
        _card(action: {'type': 'none', 'track': {'event': 'card_tap'}}),
      ]),
      onAction: (action, nodeId) => actions.add(nodeId),
      onTrack: (event, nodeId, record) => events.add('${event.event}@$nodeId'),
    );
    await tester.tap(find.text('Morning quest'));
    await tester.pump();
    expect(events, ['card_tap@card']);
    expect(actions, isEmpty);
  });

  testWidgets('openUrl on a card goes to the host as a checked standard action; the reader opens nothing', (tester) async {
    final seen = <String>[];
    await pumpDocument(
      tester,
      docWith([
        _card(action: {'type': 'openUrl', 'params': {'url': 'https://example.com/a'}}),
      ]),
      onAction: (action, nodeId) => seen.add('${action.type}:${action.standard?.runtimeType}'),
    );
    await tester.tap(find.text('Morning quest'));
    await tester.pump();
    expect(seen, ['openUrl:OpenUrlAction']);
  });

  testWidgets('a press on the margin of the card is not the card\'s', (tester) async {
    final ran = <String>[];
    final card = _card();
    card['style'] = {'margin': 24, 'padding': 8, 'background': {'kind': 'color', 'color': 'surface'}};
    await pumpDocument(tester, docWith([card]), onAction: (action, nodeId) => ran.add(nodeId));
    final box = tester.getRect(find.byType(PressableCard));
    // Inside the box (padding): the card. In the margin, just outside: nobody.
    await tester.tapAt(box.topLeft + const Offset(2, 2));
    await tester.pump();
    expect(ran, ['card']);
    await tester.tapAt(box.topLeft - const Offset(4, 4));
    await tester.pump();
    expect(ran, ['card']);
  });

  testWidgets('the keyboard focus on the card shows a ring in the colour of the theme, with the radius of the card; a touch shows none', (tester) async {
    final card = _card();
    card['style'] = {'radius': 16, 'background': {'kind': 'color', 'color': 'surface'}};
    await pumpDocument(tester, docWith([card]));

    DecoratedBox ring() => tester.widgetList<DecoratedBox>(
      find.descendant(of: find.byType(PressableCard), matching: find.byType(DecoratedBox)),
    ).firstWhere((box) => box.position == DecorationPosition.foreground);

    expect((ring().decoration as BoxDecoration).border, isNull, reason: 'no focus, no ring');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final decoration = ring().decoration as BoxDecoration;
    expect((decoration.border! as Border).top.color, RenderTheme.fallback().color(ColorToken.primary));
    expect((decoration.border! as Border).top.width, 2);
    expect(decoration.borderRadius, BorderRadiusDirectional.circular(16));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    expect((ring().decoration as BoxDecoration).border, isNull, reason: 'the focus left the card');
  });
}
