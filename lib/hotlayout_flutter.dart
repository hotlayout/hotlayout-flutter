/// HotLayout for Flutter: draws server-driven screens published by the
/// HotLayout builder.
///
/// This is the only public library of the package. A host needs four things,
/// and each has one entry here:
///
///  * a **document** — [UiDocument], loaded through a [DocumentSource]
///    ([BundledDocumentSource] from the app's assets,
///    [PublishedDocumentSource] over HTTP with a bundled fallback);
///  * a **theme** — [ThemeLoad] reads a [ThemeContract], from which the host
///    picks one [RenderTheme];
///  * **data** — a plain `Map<String, Object?>` of values for the paths the
///    document is bound to;
///  * the **widget** — [renderDocument], with [SduiActionCallback] for the
///    actions the host performs itself ([runStandardAction] performs the
///    checked ones, with executors the host passes in), [SduiTrackCallback], [SduiHapticCallback]
///    for analytics events, [SduiScreenShownCallback] for screen views and [HotlayoutReportCallback]
///    for what the reader ignored or replaced on its own;
///    [HostActions] routes the host's own actions to one handler per type.
///
/// All four may change while the user is in the flow: new data, a new version
/// of the same document and a new theme are drawn at once, and the screen
/// stack stays (see [ScreenFlow.doc]).
///
/// A complete host is in the package's `example/`.
///
/// Everything under `src/` that is not exported here is internal and may
/// change without notice.
library;

// The document and the actions it carries.
export 'src/model/action.dart' show ButtonAction, runStandardAction;
// The action catalog (9.8.0): what the host gets for `openUrl`, `deeplink` and
// `close`, the analytics event of a press and the "screen shown" event.
export 'src/model/action_catalog.dart'
    show
        ActionParamProblem,
        CloseAction,
        DeeplinkAction,
        InvalidActionParam,
        OpenUrlAction,
        ScreenShown,
        ScreenShownCause,
        StandardAction,
        TrackEvent;
// The haptic request of a press (9.25.0): the words the host gets in `onHaptic`.
export 'src/model/haptic.dart' show HapticWord;
export 'src/model/node.dart' show UiNode;
export 'src/model/tokens.dart' show ScreenPresentationToken;
export 'src/model/ui_document.dart' show ScreenEntry, UiDocument;

// Contract versions: what this renderer reads, and the verdict on a document.
export 'src/model/compatibility.dart' show VersionVerdict, kSupportedSchemaVersion;
// The icon drawings built into the renderer are versioned on their own: a
// redrawn icon changes this number and not the document contract version.
export 'src/model/icon_set.dart' show kIconSetVersion;

// Languages: the document's table, the answer for one device locale, and the
// writing direction of a locale.
export 'src/model/locale_resolve.dart' show LocaleResolution;
export 'src/model/localization.dart' show DocumentLocalization, LocalizedStrings;
export 'src/render/direction.dart' show directionOfLocale, isRtlLocale;

// What the reader ignored, replaced or refused on its own, for the host (`onReport`).
export 'src/report/hotlayout_report.dart'
    show
        HotlayoutReport,
        HotlayoutReportCallback,
        IgnoredInputReport,
        IncompatibleDocumentReport,
        InvalidThemeValuesReport,
        NewerMinorDocumentReport,
        ThemeFallbackReport,
        UnknownEntryReport,
        UnknownThemeIdReport;

// Drawing: the entry functions, the screen flow and the host callbacks.
export 'src/render/labels.dart' show RendererLabels;
export 'src/render/render_document.dart'
    show
        HotlayoutTransitions,
        ScreenFlow,
        ScreenFlowBackCallback,
        ScreenFlowController,
        ScreenScopeRequest,
        ScreenScopeResolver,
        SduiActionCallback,
        SduiHapticCallback,
        SduiRecordActionCallback,
        SduiScreenShownCallback,
        SduiTrackCallback,
        SduiValueWrite,
        renderDocument,
        renderScreen;

// A ready `onRecordAction` that routes app-specific actions to handlers by type.
export 'src/render/host_actions.dart' show HostActionCall, HostActionHandler, HostActionMiss, HostActions;

// The theme and how it is loaded.
export 'src/theme/render_theme.dart' show RenderTheme;
export 'src/theme/theme_contract.dart'
    show
        ThemeContract,
        ThemeLoad,
        ThemeLoadStatus,
        kSupportedThemeContractVersion,
        kThemeFetchTimeout;

// Where a document comes from.
export 'src/data/document_source.dart'
    show
        BundledDocumentSource,
        DocumentLoad,
        DocumentLoadStatus,
        DocumentResponse,
        DocumentSource,
        DocumentTransport,
        HttpDocumentTransport,
        PublishedDocumentSource,
        kDocumentFetchTimeout;

// Placements: named places of the app that show the document the builder put there.
export 'src/placements/hotlayout_placement.dart' show HotlayoutPlacement, PlacementReportCallback;
export 'src/placements/placement_map.dart'
    show
        PlacementMapRead,
        PlacementMapSource,
        PlacementReport,
        PlacementResolution,
        PlacementSourceStatus,
        PlacementStatus,
        isPlacementName,
        kPlacementsContractVersion,
        readPlacementMapText,
        resolvePlacement;
export 'src/placements/placement_source.dart'
    show
        HttpPlacementTransport,
        PlacementDocumentException,
        PlacementDocumentSource,
        PlacementLoad,
        PlacementMapStore,
        PlacementResponse,
        PlacementSource,
        PlacementTransport,
        placementFileUrl;
