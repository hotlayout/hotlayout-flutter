import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'package:hotlayout_flutter/src/data/document_source.dart';
import 'collection_source.dart';
import 'sample_data.dart';
import 'showcase.dart';
import 'package:hotlayout_flutter/src/data/screen_data.dart';
import 'package:hotlayout_flutter/src/model/action.dart';
import 'package:hotlayout_flutter/src/model/localization.dart';
import 'package:hotlayout_flutter/src/model/node_style.dart';
import 'package:hotlayout_flutter/src/model/node.dart';
import 'package:hotlayout_flutter/src/model/tokens.dart';
import 'package:hotlayout_flutter/src/model/ui_document.dart';
import 'package:hotlayout_flutter/src/render/render_document.dart';
import 'package:hotlayout_flutter/src/theme/render_theme.dart';
import 'package:hotlayout_flutter/src/theme/theme_contract.dart';

/// Base address of the storage bucket the demo may read a published document and theme from
/// (`--dart-define=HOTLAYOUT_STORAGE_BASE=https://firebasestorage.googleapis.com/v0/b/<bucket>`).
///
/// EMPTY BY DEFAULT: the demo then never asks the network and uses the bundled copies, so it runs
/// anywhere and carries no project identifier of its own. With a base set, the default document
/// and theme addresses below are built from it; an explicit `documentUrl` / `themeUrl` still wins.
const String kStorageBase = String.fromEnvironment('HOTLAYOUT_STORAGE_BASE');

/// Address of the published THEME in the storage named by [kStorageBase].
///
/// Same rule as for the document: `theme/published.json` is readable without
/// authentication, so there is no token or app key here. An empty
/// `--dart-define=themeUrl=` (or an empty [kStorageBase]) disables the network entirely and the
/// theme comes from the bundle.
const String kPublishedThemeUrl = String.fromEnvironment(
  'themeUrl',
  defaultValue: kStorageBase == ''
      ? ''
      : '$kStorageBase/o/orgs%2Fdemo%2Fprojects%2Fdemo%2Ftheme%2Fpublished.json?alt=media',
);

/// Launch parameters named explicitly (`--dart-define=…`) differ from the defaults: the default
/// address of the published theme and document is live storage, and with `fixture` it would be
/// read ON TOP of the named fixture (network theme instead of the fixture's theme, foreign document instead of it).
///
/// Rule: a named fixture without an explicit `themeUrl` / `documentUrl` is read from assets: the theme is
/// its own or the bundled one, the document is the fixture itself. The network is enabled only by an explicitly named address.
const bool kFixtureGiven = bool.hasEnvironment('fixture');
const bool kThemeUrlGiven = bool.hasEnvironment('themeUrl');
const bool kDocumentUrlGiven = bool.hasEnvironment('documentUrl');

/// Theme address the demo actually reads: empty means the theme comes from assets.
const String kEffectiveThemeUrl = kFixtureGiven && !kThemeUrlGiven ? '' : kPublishedThemeUrl;

/// Screen the presentation starts from (`--dart-define=screen=<screenId>`); empty means the document's
/// initial screen. An unknown id falls back to the initial screen and the log says so.
const String kStartScreen = String.fromEnvironment('screen');

/// Device locale the demo passes to the reader (`--dart-define=locale=ar-EG`); empty means the system
/// locale. The reader matches it against the document's languages itself (`ar-EG` -> `ar`).
const String kStartLocale = String.fromEnvironment('locale');

/// Startup theme (`--dart-define=theme=<id|light|dark>`): a theme id from the set, or
/// `light` / `dark` by brightness; empty means follow the system mode.
const String kStartTheme = String.fromEnvironment('theme');

/// The theme is read BEFORE the first frame: otherwise the app would flash the hard-coded
/// fallback and repaint with fresh colors, which is worse than waiting.
///
/// WHY WE WAIT FOR THE THEME BUT NOT FOR THE DOCUMENT. The document comes over the network, and
/// waiting for it before the first frame would mean a white screen exactly when the
/// network is bad; the first frame is drawn from the bundled copy and the network replaces it
/// (`DocumentSource.seed`). The theme is different: swapping colors AFTER the screen
/// is already drawn is a visible jump of the whole interface, not a refinement of content.
///
/// So we wait, but briefly: `fromNetwork` has its own three-second timeout and falls back to
/// the bundled theme on any failure. Worst case is three seconds on the splash screen, not an app that did not start.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ownThemeAsset = kFixtureThemeAssets[kStartFixture];
  // Where the theme came from, for the log. `ThemeLoad` status says "read", not "from what", so
  // `isFallback` here is about a network fallback, not about choosing an asset.
  final String themeOrigin;
  final ThemeLoad theme;
  if (ownThemeAsset != null) {
    // A fixture with its OWN theme is read only against it: the published theme
    // does not declare its tokens (`brandText`, `gold`…), and the document would
    // render without half of its look, silently, because an unknown token is simply
    // "not applied".
    theme = await ThemeLoad.fromBundle(assetPath: ownThemeAsset);
    themeOrigin = 'the fixture\'s own theme «$kStartFixture» ($ownThemeAsset)';
  } else if (kEffectiveThemeUrl.isEmpty) {
    theme = await ThemeLoad.fromBundle(assetPath: kThemeContractAsset);
    themeOrigin = kPublishedThemeUrl.isEmpty
        ? 'bundled ($kThemeContractAsset): themeUrl is empty (set HOTLAYOUT_STORAGE_BASE to read a published theme)'
        : 'bundled ($kThemeContractAsset): fixture named without themeUrl, '
              'not reading the published theme from storage';
  } else {
    theme = await ThemeLoad.fromNetwork(
      Uri.parse(kEffectiveThemeUrl),
      transport: HttpDocumentTransport(),
      assetPath: kThemeContractAsset,
    );
    themeOrigin = 'published ($kEffectiveThemeUrl)';
  }

  /*
   * A THEME FALLBACK REPORTS ITSELF. The contract policy is called
   * `fallback-and-report`, and the second half of the name matters: swapping
   * the theme is invisible to the eye (colors are "just slightly off"), so
   * without a log line it stays unknown.
   *
   * The line also states the SOURCE: with a fixture asset it must not say
   * "from the network" when there was no network.
   */
  if (theme.isFallback) {
    debugPrint('[demo] theme: bundled — ${theme.status.name}: ${theme.detail ?? 'no details'} (wanted: $themeOrigin)');
  } else {
    debugPrint('[demo] theme: «${theme.contract.defaultTheme.name}» — $themeOrigin');
  }

  runApp(HotlayoutDemoApp(themeLoad: theme));
}

