import 'action.dart';
import 'action_catalog.dart' show kSetValueActionType, kToggleValueActionType;
import 'input_rules.dart';
import 'node.dart';
import 'record_scope.dart';

/// THE WRITE ACTIONS (schema 9.19.0, `x-actions.write`): `setValue` puts a literal of the document under a data
/// path, `toggleValue` flips the flag under it. The reader performs both itself, through the same write as a
/// field's: into the session of the screen stack and to the host (`onWrite`) at the same moment. Neither reaches
/// `onAction`.
///
/// Nothing here reads data except the CURRENT value under the node's own path (the caller passes the lookup of the
/// node's data scope). The path and the value are literals of the document: `paramBindings` and `carryRecord` are
/// not read.

/// The parameter names (`x-actions.write.path.param`, `value.param`, `value.typeParam`).
const String kWritePathParam = 'path';
const String kWriteValueParam = 'value';
const String kWriteValueTypeParam = 'valueType';

/// The longest path (`x-actions.write.path.maxLength`).
const int kWritePathMaxLength = 128;

/// The value types (`x-actions.write.value.types`) and the one that applies without the word.
const List<String> kWriteValueTypes = ['string', 'boolean', 'number'];
const String kWriteDefaultValueType = 'string';

/// The two words of a flag (`x-actions.write.value.boolean.words`).
const List<String> kWriteFlagWords = ['true', 'false'];

/// What the builder publishes for a number (`x-actions.write.value.number.publishedPattern`). The reader does not
/// judge a literal by it: it parses with [parseInputNumber], like a number field.
const String kWriteNumberPublishedPatternSource = r'^(?:0|-?[1-9][0-9]*|-?(?:0|[1-9][0-9]*)\.[0-9]*[1-9])$';

/// Why a write action does nothing (`x-actions.write.problems`).
enum WriteProblem {
  missingPath('missing-path'),
  pathTooLong('path-too-long'),
  unknownValueType('unknown-value-type'),
  notAFlag('not-a-flag'),
  notANumber('not-a-number');

  const WriteProblem(this.wire);

  /// The word the artifact uses.
  final String wire;
}

/// Whether [type] is one of the two write actions.
bool isWriteActionType(String type) => type == kSetValueActionType || type == kToggleValueActionType;

/// What a press of a write action does.
sealed class WriteStep {
  const WriteStep();
}

/// Put [value] under [path]: a [String], a [bool] or a [num].
final class WriteNow extends WriteStep {
  const WriteNow(this.path, this.value);

  final String path;
  final Object value;
}

/// The value is already there: nothing is written, the analytics event still goes.
final class WriteSame extends WriteStep {
  const WriteSame(this.path, this.value);

  final String path;
  final Object value;
}

/// The action is not usable: nothing is written, nothing goes to the host.
final class WriteInvalid extends WriteStep {
  const WriteInvalid(this.problem);

  final WriteProblem problem;
}

/// The path of a write action, or the reason there is none (`writePathOf`). The parameter is read as the node's
/// OWN key; a non-string was already dropped when the action was parsed, which is "no parameter".
({String? path, WriteProblem? problem}) writePathOf(ButtonAction action) {
  final path = action.params[kWritePathParam];
  if (path == null || path.isEmpty) return (path: null, problem: WriteProblem.missingPath);
  if (path.length > kWritePathMaxLength) return (path: null, problem: WriteProblem.pathTooLong);
  return (path: path, problem: null);
}

/// The value a `setValue` writes, typed by `valueType` (`writtenLiteralOf`): a [String], a [bool] or a [num]; the
/// empty string for an absent or empty number. `null` value with a problem otherwise.
({Object? value, WriteProblem? problem}) writtenLiteralOf(ButtonAction action) {
  final word = action.params[kWriteValueTypeParam] ?? kWriteDefaultValueType;
  if (!kWriteValueTypes.contains(word)) return (value: null, problem: WriteProblem.unknownValueType);
  final literal = action.params[kWriteValueParam] ?? '';
  switch (word) {
    case 'string':
      return (value: literal, problem: null);
    case 'boolean':
      if (literal == kWriteFlagWords[0]) return (value: true, problem: null);
      if (literal == kWriteFlagWords[1]) return (value: false, problem: null);
      return (value: null, problem: WriteProblem.notAFlag);
    default:
      // A number is parsed by the number field's own rule; empty is a cleared field: the empty string, not
      // `null` and not zero.
      if (literal.isEmpty) return (value: '', problem: null);
      final number = parseInputNumber(literal);
      return number == null ? (value: null, problem: WriteProblem.notANumber) : (value: number, problem: null);
  }
}

