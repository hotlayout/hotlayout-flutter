// The schedule of a place (placement map 1.1.0): a place may name documents that stand in it for a
// window of time. The reader looks at the clock of the device itself, so a banner appears on time
// and without a network, and asks [nextPlacementBoundary] when the answer may change next.
//
// The rules are those of the `x-placementSchedule` block of `assets/contract/placements.json`; the
// `scheduleCases` of the shared table run every row of them.
//
// Tolerant reading of a schedule:
//  - `schedule` that is not a list (`null` included) is no schedule;
//  - a window with `documentId: null` is a pause: the place is empty for its time, and its `entry`
//    is not read at all;
//  - a broken window (not an object, no or malformed `documentId`, malformed `entry`, an instant of
//    another form, `until` not after `from`) is skipped whole: it shows nothing and gives no
//    boundary, and the place does not become unreadable because of it;
//  - a broken permanent content is `unreadable` whatever the schedule says;
//  - when windows overlap, the one that started LATER wins; at an equal `from`, the earlier one in
//    the list.
library;

import 'placement_map.dart';

/// The longest delay a timer is given; a longer wait is cut and counted again at its end.
const int kPlacementMaxTimerMs = 2147483647;

/// The pattern of an instant, as the artifact gives it.
const String kPlacementInstantPattern =
    r'^(?:20\d{2}-(?:(?:0[13578]|1[02])-(?:0[1-9]|[12]\d|3[01])|(?:0[469]|11)-(?:0[1-9]|[12]\d|30)|02-(?:0[1-9]|1\d|2[0-8]))|20(?:[02468][048]|[13579][26])-02-29)T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\dZ$';

final RegExp _instantPattern = RegExp(kPlacementInstantPattern);

/// Milliseconds since the epoch for an instant of the contract form `YYYY-MM-DDTHH:MM:SSZ` (UTC,
/// whole seconds, years 2000 to 2099, a real date); `null` for anything else.
///
/// The pattern is checked first, then the milliseconds are computed from its parts, so a date the
/// calendar does not have is never carried over to the next month.
int? placementInstantMs(Object? value) {
  if (value is! String || !_instantPattern.hasMatch(value)) return null;
  final parts = value.substring(0, 19).split(RegExp(r'[-T:]')).map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).millisecondsSinceEpoch;
}

class _Window {
  const _Window(this.documentId, this.entry, this.from, this.until);

  /// `null` is a pause.
  final String? documentId;
  final String? entry;
  final int from;
  final int until;
}

/// One window; `null` when it is broken and must be skipped.
_Window? _readWindow(Object? value) {
  if (value is! Map || !value.containsKey('documentId')) return null;
  final documentId = value['documentId'];
  if (documentId != null && (documentId is! String || !isPlacementDocumentId(documentId))) return null;
  String? entry;
  // A pause never reads its entry, not even a broken one.
  if (documentId != null) {
    final raw = value.containsKey('entry') ? value['entry'] : null;
    if (raw != null) {
      if (raw is! String || !isPlacementEntry(raw)) return null;
      entry = raw;
    }
  }
  final from = placementInstantMs(value.containsKey('from') ? value['from'] : null);
  final until = placementInstantMs(value.containsKey('until') ? value['until'] : null);
  if (from == null || until == null || until <= from) return null;
  return _Window(documentId as String?, entry, from, until);
}

/// The windows of the place [name], or `null` when the place has no readable permanent content.
List<_Window>? _scheduleOf(PlacementMapRead map, String name) {
  final base = resolvePlacement(map, name);
  if (map is! PlacementMapOk || base.status == PlacementStatus.unknown || base.status == PlacementStatus.unreadable) {
    return null;
  }
  final place = map.places[name];
  if (place is! Map || !place.containsKey('schedule')) return const <_Window>[];
  final schedule = place['schedule'];
  if (schedule is! List) return const <_Window>[];
  return [for (final item in schedule) ?_readWindow(item)];
}

/// What stands in the place [name] at the instant [nowMs] (milliseconds since the epoch): the window
/// that lasts (`from` included, `until` excluded), otherwise the permanent content. Without a
/// schedule it is [resolvePlacement].
PlacementResolution resolvePlacementAt(PlacementMapRead map, String name, int nowMs) {
  final base = resolvePlacement(map, name);
  final schedule = _scheduleOf(map, name);
  if (schedule == null) return base;
  _Window? winner;
  for (final item in schedule) {
    if (item.from > nowMs || nowMs >= item.until) continue;
    if (winner == null || item.from > winner.from) winner = item;
  }
  if (winner == null) return base;
  if (winner.documentId == null) return const PlacementResolution(PlacementStatus.empty);
  return PlacementResolution(PlacementStatus.document, documentId: winner.documentId, entry: winner.entry);
}

/// The earliest instant after [nowMs] at which [resolvePlacementAt] MAY give another answer: the
/// smallest `from` or `until` of a readable window that is later than [nowMs]. `null` means the
/// schedule changes nothing any more (or the place has none). At a boundary the answer may turn out
/// the same, for instance when another window holds the place; that is no change for the host.
int? nextPlacementBoundary(PlacementMapRead map, String name, int nowMs) {
  final schedule = _scheduleOf(map, name);
  if (schedule == null) return null;
  int? next;
  for (final item in schedule) {
    for (final edge in [item.from, item.until]) {
      if (edge > nowMs && (next == null || edge < next)) next = edge;
    }
  }
  return next;
}

/// Ids of the documents the place [name] can show: its permanent content and every readable window.
List<String> placementDocumentIds(PlacementMapRead map, String name) {
  final ids = <String>{};
  final permanent = resolvePlacement(map, name).documentId;
  if (permanent != null) ids.add(permanent);
  for (final item in _scheduleOf(map, name) ?? const <_Window>[]) {
    final id = item.documentId;
    if (id != null) ids.add(id);
  }
  return ids.toList();
}
