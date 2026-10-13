/// The action catalog: mirror of the builder's action catalog (schema 9.8.0,
/// artifact key `x-actions`).
///
/// An action's `type` stays an OPEN string: an action the reader does not know
/// is handed to the host. The catalog only NAMES six actions and says, for
/// each, who executes it and which parameters it has. All of that is artifact
/// data (`x-actions`); this file holds a second copy, which a test compares
/// with `screen-schema.json` field by field.
///
/// WHY THE READER OPENS NOTHING ITSELF. A document arrives over the network.
/// A URL from it, opened without the app's say-so, is a phishing page shipped
/// as one published file. So `openUrl`, `deeplink` and `close` reach the host
/// the same way as any action, but PARSED AND CHECKED ([StandardAction] or
/// [InvalidActionParam]), and the host executes them, itself or with the ready
/// `runStandardAction` (`action.dart`).
///
/// THE URL FORM IS AN ARTIFACT EXPRESSION, NOT `Uri.parse`: the platform
/// parser accepts `https:\\host`, a tab inside the scheme and
/// `https://bank@evil`. Only the expression gives the verdict; the host
/// receives the checked STRING, and `Uri` is merely a convenience getter
/// (`uri`) that never changes the verdict.
library;


/// Longest URL and longest value of any action parameter
/// (`x-actions.forms.*.maxLength`, `x-actions.paramBinding.maxLength`).
const int kActionUrlMaxLength = 2048;

/// Who executes an action (`x-actions.executors`).
enum ActionExecutor { reader, host }

/// Parameter value forms the catalog names (`x-actions.forms`). The reader judges only `httpsUrl` and `appLink`
/// here: `screenId` is checked by whoever holds the document, and `dataPath`, `literal` and `valueType` (the
/// parameters of the write actions) by the write rule itself (`write_action.dart`).
enum ActionParamForm { screenId, httpsUrl, appLink, dataPath, literal, valueType }

/// Why a parameter value failed its form (`x-actions.problems`).
enum ActionParamProblem {
  /// The value is absent or an empty string.
  missing('missing'),

  /// Longer than [kActionUrlMaxLength].
  tooLong('too-long'),

  /// The URL does not start with lowercase `https://`.
  notHttps('not-https'),

  /// The form expression did not match.
  malformed('malformed'),

  /// The expression matched, but the scheme is on the forbidden list.
  forbiddenScheme('forbidden-scheme');

  const ActionParamProblem(this.wire);

  /// The word the artifact uses for this problem.
  final String wire;
}

/// One parameter of a catalog action.
final class CatalogParam {
  const CatalogParam(this.name, this.form, {this.required = true, this.bindable = false});

  /// Name in `params`.
  final String name;

  /// The form the value is checked against.
  final ActionParamForm form;

  /// Whether the parameter is required.
  final bool required;

  /// Whether the value may come from data (`paramBindings`).
  final bool bindable;
}

/// A catalog entry.
final class CatalogAction {
  const CatalogAction(this.type, this.executor, [this.params = const []]);

  /// Action type; case-sensitive.
  final String type;

  /// Who executes it.
  final ActionExecutor executor;

  /// Parameters that have a form.
  final List<CatalogParam> params;
}

const String kSetValueActionType = 'setValue';
const String kToggleValueActionType = 'toggleValue';
const String kOpenUrlActionType = 'openUrl';
const String kDeeplinkActionType = 'deeplink';
const String kCloseActionType = 'close';

/// The URL parameter of `openUrl` and `deeplink`: one name for both actions.
const String kActionUrlParam = 'url';