/// Contract theme in the DEMO's assets: what it draws with when offline.
///
/// The package no longer owns this path; only the app that declares the asset
/// knows it, so the default `ThemeLoad.fromBundle()` in a foreign app does not depend on it.
const String kThemeContractAsset = 'assets/contract/theme.json';

/// Contract fixture from the demo assets by short name.
///
/// Fixtures are not assets of a foreign app, so they live here and not in the package.
BundledDocumentSource fixtureSource(String id, {String? title, AssetBundle? bundle}) =>
    BundledDocumentSource(
      title: title ?? id,
      assetPath: showcaseById(id)?.documentAsset ?? 'assets/contract/fixtures/$id.json',
      bundle: bundle,
    );

/// Fixtures that have their OWN THEME: `--dart-define=fixture=…` takes the theme from here,
/// not from the network and not from the default theme.
///
/// Mirrors the builder's fixture-theme table; the files live one level
/// below the documents, in `fixtures/themes/`.
const Map<String, String> kFixtureThemeAssets = {
  'obsidian': 'assets/showcase/obsidian/theme.json',
  'sunny': 'assets/showcase/sunny/theme.json',
  'orbit': 'assets/showcase/orbit/theme.json',
  'rewards-showcase-screens': 'assets/contract/fixtures/themes/rewards-showcase-theme.json',
};

/// Fixtures in assets. They stay after the network was added: they are the fallback
/// source for the presentation and a set of "how does this look" examples.
final List<({String id, String title})> kFixtures = [
  // The three showcase apps, drawn from the same documents as the web package draws on the
  // product site (`showcase.dart`). Obsidian is the default.
  for (final app in kShowcaseApps) (id: app.id, title: app.title),
  (id: 'reward-catalog-screens', title: 'Reward catalog'),
  (id: 'minimal-screen', title: 'Minimal'),
  (id: 'task-progress-screen', title: 'Task progress'),
  (id: 'tasks-flow-screens', title: 'Navigation'),
  (id: 'full-catalog-screen', title: 'All widgets'),
  (id: 'max-depth-screen', title: 'Maximum depth'),
  // 7.2.0. The only fixture with translations; English in it is INCOMPLETE on
  // purpose, so the language switch in the service panel shows both a translation
  // and the fall back to the literal.
  (id: 'localized-promo', title: 'Promo with translations'),
  // 9.0.0. Showcase: four screens with their own theme (`kFixtureThemeAssets`),
  // diagonal gradients, root states and custom button styling.
  (id: 'rewards-showcase-screens', title: 'Contract 9 showcase'),
  // 9.3.0. The whole contract icon set: an overview (sizes, color, direction,
  // list-row slots; in Arabic for RTL) and a catalog of all 332 names.
  (id: 'icon-library-screens', title: 'Icon library'),
  // 9.4.0. Text template, numbers, money, days and plurals in three languages
  // (`en`, `uk`, `ar`): a template in text, panel subtitle, list-row slots, on
  // a badge and in a row of a data-driven list.
  (id: 'template-text-screens', title: 'Templates, numbers and plurals'),
  // 9.5.0. Icon in a button and badge, three button sizes, icon button and the
  // "icon beside text" rule (`en`, `uk`, `ar`).
  (id: 'buttons-chips-screens', title: 'Buttons and chips'),
  // 9.6.0. Rich text: parts of a line with their own style (`en`, `uk`, `ar`) -
  // a "1,250 Points" balance with the caption on the number's baseline, an emphasis word,
  // a two-line paragraph with an even step, a one-line row (`maxLines: 1`).
  (id: 'rich-text-screens', title: 'Rich text'),
  // 9.7.0. Bar and ring: thickness, track color, gradient along the filled
  // part, ring diameter from the node box (`en`, `uk`, `ar`).
  (id: 'progress-screens', title: 'Bar and ring'),
  // 9.8.0. Action catalog: `openUrl`, `deeplink`, `close` handed to the host parsed and
  // validated, a parameter from data, a tap analytics event, `carryRecord`
  // ("Choose delivery" vs "Delivery, no record"). Nothing is opened:
  // the demo only writes to the log and shows a notice.
  (id: 'actions-screens', title: 'Action catalog'),
  // 9.9.0. Custom image aspect ratio, circle with `pill`, app bar actions, centered window
  // ("Complete the mission", long rules scrolling inside) and a sheet;
  // the status bar icons request (`statusBarIcons`) is fulfilled by the HOST - see
  // `_statusBarIcons` below (`en`, `uk`, `ar`).
  (id: 'media-chrome-screens', title: 'Images, app bar, window'),
  // 9.10.0. Stack overlays (a "x2" badge past a tile corner, chips on the ring edge,
  // a "CLAIM" ribbon in a card corner, an "info" button) and in-flow pull (a sheet
  // over the app bar, overlapping avatars); `en`, `uk`, `ar`.
  (id: 'offset-screens', title: 'Overlays and pull-up'),
  // 9.11.0. Carousel of challenges from data (`perView: 1`, `xl` peek, dots), a row of
  // six badges (`perView: 3`, no dots) and milestones as steps (`segments: 6`); `en`, `uk`, `ar`.
  (id: 'carousel-steps-screens', title: 'Carousel and steps'),
  // 9.12.0. Bottom zone: a navigation bar with three sections (`navigate.section`), a button
  // pinned to the bottom above the bar, and a sheet with two pinned buttons; `en`, `uk`, `ar`.
  (id: 'bottom-zone-screens', title: 'Navigation bar and pinned block'),
  // 9.13.0. Input fields: a profile form (name, email, phone with an error, consent,
  // a button at the bottom) and settings (switches, a multiline field); `en`, `uk`, `ar`.
  // What the user types goes only to the log: the demo sends nothing anywhere.
  (id: 'inputs-screens', title: 'Input fields'),
  // 9.14.0. Survey: choice, text and number, consent; the "Next" button is disabled while the
  // required fields are empty (the demo does not supply `survey.*` samples - they would prefill the form,
  // see `_demoData`); `en`, `uk`, `ar`.
  (id: 'survey-screens', title: 'Survey (required fields)'),
  // 9.15.0. Child alignment: center on a screen, a column and a container in both directions,
  // screen body at the end between the app bar and a pinned button.
  (id: 'alignment-screens', title: 'Alignment (both axes)'),
  // 9.16.0. App bar from a mock-up: a node in the leading zone, title from the start,
  // custom image size.
  (id: 'app-bar-screens', title: 'App bar from the mockup'),
  // 9.17.0. Text emphasis, list, ring label; `en` and `ar-EG`.
  (id: 'text-emphasis-screens', title: 'Emphasis, list, ring'),
  // 9.18.0. Width adaptivity: the home screen on 393 / 768 / 1280 and the
  // `lab` bench - grid 2 -> 3 -> 4, "phone only" and "wide only" blocks, style by
  // class, column -> row 2 : 1; `rewards` is a section WITHOUT an app bar; `bonus` is a modal
  // sheet. The class is measured by the app box: stretch the macOS or web window past 600 and 1024 -
  // the navigation bar moves to the top (into the app bar or its own strip) and the sheet
  // becomes a centered window; `en`, `uk`, `ar`.
  (id: 'adaptive-screens', title: 'Width adaptivity'),
  // 9.19.0. Free composition: a card with an icon tile, a pressable card (a button on the finished
  // screen: label first, then its text), a button inside it that takes its own press, a sheet with a
  // card; `en`, `uk`.
  (id: 'composition-screens', title: 'Free composition (pressable cards)'),
  // 9.19.0. Money as money: the currency sign, the sign of the number, a smaller fraction and
  // currency as their own parts of the text, isolation of the amount in Arabic; `en`, `uk`, `ar`.
  (id: 'money-screens', title: 'Money as money'),
  // 9.19.0. The app bar over a hero: the body starts at the top edge of the screen (`screenTop`) and
  // the reader adds the top safe inset inside the app bar; `en`, `uk`, `ar`.
  (id: 'hero-screens', title: 'App bar over a hero'),
  // 9.19.0. Choice controls and the write action: a segment over one list, an eye that hides the balance,
  // chips, cards two by two, a scale 0-10; a press writes into the session of the reader (and `onWrite`).
  (id: 'choice-controls-screens', title: 'Choice controls and write'),
  // 9.19.0. Parts of a list row (amount with its own style, caption, tile, line limits) and of a text
  // field (box, mark, counter); `en`, `uk`, `ar`.
  (id: 'parts-screens', title: 'List row and field parts'),
  // 9.19.0. Picture description, icon and badge from data, four forms of a date, a card without a
  // background on a wide screen.
  (id: 'alt-icon-date-screens', title: 'Description, icon from data, date parts'),
];

