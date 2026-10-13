/// The screen stack of a document: pages, modal layers, the record carried by
/// an action and the events of a shown screen.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../model/action.dart';
import '../model/action_catalog.dart';
import '../model/bottom_zone_rules.dart';
import '../model/locale_resolve.dart';
import '../model/media_chrome_rules.dart';
import '../model/record_scope.dart';
import '../model/tokens.dart';
import '../model/ui_document.dart';
import '../model/write_action.dart';
import '../theme/render_theme.dart';
import 'carousel.dart';
import 'direction.dart';
import 'host_callbacks.dart';
import 'labels.dart';
import 'modal_layer.dart';
import 'screen_widget.dart';
import 'tap_target.dart';
import 'write_run.dart';

part 'screen_flow_stack.dart';

/// Called when the system back button (or gesture) arrives while the document
/// has a screen to go back to. Return `true` when the host handled the event
/// itself (the stack is then left alone); return `false` to let the flow go one screen back.
///
/// It is never called on the first screen of the document: there the event is taken by the
/// host's route, and intercepting it is up to the host's own `PopScope`.
typedef ScreenFlowBackCallback = bool Function();

/// A handle on the screen stack of one [ScreenFlow], for a host that drives
/// "back" itself — its own toolbar button, its own gesture, or a navigation
/// setup in which the system back event does not reach the flow.
///
/// The document's screen stack stays private: the host cannot push a screen onto it or
/// rearrange frames. But two questions are legitimate, "is there anywhere to go back to inside
/// the document" and "take this step": without them a custom "back" button in the host's
/// app bar, a nested `Navigator` without `NavigatorPopHandler`, or a gesture the host catches
/// itself would have no way to reach the stack.
///
/// Optional: without a controller the flow handles the system back button on
/// its own. Create one, pass it to `renderDocument` or [ScreenFlow] as
/// `controller`, and dispose it with the widget that owns it:
///
/// ```dart
/// final flow = ScreenFlowController();
/// // …
/// renderDocument(document, theme: theme, data: data, controller: flow);
/// // …
/// if (!flow.goBack()) Navigator.of(context).maybePop();
/// ```
///
/// Listeners are notified when [canGoBack] or [currentScreenId] changes. A
/// controller serves one flow at a time: the one it was given to last.
class ScreenFlowController extends ChangeNotifier {
  _ScreenFlowState? _flow;
  bool _disposed = false;

  /// Whether the document has a screen to go back to: `false` on its first
  /// screen, and while the controller is not attached to a flow.
  bool get canGoBack => _flow?._canGoBack ?? false;

  /// The `screenId` of the screen shown now (the topmost one, a modal sheet
  /// included); `null` while the controller is not attached to a flow.
  String? get currentScreenId => _flow?._stack.last.screen.screenId;

  /// Goes one screen back inside the document — exactly what the document's
  /// own `navigate.back` action and the arrow of its `AppBar` do; a modal
  /// screen is closed.
  ///
  /// Returns `false`, and does nothing, when the first screen is shown:
  /// leaving the flow is the host's decision.
  bool goBack() => _flow?._goBack() ?? false;

  // No "already in use" check: when a flow is replaced by another at the same place (a new key),
  // Flutter creates the new state first and only then disposes the old one, so for a moment
  // there are two, and that is not a host error. The last one wins.
  void _attach(_ScreenFlowState flow) => _flow = flow;

  void _detach(_ScreenFlowState flow) {
    if (identical(_flow, flow)) _flow = null;
  }

  // Flow notifications may be deferred to the end of the frame, and the host may dispose the
  // controller earlier.
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flow = null;
    super.dispose();
  }
}

