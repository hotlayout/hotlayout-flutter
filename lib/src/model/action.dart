import 'package:flutter/foundation.dart' show VoidCallback;

import 'action_catalog.dart';

// An action as written in the document: `{ type: string, params?: Map<String, String> }`.
//
// `type` is a free string rather than an enum: an unknown action must degrade
// as gently as an unknown widget type. The reader does not interpret it; it
// hands it out with its parameters and the host decides whether it can run it.
/// What a button or a list row does when tapped.
///
/// [type] is a free string. The renderer performs [navigate], [navigateBack], [navigateSection] and the two write
/// actions `setValue` and `toggleValue` (9.19.0) itself; every other type is handed to the host through
/// `onAction` untouched.
final class ButtonAction {
  /// Creates an action of [type] with [params].
  const ButtonAction(this.type, [this.params = const {}])
    : standard = null,
      invalid = null,
      paramBindings = const {},
      track = null,
      carryRecord = false;

  const ButtonAction._(
    this.type,
    this.params, {
    this.standard,
    this.invalid,
    this.paramBindings = const {},
    this.track,
    this.carryRecord = false,
  });

  // The contract default for `Button.action`.
  /// An action that does nothing.
  static const ButtonAction none = ButtonAction('none');

  // Navigation to a screen of THIS document; the target is `params.screenId`.
  // Together with `navigate.back` and `navigate.section` it is one of the few
  // actions the reader interprets itself; the rest go to the host opaque.
  /// Opens the screen named in `params['screenId']`. Reaches the host only
  /// when the document has no such screen.
  static const String navigate = 'navigate';

  // One step back in the screen stack. It has no target by definition.
  /// Goes one screen back. Reaches the host only from the first screen, where
  /// it means "leave the flow".
  static const String navigateBack = 'navigate.back';

  // Section switch (9.12.0): the stack becomes ONE named screen and everything
  // above it is closed. The target is `params.screenId`, as in `navigate`. The
  // reader performs it itself.
  /// Switches to the section screen named in `params['screenId']`: the stack
  /// becomes that one screen. Reaches the host only when the document has no
  /// such screen.
  static const String navigateSection = 'navigate.section';

  // The `type` of the "no action" value.
  /// An action that does nothing and does not reach the host (it may still
  /// carry an analytics `track`).
  static const String noneType = 'none';

  /// The parameter of [navigate] that names the target screen.
  static const String screenIdParam = 'screenId';

  /// The action type, as written in the document.
  final String type;
  /// Parameters of the action. Only string values are read (a number or a flag
  /// is skipped, not turned into text), and an entry whose key is not of the
  /// schema form is skipped too. In an action handed to the
  /// host these are the parameters AFTER `paramBindings` were applied (9.8.0).
  final Map<String, String> params;

  // ACTION CATALOG (9.8.0). The action the host receives is [handOver] of the
  // document's action: `standard` and `invalid` are set only there, never both.
  /// A catalog action the HOST performs (`openUrl`, `deeplink`, `close`) whose
  /// parameters passed the form check. `null` for any other action, and for
  /// an invalid one. The renderer never performs it; see [runStandardAction].
  final StandardAction? standard;

  /// A catalog action whose parameter failed the form check. Still handed to
  /// the host (it may know more than the document), but never run by
  /// [runStandardAction].
  final InvalidActionParam? invalid;

  // DOCUMENT fields: the reader uses them itself and does not hand them to the
  // host (the handed-over action has no `track`, `paramBindings` or `carryRecord`).
  /// Parameter name -> data path, as written in the document. Empty in an
  /// action handed to the host.
  final Map<String, String> paramBindings;

  /// The analytics event of the press, as written in the document. `null` in an
  /// action handed to the host: the event goes to `onTrack`.
  final TrackEvent? track;

  /// `navigate` only: the opened page gets the record scope of the node even
  /// outside a list row. Exactly `true` in the document, nothing else.
  final bool carryRecord;

  // Only for [navigate] with a non-empty `screenId`. `null` means "not a
  // navigation" or "a navigation without a target" (a broken document).
  /// The target screen of a [navigate] action; `null` for any other action.
  String? get navigationTarget {
    if (type != navigate) return null;
    final target = params[screenIdParam];
    return target == null || target.isEmpty ? null : target;
  }

  /// The target screen of a [navigateSection] action; `null` for any other
  /// action and for a section action without a screen.
  String? get sectionTarget {
    if (type != navigateSection) return null;
    final target = params[screenIdParam];
    return target == null || target.isEmpty ? null : target;
  }