/// Demo data: dictionary samples WITHOUT `survey.*`. The survey must start from an empty form
/// ("Next" disabled until required fields are filled) - dictionary samples would prefill it, while
/// they stay in `sampleScreenData`: the dictionary mirror is complete and a test guards it.
final Map<String, Object?> _demoData = {
  for (final entry in sampleScreenData.entries)
    if (!entry.key.startsWith('survey.')) entry.key: entry.value,
};

/// The "now" of the sample data - see [kSampleNow].
final DateTime _sampleNow = DateTime.parse(kSampleNow);

/// Bundled copy: the document the screen is drawn from until (or unless) the network
/// supplies its own. It is the same one that used to be shown from assets.
///
/// `flutter run --dart-define=fixture=task-progress-screen` changes both the copy and
/// what is visible at startup.
const String kStartFixture = String.fromEnvironment(
  'fixture',
  defaultValue: 'obsidian',
);

/// Scenario of the Orbit sample data (`--dart-define=scenario=newMember|afterPayment`).
const String kStartScenario = String.fromEnvironment('scenario', defaultValue: 'default');

/// Tab of Orbit's missions screen (`--dart-define=tab=active|new|done`); empty keeps the data's own.
const String kStartTab = String.fromEnvironment('tab');

/// Address of the published document in the storage named by [kStorageBase].
///
/// `reward-catalog` is the `documentId` of the demo document; `published.json`
/// is readable per storage rules, so there is no token or app key here.
///
/// An empty address (no [kStorageBase], or `--dart-define=documentUrl=`) disables the network
/// entirely: the presentation uses assets only. Needed exactly when there is no internet and a
/// second of waiting is wasted.
const String kPublishedDocumentUrl = String.fromEnvironment(
  'documentUrl',
  defaultValue: kStorageBase == ''
      ? ''
      : '$kStorageBase/o/orgs%2Fdemo%2Fprojects%2Fdemo%2Fdocuments%2Freward-catalog%2Fpublished.json?alt=media',
);

/// Document address the demo actually reads: a named fixture without an explicit `documentUrl` comes from
/// assets only (see [kFixtureGiven]); otherwise it would be replaced by the published document from storage.
const String kEffectiveDocumentUrl = kFixtureGiven && !kDocumentUrlGiven ? '' : kPublishedDocumentUrl;

/// Address of the COLLECTION in Firebase Storage.
///
/// This is not a document but the data behind it: catalog records, each with its own name,
/// price and photo. The document only references them by paths (`item.name`,
/// `item.price`, `item.image`), which is why one details screen shows different
/// records rather than the same one repeatedly.
///
/// THERE IS NO DEFAULT ADDRESS, on purpose.
///
/// Data in a product comes from the CLIENT'S BACKEND: the data dictionary describes what it
/// promises to layouts, and our storage does not see it. So the project layout
/// (`orgs/{orgId}/projects/{projectId}/…`) has no place for a catalog at all.
///
/// Without `--dart-define=collectionUrl=…` the screen is drawn from document
/// fallbacks, and collection handling can be checked by pointing to any address of your own.
///
/// What the demo checks over the network is the document and the theme, exactly what
/// comes from storage in a product.
const String kCollectionDataUrl = String.fromEnvironment('collectionUrl');

/// Default collection source, or `null` when there is no address.
CollectionSource? defaultCollectionSource({DocumentTransport? transport}) {
  if (kCollectionDataUrl.isEmpty) return null;
  return CollectionSource(
    url: Uri.parse(kCollectionDataUrl),
    transport: transport ?? HttpDocumentTransport(),
  );
}

/// Document sources: network first, bundled fixtures after it.
///
/// A list rather than a single source, because the question "where does what I see come from"
/// needs a visible answer and the ability to change it right during a presentation.
List<DocumentSource> defaultDocumentSources({
  DocumentTransport? transport,
  String documentUrl = kEffectiveDocumentUrl,
}) {
  final start = _startFixture();
  final bundled = [
    for (final fixture in kFixtures)
      fixtureSource(fixture.id, title: fixture.title),
  ];
  final fallback = fixtureSource(start.id, title: start.title);
  if (documentUrl.isEmpty) {
    // No network: the presentation starts from the bundled copy, so it comes first.
    return [fallback, ...bundled.where((source) => source.assetPath != fallback.assetPath)];
  }
  return [
    PublishedDocumentSource(
      url: Uri.parse(documentUrl),
      fallback: fallback,
      transport: transport ?? HttpDocumentTransport(),
    ),
    ...bundled,
  ];
}

