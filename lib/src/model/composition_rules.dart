import 'action.dart';
import 'bindable.dart';
import 'long_press.dart' show kLongPressKey, kLongPressLabelKey;
import 'action_catalog.dart' show kSetValueActionType, kToggleValueActionType;

/// FREE COMPOSITION (schema 9.19.0, `x-style.layout.composition`).
///
/// Three statements, one of which the reader executes:
///
///  1. a column, a row and a container accept a child of their own type: the reader never checked child
///     types and still does not, it draws what arrived;
///  2. the tree may be eight levels deep: the number is the builder's, the reader does not check it and
///     draws any tree up to [kReaderParseLimit]; a deeper subtree is not parsed (see `UiNode.parse`);
///  3. a node that holds children and carries an `action` is a PRESSABLE CONTAINER: a card that is a
///     button on the finished screen. It runs the same action through the same `onAction` as a button.

/// The reader's own parse limit (`depth.readerParseLimit`): nodes deeper than this many levels below the
/// screen root are not parsed. A guard against a stack overflow on a hostile document, not a contract
/// limit: the builder publishes eight levels.
const int kReaderParseLimit = 32;

/// Whether the tree under [root] (a raw screen root) goes deeper than [kReaderParseLimit] levels below it. Such a
/// screen is rejected whole (`depth.readerAboveParseLimit`), not drawn as far as it goes: half a screen is a wrong
/// screen. Walked level by level without recursion, so a hostile tree cannot overflow the stack here either; only
/// objects count as nodes.
bool exceedsParseLimit(Object? root) {
  var level = <Object?>[root];
  for (var depth = 0; depth <= kReaderParseLimit; depth += 1) {
    final next = <Object?>[];
    for (final node in level) {
      final children = node is Map ? node['children'] : null;
      if (children is List) next.addAll(children.whereType<Map<Object?, Object?>>());
    }
    if (next.isEmpty) return false;
    level = next;
  }
  return true;
}

/// The widget types whose node may be a pressable container (the ones with the `action` and `label`
/// props of `$defs.PressAction` / `$defs.PressLabel`). A `Grid` with the same field is not pressable: the
/// schema does not read it there.
const Set<String> kPressableTypes = {'Column', 'Row', 'Container', 'Stack'};

/// The press of a container as the document wrote it.
final class PressTarget {
  const PressTarget({required this.action, this.label, this.longPress, this.longPressLabel});

  /// The action, exactly as a button's: catalog, `track`, `paramBindings`, `carryRecord`. A card that holds only a
  /// long press has [ButtonAction.none] here: a tap on it does nothing.
  final ButtonAction action;

  /// The accessible name of the card. It goes FIRST; the text of the content follows. `null` means there
  /// is no field.
  final BindableString? label;

  /// The long press (9.26.0): the same form as [action] and the same way of running. `null` when the node has none,
  /// or its action does nothing.
  final ButtonAction? longPress;

  /// The name of the long press for assistive technology (9.26.0); `null` means there is no field.
  final BindableString? longPressLabel;

  /// Whether the tap of [action] does something (otherwise the card is a control for its long press only).
  bool get hasAction => isPressAction(action);
}

/// Whether [action] makes its holder a control: any type but `none`, or `none` that carries an analytics
/// `track` (the event is a consequence of the press). A card whose action is `none` without an event is
/// an ordinary card: a button that does nothing would lie to the screen reader.
bool isPressAction(ButtonAction action) => action.type != ButtonAction.noneType || action.track != null;

/// The long press of a node's props (9.26.0), or `null`: no field, a field of the wrong shape, an action that does
/// nothing, or a write action (`setValue` / `toggleValue` are not published there, and the reader does not run them
/// on a long press).
ButtonAction? readLongPress(Map<String, Object?> props) {
  final raw = props[kLongPressKey];
  if (raw is! Map) return null;
  final action = ButtonAction.parse(raw);
  if (!isPressAction(action) || (action.type == kSetValueActionType || action.type == kToggleValueActionType)) return null;
  return action;
}

/// Reads `action` and `label` of a container's props, and the long press with its name (9.26.0). `null` means the
/// node is not pressable: no field, a field of the wrong shape, `none` without an event, and no long press either.
///
/// [labelKey] and [longPressLabelKey] are the localization keys of the `label` and `longPressLabel` fields of this
/// node (`null` for a document without translations).
PressTarget? readPressTarget(Map<String, Object?> props, {String? labelKey, String? longPressLabelKey}) {
  final raw = props['action'];
  final action = raw is Map ? ButtonAction.parse(raw) : ButtonAction.none;
  final longPress = readLongPress(props);
  if (!isPressAction(action) && longPress == null) return null;
  final label = props['label'];
  final longLabel = props[kLongPressLabelKey];
  return PressTarget(
    action: isPressAction(action) ? action : ButtonAction.none,
    label: label is Map ? BindableString.parse(label, key: labelKey) : null,
    longPress: longPress,
    longPressLabel: longLabel is Map ? BindableString.parse(longLabel, key: longPressLabelKey) : null,
  );
}
