import 'package:flutter/material.dart';

import '../model/localization.dart';
import '../model/ui_document.dart';
import '../model/write_action.dart' show isWritablePath;
import '../theme/render_theme.dart';
import '../report/hotlayout_report.dart';
import '../report/report_hub.dart';
import 'host_callbacks.dart';
import 'labels.dart';
import 'picture_policy.dart';
import 'screen_flow.dart';
import 'screen_transitions.dart';
import 'screen_widget.dart';
import 'version_notice.dart';

export 'choice_scope.dart' show ChoiceOptionMark;
export 'host_callbacks.dart'
    show
        ScreenScopeRequest,
        ScreenScopeResolver,
        SduiActionCallback,
        SduiHapticCallback,
        SduiRecordActionCallback,
        SduiScreenShownCallback,
        SduiTrackCallback,
        SduiValueWrite;
export 'icon_box.dart' show IconBox, OwnGlyphBox;
export 'layout/marker_column_end.dart' show MarkerColumnEnd, RenderMarkerColumnEnd;
export 'layout/row_layout.dart' show RenderRowLayout, RowChildWidth, RowLayout, RowLayoutParentData, RowSlot;
export 'layout/stretch_column.dart' show FlowGap, FlowPull, RenderStretchColumn, StretchColumn;
export 'modal_layer.dart' show kModalLayerKey;
export 'picture_policy.dart' show ImageUrlResolver, kDefaultMaxDownloadBytes;
export 'screen_flow.dart' show ScreenFlow, ScreenFlowBackCallback, ScreenFlowController;
export 'screen_transitions.dart' show HotlayoutTransitions;

