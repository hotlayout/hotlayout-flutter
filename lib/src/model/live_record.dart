/// THE LIVE RECORD OF A PAGE (schema 9.27.0; rules in `x-liveRecord`).
///
/// The record a stack frame holds (opened from a list row, inherited by a modal layer, carried by `carryRecord`) used
/// to be frozen at the moment of the transition. Now it is a CHAIN of links, one per `Repeater` instance it came from,
/// outer first; a link remembers the collection the list read (`source`), the entity (`item`) and the fields of the
/// record. Whenever the host gives new data, every link of every frame looks for its record by the key `<item>.id`:
/// first in its own collection, then in every other collection the document names for the same entity. A link that is
/// found takes the new record whole; one that is not keeps the last record it had. The stack, the screen-shown event,
/// analytics and the cause of a show do not change.
///
/// Mirror of `live-record.ts`; `test/live_record_cases_test.dart` runs the shared table row by row.
library;

import 'record_scope.dart';

/// The field that keys a record of an entity: `task.id` for `task`.
const String kLiveRecordKeyField = 'id';

/// One link of the chain: a `Repeater` instance the record came from.
final class RecordLink {
  const RecordLink({required this.source, required this.item, required this.fields});

  /// The collection the list read (`Repeater.source`).
  final String source;

  /// The entity of the record (`Repeater.item`).
  final String item;

  /// The fields of the record, as the host gave them: a short name or a full path.
  final Object? fields;

  @override
  String toString() => 'RecordLink($source, $item, $fields)';
}

/// The links of a frame, outer first. Empty: a frame without a record.
typedef RecordChain = List<RecordLink>;

/// A collection by name, as the host gave it now; anything that is not a list holds no records.
typedef CollectionLookup = Object? Function(String source);

/// The collections of every entity, in the order of the document: `task` to [`tasks`, `doneTasks`].
typedef EntitySources = Map<String, List<String>>;

/// The key of a record: a non-empty string or a finite number. Anything else, or no field, and the record is not live.
Object? liveKeyOf(String item, Object? fields) {
  final key = instanceRecord(item, fields)['$item.$kLiveRecordKeyField'];
  if (key is String) return key.isEmpty ? null : key;
  if (key is num) return key.isFinite ? key : null;
  return null;
}

/// The record of a frame: the links laid over one another, the inner one stronger. `null` for no links.
Map<String, Object?>? recordOfChain(RecordChain chain) {
  Map<String, Object?>? record;
  for (final link in chain) {
    record = overlayRecord(record, instanceRecord(link.item, link.fields));
  }
  return record;
}

/// The chain of a node: the links of its frame, and over them the instances the node is drawn in.
RecordChain chainWith(RecordChain? frame, RecordChain? instances) {
  if (instances == null || instances.isEmpty) return frame ?? const [];
  return frame == null || frame.isEmpty ? instances : [...frame, ...instances];
}

/// The collections of every entity as the DOCUMENT names them: the `source` of every `Repeater` with this `item`,
/// screens in the order of the document, depth first, each collection once. A reader has no data dictionary: the
/// document is all it knows about which collections carry the same entity. [roots] are the raw roots of the screens.
EntitySources entitySourcesOf(Iterable<Object?> roots) {
  final found = <String, List<String>>{};
  void walk(Object? value, int depth) {
    if (value is! Map || depth > 64) return;
    final props = value['props'];
    if (value['type'] == 'Repeater' && props is Map) {
      final source = props['source'];
      final item = props['item'];
      if (source is String && source.isNotEmpty && item is String && item.isNotEmpty) {
        final list = found.putIfAbsent(item, () => []);
        if (!list.contains(source)) list.add(source);
      }
    }
    final children = value['children'];
    if (children is List) {
      for (final child in children) {
        walk(child, depth + 1);
      }
    }
  }

  for (final root in roots) {
    walk(root, 0);
  }
  return found;
}

/// Where a link looks for its record: its own collection first, then the others of the same entity.
List<String> searchOrderOf(RecordLink link, EntitySources sources) => [
  link.source,
  ...?sources[link.item]?.where((source) => source != link.source),
];

/// The record of the link in the collections the host gives now, or `null`: the link is not live, or no collection
/// holds a record with its key. The first record with the key wins; no type conversion.
Object? findLiveRecord(RecordLink link, CollectionLookup collections, EntitySources sources) {
  final key = liveKeyOf(link.item, link.fields);
  if (key == null) return null;
  for (final source in searchOrderOf(link, sources)) {
    final listed = collections(source);
    if (listed is! List) continue;
    for (final candidate in listed) {
      if (candidate is Map && liveKeyOf(link.item, candidate) == key) {
        return candidate;
      }
    }
  }
  return null;
}

bool _sameRecord(String item, Object? a, Object? b) {
  if (identical(a, b)) return true;
  final left = instanceRecord(item, a);
  final right = instanceRecord(item, b);
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) return false;
  }
  return true;
}

/// The chain of a frame after the host gave new collections. A found link takes the new record whole; one that was
/// not found keeps its last record. Nothing changed: the same list, so the caller need not make a new frame.
RecordChain refreshRecordChain(RecordChain chain, CollectionLookup collections, EntitySources sources) {
  var changed = false;
  final next = <RecordLink>[];
  for (final link in chain) {
    final found = findLiveRecord(link, collections, sources);
    if (found == null || _sameRecord(link.item, found, link.fields)) {
      next.add(link);
    } else {
      changed = true;
      next.add(RecordLink(source: link.source, item: link.item, fields: found));
    }
  }
  return changed ? next : chain;
}

/// Mirror of the scalar rows of `x-liveRecord`; checked against the artifact by a test.
const Map<String, Object> kLiveRecordRules = {
  'appliesTo':
      'every record a frame of the stack holds (x-dataScope): opened from a list row, inherited by a modal layer, carried by «carryRecord»',
  'field': 'none: no document field turns it on, and no document changes its meaning while the data stays the same',
  'when': 'whenever the reader is given new collections; every frame of the stack, not only the top one',
  'found': 'the instance takes the found record whole: a field the new record lacks is gone from that instance',
  'notFound':
      'the instance keeps the last record it had: it neither empties nor goes back to the record of the navigation',
  'notAShow':
      'the stack, the screen-shown event, analytics and the show cause do not change; the screen keeps its scroll, carousels and inputs',
  'layers': 'unchanged: record, session, host, data',
  'valueTransition': 'a bound value that changed animates as any changed value does («animateChanges»)',
  'handed': 'actions on the screen carry the refreshed record to the host',
};
