import 'action.dart';
import 'bindable.dart';

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
  const PressTarget({required this.action, this.label});

  /// The action, exactly as a button's: catalog, `track`, `paramBindings`, `carryRecord`.
  final ButtonAction action;

  /// The accessible name of the card. It goes FIRST; the text of the content follows. `null` means there
  /// is no field.
  final BindableString? label;
}

/// Whether [action] makes its holder a control: any type but `none`, or `none` that carries an analytics
/// `track` (the event is a consequence of the press). A card whose action is `none` without an event is
/// an ordinary card: a button that does nothing would lie to the screen reader.
bool isPressAction(ButtonAction action) => action.type != ButtonAction.noneType || action.track != null;

/// Reads `action` and `label` of a container's props. `null` means the node is not pressable: no field,
/// a field of the wrong shape, `none` without an event.
///
/// [labelKey] is the localization key of the `label` field of this node (`null` for a document without
/// translations).
PressTarget? readPressTarget(Map<String, Object?> props, {String? labelKey}) {
  final raw = props['action'];
  if (raw is! Map) return null;
  final action = ButtonAction.parse(raw);
  if (!isPressAction(action)) return null;
  final label = props['label'];
  return PressTarget(
    action: action,
    label: label is Map ? BindableString.parse(label, key: labelKey) : null,
  );
}