/// Fixture named in `--dart-define=fixture=…`, or the first in the list.
///
/// Silently taking the first is not acceptable: a typo in the name would look like
/// "why is this the wrong screen".
({String id, String title}) _startFixture() {
  for (final fixture in kFixtures) {
    if (fixture.id == kStartFixture) return fixture;
  }
  if (kDebugMode) debugPrint('[demo] unknown fixture "$kStartFixture" — taking the first');
  return kFixtures.first;
}

class HotlayoutDemoApp extends StatefulWidget {
  HotlayoutDemoApp({
    required this.themeLoad,
    List<DocumentSource>? sources,
    CollectionSource? collection,
    super.key,
  }) : sources = sources ?? defaultDocumentSources(),
       collection = collection ?? defaultCollectionSource();

  final ThemeLoad themeLoad;

  /// First source of the list - the one the presentation starts from.
  final List<DocumentSource> sources;

  /// Where the data referenced by document paths comes from. `null` means
  /// no collection, and every binding takes the document's `fallback`.
  final CollectionSource? collection;

  @override
  State<HotlayoutDemoApp> createState() => _HotlayoutDemoAppState();
}

class _HotlayoutDemoAppState extends State<HotlayoutDemoApp> with WidgetsBindingObserver {
  /// `null` means "auto": the system mode picks the theme. A string is a manual
  /// user choice, which beats auto.
  String? _themeId;

  @override
  void initState() {
    super.initState();
    _themeId = _startThemeId(widget.themeLoad.contract);
    // We listen to `PlatformDispatcher`, not `MediaQuery`: the theme choice
    // is made ABOVE `MaterialApp`, where there is no `MediaQuery` yet.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Theme from `--dart-define=theme=…`: a theme id from the set, or `light` / `dark` by brightness.
  static String? _startThemeId(ThemeContract contract) {
    if (kStartTheme.isEmpty) return null;
    if (contract.themes.containsKey(kStartTheme)) return kStartTheme;
    final brightness = switch (kStartTheme) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => null,
    };
    if (brightness != null) {
      for (final theme in contract.themes.values) {
        if (theme.brightness == brightness) return theme.id;
      }
    }
    debugPrint('[demo] theme "$kStartTheme" is not in the set (${contract.themes.keys.join(', ')}): following the system mode');
    return null;
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final contract = widget.themeLoad.contract;
    // The "system mode -> theme" mapping is no longer hard-coded: it is done by the
    // contract's `brightness` field. The app does not know theme names - it only
    // knows whether it is dark now.
    final theme = _themeId != null
        ? contract.themeById(_themeId)
        : contract.themeForBrightness(
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
          );
    return MaterialApp(
      title: 'HotLayout',
      debugShowCheckedModeBanner: false,
      theme: theme.toMaterialTheme(),
      home: DocumentHost(
        theme: theme,
        themeLoad: widget.themeLoad,
        sources: widget.sources,
        collection: widget.collection,
        // The switch appears only when the artifact actually has something to
        // switch: a single theme in the list is not a choice but noise.
        onThemeSelected: contract.themes.length > 1 ? (id) => setState(() => _themeId = id) : null,
      ),
    );
  }
}

/// Demo host: the screen shows EXACTLY the document and nothing of its own.
///
/// The host has no title or switches of its own, so nothing duplicates the
/// document's `AppBar`. All scaffolding sits behind a gesture (see [_ServiceCorner]) and
/// in `--dart-define`.
///
/// The host still draws two things, and both follow from the contract being
/// silent about them:
///  * **system inset strips.** The document is drawn BETWEEN them: below the status bar
///    and above the home indicator. Otherwise "full screen" would put text under
///    the notch;
///  * **styling of those strips.** Taken from the document: the `Screen` background lies under
///    everything (it may be a gradient), and the top strip adds the `AppBar`'s own
///    background on top, but only if the bar has one, since the field is optional. This is a HOST
///    decision on contract data: the contract itself knows nothing about the status bar.
class DocumentHost extends StatefulWidget {
  const DocumentHost({
    required this.theme,
    required this.themeLoad,
    required this.sources,
    this.collection,
    this.onThemeSelected,
    super.key,
  });

  final RenderTheme theme;
  final ThemeLoad themeLoad;

  /// Where to take the document from. The first is the starting one; the rest are
  /// available from the service panel.
  final List<DocumentSource> sources;

  /// Collection of data the document addresses by paths.
  final CollectionSource? collection;

  final ValueChanged<String>? onThemeSelected;

  @override
  State<DocumentHost> createState() => _DocumentHostState();
}

class _DocumentHostState extends State<DocumentHost> with WidgetsBindingObserver {
  late DocumentSource _source = widget.sources.first;

  /// The document currently on screen, together with the reason why it is this one.
  ///
  /// Not a `Future` in a `FutureBuilder`: during a refresh the PREVIOUS document
  /// must stay on screen, while a `FutureBuilder` on a new future would show
  /// emptiness. Flicker on every return from background is not acceptable.
  DocumentLoad? _load;

  /// Error after which there is nothing to draw: not even the bundled copy is readable.
  Object? _error;

  /// Number of the current read. A response from a stale one (the source was
  /// switched in the meantime) is silently dropped; otherwise a document nobody
  /// asked for anymore would end up on screen.
  int _request = 0;

  /// Screen the renderer shows RIGHT NOW.
  ///
  /// Not `initialScreen`: the system inset strips take their styling from the
  /// current screen, and the stack is driven by the renderer. With a gradient the
  /// initial screen would leave a white strip above the next screen's gradient.
  ScreenEntry? _screen;

  /// Request of the top screen for system status bar icons (9.9.0):
  /// `light` / `dark`, or `null` when the screen asks for nothing.
  ///
  /// THIS IS AN EXAMPLE FOR THE INTEGRATOR. The package never touches the system bar (no
  /// `SystemChrome` in `lib/`): whether to honor the request is decided by the app,
  /// which knows how the reader is placed (edge to edge or in a frame with its own header).
  /// The request travels in `ScreenShown.statusBarIcons` only when the screen named it;
  /// here it is fulfilled by an `AnnotatedRegion` over the whole window.
  String? _statusBarIcons;