/// The action catalog (`x-actions.catalog`), in artifact order.
const List<CatalogAction> kActionCatalog = [
  CatalogAction('none', ActionExecutor.reader),
  CatalogAction('navigate', ActionExecutor.reader, [CatalogParam('screenId', ActionParamForm.screenId)]),
  CatalogAction('navigate.back', ActionExecutor.reader),
  CatalogAction('navigate.section', ActionExecutor.reader, [CatalogParam('screenId', ActionParamForm.screenId)]),
  CatalogAction(kOpenUrlActionType, ActionExecutor.host, [
    CatalogParam(kActionUrlParam, ActionParamForm.httpsUrl, bindable: true),
  ]),
  CatalogAction(kDeeplinkActionType, ActionExecutor.host, [
    CatalogParam(kActionUrlParam, ActionParamForm.appLink, bindable: true),
  ]),
  CatalogAction(kCloseActionType, ActionExecutor.host),
  CatalogAction(kSetValueActionType, ActionExecutor.reader, [
    CatalogParam('path', ActionParamForm.dataPath),
    CatalogParam('value', ActionParamForm.literal, required: false),
    CatalogParam('valueType', ActionParamForm.valueType, required: false),
  ]),
  CatalogAction(kToggleValueActionType, ActionExecutor.reader, [CatalogParam('path', ActionParamForm.dataPath)]),
];

/// The catalog entry for [type]; `null` means the action is not named (an
/// app-specific action: its parameters are not judged and neither `standard`
/// nor `invalid` is set).
CatalogAction? catalogActionOf(String type) {
  for (final entry in kActionCatalog) {
    if (entry.type == type) return entry;
  }
  return null;
}

/// `x-actions.forms.httpsUrl.pattern`, verbatim. ASCII classes only, so Dart's
/// `RegExp` reads it the same way as JS's `RegExp`, and no flags are needed.
///
/// The host has at least TWO labels and the last one (the zone) is two or more
/// letters or `xn--…`, so no IPv4 notation (`2130706433`, `0x7f.1`, `127.1`)
/// and no single-label name passes; the port is 1..65535 without leading zeros.
final RegExp kHttpsUrlPattern = RegExp(
  r"^https:\/\/(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+(?:[A-Za-z]{2,}|xn--[A-Za-z0-9-]*[A-Za-z0-9])(?::(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?(?:[/?#][A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]*)?$",
);

/// Source of [kHttpsUrlPattern], for comparison with the artifact.
const String kHttpsUrlPatternSource =
    r"^https:\/\/(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+(?:[A-Za-z]{2,}|xn--[A-Za-z0-9-]*[A-Za-z0-9])(?::(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?(?:[/?#][A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]*)?$";

/// `x-actions.forms.appLink.pattern`, verbatim; the first group is the scheme.
const String kAppLinkPatternSource =
    r"^([a-z][a-z0-9+.-]{1,31}):[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+$";

/// A whole app link.
final RegExp kAppLinkPattern = RegExp(kAppLinkPatternSource);

/// `x-actions.forms.appLink.schemePattern`.
const String kAppLinkSchemePatternSource = r'^[a-z][a-z0-9+.-]{1,31}$';

/// Schemes that are NEVER an app link (`x-actions.forms.appLink
/// .forbiddenSchemes`). This is the first layer of defence; the second is the
/// scheme allow-list the HOST passes to the `runStandardAction` helper.
const List<String> kForbiddenLinkSchemes = [
  'javascript',
  'data',
  'file',
  'blob',
  'vbscript',
  'filesystem',
  'content',
  'jar',
  'resource',
  'intent',
  'android-app',
  'about',
  'chrome',
  'view-source',
  'http',
  'https',
  'ftp',
  'ws',
  'wss',
];

/// `x-actions.problemOrder`: the order of the checks is part of the rule.
const String kActionProblemOrder = 'missing-then-too-long-then-form';

/// The scheme of an app link, if the string has that form.
String? appLinkSchemeOf(String value) => kAppLinkPattern.firstMatch(value)?.group(1);