/// The widget behind `renderDocument`: a document's stack of screens.
///
/// The stack is ours rather than a `Navigator`: the document arrives whole, its screens are
/// not app routes but pages of one flow, and the host may embed this flow anywhere without
/// handing over a whole `Navigator`.
///
/// Prefer `renderDocument`, which also checks the contract version.
class ScreenFlow extends StatefulWidget {
  /// Creates the flow. See `renderDocument` for the parameters.
  const ScreenFlow({
    required this.doc,
    required this.theme,
    required this.data,
    this.entry,
    this.locale,
    this.now,
    this.onAction,
    this.onRecordAction,
    this.onTrack,
    this.onScreenChanged,
    this.onScreenShown,
    this.scopeFor,
    this.onWrite,
    this.autofill = true,
    this.labels = const RendererLabels(),
    this.controller,
    this.onSystemBack,
    this.handleSystemBack = true,
    super.key,
  });

  /// The document to draw.
  final UiDocument doc;

  /// The public entry-point name to open; `null` opens the initial screen.
  ///
  /// `null` means "nothing in particular was asked for", i.e. the initial screen. A name the
  /// document does not have gives the same: the contract policy says
  /// `unknownEntryPoint: 'use-initial'`, because a name outlives the document: it has already
  /// gone out in a push notification and will come back after the document was updated.
  final String? entry;

  /// The theme to draw with.
  final RenderTheme theme;
  /// Values for the paths the document is bound to.
  final Map<String, Object?> data;

  /// The language to show. Changing it does not reset the screen stack.
  ///
  /// It lives here, not in the document: the document carries ALL languages but shows one at a
  /// time, and a language change is not a document change, so the stack and scroll are not reset.
  final String? locale;

  /// The moment "days until" texts are counted from. `null` reads the device
  /// clock on every build. Changing it does not reset the screen stack.
  ///
  /// A parameter rather than `DateTime.now()` deep in the tree: a test using the machine clock
  /// would change its answer by the day it runs, and a host with server time would have no way
  /// to supply it. The same kind of decision as the language: the renderer does not choose, it
  /// asks.
  final DateTime? now;

  /// Receives every action the flow did not perform itself.
  final SduiActionCallback? onAction;

  /// Like [onAction], with the record of the node the action was invoked on
  /// (see [SduiRecordActionCallback]). When both are given, only this one is
  /// called.
  final SduiRecordActionCallback? onRecordAction;

  /// Tells which screen is shown now. A notification, not a control.
  ///
  /// The stack is the renderer's internal business and the host does not drive it. But the FACT
  /// "this screen is shown" is needed by the host: it paints the system bars, and their styling
  /// comes from the current screen, not the initial one. The host learns what is shown and
  /// cannot order another screen to be shown.
  @Deprecated('Use onScreenShown: it says why the screen is shown and with which record.')
  final ValueChanged<ScreenEntry>? onScreenChanged;

  /// Tells that the screen on top of the stack changed: the first show, a
  /// forward step (a modal sheet too), a step back (the screen beneath the
  /// removed one, the sheet closed), a new entry or a new document. Exactly one
  /// per show; a rebuild, new data, another locale or a re-parsed copy of the
  /// same document is not a show. Called after the frame, never from `build`.
  ///
  /// There is one rule: the shown screen is the top of the stack, and the event happens when
  /// the top became a different FRAME. There is no second "when" rule for `onScreenChanged`: it
  /// is called at the same moment.
  final SduiScreenShownCallback? onScreenShown;

  /// The analytics event of a press (`action.track`); see [SduiTrackCallback].
  final SduiTrackCallback? onTrack;

  /// Supplies the data of one screen from its navigation parameters.
  ///
  /// What the host fills a screen's entry with. `null` means "nothing", and the flow then
  /// behaves exactly as without it.
  final ScreenScopeResolver? scopeFor;

  /// Receives what the user changes in a bound input: the data path and a
  /// [String] (`TextField`) or a [bool] (`Switch`, `Checkbox`); see
  /// [SduiValueWrite]. The flow also keeps the value itself, in the session of
  /// its stack of screens, so conditions and texts on the same screen follow it.
  final SduiValueWrite? onWrite;