  /// Last action the renderer handed to the host. For the developer: visible in the
  /// service panel, never on screen.
  String? _lastAction;

  /// Data the document references by paths.
  ///
  /// The initial value is an EMPTY catalog, not `null` and not "loading":
  /// the first frame is drawn from document fallbacks and no waiting state exists
  /// on screen. It is the same principle as for the document itself (the bundled
  /// copy as a floor): if the catalog did not arrive, the screen is intact, just
  /// with numbers from the document.
  CollectionCatalog _records = CollectionCatalog.empty;

  /// The showcase app on screen (`showcase.dart`), or `null` for any other source. A showcase is
  /// drawn edge to edge with the host's data for it: the reader adds the system insets itself.
  ShowcaseApp? get _showcase => _source is BundledDocumentSource
      ? showcaseByDocumentAsset((_source as BundledDocumentSource).assetPath)
      : null;

  final GlobalKey _scaffoldKey = GlobalKey(debugLabel: 'demo-scaffold');

  /// What the host answers for [_showcase]; read before the document is put on screen.
  ShowcaseData? _showcaseData;
  String? _showcaseOf;

  /// Language chosen BY HAND in the service panel, or `null` for "as on the device".
  ///
  /// Same fork as for the theme (a manual choice beats auto), for the same
  /// reason: during a presentation the language must be switched deliberately without changing
  /// the phone's language. Automatic choice stays the default, because
  /// that is what a real app will do.
  String? _pickedLocale;

  @override
  void initState() {
    super.initState();
    // Refresh on return from background: pressing "Publish" in the builder and
    // switching to the app shows the new version without tapping anything.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_activate(_source));
    // The catalog is read IN PARALLEL with the document and waits for nobody: the document
    // is drawn without it, and when the data arrives the screen is repainted with it.
    unawaited(_loadCollection());
  }