/// Checks a value against a form. `null` means it passed.
///
/// Order: missing, then too long, then the form. `screenId` is not judged here
/// (only whoever holds the document knows whether such a screen exists). The
/// value is neither trimmed nor normalized: a leading space is `not-https`,
/// an uppercase scheme is not a scheme.
ActionParamProblem? paramFormProblem(ActionParamForm form, String? value) {
  if (value == null || value.isEmpty) return ActionParamProblem.missing;
  if (form != ActionParamForm.httpsUrl && form != ActionParamForm.appLink) return null;
  if (value.length > kActionUrlMaxLength) return ActionParamProblem.tooLong;
  if (form == ActionParamForm.httpsUrl) {
    if (!value.startsWith('https://')) return ActionParamProblem.notHttps;
    return kHttpsUrlPattern.hasMatch(value) ? null : ActionParamProblem.malformed;
  }
  final scheme = appLinkSchemeOf(value);
  if (scheme == null) return ActionParamProblem.malformed;
  return kForbiddenLinkSchemes.contains(scheme) ? ActionParamProblem.forbiddenScheme : null;
}

// ───────────────────────────── parameter from data ─────────────────────────────

/// `x-actions.paramBinding`: a value from data counts only if it is a
/// NON-EMPTY STRING no longer than [kActionUrlMaxLength]. A number is not
/// turned into text: `String(3.0)` in JS is `3` but `'${3.0}'` in Dart is
/// `3.0`, so two readers would hand the host two different parameters.
String? boundParamValue(Object? value) =>
    value is String && value.isNotEmpty && value.length <= kActionUrlMaxLength ? value : null;

// ───────────────────────────── what the host receives ─────────────────────────────

/// A standard action whose parameters PASSED the check. This is what
/// `runStandardAction` executes; the reader itself executes nothing.
sealed class StandardAction {
  const StandardAction();
}

/// The URL as a `Uri`, for the executor's convenience: `null` when the platform
/// cannot parse it, or parses it so that the first field read throws
/// (`h:9999…` passes `Uri.tryParse` but `port` throws `FormatException`). The
/// form verdict does not depend on this.
Uri? safeUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  try {
    uri.port;
    uri.host;
  } on FormatException {
    return null;
  }
  return uri;
}

/// `openUrl`: [url] is the STRING that passed `httpsUrl`, byte for byte.
///
/// Only the form expression gives the verdict. `Uri` is deliberately not a
/// field: the platform parser would judge a URL differently from the other
/// readers (port 99999999999999999999, `[x`), and one URL would be `standard`
/// in one reader and `invalid` in another.
final class OpenUrlAction extends StandardAction {
  const OpenUrlAction(this.url);

  /// The checked URL; this is what the executor receives.
  final String url;

  /// Convenience: the URL as a `Uri`. `null` does NOT change the verdict; an
  /// executor that needs a `Uri` decides itself what to do with a URL the
  /// platform could not parse.
  Uri? get uri => safeUri(url);

  @override
  String toString() => 'openUrl($url)';
}

/// `deeplink`: [url] is the STRING that passed `appLink`, [scheme] is its scheme.
final class DeeplinkAction extends StandardAction {
  const DeeplinkAction(this.url, this.scheme);

  /// The checked link; this is what the executor receives. The link's path and
  /// query are UNTRUSTED: the app's router has to judge them.
  final String url;

  /// The link scheme (lowercase).
  final String scheme;

  /// Convenience: the link as a `Uri`; `null` does not change the verdict.
  Uri? get uri => safeUri(url);

  @override
  String toString() => 'deeplink($url)';
}

/// `close`: asks the host to close the flow. The reader leaves the screen stack alone.
final class CloseAction extends StandardAction {
  const CloseAction();

  @override
  String toString() => 'close';
}

/// A catalog action whose parameter failed its form: the host RECEIVES it (it
/// may know more than the document), but it has no `standard`, and
/// `runStandardAction` never executes it.
final class InvalidActionParam {
  const InvalidActionParam(this.param, this.problem);