/// Whether [current] already IS [value] (`holdsWritten`): equality by type, no conversion. A number is read the way
/// a number field reads it (`7.0` is `7`), `"7"` is not `7`; the empty string equals an absent value and `null`.
bool holdsWritten(Object? current, Object value) {
  if (value is num) return readInputNumber(current) == value;
  if (value is bool) return current == value;
  return value == '' ? current == '' || current == null : current == value;
}

/// What a press of [action] does with the data it reads through [read] (`writeStepOf`); `null` when the action is
/// not a write action.
WriteStep? writeStepOf(ButtonAction action, Object? Function(String path) read) {
  if (!isWriteActionType(action.type)) return null;
  final target = writePathOf(action);
  final path = target.path;
  if (path == null) return WriteInvalid(target.problem!);
  // A toggle writes the negation of what is SHOWN: on only for the flag `true`. It always writes, and it does not
  // read `value` or `valueType`.
  if (action.type == kToggleValueActionType) return WriteNow(path, !readInputFlag(read(path)));
  final literal = writtenLiteralOf(action);
  final value = literal.value;
  if (value == null) return WriteInvalid(literal.problem!);
  return holdsWritten(read(path), value) ? WriteSame(path, value) : WriteNow(path, value);
}

/// Whether the reader writes under [path] at all (the write gate): the shape of a data path without a forbidden
/// segment. The host sees every write in `onWrite` and may drop the ones it does not expect.
///
/// [allowed] is the host's allow-list (`writablePaths`): a `bool Function(String)` or an `Iterable<String>`; `null`
/// allows every well-formed path. Anything else, and a predicate that throws, allows nothing.
bool isWritablePath(String path, [Object? allowed]) {
  if (!isSafeDataPath(path)) return false;
  return switch (allowed) {
    null => true,
    final bool Function(String) check => _passes(check, path),
    final Iterable<Object?> paths => paths.contains(path),
    _ => false,
  };
}

bool _passes(bool Function(String) check, String path) {
  try {
    return check(path);
  } on Object {
    return false;
  }
}

/// The role a node with a write action has on the finished screen.
enum WriteControlRole { option, toggle }

/// A node whose action writes, as a control: an option of a choice (selected when the value is under its path) or
/// a toggle (on when `true` is under its path).
typedef WriteControl = ({WriteControlRole role, String path, bool on});

/// The control a press of [action] makes of its node (`writeControlOf`), or `null` for a plain button: not a write
/// action, an invalid one, or a `setValue` that clears (an empty value is a command, not an option).
WriteControl? writeControlOf(ButtonAction action, Object? Function(String path) read) {
  if (!isWriteActionType(action.type)) return null;
  final path = writePathOf(action).path;
  if (path == null) return null;
  if (action.type == kToggleValueActionType) {
    return (role: WriteControlRole.toggle, path: path, on: readInputFlag(read(path)));
  }
  final value = writtenLiteralOf(action).value;
  if (value == null || value == '') return null;
  return (role: WriteControlRole.option, path: path, on: holdsWritten(read(path), value));
}

/// The path an option writes (`optionWriteOf`): a valid `setValue` with a non-empty value. `null` otherwise.
String? optionPathOf(ButtonAction action) {
  if (action.type != kSetValueActionType) return null;
  final path = writePathOf(action).path;
  final value = writtenLiteralOf(action).value;
  return path == null || value == null || value == '' ? null : path;
}

/// The action a node performs on a press: a button, an icon button, a list row with an action, or a pressable
/// container (`writeActionOfNode`). `null` for the rest.
ButtonAction? pressActionOf(UiNode node) {
  if (node is ButtonNode) return node.action;
  if (node is IconButtonNode) return node.action;
  if (node is ListTileNode) return node.action;
  if (node is ChildNode) return node.press?.action;
  return null;
}

/// The place of an option in its group (`choicePlaceOf`): the position (from 1) and the size.
typedef ChoicePlace = ({int position, int size});

/// The place of [node] among its [siblings] (the children of ONE parent in document order): the group is the SHOWN
/// options that write the same path. One option, a node that is not an option and an option under another parent
/// have no place. The web reader says the place aloud; Flutter does not promise it.
ChoicePlace? choicePlaceOf(List<UiNode> siblings, UiNode node, {bool Function(UiNode sibling)? isShown}) {
  bool isOptionOf(UiNode other, String path) {
    final action = pressActionOf(other);
    return action != null && optionPathOf(action) == path;
  }

  final action = pressActionOf(node);
  final path = action == null ? null : optionPathOf(action);
  if (path == null) return null;
  final group = [for (final sibling in siblings) if (isOptionOf(sibling, path) && (isShown?.call(sibling) ?? true)) sibling];
  final at = group.indexWhere((sibling) => sibling.id == node.id);
  return at == -1 || group.length < 2 ? null : (position: at + 1, size: group.length);
}