  /// Read the data collection. Silently: it has no look of its own on screen;
  /// it shows only in whether numbers and photos belong to this very record.
  Future<void> _loadCollection() async {
    final source = widget.collection;
    if (source == null) return;
    final catalog = await source.load();
    if (!mounted) return;
    debugPrint('[demo] data collection: ${catalog.length} rec.');
    setState(() => _records = catalog);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Language we draw in now.
  ///
  /// `null` means "the literals' language", which for a single-language document is the only
  /// possible answer. Matching the device locale against the document's languages is done by
  /// the document ITSELF ([DocumentLocalization.localeFor]), not by the host: the rule must
  /// be the same for all hosts.
  String? get _locale {
    // `--dart-define=locale=ar-EG`: the DEVICE locale as is - the reader matches it to the
    // document's languages (`ar-EG` -> `ar`); a manual choice in the service panel is stronger.
    if (_pickedLocale == null && kStartLocale.isNotEmpty) return kStartLocale;
    final table = _load?.document.localization;
    if (table == null) return null;
    return _pickedLocale ?? table.localeFor(WidgetsBinding.instance.platformDispatcher.locales);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // The phone language rarely changes, but if it does the screen must follow,
    // except when the language was chosen by hand: then auto stays silent.
    if (_pickedLocale == null) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quiet: an automatic refresh must show nothing on screen. The result is
    // visible in the log and the service panel; if the document did not change,
    // nothing is visible at all, and that is right.
    if (state == AppLifecycleState.resumed) unawaited(_refresh(announce: false));
  }

  /// Make [source] current and read a document from it.
  Future<void> _activate(DocumentSource source, {bool announce = false}) async {
    final request = ++_request;
    if (!identical(source, _source)) setState(() => _source = source);
    final showcase = _showcase;
    if (showcase != null && _showcaseData == null || showcase != null && _showcaseOf != showcase.id) {
      final data = await ShowcaseData.load(showcase);
      if (!mounted || request != _request) return;
      setState(() {
        _showcaseData = data;
        _showcaseOf = showcase.id;
      });
    }

    // While the network thinks, the screen shows the bundled copy, not emptiness or an
    // indicator. Only on an empty screen: during a refresh what is shown is
    // already better than any placeholder.
    final seed = source.seed;
    if (seed != null && _load == null) {
      try {
        final preview = await seed.load();
        if (mounted && request == _request && _load == null) _apply(preview);
      } on Object catch (error) {
        // Silent: if the bundled copy is unreadable, the main read will say so;
        // it will fall back to it anyway.
        debugPrint('[demo] bundled copy could not be read: $error');
      }
    }

    try {
      final load = await source.load();
      if (!mounted || request != _request) return;
      final changed = _apply(load);
      debugPrint('[demo] document: ${_describe(load)}');
      if (announce) _announce(load, changed: changed);
    } on Object catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error);
    }
  }

  /// Re-read the current source.
  Future<void> _refresh({required bool announce}) async {
    if (!_source.isRefreshable) {
      // An asset does not change between reads, so "refreshing" it would show
      // the same thing and falsely claim something happened.
      if (announce) _showMessage('Source «${_source.title}» is bundled, nothing to refresh');
      return;
    }
    await _activate(_source, announce: announce);
  }

  /// Put what was read on screen. Returns `true` if the document CHANGED.
  ///
  /// The answer is needed not only for the screen stack but for the notice: "went to
  /// the network" and "what is shown became different" are different news. After
  /// publishing a change and pressing "refresh", "From network" would suggest the phone
  /// shows it, although the network returned the same document as before.
  bool _apply(DocumentLoad load) {
    final previous = _load;
    // The same document is no reason to rebuild the flow, and most refreshes
    // change nothing. A new version of the same document keeps the stack in
    // `ScreenFlow` while its screens exist.
    final unchanged = previous != null && previous.signature == load.signature;
    setState(() {
      _error = null;
      _load = unchanged ? load.reusing(previous.document) : load;
      if (!unchanged) _screen = null;
    });
    return !unchanged;
  }

  /// Response to an explicit gesture: a short notice saying what happened.
  ///
  /// Only for explicit ones; automatic refresh stays silent. The notice is not
  /// scaffolding in the frame but the answer to a gesture just made: without it,
  /// "Refresh" on an unchanged document looks like nothing happened, and one cannot
  /// tell whether it went to the network.
  void _announce(DocumentLoad load, {required bool changed}) =>
      _showMessage(_describe(load, changed: changed));

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  String _describe(DocumentLoad load, {bool changed = true}) {
    final reason = load.detail == null ? '' : ' — ${load.detail}';
    return switch (load.status) {
      /*
       * Two different news under one status. "Updated" means something different
       * arrived from storage; "no changes" means the request happened but storage
       * holds exactly the same. The second reads as a phone fault until it is
       * named aloud: the next question is for the builder -
       * whether what was edited has been published.
       */
      DocumentLoadStatus.network when !changed =>
        'From network: unchanged — storage has the same version',
      DocumentLoadStatus.network => 'From network, updated: «${load.document.name}»',
      DocumentLoadStatus.bundled => 'Bundled copy: «${load.document.name}»',
      DocumentLoadStatus.notPublished => 'Not published yet, bundled copy$reason',
      DocumentLoadStatus.serverError => 'Storage gave no document, bundled copy$reason',
      DocumentLoadStatus.timedOut => 'Network timed out, bundled copy$reason',
      DocumentLoadStatus.unreachable => 'No network, bundled copy$reason',
      DocumentLoadStatus.malformed => 'Document unusable, bundled copy$reason',
      DocumentLoadStatus.incompatible => 'Document of another version, bundled copy$reason',
    };
  }

  /// "14:07:52" - exactly what is needed to see whether a read happened at all.
  static String _clock(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final doc = _load?.document;
    final showcase = _showcase;
    final scaffold = showcase != null ? _showcaseScaffold(doc) : Scaffold(
      backgroundColor: widget.theme.color(ColorToken.surface),
      body: Stack(
        children: [
          // The screen background is drawn over the WHOLE area, including the system
          // inset strips. Before 7.0.0 the strips were painted separately; for a
          // solid background that gave the same pixel, but for a gradient the same fill
          // drawn twice in different boxes would diverge at the seam. Now exactly the same
          // styling lies under the strips as under the document.
          Positioned.fill(
            child: DecoratedBox(
              key: const ValueKey('demo-screen-backdrop'),
              decoration: _screenDecoration(doc),
            ),
          ),
          Column(
            children: [
              // The top strip has its own background only when the document's bar
              // has one: otherwise it stays transparent and the screen background
              // reaches the top, which is what making `AppBar.background` optional
              // in 7.0.0 was for.
              DecoratedBox(
                key: const ValueKey('demo-top-strip'),
                decoration: _appBarDecoration(doc),
                child: SizedBox(height: insets.top, width: double.infinity),
              ),
              // The strip above is the host's own handling of the top inset, so the reader gets zero
              // (schema 9.19.0: the reader adds the top inset itself unless the host did).
              Expanded(child: MediaQuery.removeViewPadding(context: context, removeTop: true, child: _body(doc))),
              SizedBox(height: insets.bottom, width: double.infinity),
            ],
          ),
          // The service corner lies ON TOP of the status bar strip, outside
          // the document altogether: by construction it cannot conflict with its nodes.
          _ServiceCorner(
            height: insets.top,
            onOpen: () => _openServicePanel(context),
            onRefresh: () => _refresh(announce: true),
            // What is shown NOT from the network must be visible without gestures and without the
            // panel: see the comment on `_ServiceCorner.fallback`.
            fallback: _load?.isFallback ?? false,
          ),
        ],
      ),
    );
    // The screen's request for status bar icons is fulfilled by the host (9.9.0): here by a wrapper
    // over the window. If the screen asks for nothing, we do not touch it and the system decides.
    final icons = switch (_statusBarIcons) {
      'light' => SystemUiOverlayStyle.light,
      'dark' => SystemUiOverlayStyle.dark,
      _ => null,
    };
    // The key keeps the screen flow alive when the wrapper appears or goes: without it a screen
    // that asks for status bar icons would remount the whole flow and send it back to the first screen.
    final keyed = KeyedSubtree(key: _scaffoldKey, child: scaffold);
    if (icons == null) return keyed;
    return AnnotatedRegion<SystemUiOverlayStyle>(value: icons, child: keyed);
  }

  /// A showcase app: the document fills the window, the reader adds the status bar and
  /// home-indicator insets itself and paints the app bar's background under the status bar.
  Widget _showcaseScaffold(UiDocument? doc) {
    final insets = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: widget.theme.color(ColorToken.surface),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              key: const ValueKey('demo-screen-backdrop'),
              decoration: _screenDecoration(doc),
            ),
          ),
          Positioned.fill(child: _body(doc)),
          _ServiceCorner(
            height: insets.top,
            onOpen: () => _openServicePanel(context),
            onRefresh: () => _refresh(announce: true),
            fallback: _load?.isFallback ?? false,
          ),
        ],
      ),
    );
  }

  /// Document the presentation starts from: with `--dart-define=screen=<screenId>` - the same document
  /// with [kStartScreen] as its initial screen. One object per document (identity memory): a new
  /// object each time would rebuild every screen of the stack for nothing.
  UiDocument _startedAt(UiDocument doc) {
    if (kStartScreen.isEmpty) return doc;
    final cached = _startedCache;
    if (cached != null && identical(cached.$1, doc)) return cached.$2;
    UiDocument started = doc;
    if (doc.screenById(kStartScreen) == null) {
      debugPrint(
        '[demo] screen "$kStartScreen" is not in the document (${doc.screens.map((s) => s.screenId).join(', ')}): '
        'using the start screen',
      );
    } else {
      started = UiDocument(
        schemaVersion: doc.schemaVersion,
        documentId: doc.documentId,
        name: doc.name,
        initialScreenId: kStartScreen,
        screens: doc.screens,
        entryPoints: doc.entryPoints,
        localization: doc.localization,
      );
    }
    _startedCache = (doc, started);
    return started;
  }

  (UiDocument, UiDocument)? _startedCache;

  Widget _body(UiDocument? doc) {
    if (_error != null) {
      return Center(child: Text('Could not read the document:\n$_error'));
    }
    // The empty screen lasts exactly one frame, while the bundled copy is read from
    // the bundle. There is deliberately no indicator: it would spin even if the
    // network never answers, which is exactly the "endless animation" a
    // presentation must not have.
    if (doc == null) return const SizedBox.expand();
    final showcase = _showcase;
    final answers = _showcaseData;
    if (showcase != null && answers == null) return const SizedBox.expand();
    final Map<String, Object?> data = answers == null
        ? _demoData
        : {
            ...answers.forLocale(_locale, scenario: kStartScenario),
            if (kStartTab.isNotEmpty) 'ui.missionsTab': kStartTab,
          };

    return renderDocument(
      _startedAt(doc),
      theme: widget.theme,
      data: data,
      // A showcase draws pictures from the product site only (its own addresses, or ones relative
      // to it); every other source keeps the package's default rule.
      resolveImageUrl: showcase == null ? null : showcaseImageUrl,
      locale: _locale,
      // The DEMO CLOCK is the moment the samples are imagined at (`x-sampleNow`), not
      // the machine clock: the data here is sample data, and "52 days left" must
      // stay 52 today, in a month and next to the builder canvas.
      // A real app does not pass this parameter.
      now: answers?.now ?? _sampleNow,
      // Screen entry: the renderer asks what the transition parameters mean, and the host
      // answers from the catalog. The closure is over the FIELD, not a snapshot:
      // the catalog arrives later than the first frame, and `setState` must repaint the already
      // opened screen, not just the next one.
      scopeFor: _records.scopeFor,
      // Only what the renderer did not handle itself arrives here:
      // transitions between document screens it performs without the host.
      //
      // The node's record travels with the action (9.2.0): a list row says WHICH
      // reward the action is about, and the "Redeem" button on a details screen opened from a row is
      // about the one the screen was opened with. This is how a real app learns
      // what to redeem.
      //
      // An "action: share (node promo-link)" notice used to pop up here. Useful for
      // the developer, but for a viewer it is a debugging trace over the product,
      // i.e. the same scaffolding in the frame. Now the action goes to the log and the
      // service panel, not to the screen: the demo host cannot do anything with it -
      // a real app implements `share`.
      onRecordAction: (action, nodeId, record) {
        final which = record?['item.name'] ?? record?['item.id'];
        _lastAction = '$action (node $nodeId${which == null ? '' : ', record: $which'})';
        debugPrint('[demo] host action: $_lastAction');
        _performStandard(action);
      },
      // A write (9.13.0 fields, and 9.19.0 `setValue` / `toggleValue` actions): a path and a string, bool or
      // number, on EVERY change. The demo
      // sends and stores nothing - only the log; a real app is responsible for
      // throttling network calls on such writes.
      onWrite: (path, value) {
        // A string, bool or (9.14.0) number; for a numeric field cleared or non-numeric it is ''.
        debugPrint('[demo] field write: $path = ${value.runtimeType} (input values are not logged)');
      },
      // Tap analytics event (9.8.0): arrives BEFORE the action. The demo sends it
      // nowhere - only logs it.
      onTrack: (event, nodeId, record) {
        debugPrint('[demo] analytics: $event (node $nodeId)');
      },
      // The "screen shown" event replaced `onScreenChanged`: it also says why
      // (entry, forward, back) and with which record. The demo only repaints
      // the system strips on it.
      onScreenShown: (shown) {
        debugPrint('[demo] shown: $shown');
        final screen = doc.screenById(shown.screenId);
        if (!mounted || screen == null) return;
        if (identical(_screen, screen) && _statusBarIcons == shown.statusBarIcons) return;
        setState(() {
          _screen = screen;
          _statusBarIcons = shown.statusBarIcons;
        });
      },
    );
  }

  /// Standard actions of the 9.8.0 catalog: the renderer opens nothing itself, the host
  /// calls the helper with EXECUTORS. Here they only write to the log and show
  /// a notice - the demo has nothing to open and, above all, must not: the address in
  /// the document comes from the network.
  void _performStandard(ButtonAction action) {
    final invalid = action.invalid;
    if (invalid != null) {
      _showMessage('${action.type}: invalid parameter «${invalid.param}» (${invalid.problem.wire})');
      return;
    }
    runStandardAction(
      action,
      openUrl: (url) => _showMessage('openUrl: $url'),
      // The host names the app's schemes. There is deliberately no empty list: without
      // it `deeplink` is never executed.
      deeplinkSchemes: const ['myapp'],
      openDeeplink: (url) => _showMessage('deeplink: $url'),
      close: () => _showMessage('close: the host would close the flow'),
    );
  }

  /// Root of the screen shown now.
  ///
  /// Before `onScreenChanged` the host saw only the INITIAL screen and had to
  /// style the strips with it. `initialScreen` stays as the fallback: the first
  /// notification arrives after the first frame, and something has to be drawn
  /// before it.
  ScreenNode? _rootOf(UiDocument? doc) {
    final root = (_screen ?? doc?.initialScreen)?.root;
    return root is ScreenNode ? root : null;
  }

  /// System strip styling comes from the document, not from our taste.
  BoxDecoration _screenDecoration(UiDocument? doc) {
    final root = _rootOf(doc);
    if (root == null) {
      return BoxDecoration(color: widget.theme.color(ColorToken.surface));
    }
    return hostScreenDecoration(root, widget.theme, const ScreenData(sampleScreenData));
  }

  /// Top strip background: the document bar's own background, or nothing.
  ///
  /// "Nothing" is not an error or a forgotten default: a bar without `background`
  /// is transparent per the 7.0.0 contract, and the strip above it must be too,
  /// otherwise a color absent from the document would appear under the status bar.
  BoxDecoration _appBarDecoration(UiDocument? doc) {
    final root = _rootOf(doc);
    if (root == null) return const BoxDecoration();
    return hostAppBarDecoration(root, widget.theme, const ScreenData(sampleScreenData));
  }

  /// Scaffolding: document source and refresh, theme choice, theme load state.
  ///
  /// A sheet, not an on-screen panel: it should be shown rarely and deliberately.
  Future<void> _openServicePanel(BuildContext context) async {
    final load = widget.themeLoad;
    final document = _load;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              dense: true,
              title: const Text('Service panel'),
              subtitle: Text(
                load.isFallback
                    ? 'The theme from the artifact could not be read (${load.status.name}) — '
                          'drawing with the built-in «${load.contract.defaultTheme.name}».'
                    : 'Theme: ${widget.theme.name}',
              ),
            ),
            // Document state is the main thing here: it answers the question
            // "why don't I see what I just published".
            if (document != null)
              ListTile(
                dense: true,
                title: const Text('Document'),
                subtitle: Text('${_describe(document)}\nat ${_clock(document.receivedAt)}'),
              ),
            if (_source.isRefreshable)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Refresh from network'),
                subtitle: const Text('a double tap in the corner does the same'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_refresh(announce: true));
                },
              ),
            // Data catalog. The question the row answers: "why does the screen show
            // document fallbacks and not real numbers" - the catalog did not arrive.
            if (widget.collection != null)
              ListTile(
                dense: true,
                title: const Text('Data collection'),
                subtitle: Text(
                  _records.isEmpty
                      ? 'not loaded — bindings use the document fallback'
                      : 'records: ${_records.length}',
                ),
              ),
            if (_lastAction != null)
              ListTile(
                dense: true,
                title: const Text('Last host action'),
                subtitle: Text(_lastAction!),
              ),
            const Divider(height: 1),
            for (final source in widget.sources)
              ListTile(
                title: Text(source.title),
                trailing: identical(source, _source) ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_activate(source, announce: true));
                },
              ),
            // Language switch (7.2.0). Appears only when the document actually
            // has something to switch: a single language is not a choice but a panel row
            // that does nothing.
            if (document != null && document.document.locales.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('Document language'),
                subtitle: Text(
                  _pickedLocale == null
                      ? 'as on the device → ${_locale ?? '—'}'
                      : 'picked manually: $_pickedLocale',
                ),
              ),
              ListTile(
                title: const Text('As on the device'),
                trailing: _pickedLocale == null ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _pickedLocale = null);
                },
              ),
              for (final locale in document.document.locales)
                ListTile(
                  title: Text(_localeLabel(locale, document.document.localization!)),
                  trailing: locale == _pickedLocale ? const Icon(Icons.check) : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _pickedLocale = locale);
                  },
                ),
            ],
            if (widget.onThemeSelected != null) ...[
              const Divider(height: 1),
              for (final id in load.contract.themeIds)
                ListTile(
                  title: Text(load.contract.themes[id]!.name),
                  trailing: id == widget.theme.id ? const Icon(Icons.check) : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onThemeSelected!(id);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Language label in the service panel.
///
/// The translation count is not decoration: it explains why in Kazakh
/// the screen is intact, while in English half of the strings stay Russian -
/// `missingTranslation: 'fall-back-to-default-locale'` is visible to the eye, not only
/// in the contract.
String _localeLabel(String locale, DocumentLocalization table) {
  if (locale == table.defaultLocale) return '$locale — document language';
  final translated = table.stringsFor(locale).length;
  return '$locale — translations: $translated';
}

/// Invisible entry to the scaffolding: gestures in the status bar strip.
///
/// Why this and not a `kDebugMode` panel: demos run from a plain
/// `flutter run`, i.e. in debug, and the panel would be on screen exactly when it
/// must not be visible. Why not only `--dart-define`: documents must be switched
/// during a presentation too, without restarting the app.
///
/// There are two gestures, both where the viewer does not tap:
///  * **long press** - the service panel;
///  * **double tap** - re-read the document.
///
/// Refresh is a separate gesture, not just a panel row, on purpose: during a
/// presentation it is the most frequent action ("published - show it"), and three taps
/// instead of one would cost pauses. There is no button on the screen at all:
/// this is a presentation tool, not a UI element, and it does not belong in the frame.
///
/// Neither gesture intercepts document taps: the detector is
/// `translucent` and claims only long-press and double-tap.
class _ServiceCorner extends StatelessWidget {
  const _ServiceCorner({
    required this.height,
    required this.onOpen,
    required this.onRefresh,
    this.fallback = false,
  });

  final double height;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;

  /// Whether what is shown is a FALLBACK - the bundled copy instead of the published one.
  ///
  /// THE ONLY SCAFFOLDING THAT IS STILL VISIBLE. The host rule is to stay out of the frame,
  /// and it is right for the normal course of things: everything service is hidden behind a
  /// gesture. But a fallback is not a service detail, it is a statement about the presentation itself:
  /// the screen shows NOT what is in storage. Staying silent would present an outdated
  /// version with the same confidence as a fresh one.
  ///
  /// A notice does not fit: it lives three seconds, and the situation persists.
  /// So the dot is permanent, tiny, in the status bar strip, i.e. outside the
  /// document. What exactly happened is still told by the long-press panel.
  final bool fallback;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    // Minimum for a device without a notch: the strip is zero there, but the
    // scaffolding must still be reachable by finger.
    height: height < 24 ? 24 : height,
    width: 96,
    child: GestureDetector(
      key: const ValueKey('demo-service-corner'),
      behavior: HitTestBehavior.translucent,
      onLongPress: onOpen,
      onDoubleTap: onRefresh,
      child: fallback
          ? const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: _FallbackDot(),
              ),
            )
          : null,
    ),
  );
}