  /// Parameter name.
  final String param;

  /// What is wrong with it.
  final ActionParamProblem problem;

  @override
  String toString() => 'invalid($param: ${problem.wire})';
}

/// A standard action, or the reason there is none: `(standard, invalid)`.
/// Never both; both `null` means the action is not in the catalog or the
/// reader executes it.
///
/// [params] are the parameters AFTER data substitution.
({StandardAction? standard, InvalidActionParam? invalid}) checkStandardAction(
  String type,
  Map<String, String> params,
) {
  final entry = catalogActionOf(type);
  if (entry == null || entry.executor != ActionExecutor.host) {
    return (standard: null, invalid: null);
  }
  for (final param in entry.params) {
    final problem = paramFormProblem(param.form, params[param.name]);
    if (problem != null && (param.required || problem != ActionParamProblem.missing)) {
      return (standard: null, invalid: InvalidActionParam(param.name, problem));
    }
  }
  switch (type) {
    case kOpenUrlActionType:
      return (standard: OpenUrlAction(params[kActionUrlParam]!), invalid: null);
    case kDeeplinkActionType:
      final url = params[kActionUrlParam]!;
      return (standard: DeeplinkAction(url, appLinkSchemeOf(url)!), invalid: null);
    default:
      return (standard: const CloseAction(), invalid: null);
  }
}

// ───────────────────────────── analytics event ─────────────────────────────

/// `x-actions.track.namePattern`: an event name and the key of its parameter.
/// The names `constructor` and `prototype` are not allowed.
const String kTrackNamePatternSource = r'^(?!(?:constructor|prototype)$)[A-Za-z][A-Za-z0-9_]*$';
final RegExp kTrackNamePattern = RegExp(kTrackNamePatternSource);

/// `x-actions.params`: the key of a `params` / `paramBindings` entry. An entry
/// that does not have this form is SKIPPED (`invalidEntry: skip`) and the rest
/// of the action works; a value is not turned into text.
const String kParamKeyPatternSource = r'^(?!(?:__proto__|constructor|prototype)$)\S+$';
final RegExp kParamKeyPattern = RegExp(kParamKeyPatternSource);
const int kParamKeyMaxLength = 32;
const int kParamValueMaxLength = 2048;

/// Whether the reader accepts a `params` / `paramBindings` entry with this key.
bool isParamKey(String key) =>
    key.isNotEmpty && key.length <= kParamKeyMaxLength && kParamKeyPattern.hasMatch(key);
const int kTrackEventMaxLength = 40;
const int kTrackParamKeyMaxLength = 40;
const int kTrackParamValueMaxLength = 100;
const int kTrackMaxParams = 25;

/// The analytics event of a press (`action.track`), as the host receives it.
final class TrackEvent {
  const TrackEvent(this.event, [this.params = const {}]);

  /// Event name: a Latin letter, then letters, digits and `_`, up to 40 characters.
  final String event;

  /// Parameters; an empty map means none.
  final Map<String, String> params;

  /// Reads `action.track` from JSON. `null` means the field is absent or has
  /// the wrong form; the field is then IGNORED ENTIRELY and the action still
  /// works, because half an event (no name, or a foreign parameter) would tell
  /// the host nothing.
  static TrackEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    final event = raw['event'];
    if (event is! String || event.length > kTrackEventMaxLength || !kTrackNamePattern.hasMatch(event)) {
      return null;
    }
    final rawParams = raw['params'];
    if (rawParams == null) return TrackEvent(event);
    if (rawParams is! Map || rawParams.length > kTrackMaxParams) return null;
    final params = <String, String>{};
    for (final entry in rawParams.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          key.length > kTrackParamKeyMaxLength ||
          !kTrackNamePattern.hasMatch(key) ||
          value is! String ||
          value.length > kTrackParamValueMaxLength) {
        return null;
      }
      params[key] = value;
    }
    return TrackEvent(event, Map.unmodifiable(params));
  }

  @override
  String toString() => params.isEmpty ? 'track($event)' : 'track($event, $params)';
}