  /// Whether the text fields give autofill hints to the platform. `false` —
  /// none at all; for documents from a source you do not fully trust.
  final bool autofill;

  /// The renderer's own words (back arrow, image placeholder). English by
  /// default; see [RendererLabels].
  final RendererLabels labels;

  /// A handle on this flow's stack for a host that drives "back" itself;
  /// see [ScreenFlowController]. Optional.
  final ScreenFlowController? controller;

  /// Whether the flow handles the system back button itself. `true` by
  /// default.
  ///
  /// When the document has a screen to go back to, the Android back button
  /// and gesture (predictive back included) and the browser's back button go
  /// **one screen back inside the document** — the same step as the
  /// document's `navigate.back` action — and a modal screen is closed. On the
  /// first screen the event is not intercepted: the route the flow stands in
  /// is popped by your `Navigator`, as it would be without the flow. The iOS
  /// back swipe pops that route from the first screen only; on a deeper screen
  /// it is disabled, as it is for any route that handles "back" itself.
  ///
  /// The flow takes part in "back" through a `PopScope`, so the usual Flutter
  /// rules apply: a dialog or sheet of the host that is open above the flow is
  /// closed first, and a nested `Navigator` receives the event only when the
  /// host forwards it (`NavigatorPopHandler`). Where the event does not reach
  /// the flow, use a [controller].
  ///
  /// Pass `false` when your own navigation decides what "back" means; the
  /// flow then leaves the event alone, and [controller] is how you step back.
  ///
  /// Why `PopScope` and not a binding observer: `PopScope` tells the host's route in advance
  /// whether it may be popped (`canPop`), which is what the predictive back gesture of Android 14
  /// needs, since the system decides which animation to show BEFORE the gesture completes. So
  /// `canPop` is not "always false with a manual `pop` in response" but true exactly when the
  /// document is on its first screen. A `didPopRoute` observer cannot say this and would also
  /// run ahead of the host's dialogs.
  final bool handleSystemBack;

  /// Called before the flow goes back on a system back event; return `true`
  /// to cancel the step. Not called on the first screen, where the event is
  /// the host's already. See [ScreenFlowBackCallback].
  final ScreenFlowBackCallback? onSystemBack;

  @override
  State<ScreenFlow> createState() => _ScreenFlowState();
}

/// A screen in the stack TOGETHER with the parameters and record it was opened with.
///
/// A triple rather than a bare `ScreenEntry`: the same screen opened from two different list
/// rows is two different frames, and the RECORD carries the difference (the template
/// parameters are the same in all instances). It cannot be kept in the screen's state: the
/// stack knows what was put on it, the screen does not. "Back" removes the frame together with
/// its record (`recordLifetime: 'while-screen-in-stack'`), so nothing extra is needed for that.
///
/// [params] are for the host ([ScreenScopeRequest]); they are not the screen's data.
///
/// [memory] is the frame's carousel memory (`carousel.active.heldBy: 'stack-frame'`): which
/// card is open in each of the screen's carousels. It lives while the frame is in the stack,
/// even when the screen under the top one is not built.
typedef _Frame = ({
  ScreenEntry screen,
  Map<String, String> params,
  Map<String, Object?>? record,
  CarouselMemory memory,
});

class _ScreenFlowState extends State<ScreenFlow> {
  late List<_Frame> _stack = [_initialFrame];

  /// Margin of the window in the middle (`modalLayer.center.margin`, theme step `xl`).
  double get _windowMargin => widget.theme.space(SpacingToken.xl);

  /// What the user changed by hand in bound fields.
  ///
  /// It lives exactly as long as the screen stack: went into details, came back, chose another,
  /// went again, and it must show the new one. This is SESSION state, which is why it is here
  /// and not in the group's node: a node dies with its screen, and the choice must outlive the
  /// transition. It is addressed by the DATA path the document named, not by node `id`, so two
  /// groups with the same `id` on different screens share nothing as long as they are bound to
  /// different paths.
  ///
  /// It never reaches the document or the store: the user's choice is app state, and
  /// `published.json` is what the manager made.
  Map<String, Object?> _session = const {};

