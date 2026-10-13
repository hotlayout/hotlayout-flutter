/// COLLECTION source - **host data, not part of the renderer**.
///
/// The boundary runs exactly where it does in a real app: the renderer knows that
/// a screen has an entry (the record it was opened with) and asks the host what values
/// that entry means; WHAT `item.id` is and where the rest of the entity comes from is the
/// host's business. If this file lived in `render/`, the renderer would have to learn the words
/// of a specific domain, and a second product on the same contract could no longer
/// supply its own entities. That is why the file is named by ROLE ("collection
/// source") and not by demo content.
///
/// The source format is the one already stored in Firebase Storage: a wrapper with the
/// collection name from the data dictionary and an array of records.
///
/// ```jsonc
/// { "items": [ { "id", "name", "image", "description", "price" } ] }
/// ```
///
/// Field names here match the paths the document is bound to
/// (`item.name`, `item.price`) - this is a convention about DATA, not about the
/// contract. So there is nothing to translate a backend dictionary into a document
/// dictionary: the adapter carries values verbatim, with their types. Numbers stay
/// numbers: `ProgressBar` expects a number, and the string "3" would be a type
/// error there, not a value.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/data/document_source.dart';

/// Record path by which a list row names its entity.
///
/// Since 9.2.0 a list row carries its record itself: the renderer hands it to the host in
/// `ScreenScopeRequest.record` (a flat "path -> value" map). The transition parameter
/// (`action.params`) no longer works for this - it is the same for all instances of
/// the template - and the demo has no `itemId` convention.
const String kRecordIdPath = 'item.id';

/// Data path that holds the selected record.
///
/// The same one the document binds `ChoiceGroup.value` to on the selection screen.
/// This is a DIFFERENT interaction from a list row: the renderer carries the row's record
/// itself, while this path is what the user marked with a radio and confirmed with a
/// button (a button outside a list carries no record).
const String kSelectedItemPath = 'item.selectedId';

/// Name of the collection in the data dictionary that the demo source carries.
const String kDemoCollection = 'items';

/// Prefix of the record entity of the same collection.
///
/// The data dictionary names both separately (`collections[].path` and
/// `collections[].item`), and they are separate here too: the collection is `items`, while
/// the record in binding paths is `item`.
const String kDemoItem = 'item';

/// A record by identifier, plus the ability to produce a screen data scope.
@immutable
final class CollectionCatalog {
  const CollectionCatalog(this._byId);

  /// No catalog: it did not arrive, could not be parsed, or was never requested.
  ///
  /// There is deliberately no separate "loading" state - an empty catalog is the
  /// answer "no data yet", and bindings on it take the document's `fallback`.
  /// So the screen is intact without a network and no spinner ever appears.
  static const CollectionCatalog empty = CollectionCatalog(<String, Map<String, Object?>>{});

  /// `id -> {item: {...}, <nested entity>: {...}}` - already in the form of binding
  /// paths.
  final Map<String, Map<String, Object?>> _byId;

  bool get isEmpty => _byId.isEmpty;

  int get length => _byId.length;

  /// Whether the catalog has a record with this id - for the service panel and tests.
  bool contains(String id) => _byId.containsKey(id);

  /// Screen data scope by its entry.
  ///
  /// The record is looked up in TWO ways, in this order:
  ///
  /// 1. `item.id` of the record the screen was opened with - a tap on a list row: the
  ///    renderer brought the row's record itself ([ScreenScopeRequest.record]);
  /// 2. `item.selectedId` in screen data - the user marked a record with a radio,
  ///    and the button did a plain `navigate`, which carries no record. This is how
  ///    the demo catalog works. `read` goes through the layers record -> session ->
  ///    document data: a screen without a record sees what was picked by finger.
  ///
  /// An empty map means "I substitute nothing": the record is named by neither
  /// way, or there is no such record in the catalog. Then the screen is drawn from
  /// document data, exactly as before scopes existed. The fields of the record itself
  /// (a row's `item.name`) are stronger than the host scope anyway: the host only
  /// supplements it with what the row lacks (`task.*`).
  Map<String, Object?> scopeFor(ScreenScopeRequest request) {
    final id = _asId(request.record?[kRecordIdPath]) ?? _asId(request.read(kSelectedItemPath));
    if (id == null || id.isEmpty) return const {};
    return _byId[id] ?? const {};
  }