/// Draws a document: its screens, the navigation between them and its modal sheets.
///
/// A document is a set of screens, so this returns not a static tree but a stateful node that
/// holds the screen stack and performs the transitions itself.
///
///  * [theme] — the values of the tokens the document refers to.
///  * [data] — values for the paths the document is bound to, flat
///    (`'user.points': 1250`) or nested (`'user': {'points': 1250}`); a
///    collection is a list of records under the collection name.
///  * [entry] — a public entry-point name; `null` or an unknown name opens
///    the initial screen.
///  * [locale] — the language to show, as the platform gives it (`ar-EG`);
///    the document finds its own language for it. `null` draws the source
///    language (`localization.defaultLocale`), which is no coincidence: a language the
///    document lacks gives the same. The host decides WHICH language to ask for (it has
///    both the device locale and the user's manual choice), and the renderer must not choose
///    for it, just as it does not choose the theme.
///  * [now] — the moment "days until" texts are counted from (`format:
///    'daysUntil'`). `null` reads the device clock each time the screen is
///    built. The screen does not redraw itself as time passes.
///  * [onAction] — every action other than navigation inside the document.
///  * [onRecordAction] — the same, with the record of the node the action was
///    invoked on; when both are given, only this one is called.
///  * [onScreenChanged] — tells which screen is shown now. Deprecated: use
///    [onScreenShown], which says why and with which record.
///  * [onScreenShown] — the "screen shown" event: the screen on top of the
///    stack changed (first show, forward, back, a sheet closed). Exactly one
///    per show.
///  * [onTrack] — the analytics event of a press (`action.track`), once per
///    press and before the action itself.
///  * [onHaptic] — the haptic request of a press (`action.haptic`), once per
///    press and before the analytics event and the action. The renderer never
///    vibrates by itself: the host decides.
///  * [scopeFor] — the data of one screen, from its navigation parameters.
///  * [onWrite] — what the user changed in a bound input (`TextField`,
///    `Switch`, `Checkbox`, `ChoiceGroup`): the data path and a [String], a
///    [bool] or a [num]. Called on every change, at once. The value is user input: check
///    it on the backend, and throttle here if a network stands behind it.
///  * [resolveImageUrl] — the host's decision about every picture address (the document's and the data's,
///    `data:` addresses included): return the address to fetch, or `null` to refuse it; a refused picture draws
///    the "image unavailable" placeholder and makes no request. The default allows `https` addresses with a
///    host name only (no IP literal in any notation, no single-word host such as `localhost`, no user info, no
///    other scheme), the host form of the contract's `openUrl`. Redirects are followed by hand, at most three,
///    and each target passes the policy again.
///  * [maxDownloadBytes] — the most bytes of one picture body that is read (10 MiB (10 485 760 bytes) by default). A larger
///    `Content-Length` is refused before the body is read. A picture is also decoded at the size of its box
///    (never above 4096 pixels on a side) and a request gives up after 30 seconds.
///  * [writablePaths] — the data paths the document may write, as a `bool Function(String path)` or an
///    `Iterable<String>`. A write to any other path reaches neither the session nor [onWrite]. The default
///    allows every well-formed path.
///  * [autofill] — `false` turns every autofill hint of the text fields off.
///    Pass it for documents from a source you do not fully trust.
///  * [labels] — the renderer's own words, English by default.
///  * [transitions] — how one screen replaces another: the platform's motion by default,
///    [HotlayoutTransitions.none] for none (see [HotlayoutTransitions]).
///  * [controller], [onSystemBack], [handleSystemBack] — the system back
///    button and the document's stack; see [ScreenFlow].
///  * [onReport] — what the reader ignored, replaced or refused on its own (see [HotlayoutReport]): once per
///    cause for the life of the widget, also in release builds.
///
/// The widget keeps its own stack of screens and does not use `Navigator`. It
/// draws only the document: no `Scaffold`, no safe-area padding. The system
/// back button goes one screen back inside the document and leaves the route
/// to your `Navigator` on the first screen. A document
/// whose major contract version differs from the renderer's is not drawn; a
/// notice is shown instead — [RendererLabels.updateRequired] for a newer
/// document, [RendererLabels.screenUnavailable] for an older one.
Widget renderDocument(
  UiDocument doc, {
  required RenderTheme theme,
  required Map<String, Object?> data,
  String? entry,
  String? locale,
  DateTime? now,
  SduiActionCallback? onAction,
  SduiRecordActionCallback? onRecordAction,
  SduiTrackCallback? onTrack,
  SduiHapticCallback? onHaptic,
  @Deprecated('Use onScreenShown: it says why the screen is shown and with which record.')
  ValueChanged<ScreenEntry>? onScreenChanged,
  SduiScreenShownCallback? onScreenShown,
  ScreenScopeResolver? scopeFor,
  SduiValueWrite? onWrite,
  bool autofill = true,
  ImageUrlResolver? resolveImageUrl,
  int maxDownloadBytes = kDefaultMaxDownloadBytes,
  Object? writablePaths,
  RendererLabels labels = const RendererLabels(),
  ScreenFlowController? controller,
  ScreenFlowBackCallback? onSystemBack,
  bool handleSystemBack = true,
  HotlayoutTransitions transitions = HotlayoutTransitions.platform,
  HotlayoutReportCallback? onReport,
}) {
  final verdict = doc.versionVerdict;
  final version = versionReports(doc, verdict);
  final found = [...version, ...doc.reports, ...theme.reports];
  // A different major version cannot be read. Silently drawing nothing is the worst option: the
  // user sees a broken app and does not know why.
  if (!verdict.canRender) {
    return ReportListener(
      onReport: onReport,
      initial: found,
      announced: version,
      child: VersionNotice(theme: theme, verdict: verdict, documentVersion: doc.schemaVersion, labels: labels),
    );
  }
  return ReportListener(
    onReport: onReport,
    initial: found,
    announced: version,
    child: ScreenFlow(
    doc: doc,
    theme: theme,
    data: data,
    entry: entry,
    locale: locale,
    now: now,
    onAction: onAction,
    onRecordAction: onRecordAction,
    onTrack: onTrack,
    onHaptic: onHaptic,
    onScreenChanged: onScreenChanged,
    onScreenShown: onScreenShown,
    scopeFor: scopeFor,
    onWrite: onWrite,
    autofill: autofill,
    resolveImageUrl: resolveImageUrl,
    maxDownloadBytes: maxDownloadBytes,
    writablePaths: writablePaths,
    labels: labels,
    controller: controller,
    onSystemBack: onSystemBack,
    handleSystemBack: handleSystemBack,
    transitions: transitions,
    ),
  );
}

