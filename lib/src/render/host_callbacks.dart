/// What the host passes to the renderer: callbacks for actions, analytics, screen
/// views and written values, and how a press is handed to them.
library;

import '../model/action.dart';
import '../model/action_catalog.dart';
import '../model/haptic.dart';

/// Receives every action the renderer did not perform itself, together with
/// the id of the node that was tapped.
///
/// The renderer handles `navigate`, `navigate.back`, `navigate.section` and the two write actions (`setValue`,
/// `toggleValue`) itself; any other `action.type` is a free-form string and the host decides what to do with it.
typedef SduiActionCallback = void Function(ButtonAction action, String nodeId);

/// Receives every action the renderer did not perform itself, together with
/// the id of the node that was tapped and **the record of that node** (schema 9.2.0,
/// `actionRecord: 'node-record-scope'`).
///
/// This is a separate typedef rather than a third parameter of [SduiActionCallback]: a
/// function with two parameters is not a subtype of one with a named optional third, so
/// changing the old typedef would break EVERY existing host. A new capability is a new
/// optional input (`onRecordAction`); the old one stays as it was.
///
/// [record] answers "which record is this action about": the record of the
/// list row the node is drawn in, laid over the record the screen was opened
/// with — a flat map of data paths to values (`{'item.id': 'bottle',
/// 'item.name': 'Bottle'}`), the same shape as `source.record` in
/// `@hotlayout/react`. It is `null` when the node has no record: a button
/// outside any list on a screen opened without one. The map is unmodifiable and
/// holds only keys that have the form of a data path.
///
/// Treat values from [record] as user input: validate an id on your backend
/// before you act on it.
typedef SduiRecordActionCallback =
    void Function(ButtonAction action, String nodeId, Map<String, Object?>? record);

/// Receives the analytics event of a press (`action.track`, schema 9.8.0,
/// `actionTrack: 'once-per-press-before-action'`): once per press,
/// BEFORE anything else the press causes — before the action is performed or
/// handed to the host, and for the `none` action too. [nodeId] and [record] are
/// the same as in [SduiRecordActionCallback].
///
/// It is a separate input rather than a field of [ButtonAction]: the event is not an action
/// but a companion of any action, and a host that counts analytics should not also have to
/// handle the action itself.
typedef SduiTrackCallback = void Function(TrackEvent event, String nodeId, Map<String, Object?>? record);

/// Receives the haptic request of a press (`action.haptic`, schema 9.25.0): once per press, BEFORE the analytics event
/// and the action of the same press, also for the `none` action. The reader never vibrates by itself: the host decides
/// what the word means (`HapticFeedback.lightImpact` and the like) and whether to do it at all, with the settings of the
/// user. [nodeId] and [record] are the same as in [SduiTrackCallback].
typedef SduiHapticCallback = void Function(HapticWord word, String nodeId, Map<String, Object?>? record);

/// Receives the "screen shown" event (`ScreenShown`): exactly once per show,
/// after the frame, never from `build`.
typedef SduiScreenShownCallback = void Function(ScreenShown shown);

/// What the host is told when a screen asks for its data: the parameters the
/// navigation passed, `record` — the record the screen was opened with (a flat
/// map of data paths, `null` when it was opened without one: a button outside
/// a list, an entry point), and `read` — a lookup of a path in the data
/// without the screen scope, where the record is already the strongest layer.
///
/// It is a pair rather than just the parameter map: a screen's entity can be named in two
/// ways, by a navigation parameter or by what the user chose in a bound field on the previous
/// screen, and both must be available to ONE rule. [read] looks at the data without the scope
/// (otherwise the scope would be computed from itself).
///
/// A host that supplies an entity for the screen should look at `record`
/// first and not search for the entity in the session: a screen opened from a
/// list row already knows which record it is about.
typedef ScreenScopeRequest = ({
  Map<String, String> params,
  Map<String, Object?>? record,
  Object? Function(String path) read,
});

/// Supplies the data of one screen from its navigation parameters.
///
/// The renderer knows neither what `itemId` is nor where a record comes from: it only knows
/// that a screen has an ENTRY and asks the host which values that entry means. Otherwise an
/// entity dictionary would have to be hard-wired into the renderer.
///
/// Return a nested map (`{'item': {...}}`) or a flat one
/// (`{'item.name': ...}`; [ScreenData] reads both); return an empty map to supply nothing.
/// Called on every build, so data that arrives after the navigation still reaches the
/// open screen.
typedef ScreenScopeResolver = Map<String, Object?> Function(ScreenScopeRequest request);