/// Mirror of `x-actions` for comparison with the artifact: everything except
/// the expressions and lists that are already constants above.
const Map<String, Object> kActionCatalogMirror = {
  'executors': ['reader', 'host'],
  'problemOrder': kActionProblemOrder,
};

/// Mirror of the fourteen action policy rows of schema 9.8.0
/// (`x-compatibility.policy`).
const Map<String, String> kActionPolicy = {
  'standardActionExecution': 'host-only-reader-opens-nothing',
  'standardActionParams': 'checked-by-form-before-handover',
  'invalidStandardAction': 'hand-over-marked-invalid',
  'actionParamBinding': 'non-empty-string-else-literal',
  'closeAction': 'host-closes-flow-stack-untouched',
  'actionTrack': 'once-per-press-before-action',
  'screenShown': 'once-when-top-of-stack-changes',
  'screenShownOnBack': 'new-show-with-cause-back',
  'screenShownOnServer': 'never-on-server',
  'carryRecord': 'page-opens-with-node-record',
  'unbindableParamBinding': 'ignore-binding-use-literal',
  'keyAutoRepeat': 'not-a-press',
  'stackScreenGone': 'restart-from-entry',
  'actionParamComposition': 'none',
};

// ───────────────────────────── "screen shown" event ─────────────────────────────

/// Why a screen was shown (`x-screenShown.causes`).
enum ScreenShownCause {
  /// First show; the host changed the entry or the document.
  entry('entry'),

  /// `navigate` put a screen on top (a modal layer too).
  forward('forward'),

  /// The top screen was removed: the event is for the screen beneath it.
  back('back'),

  /// `navigate.section` (9.12.0): the stack became one named screen. The
  /// artifact word is `switch`, which is reserved in Dart, so the constant is
  /// named differently.
  switchSection('switch');

  const ScreenShownCause(this.wire);

  /// The artifact word.
  final String wire;
}

/// The "screen shown" event (`x-screenShown`): the shown screen is the top of
/// the stack, and the event fires when the top becomes a different FRAME.
/// There is no "hidden" event.
final class ScreenShown {
  const ScreenShown({
    required this.documentId,
    required this.screenId,
    required this.entry,
    required this.presentation,
    required this.cause,
    required this.depth,
    required this.record,
    this.modalPlacement,
    this.statusBarIcons,
  });

  /// The document the screen belongs to.
  final String documentId;

  /// The shown screen.
  final String screenId;

  /// Name of the entry point the flow started from; set only when the host
  /// named it and the document has such a name, otherwise `null`. One per flow.
  final String? entry;

  /// How the screen is shown: as a page or as a layer.
  final String presentation;

  /// Why it was shown.
  final ScreenShownCause cause;

  /// Stack length AFTER the change; the first screen is 1.
  final int depth;

  /// The row record the screen was opened with, as a flat map of paths; `null`
  /// means no record.
  final Map<String, Object?>? record;

  /// Where the layer sits: `bottom` or `center` (9.9.0), ONLY when the screen
  /// is modal and named a known word; otherwise `null` (the key is absent from
  /// the event).
  final String? modalPlacement;

  /// The screen's request for system status bar icons: `light` or `dark`
  /// (9.9.0), only when the screen named it. The reader does not touch the
  /// system bar; the host fulfils the request.
  final String? statusBarIcons;

  @override
  String toString() => 'ScreenShown($screenId, cause: ${cause.wire}, depth: $depth)';
}

/// The entry name for the event: the one the host named, if the document knows
/// it; otherwise `null` (own keys of `entryPoints`, not inherited ones).
String? shownEntryOf(String? requested, Map<String, String> entryPoints) {
  if (requested == null) return null;
  return entryPoints.containsKey(requested) ? requested : null;
}
