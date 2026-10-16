import '../model/record_scope.dart';

/// The data scope of ONE screen.
///
/// The data dictionary is not one per document: two screens of one document must be able to
/// show different entities. A list of seven rows leads to a details screen, and the details
/// must differ per row, which a single shared `item.name` could not do.
///
/// **There are four layers and the order between them is part of the contract**
/// (`x-dataScope.layers`, [kDataLayerOrder]), strongest first:
///
/// 1. **record**: the record scope of the node. It is the record the screen was opened with
///    (the list row that was tapped), and on top of it the records of the `Repeater` instances
///    the node is drawn in. A flat map of "path to value".
/// 2. **session**: what the user changed by hand in a BOUND field (`ChoiceGroup.value` with
///    `kind: 'binding'`). It lives as long as the screen stack and reaches neither the document
///    nor storage.
/// 3. **screen scope**: the entity supplied by the HOST ([ScreenScopeResolver]). Where the
///    record comes from (network, database, cache) is no concern of the reader.
/// 4. **document data**: one set for all screens (`campaign.title`).
///
/// The record is stronger than the session on purpose: if the user taps the row "Bottle" while
/// the radio sat on "Backpack", the details screen is about the bottle ENTIRELY. If the session
/// were stronger, a record field written elsewhere would silently act on the next screen. A path
/// the record does not carry is read from the session as usual.
///
/// "Absent" in a layer is a missing key or `null`: the next layer is read. `false`, `0` and the
/// empty string are values.
///
/// **There is no `params.*` path**: the parameters of `navigate` are a free map of strings for
/// the host, not screen data.
///
/// A screen with no record, no session and no scope is drawn exactly as it would be without
/// these layers. That is a requirement, not a side effect: a document that uses none of the
/// newer features must not look different.
///
/// There is deliberately no "data is still loading" state. While the scope has not arrived (or
/// never will), `lookup` returns `null` and the binding uses the document's `fallback`, the same
/// principle that applies to the document itself: the screen stays whole, with no spinner.
class ScreenData {
  /// Document data without a record or screen scope.
  const ScreenData(this._document)
    : _record = null,
      _session = const <String, Object?>{},
      _scope = const <String, Object?>{},
      _shown = const <String, Object?>{},
      _labelShown = null;

  /// Document data plus the input of a specific screen.
  const ScreenData.scoped({
    Map<String, Object?> document = const <String, Object?>{},
    Map<String, Object?>? record,
    Map<String, Object?> session = const <String, Object?>{},
    Map<String, Object?> scope = const <String, Object?>{},
    Map<String, Object?> shown = const <String, Object?>{},
    Map<String, Object?>? labelShown,
  }) : _document = document,
       _record = record,
       _session = session,
       _scope = scope,
       _shown = shown,
       _labelShown = labelShown;

  static const ScreenData empty = ScreenData(<String, Object?>{});

  final Map<String, Object?> _document;
  final Map<String, Object?>? _record;
  final Map<String, Object?> _session;
  final Map<String, Object?> _scope;

  /// The numbers a node is LEADING to their new values right now (schema 9.21.0, `animateChanges`): path to the
  /// value shown at this moment. Not a data layer: it lies over all of them and exists only for the subtree of
  /// the node that leads, so what is drawn there is the shown number written by the same format, template and
  /// plural word as the final one.
  final Map<String, Object?> _shown;

  /// The same numbers as the LABEL of a scale writes them (in steps), when they differ from [_shown].
  final Map<String, Object?>? _labelShown;

  /// This data with the numbers [shown] laid over every layer. [labelShown] are the steps the label of a scale
  /// shows, where they differ.
  ScreenData withShown(Map<String, Object?> shown, {Map<String, Object?>? labelShown}) => ScreenData.scoped(
    document: _document,
    record: _record,
    session: _session,
    scope: _scope,
    shown: {..._shown, ...shown},
    labelShown: labelShown,
  );

  /// The data as the LABEL of a scale reads it: the shown numbers in steps. The same data when there are none.
  ScreenData get labelView => _labelShown == null
      ? this
      : ScreenData.scoped(document: _document, record: _record, session: _session, scope: _scope, shown: {..._shown, ..._labelShown});

  /// The record scope of the node (layer 1): a flat map of "path to value", or `null` when
  /// there is no record at all. This is what the host receives together with an action.
  Map<String, Object?>? get record => _record;

  /// The same data but WITHOUT layer 3.
  ///
  /// It is needed exactly where the scope is still being computed: the host decides which
  /// entity to supply and reads data for that, and reading the scope from the scope itself would
  /// be circular. The record stays, since a host that computes the scope must see it.
  ScreenData get withoutScope =>
      ScreenData.scoped(document: _document, record: _record, session: _session, shown: _shown, labelShown: _labelShown);

  /// The same data plus the RECORD OF A LIST INSTANCE under the prefix [item].
  ///
  /// A repeater adds no new data layer: the instance record goes into layer 1 on top of the one
  /// the screen was opened with (the inner one is stronger, and a missing value overrides
  /// nothing: [overlayRecord]). That is why ONE template works as a list row and as a details
  /// screen: both read `task.title`.
  ///
  /// The record must not go into the host scope layer, which is weaker than the session: then
  /// `item.selectedId` in a list row would be read from the session for EVERY row.
  ///
  /// In a nested list the outer record stays available under its own name, since the prefixes
  /// differ (`group` and `item`); with equal prefixes the inner one wins, field by field.
  ScreenData withItem(String item, Object? value) => ScreenData.scoped(
    document: _document,
    record: overlayRecord(_record, instanceRecord(item, value)),
    session: _session,
    scope: _scope,
    shown: _shown,
    labelShown: _labelShown,
  );

  /// The records of a collection by path. An empty list if there is no data or it is not a list:
  /// the screen stays whole, as with any missing binding.
  List<Object?> listOf(String path) {
    final value = lookup(path);
    return value is List ? value : const [];
  }

  /// The value for a path: the first layer that has it ([readLayered]).
  Object? lookup(String path) {
    // A number that is being led to its new value shows the value of this moment, over every layer.
    if (_shown.containsKey(path)) return _shown[path];
    return readLayered(
      {'record': _record, 'session': _session, 'host': _scope, 'data': _document},
      path,
      read: _lookupIn,
    )?.value;
  }

  /// The builder produces a flat "path to value" map (`data-contract`), but a real backend is
  /// more likely to send nested JSON, so both are supported: the exact key first, then a walk
  /// over the segments.
  static Object? _lookupIn(Map<String, Object?> values, String path) {
    if (values.containsKey(path)) return values[path];

    Object? current = values;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}
