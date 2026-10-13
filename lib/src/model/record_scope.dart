/// Record scope and data layers: mirror of the builder's `record-scope.ts` (schema 9.2.0).
///
/// The question the contract did not answer before: a list row (`Repeater`) has a `navigate` action to a
/// detail screen, so which RECORD does that screen see? Three readers answered differently and never
/// disagreed out loud; Flutter carried nothing and had a private path `params.*` that the builder's
/// validator does not allow. Now the rule is part of the contract and this file is its second copy. Do
/// not be "smarter" than the reference implementation here: the shared case table
/// (`assets/contract/fixtures/scope/record-scope-cases.json`) is run by a test row by row.
///
/// Four statements, each with a row in `x-compatibility.policy` ([kRecordScopePolicy]):
///  1. A NODE'S RECORD SCOPE is the record the screen was opened with, and over it the records of the
///     `Repeater` instances the node is drawn in ([overlayRecord]);
///  2. AN ACTION CARRIES THE RECORD SCOPE OF ITS NODE; `navigate` opens the screen with it when a list
///     row was pressed, and a page not opened from a row WITHOUT a record ([recordForOpenedScreen]);
///  3. the record lives as long as the screen is on the stack: this is about the stack frame, not this
///     file;
///  4. THE LAYER ORDER IS THE SAME IN ALL READERS: record, session, host scope, data
///     ([kDataLayerOrder], [readLayered]); `null` and a missing key mean "absent", and the next layer
///     is read.
///
/// The `params` of a `navigate` action are NOT screen data: they are a free map of strings for the
/// host. The contract has no path `params.*`, and neither does this code.
library;

/// Data layers of a screen, from strongest to weakest (`x-dataScope.layers`).
const List<String> kDataLayerOrder = ['record', 'session', 'host', 'data'];

/// What a node's record scope consists of, from weaker to stronger (`x-dataScope.recordSources`).
const List<String> kRecordSources = ['opened-screen', 'repeater-instance'];

/// Mirror of the eight policy rows of 9.2.0; a test checks them against the artifact.
const Map<String, String> kRecordScopePolicy = {
  'actionRecord': 'node-record-scope',
  'navigateFromListItem': 'open-with-node-record',
  'navigateOutsideListItem': 'page-without-record-modal-keeps-record',
  'recordLifetime': 'while-screen-in-stack',
  'dataLayerOrder': 'record-session-host-data',
  'absentInDataLayer': 'read-next-layer',
  'navigateParams': 'for-host-not-data',
  'pickedChoice': 'shown-while-bound-value-unchanged',
};

/// The forms in which the reader sees `x-dataScope.absent`: what exactly "no value" means in a layer.
const List<String> kAbsentForms = ['missing-key', 'null'];

/// "No value": the key is missing or `null` is under it. The same "absent" as in conditions. `false`,
/// `0` and an empty string are values.
bool isAbsent(Object? value) => value == null;

/// The value at a path and the layer that gave it; `null` means it is absent everywhere (then the
/// binding's `fallback` and the condition's `missingConditionValue` apply).
///
/// [layers] are the layers by the names in [kDataLayerOrder]; a missing layer is empty. [read] is how a
/// layer answers a path: by its own key in a flat map (the default) or also by walking nested maps (how
/// `ScreenData` reads, since host data may be nested JSON).
({String layer, Object value})? readLayered(
  Map<String, Map<String, Object?>?> layers,
  String path, {
  Object? Function(Map<String, Object?> layer, String path) read = _ownKey,
}) {
  for (final name in kDataLayerOrder) {
    final layer = layers[name];
    if (layer == null) continue;
    final value = read(layer, path);
    if (!isAbsent(value)) return (layer: name, value: value!);
  }
  return null;
}

/// A flat map's own key. Dart has no prototypes, but the rule is the same as in the reference
/// implementation: a path is a key, not a walk.
Object? _ownKey(Map<String, Object?> layer, String path) => layer[path];

/// Longest record path (mirror of the web reader's `MAX_DATA_PATH_LENGTH`).
const int kMaxDataPathLength = 128;

final RegExp _pathSegment = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

/// Segments that cannot occur in a data path. Dart has no prototypes, but the key goes to the host
/// app, which may put it into JSON for its backend or a web view.
const List<String> _forbiddenSegments = ['__proto__', 'constructor', 'prototype'];

