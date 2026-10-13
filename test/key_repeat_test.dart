/// KEY AUTO-REPEAT IS NOT A PRESS (policy row
/// `keyAutoRepeat: not-a-press`).
///
/// A held activation key (Enter, space) sends `KeyDownEvent`, then
/// `KeyRepeatEvent` about every 30 ms. A Material button via `Shortcuts` ->
/// `ActivateIntent` would fire `onPressed` on every repeat: one held
/// key - ten analytics events and ten `openUrl`s. The test presses the key
/// with REAL focus on a real button, rather than calling a function.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotlayout_flutter/hotlayout_flutter.dart';

import 'support/fixtures.dart';

const _openUrl = {
  'type': 'openUrl',
  'params': {'url': 'https://example.com/promo'},
  'track': {'event': 'promo_open'},
};

Map<String, Object?> _iconButton() => {
  'id': 'ib',
  'type': 'IconButton',
  'props': {
    'icon': 'arrow-left',
    'label': {'kind': 'literal', 'value': 'Open'},
    'variant': 'primary',
    'size': 'md',
    'action': _openUrl,
  },
};

void main() {
  final cases = <String, Map<String, Object?>>{
    'Button': buttonNode('Open', action: _openUrl),
    'Button without background (TextButton)': buttonNode('Open', action: _openUrl, variant: 'ghost'),
    'Button with border (OutlinedButton)': buttonNode('Open', action: _openUrl, variant: 'secondary'),
    'IconButton': _iconButton(),
    'ListTile with an action': listTileNode('Open', action: _openUrl),
  };

  for (final MapEntry(key: name, value: node) in cases.entries) {
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets('$name: held ${key.keyLabel.isEmpty ? 'Space' : key.keyLabel} - one action and one event', (tester) async {
        final tracks = <TrackEvent>[];
        final handed = <ButtonAction>[];
        await pumpDocument(
          tester,
          docWith([node]),
          onTrack: (event, nodeId, record) => tracks.add(event),
          onAction: (action, nodeId) => handed.add(action),
        );

        // A list row is not focusable (it has no keyboard activation): then
        // only the absence of repeat is checked, focus is set only where it exists.
        final focusable = find.bySubtype<ButtonStyleButton>().evaluate().isNotEmpty;
        if (focusable) {
          // Focus is on the button, not on an ancestor: the nearest `Focus` above
          // the button label or drawing is its own.
          final inner = find.descendant(of: find.bySubtype<ButtonStyleButton>(), matching: find.byType(Padding)).first;
          Focus.of(tester.element(inner), scopeOk: false).requestFocus();
          await tester.pump();
          expect(FocusManager.instance.primaryFocus?.context, isNotNull);
        }

        await tester.sendKeyDownEvent(key);
        if (focusable) expect(handed, hasLength(1), reason: 'the first key press acts');
        for (var i = 0; i < 5; i += 1) {
          await tester.sendKeyRepeatEvent(key);
        }
        await tester.sendKeyUpEvent(key);
        await tester.pump();

        expect(handed.length, lessThanOrEqualTo(1), reason: 'a held key is not five presses');
        expect(tracks.length, handed.length, reason: 'the analytics event is exactly per action');
        if (focusable) {
          expect(handed, hasLength(1), reason: 'the first key press acts');
        }
      });
    }
  }
}