  /// Identifier from data. Not a string - not an identifier: numbers and maps here
  /// mean the document bound `value` to the wrong place.
  static String? _asId(Object? value) => value is String ? value : null;

  /// Catalog parsing. Never throws: a broken catalog means "no data", not
  /// "no screen".
  ///
  /// [collection] is the wrapper key in the JSON, [item] is the prefix under which a record
  /// becomes visible to document bindings. Both names come from the data dictionary
  /// rather than being hard-coded here: a second collection source (`tasks` -> `task`)
  /// uses the same code.
  static CollectionCatalog parse(
    String source, {
    String collection = kDemoCollection,
    String item = kDemoItem,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      debugPrint('[demo] collection "$collection" is not JSON: $error');
      return empty;
    }
    if (decoded is! Map) return empty;
    final list = decoded[collection];
    if (list is! List) return empty;

    final byId = <String, Map<String, Object?>>{};
    for (final raw in list) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! String || id.isEmpty) continue;

      byId[id] = Map<String, Object?>.unmodifiable(<String, Object?>{
        // The whole record, under the prefix of its entity (`item.name`, `item.price`).
        item: _stringKeyed(raw),
        /*
         * Nested entities go UNDER THEIR OWN NAMES, not only inside the record.
         *
         * This is a SYNONYM of the path, not a copy of the data: a document showing a task
         * inside a catalog record does not need to know that the task is nested in it.
         * The rule is structural: every nested map field becomes a prefix.
         */
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is Map && entry.key != item)
            entry.key as String: _stringKeyed(entry.value as Map<Object?, Object?>),
      });
    }
    return CollectionCatalog(Map<String, Map<String, Object?>>.unmodifiable(byId));
  }

  /// JSON map in a form suitable for `ScreenData`.
  ///
  /// There are deliberately no renames here: when the data source names fields the same
  /// as the document, any alias at this point is a second rule that can diverge from the
  /// first. Values are carried VERBATIM, with their types: a number stays a number.
  static Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      });
}

/// Where the host gets the collection from.
///
/// The transport is the same [DocumentTransport] as for the document, and this is not
/// about saving lines: a second abstraction over the network would mean a second set of
/// timeout rules and a second way to fail during a presentation.
final class CollectionSource {
  CollectionSource({
    required this.url,
    required this.transport,
    this.collection = kDemoCollection,
    this.item = kDemoItem,
    this.timeout = kCollectionFetchTimeout,
  });

  final Uri url;
  final DocumentTransport transport;

  /// Collection name in the data dictionary - also the wrapper key in the JSON.
  final String collection;

  /// Prefix of this collection's record entity.
  final String item;

  final Duration timeout;

  /// Reads the collection. **Never throws** - any failure yields
  /// [CollectionCatalog.empty], i.e. a screen with document fallbacks.
  ///
  /// This is the same policy as for the document (fall back instead of failing), except that
  /// the floor here is not a bundled copy but the document itself: it always has something
  /// to show without data.
  Future<CollectionCatalog> load() async {
    try {
      final response = await transport.fetch(url).timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('[demo] collection "$collection": the server answered ${response.statusCode}');
        return CollectionCatalog.empty;
      }
      return CollectionCatalog.parse(response.body, collection: collection, item: item);
    } on TimeoutException {
      debugPrint('[demo] collection "$collection" did not arrive within $timeout: drawing the document fallbacks');
      return CollectionCatalog.empty;
    } on Object catch (error) {
      debugPrint('[demo] collection "$collection" could not be read ($error): drawing the document fallbacks');
      return CollectionCatalog.empty;
    }
  }
}

/// How long to wait for the collection.
///
/// The same as for the document: waiting blocks nobody here (the screen is already
/// drawn with fallbacks), and a longer time would only mean data being
/// swapped in before the viewer's eyes half a minute after opening.
const Duration kCollectionFetchTimeout = kDocumentFetchTimeout;