/// Whether [value] has the shape of a data path: identifiers separated by dots (`item.selectedId`),
/// without forbidden segments, no longer than [kMaxDataPathLength].
bool isSafeDataPath(Object? value) {
  if (value is! String || value.isEmpty || value.length > kMaxDataPathLength) return false;
  for (final segment in value.split('.')) {
    if (!_pathSegment.hasMatch(segment) || _forbiddenSegments.contains(segment)) return false;
  }
  return true;
}

/// A collection record by entity paths: the `name` field of an `item` record is `item.name`. A field
/// already named by a full path stays as it is. The prefix is named by `Repeater.item` (the data
/// dictionary); it is not guessed from the collection name.
///
/// A nested map is expanded into paths (`task: {title}` gives `item.task.title`): the record for the
/// host is a flat "path to value" map, the same shape as `source.record` in the web reader. Lists stay a
/// value (`item.tags`). Keys that do not have the shape of a data path are dropped (see
/// [isSafeDataPath]), and so are `null`s: a record does not carry an absent value.
///
/// A record that is not a map (a list of scalars) becomes the value of the prefix itself.
Map<String, Object?> instanceRecord(String itemPrefix, Object? fields) {
  final record = <String, Object?>{};
  void put(String path, Object? value) {
    if (isAbsent(value) || !isSafeDataPath(path)) return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is String) put('$path.$key', entry.value);
      }
      return;
    }
    record[path] = value;
  }

  if (fields is Map) {
    for (final entry in fields.entries) {
      final key = entry.key;
      if (key is! String) continue;
      put(key.startsWith('$itemPrefix.') ? key : '$itemPrefix.$key', entry.value);
    }
  } else {
    put(itemPrefix, fields);
  }
  return Map<String, Object?>.unmodifiable(record);
}

/// A record that can be handed to the host and carried to the next screen: a new immutable map with
/// only keys of the data path shape ([isSafeDataPath]) and non-`null` values. `null` stays `null`: "no
/// record" is not the same as "an empty record".
Map<String, Object?>? safeRecord(Map<String, Object?>? record) {
  if (record == null) return null;
  return Map<String, Object?>.unmodifiable({
    for (final entry in record.entries)
      if (isSafeDataPath(entry.key) && !isAbsent(entry.value)) entry.key: entry.value,
  });
}

/// A record over a record: the inner instance is stronger than the outer one, and that is stronger than
/// the record the screen was opened with. An absent value overrides nothing. `null` means there is no
/// record at all (not "an empty record").
Map<String, Object?>? overlayRecord(Map<String, Object?>? outer, Map<String, Object?>? inner) {
  if (inner == null) return outer;
  if (outer == null) return inner;
  final merged = <String, Object?>{...outer};
  for (final entry in inner.entries) {
    if (!isAbsent(entry.value)) merged[entry.key] = entry.value;
  }
  return Map<String, Object?>.unmodifiable(merged);
}

/// How the screen a transition leads to is shown.
enum OpenedPresentation { page, modal }

/// The record a screen opened by `navigate` gets.
///
///  * from a list row: the node's record scope;
///  * not from a row, a modal layer: the record of the screen under it (which is the node's record
///    scope, since outside a list it equals the screen's record);
///  * not from a row, a page: no record.
///
/// Why a page does not inherit: "Back to catalog" on a detail screen is an ordinary `navigate`; if it
/// carried the record further, the catalog would open "about the bottle", and choosing a circle on it
/// would no longer lead to the details of the chosen item. A list row NAMES a record, a screen button
/// does not.
///
/// Since 9.8.0 there is a fourth input, [carryRecord]: the action's explicit word (`ButtonAction
/// .carryRecord`, exactly `true`). Then even a page not opened from a row gets the node's record scope
/// ("Choose delivery" from the detail screen is a page about the same item). The default rule does not
/// change: "Back to catalog" without the word still opens a clean catalog.
Map<String, Object?>? recordForOpenedScreen({
  required Map<String, Object?>? nodeRecord,
  required bool insideListItem,
  required OpenedPresentation presentation,
  bool carryRecord = false,
}) {
  if (insideListItem || presentation == OpenedPresentation.modal || carryRecord) return nodeRecord;
  return null;
}