/// Draws one screen without navigation, for a host that keeps the stack of
/// screens itself.
///
/// [strings] are the translations to draw (`UiDocument.stringsFor`), [locale]
/// the language bound dates and numbers are formatted in (`binding.format`; `null` is the
/// language `intl` considers current), [now] the moment
/// "days until" texts are counted from (`null`: the device clock). [record] is the record the screen
/// was opened with — a flat map of data paths (`{'item.id': 'bottle'}`), the
/// strongest layer of the screen's data. The host names the screen's record itself through
/// [record]: without a stack the reader cannot know which row the screen was opened from.
/// [params] are handed to [scopeFor] and are not data of the screen
/// (`navigateParams: 'for-host-not-data'`). [params], [record], [session] and [scopeFor] are
/// the screen's input and are all empty by default, in which case the result is the same as for
/// a host that does not manage a stack: it has no source for an input either. [session] and
/// [scopeFor] are the data of this screen; [onWrite] receives what the user changes in a bound
/// input (see [SduiValueWrite]) and [autofill] turns the autofill hints of the text fields
/// off when `false`.
/// [onRecordAction] is [onAction] plus the record of the node; when both are
/// given, only [onRecordAction] is called. [onTrack] gets the analytics event of
/// a press (`action.track`), before the action; [onHaptic] gets the haptic request of the press (`action.haptic`),
/// before the event. [resolveImageUrl], [maxDownloadBytes] and [writablePaths] are the same as in `renderDocument`.
Widget renderScreen(
  ScreenEntry screen, {
  required RenderTheme theme,
  required Map<String, Object?> data,
  Map<String, String> params = const {},
  Map<String, Object?>? record,
  Map<String, Object?> session = const {},
  ScreenScopeResolver? scopeFor,
  LocalizedStrings strings = LocalizedStrings.none,
  String? locale,
  DateTime? now,
  SduiActionCallback? onAction,
  SduiRecordActionCallback? onRecordAction,
  SduiTrackCallback? onTrack,
  SduiHapticCallback? onHaptic,
  SduiValueWrite? onWrite,
  bool autofill = true,
  ImageUrlResolver? resolveImageUrl,
  int maxDownloadBytes = kDefaultMaxDownloadBytes,
  Object? writablePaths,
  RendererLabels labels = const RendererLabels(),
  HotlayoutReportCallback? onReport,
}) => ReportListener(
  onReport: onReport,
  initial: theme.reports,
  child: screenWidget(
  screen,
  theme: theme,
  data: data,
  params: params,
  record: record,
  session: session,
  scopeFor: scopeFor,
  strings: strings,
  locale: locale,
  now: now,
  handler: (action, nodeId, origin) {
    // The haptic request goes first, then the analytics event, for any action; without a screen flow there is no
    // navigation here, so the rest is handing over to the host.
    sendHaptic(action, nodeId, origin, onHaptic);
    sendTrack(action, nodeId, origin, onTrack);
    return handToHost(action, nodeId, origin, onAction: onAction, onRecordAction: onRecordAction);
  },
  onWrite: onWrite == null
      ? null
      : (path, value) {
          if (isWritablePath(path, writablePaths)) onWrite(path, value);
        },
  autofill: autofill,
  pictures: PicturePolicy(resolveImageUrl: resolveImageUrl, maxDownloadBytes: maxDownloadBytes),
  labels: labels,
  ),
);