  /// Reads an action from decoded JSON. Never throws: anything unusable is [none].
  ///
  /// The 9.8.0 fields (`paramBindings`, `track`, `carryRecord`) are read one by
  /// one: a field of the wrong shape is ignored and the rest of the action
  /// works (`schemaCases` of `action-cases.json`).
  static ButtonAction parse(Object? raw) {
    if (raw is! Map) return none;
    final type = raw['type'];
    if (type is! String || type.isEmpty) return none;

    final track = TrackEvent.parse(raw['track']);
    final bindings = _parseBindings(raw['paramBindings']);
    final carry = raw['carryRecord'] == true;

    final rawParams = raw['params'];
    if (rawParams is! Map) {
      return ButtonAction._(type, const {}, paramBindings: bindings, track: track, carryRecord: carry);
    }
    // The schema promises Map<String, String> with keys of the `x-actions.params`
    // form, but a value from the network is checked here. An entry is SKIPPED
    // when its key has the wrong form (empty, containing whitespace, longer than
    // 32, `__proto__` / `constructor` / `prototype`) or its value is not a
    // string or is longer than 2048 characters. A number or a flag is NOT turned
    // into text: `3.0` is "3.0" in Dart and "3" in JS, so two readers would hand
    // the host different values.
    final params = <String, String>{};
    for (final entry in rawParams.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !isParamKey(key)) continue;
      if (value is! String || value.length > kParamValueMaxLength) continue;
      params[key] = value;
    }
    return ButtonAction._(
      type,
      Map.unmodifiable(params),
      paramBindings: bindings,
      track: track,
      carryRecord: carry,
    );
  }

  // `paramBindings`: parameter name -> data path. If it is not a map the field
  // is ignored; an entry with a `__proto__` key or a non-string or empty path
  // is skipped on its own (the other bindings still work).
  static Map<String, String> _parseBindings(Object? raw) {
    if (raw is! Map) return const {};
    final bindings = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final path = entry.value;
      if (key is! String || !isParamKey(key)) continue;
      if (path is! String || path.isEmpty || path.length > 128) continue;
      bindings[key] = path;
    }
    return bindings.isEmpty ? const {} : Map.unmodifiable(bindings);
  }

  /// The action as the HOST gets it (`handedAction` of the contract).
  ///
  /// [read] reads a data path with the data scope of the node, at the moment of
  /// the press. A non-empty string it returns replaces the literal of the
  /// parameter; anything else (a number, a flag, an object, `null`, an empty or
  /// too long string) is "no value" and the literal stays. A value that fails
  /// the address form is NOT replaced by the literal: the action is invalid.
  ///
  /// The result carries `standard` or `invalid` for a catalog action performed
  /// by the host, and neither `track`, nor `paramBindings`, nor `carryRecord`.
  ButtonAction handOver(Object? Function(String path) read) {
    final resolved = <String, String>{...params};
    final catalog = catalogActionOf(type);
    for (final entry in paramBindings.entries) {
      // A parameter of a catalog action whose catalog entry says
      // `bindable: false` (today `navigate.screenId`) is not read from data:
      // the literal applies. An app-specific action, and parameters the catalog
      // does not name (`openUrl.target`), are read from data as usual.
      if (catalog != null && _isUnbindable(catalog, entry.key)) continue;
      final value = boundParamValue(read(entry.value));
      if (value != null) resolved[entry.key] = value;
    }
    final checked = checkStandardAction(type, resolved);
    return ButtonAction._(
      type,
      resolved.isEmpty ? const {} : Map.unmodifiable(resolved),
      standard: checked.standard,
      invalid: checked.invalid,
    );
  }

  static bool _isUnbindable(CatalogAction catalog, String name) {
    for (final param in catalog.params) {
      if (param.name == name) return !param.bindable;
    }
    return false;
  }

  @override
  String toString() => params.isEmpty ? type : '$type($params)';
}

// THE STANDARD-ACTION HELPER: optional, and used by the host, not by the reader.
//
// The only place in the package where anything is executed, and the host calls
// it from its own `onAction`. The reader opens nothing itself: the render path
// has no `url_launcher` and no `Navigator.pop` outside its own stack, and a
// test guards that.
/// Performs the STANDARD action the host got in its `onAction`, with the
/// executors the host passes in. Call it from your own callback; the renderer
/// never calls it.
///
/// Acts only on `action.standard` (an invalid or an app-specific action gives
/// `false`):
///
///  * [openUrl] — opens an address that passed the `https` form; without it
///    `openUrl` is not performed;
///  * [deeplinkSchemes] — the schemes YOUR app owns. Without the list a
///    `deeplink` is never performed, whatever the document says: the contract's
///    own list of forbidden schemes is the first layer, this one is the second
///    and it is mandatory;
///  * [openDeeplink] — opens a link of one of those schemes;
///  * [close] — closes the flow (the renderer does not touch its stack).
///
/// Returns `true` when an executor was called. The package has no dependency
/// that could open an address by itself: `launchUrl` of `url_launcher` is the
/// usual executor (see the README).
bool runStandardAction(
  ButtonAction action, {
  void Function(String url)? openUrl,
  Iterable<String>? deeplinkSchemes,
  void Function(String url)? openDeeplink,
  VoidCallback? close,
}) {
  // Read the action ONCE. `action.standard` is a `final` field, but the class
  // may be subclassed; values are read into locals, and those are what gets
  // checked and passed to the executor.
  final standard = action.standard;
  switch (standard) {
    case OpenUrlAction():
      final url = standard.url;
      if (openUrl == null) return false;
      if (paramFormProblem(ActionParamForm.httpsUrl, url) != null) return false;
      openUrl(url);
      return true;
    case DeeplinkAction():
      final url = standard.url;
      final scheme = standard.scheme;
      if (openDeeplink == null || deeplinkSchemes == null) return false;
      // Only a list of strings counts: an `Iterable<Object?>` holding anything
      // else, or a bare string passed as a "list" of schemes, yields nothing.
      final owned = _stringSchemes(deeplinkSchemes);
      if (owned == null || !owned.contains(scheme)) return false;
      if (paramFormProblem(ActionParamForm.appLink, url) != null || appLinkSchemeOf(url) != scheme) return false;
      openDeeplink(url);
      return true;
    case CloseAction():
      if (close == null) return false;
      close();
      return true;
    case null:
      return false;
  }
}

/// The schemes the host passed: string elements only. An `Iterable` with a
/// non-string element means "no schemes". One pass only: a lazy `Iterable` may
/// give a different answer the second time.
Set<String>? _stringSchemes(Iterable<Object?> schemes) {
  final owned = <String>{};
  for (final scheme in schemes) {
    if (scheme is! String) return null;
    owned.add(scheme);
  }
  return owned;
}