  /// The initial frame has no parameters: the document arrives whole, and nobody knows who
  /// opened the first screen. Empty parameters here mean there was no navigation.
  ///
  /// The screen here is not necessarily the initial one: the host may have named a PUBLIC ENTRY
  /// POINT, and the document then opens from it. The parameters stay empty: the entry says WHERE
  /// to start, not with which data.
  ///
  /// The initial frame has no record either: an external entry carries no record
  /// (the "detail screen without a record" case), which is the
  /// host's business.
  _Frame get _initialFrame =>
      (screen: widget.doc.screenForEntry(widget.entry), params: const {}, record: null, memory: CarouselMemory());

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // The first screen is also a screen change from the host's point of view: otherwise it would
    // have to guess on its own that the initial screen is shown and duplicate the logic of
    // `initialScreen` (which knows how to fall back to the first screen).
    _stackChanged(ScreenShownCause.entry, duringBuild: true);
  }

  /// Esc closes the top modal layer the same way a tap on the scrim does (desktop and web; React
  /// does the same). This is an ORDINARY key, not the system "back", which stays with the host
  /// (`_onSystemBack`). The handler is global, so the conditions are strict: a layer really is
  /// on top, our route is the current one (a host dialog above us takes Esc for itself), and it
  /// is a key press, not an auto-repeat or a release.
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || _stack.length < 2) return false;
    final top = _stack.length - 1;
    if (_presentationAt(top) != ScreenPresentationToken.modal) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _handleAction(
      const ButtonAction(ButtonAction.navigateBack),
      _stack[top].screen.screenId,
      (record: _stack[top].record, insideListItem: false, read: readNothing),
    );
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    final controller = widget.controller;
    if (controller != null) {
      controller._detach(this);
      // After the flow is removed the controller answers "nowhere to go and nothing to go to": the
      // host's listener must learn this, but not in the middle of tearing down the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller._changed());
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(ScreenFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new document OR another entry is a new flow: the old stack has nothing to do with them.
    // The second matters: the host changes the entry when the user came through another link, and
    // keeping the old history would mean "back" into someone else's flow.
    final controllerChanged = !identical(oldWidget.controller, widget.controller);
    if (controllerChanged) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    final restarted = oldWidget.entry != widget.entry || !_sameFlowDocument(oldWidget.doc);
    if (restarted) {
      _stack = [_initialFrame];
      // Records too: they are addressed by paths of the OLD document, and carrying them into the new
      // one would show a choice it may not have.
      _session = const {};
      _stackChanged(ScreenShownCause.entry, duringBuild: true);
    } else if (controllerChanged) {
      _notifyController(duringBuild: true);
    }
  }

  /// Whether a new document object is the same FLOW.
  ///
  /// A host that parses JSON in `build` gives a new object of the same document every time, and
  /// this is not a show: the stack, session and record stay (`rerender` of the `flowCases`
  /// table). The same document means the same `documentId` that has every screen of the stack;
  /// the frames then take screens from the NEW object, because the content may have changed. A
  /// different `documentId`, or a screen that no longer exists, is a new flow.
  bool _sameFlowDocument(UiDocument old) {
    if (identical(old, widget.doc)) return true;
    if (old.documentId != widget.doc.documentId) return false;
    final remapped = <_Frame>[];
    for (final frame in _stack) {
      final screen = widget.doc.screenById(frame.screen.screenId);
      if (screen == null) return false;
      remapped.add((screen: screen, params: frame.params, record: frame.record, memory: frame.memory));
    }
    _stack = remapped;
    return true;
  }

  /// Whether the document has a screen to go back to.
  bool get _canGoBack => _stack.length > 1;

  /// Whether the flow takes the system "back" RIGHT NOW.
  ///
  /// This is `canPop` inside out: the host's route may be popped exactly when the flow does not
  /// take the event, on the first screen or when the host turned interception off.
  bool get _interceptsSystemBack => widget.handleSystemBack && _canGoBack;

  /// One step back in the document: ONE path for all entries: the `navigate.back` action, the
  /// bar's arrow, a tap on the modal scrim, the system "back" and the controller. A second path
  /// would diverge from the first at the first change.
  bool _goBack() {
    if (!_canGoBack) return false;
    setState(() => _stack = _stack.sublist(0, _stack.length - 1));
    _stackChanged(ScreenShownCause.back);
    return true;
  }

  /// The system "back" that the route did NOT perform (`didPop == false`).
  void _onSystemBack(bool didPop, Object? result) {
    // `didPop` means the route is already removed and there is nothing to do. The second condition:
    // another `PopScope` of the same route forbade the pop and we did not, so the event is not ours.
    if (didPop || !_interceptsSystemBack) return;
    if (widget.onSystemBack?.call() ?? false) return;
    _goBack();
  }

  /// The stack changed: tell the host which screen is shown and wake the controller's listeners.
  void _stackChanged(ScreenShownCause cause, {bool duringBuild = false}) {
    _dropInputFocus(duringBuild: duringBuild);
    _announceScreen(cause);
    _notifyController(duringBuild: duringBuild);
  }

  /// A transition between screens drops focus (`inputFocusOnScreenChange`): the keyboard of the
  /// screen that left must not hang over the new one. Only focus INSIDE this flow: a host's own
  /// field next to it is not touched.
  void _dropInputFocus({required bool duringBuild}) {
    void drop() {
      if (!mounted) return;
      final focused = FocusManager.instance.primaryFocus;
      final inside = focused?.context?.findAncestorStateOfType<_ScreenFlowState>();
      if (identical(inside, this)) focused!.unfocus();
    }

    if (duringBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) => drop());
    } else {
      drop();
    }
  }

  /// A controller listener almost certainly calls `setState`, so from `initState` and
  /// `didUpdateWidget` the notification is deferred to the end of the frame, for the same reason
  /// as in [_announceScreen].
  void _notifyController({required bool duringBuild}) {
    final controller = widget.controller;
    if (controller == null) return;
    if (!duringBuild) {
      controller._changed();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.controller, controller)) controller._changed();
    });
  }

  /// Tell the host about the current screen: after the frame, not during build.
  ///
  /// The host almost certainly calls `setState` on this notification (it paints the system inset
  /// bars behind the screen), and `setState` during build is an exception.
  ///
  /// The "screen shown" event is assembled HERE, at the moment of change, not at the end of the
  /// frame: the stack may change again in between, and a show that happened must report itself as
  /// it was. `onScreenChanged` is called at the same moment, so there is no second "when" rule.
  void _announceScreen(ScreenShownCause cause) {
    // ignore: deprecated_member_use_from_same_package
    final onScreenChanged = widget.onScreenChanged;
    final onScreenShown = widget.onScreenShown;
    if (onScreenChanged == null && onScreenShown == null) return;
    final frame = _stack.last;
    final screen = frame.screen;
    final shown = ScreenShown(
      documentId: widget.doc.documentId,
      screenId: screen.screenId,
      entry: shownEntryOf(widget.entry, widget.doc.entryPoints),
      presentation: _presentationAt(_stack.length - 1).wire,
      cause: cause,
      depth: _stack.length,
      record: frame.record,
      // Only when the screen named it: an event never carries a needless key. The layer's placement
      // is read only for a modal screen (`modalPlacementOnPage`).
      modalPlacement: _presentationAt(_stack.length - 1) == ScreenPresentationToken.modal
          ? screen.modalPlacement?.wire
          : null,
      statusBarIcons: screen.statusBarIcons?.wire,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      onScreenChanged?.call(screen);
      onScreenShown?.call(shown);
    });
  }

  /// The renderer performs two actions itself and hands the rest to the host.
  ///
  /// None of the "did not work" cases is an exception: a transition to a missing screen or a step
  /// back from the root is something the document or host did not account for, not a reason to
  /// crash the app.
  ///
  /// Each action arrives together with its ORIGIN ([ActionOrigin]): the record scope of its node
  /// and the mark "the node is in a list instance". They decide which record the screen opens
  /// with ([recordForOpenedScreen]), and the host gets the record with every action it receives.
  void _handleAction(ButtonAction action, String nodeId, ActionOrigin origin) {
    // The analytics event goes FIRST and exactly once, whatever happens next: a reader action
    // handed to the host, `none`, a transition to a screen that does not exist.
    sendTrack(action, nodeId, origin, widget.onTrack);

    // `none` is a reader action that does nothing and does not reach the host.
    if (action.type == ButtonAction.noneType) return;

    // THE WRITE ACTIONS (`x-actions.write`): the reader performs them itself, after the event, through the same
    // write as a field's. Not handed to the host as actions, valid or not.
    final writeStep = writeStepOf(action, origin.read);
    if (writeStep != null) {
      runWriteStep(writeStep, write: _write);
      return;
    }

    if (action.type == ButtonAction.navigate) {
      final target = action.navigationTarget;
      final screen = target == null ? null : widget.doc.screenById(target);
      if (screen != null) {
        // Transition parameters go to the screen WHOLE, with `screenId`, but only as input for the
        // host: they give no data to the screen.
        final record = recordForOpenedScreen(
          nodeRecord: origin.record,
          insideListItem: origin.insideListItem,
          presentation: screen.presentation == ScreenPresentationToken.modal
              ? OpenedPresentation.modal
              : OpenedPresentation.page,
          carryRecord: action.carryRecord,
        );
        setState(() => _stack = [..._stack, (screen: screen, params: action.params, record: record, memory: CarouselMemory())]);
        _stackChanged(ScreenShownCause.forward);
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[hotlayout] cannot navigate to screen "${target ?? '<no screenId>'}": '
          'document "${widget.doc.documentId}" has no such screen',
        );
      }
      // The host may know more than the document (for example, how to open this screen with another
      // document), so the action goes on instead of disappearing.
      _toHost(action, nodeId, origin);
      return;
    }

    // SECTION SWITCH (`x-actions.section`): the stack becomes ONE named screen, everything above it
    // (modal layers too) is closed. The section is shown from the start: the reader remembers
    // neither the stack nor the scroll of sections, so the frame is new. The row record is NOT
    // carried, whichever list row was tapped (`sectionSwitchRecord`). The analytics event has
    // already gone (above).
    if (action.type == ButtonAction.navigateSection) {
      final target = action.sectionTarget;
      final screen = target == null ? null : widget.doc.screenById(target);
      if (screen != null) {
        // The stack is already this screen: nothing happens, not even an event (`sectionSwitchSameScreen`).
        final next = sectionStackOf([for (final frame in _stack) frame.screen.screenId], screen.screenId);
        if (next == null) return;
        // A section declared modal is a page: it is the root of the stack (`sectionTargetModal`,
        // `_presentationAt`).
        setState(() => _stack = [(screen: screen, params: action.params, record: null, memory: CarouselMemory())]);
        _stackChanged(ScreenShownCause.switchSection);
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[hotlayout] cannot switch to section "${target ?? '<no screenId>'}": '
          'document "${widget.doc.documentId}" has no such screen',
        );
      }
      // An unknown section is a host action, like `navigate` to an unknown screen.
      _toHost(action, nodeId, origin);
      return;
    }

    if (action.type == ButtonAction.navigateBack) {
      if (_goBack()) return;
      // Back from the first screen leaves the flow, and the renderer has no right to decide where
      // to. It is handed to the host.
      _toHost(action, nodeId, origin);
      return;
    }

    _toHost(action, nodeId, origin);
  }

  /// Hand the action to the host: with the record if it asked for one, without if not.
  void _toHost(ButtonAction action, String nodeId, ActionOrigin origin) => handToHost(
    action,
    nodeId,
    origin,
    onAction: widget.onAction,
    onRecordAction: widget.onRecordAction,
  );

  /// Write what the user changed in a bound field.
  ///
  /// The comparison before `setState` is not an optimisation: a repeated tap on an already
  /// selected option would otherwise rebuild the screen with no change.
  void _write(String path, Object value) {
    // The reader's session is a data layer: dependent conditions and texts of this screen change at
    // the same moment. The host gets the same value right after it, BEFORE any action pressed after
    // the change (`inputWrite`): the action sees what was typed.
    if (_session[path] != value) {
      setState(() => _session = Map<String, Object?>.unmodifiable({..._session, path: value}));
    }
    widget.onWrite?.call(path, value);
  }

  /// The locale for formatting dates and numbers (`binding.format`; the `formattingLocale` rule).
  ///
  /// Three answers, in decreasing certainty:
  ///  1. a localized document whose translation was FOUND: the requested locale in canonical
  ///     form (`ar-EG` with an `ar` translation gives Arabic text beside Egyptian formatting);
  ///  2. a localized document with no translation: the SOURCE language, otherwise the result
  ///     would be English text with Arabic digits;
  ///  3. a document without localization: what the host asked for, and if the host is silent, the
  ///     DEVICE language. Not `Localizations.localeOf`: that is narrowed to the app's
  ///     `supportedLocales` and for a typical host always gives `en_US`.
  String get _formatLocale =>
      _resolution.formatting ?? WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();

  /// ONE answer to "which language to show" (`localeResolution: 'once-per-document'`). Held per
  /// pair (document, host request): asking `shownLocale` twice, for the date and for the
  /// direction, could let the two questions diverge.
  LocaleResolution get _resolution {
    final cached = _resolutionCache;
    if (cached != null && identical(cached.$1, widget.doc) && cached.$2 == widget.locale) {
      return cached.$3;
    }
    final fresh = widget.doc.localeResolution(widget.locale);
    _resolutionCache = (widget.doc, widget.locale, fresh);
    return fresh;
  }

  (UiDocument, String?, LocaleResolution)? _resolutionCache;

  @override
  Widget build(BuildContext context) {
    /*
     * The writing direction comes from the DOCUMENT'S language, and is set here, on the whole
     * screen flow.
     *
     * Not from the app's locale: a document may be Arabic inside an app that itself works in
     * English, and the reverse. The language a document is SHOWN in and the app's language are
     * different things, exactly as in the builder, where the chrome stays left to right while the
     * screen on the canvas is mirrored.
     *
     * `Directionality` is on the whole flow, not each screen: a modal opened over a page belongs
     * to the same document, and two different directions in one stack would mean the sheet slides
     * in from a different side than the screen beneath it.
     *
     * The language is the one the document is SHOWN in, not the one the host asked for. Arabic,
     * which the document lacks, gives the default-language texts, and they would be laid out right
     * to left: an English screen mirrored. The host is heard only when the document names no
     * languages at all. The device language (the third answer of `_formatLocale`) is deliberately
     * not used here: it suits date formatting, but a non-localized document must not flip because
     * of the phone's settings.
     */
    return PopScope<Object?>(
      // True exactly when we do not take the event: the system (the Android 14 predictive gesture)
      // and the host's `Navigator` know in advance that "back" will pop the route rather than take a
      // step in the document.
      canPop: !_interceptsSystemBack,
      onPopInvokedWithResult: _onSystemBack,
      child: Directionality(
        textDirection: directionOfLocale(_resolution.directionLocale),
        // The root of the flow for touch areas: one for all layers, because a modal and the screen
        // under it are the same flow.
        child: TapTargetScope(child: _buildStack()),
      ),
    );
  }

}