/// The "shown not from the network" dot.
///
/// The color is deliberately not from the document theme: the theme is the PRODUCT's styling, and
/// the dot speaks about the presentation itself and must stay noticeable whatever palette
/// the builder sent. The size is just enough to be noticed peripherally and not
/// mistaken for a screen element.
class _FallbackDot extends StatelessWidget {
  const _FallbackDot();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('demo-fallback-dot'),
    width: 8,
    height: 8,
    decoration: const BoxDecoration(
      color: Color(0xFFE8A600),
      shape: BoxShape.circle,
    ),
  );
}

/// Styling of the strips under the screen: the EFFECTIVE root style, i.e. the base plus the first
/// state whose condition held (`x-style.caseSelection: 'first-match'`) - the same
/// resolved style as in the renderer. A root with a "locked" state that changes the
/// background gets strips of that color.
///
/// Conditions are evaluated on the HOST'S DATA ([data]), not on screen data: the list record
/// the renderer sees does not belong to the host here. A state that depends on a record
/// is "not met" here (a missing value is empty).
///
/// A BACKGROUND IMAGE for the strips is nothing: loading a network resource for a few
/// pixels under the status bar would duplicate the "loading" and "unavailable" states
/// the renderer already draws. The strip stays the app color
/// (`surface`), and the seam is visible only where the image is dark; gradient and
/// color are taken as is.
@visibleForTesting
BoxDecoration hostScreenDecoration(ScreenNode root, RenderTheme theme, ScreenData data) {
  final style = resolveNodeStyle(root.style, root.styleWhen, data, applicable: theme.applicableStyle);
  return theme.backgroundDecoration(style?.background);
}

/// Top strip background: the effective background of the document bar (with state), or nothing.
@visibleForTesting
BoxDecoration hostAppBarDecoration(ScreenNode root, RenderTheme theme, ScreenData data) {
  final header = root.children.firstOrNull;
  if (header is! AppBarNode) return const BoxDecoration();
  final style = resolveNodeStyle(header.style, header.styleWhen, data, applicable: theme.applicableStyle);
  return theme.backgroundDecoration(style?.background);
}
