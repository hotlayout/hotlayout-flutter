/// THE HAPTIC REQUEST OF A PRESS (schema 9.25.0, `haptic` next to `type` and `track` on any action; rules in
/// `x-haptic`).
///
/// The reader never vibrates by itself: it hands the word to the host (`onHaptic`) and the host decides what to do
/// with it, with the settings of the user. The request goes once per press, BEFORE the analytics event and the action
/// of the same press (`haptic`, `track`, `action`), also when the action is `none` or the host cancels it. Not
/// requested: a disabled control, the auto-repeat of a key, a press that did not reach the node, a drag that is not
/// complete, an unknown word, no field (a section switch too). The action handed to the host does not carry the field.
library;

/// The words of the field.
enum HapticWord {
  light('light'),
  medium('medium'),
  heavy('heavy'),
  selection('selection'),
  success('success'),
  warning('warning');

  const HapticWord(this.wire);

  final String wire;

  /// The word of the document, or `null`: an absent field, an unknown word, an empty string and a value that is not a
  /// string are all "no request".
  static HapticWord? parse(Object? raw) {
    for (final word in values) {
      if (word.wire == raw) return word;
    }
    return null;
  }
}