/// Receives a value the user changed in a bound input: a [String] from a
/// `TextField` (and from a `ChoiceGroup`), a [bool] from a `Switch` or a
/// `Checkbox` (9.13.0), a [num] from a number `TextField` (9.14.0: an [int] for
/// a whole value, a [double] otherwise; an empty [String] when the field was
/// cleared or holds something that is not a number). Called on every change, at
/// once and without throttling — throttling a network behind it is the host's job.
///
/// The `setValue` and `toggleValue` actions (9.19.0) write through the same callback and never reach `onAction`:
/// the literal of the action, typed by its `valueType` ([String], [bool] or [num]; an empty [String] for a cleared
/// number), under the data path it names. A path the reader does not write to (a prototype segment, not the form of
/// a data path) is not written at all. The reader has no list of paths the host allows; the host sees every write
/// here and may drop the ones it does not expect.
///
/// This is neither a contract "action" nor a host event: a field whose value is bound to a
/// path reads that path and writes to it. Whoever holds the data decides where exactly (here
/// it is [ScreenFlow], and the write lives as long as the stack).
///
/// Used with `renderDocument` and `renderScreen`. With `renderScreen` the host
/// that keeps the screen state itself also feeds the value back through
/// `session` or `data`.
typedef SduiValueWrite = void Function(String path, Object value);

// Where an action came from: the record scope of its node, and whether the node is drawn in
// a `Repeater` instance. The second is needed not by the host but by the stack: `navigate`
// from a list row opens the screen with the row's record, and a page without it does
// (`recordForOpenedScreen`).
//
// `read` reads a data path with THIS NODE'S scope at the moment of the press, the same one
// the text binding on it uses (`paramBindings`, schema 9.8.0): node record, session, host
// scope, data.
typedef ActionOrigin = ({
  Map<String, Object?>? record,
  bool insideListItem,
  Object? Function(String path) read,
});

Object? readNothing(String path) => null;

/// The haptic request of a press: the very first thing a press does, before the analytics event (`order: haptic, track,
/// action`). Nothing when the action has no word or the host passed no callback.
void sendHaptic(ButtonAction action, String nodeId, ActionOrigin origin, SduiHapticCallback? onHaptic) {
  final word = action.haptic;
  if (word == null || onHaptic == null) return;
  onHaptic(word, nodeId, origin.record);
}

/// Analytics event of a press: after the haptic request, FIRST among the rest, exactly once, for any action (including `none`).
void sendTrack(ButtonAction action, String nodeId, ActionOrigin origin, SduiTrackCallback? onTrack) {
  final track = action.track;
  if (track == null || onTrack == null) return;
  onTrack(track, nodeId, origin.record);
}

/// Hands the action to the host as the host receives it (`handedAction`): parameters from
/// data substituted, a standard action checked against its form. `none` never reaches the
/// host: it is a reader action that does nothing.
///
/// The answer is the host's promise, when the callback returned a `Future` (the callback types are `void`, so a
/// closure or a method may return one anyway; [HostActions.handle] does): a "swipe to confirm" button stays busy
/// until it completes. `null` when there was nothing to wait for. A failure of the `Future` is the host's to report;
/// here it only ends the waiting.
Future<void>? handToHost(
  ButtonAction action,
  String nodeId,
  ActionOrigin origin, {
  required SduiActionCallback? onAction,
  required SduiRecordActionCallback? onRecordAction,
}) {
  if (action.type == ButtonAction.noneType) return null;
  final handed = action.handOver(origin.read);
  // The callbacks are typed `void`, so the result can only be read through `Function.apply`.
  final Object? raw = onRecordAction != null
      ? Function.apply(onRecordAction, [handed, nodeId, origin.record])
      : (onAction == null ? null : Function.apply(onAction, [handed, nodeId]));
  // Only a real `Future` is a promise; anything else (a thenable of another kind, a number) is "no promise".
  return raw is Future ? raw.then<void>((_) {}, onError: (Object _) {}) : null;
}

/// Takes an action with its origin; the result is the host's promise (see [handToHost]), or `null`.
typedef ActionHandler = Future<void>? Function(ButtonAction action, String nodeId, ActionOrigin origin);
