# Contributing to hotlayout_flutter

This guide is for people who change the package. If you only want to use it in an app, read
`README.md` and the working example in `example/`.

`hotlayout_flutter` is a Flutter reader for [HotLayout](https://hotlayout.com) server-driven UI.
It takes a JSON document built in the HotLayout builder, a theme and your data, and draws the
screens with native Flutter widgets.

## Repository layout

The repository holds three Dart packages with three `pubspec.yaml` files:

| What | Where | Purpose |
|---|---|---|
| library | repository root: `lib/hotlayout_flutter.dart` + `lib/src/` | what an integrator depends on; the only part that ships in the pub archive |
| example | `example/` | the quick-start scenario only; shown on the pub.dev Example tab; its snippets are the code blocks of `README.md` |
| demo | `demo/` (package `hotlayout_demo`: `lib/`, `test/`, `integration_test/`, `android/`, `ios/`, `macos/`, `web/`) | a showcase app with a service panel, fixture picker and sample data; used to check the network path |

`flutter pub get` in the root also resolves `example/`; `demo/` is resolved separately
(`cd demo && flutter pub get`).

### The library: `lib/src/`

```
lib/hotlayout_flutter.dart   the public entry point (the only public file)
lib/src/model/               parsing and the rules of the contract (no widgets)
  nodes/                       node classes per family (layout, content, controls, chrome, ...)
  *_rules.dart                 reference implementations of contract rules (layout, form,
                               input, progress, carousel, bottom zone, width class, ...)
  action*.dart, bindable.dart, binding_format.dart, text_template.dart, plural_rules.dart,
  localization.dart, locale_resolve.dart, visibility.dart, node_style.dart, icon_set.dart, ...
lib/src/render/              turns the model into widgets
  node_renderer.dart           the context a subtree is drawn with + dispatch node -> widget
  render_document.dart         public rendering functions (`renderDocument`, `renderScreen`)
  screen_flow*.dart            the screen stack, system "back", modal layers
  screen_widget.dart, screen_zones.dart, screen_form.dart  one screen: zones, form state
  widgets/                     one file per widget family (text, button, row, column, grid,
                               image, list_tile, tabs, app_bar, nav_bar, progress, repeater,
                               carousel, input_fields, ...); `node_box.dart` draws the style box
  layout/                      layout helpers (row layout, stretching column, size limits)
  inputs/                      text field and toggle state shared by the input widgets
lib/src/theme/               theme contract loading, `RenderTheme`, roles, gradients and the
                             embedded fallback theme
lib/src/data/                document sources (bundled and HTTP) and screen data
```

Rules for the public entry point:

- `lib/hotlayout_flutter.dart` exports with `show` only. The list of exported names is written
  down in `test/public_api_test.dart`, so a new public name is a deliberate decision.
- Every Dart block in `README.md` is a verbatim excerpt of a file in `example/` (ignoring
  indentation and blank lines). To add a README example, add it to `example/lib/recipes.dart`
  first. The same test can check other Markdown pages that quote the examples:
  `HOTLAYOUT_DOCS=/path/a.md:/path/b.md flutter test test/public_api_test.dart`.
- Text that the app user sees or hears and that is not in the document (the "back" label, an
  image placeholder, the version notice) lives in `RendererLabels`: English by default, the host
  supplies its own. There must be no strings in other languages in `lib/src/`.
- Logs and `detail` fields are English and prefixed with `[hotlayout]`: an integrator reads them.

### Assets and the demo

- The package declares **no assets** and reads none at runtime. The built-in theme is code
  (`lib/src/theme/fallback_theme.dart`); the host supplies the document and the theme
  (`assetPath` in `BundledDocumentSource` and `ThemeLoad.fromBundle` is required).
- `assets/contract/` is a repository folder holding a copy of the contract artifacts. The package
  tests read it from disk (`test/support/fixtures.dart`: `readFixture`, `diskFixtureSource`,
  `diskAssetBundle`), not through `rootBundle`.
- The demo declares the same files as its own assets: `demo/assets/contract` is a symbolic link
  to `../../assets/contract`, so there is one copy. (On Windows git needs `core.symlinks=true`.)
- The demo deliberately imports `package:hotlayout_flutter/src/...` (its service strips read the
  resolved style of the root), so the `implementation_imports` lint is switched off in
  `demo/analysis_options.yaml`. `example/` never does this: it checks the public entry point.
- `demo/lib/sample_data.dart` and `demo/lib/collection_source.dart` are host code, but the
  renderer's fixture tests need exactly this data. They reach it through
  `test/support/demo_data.dart`, the only relative import into `demo/lib/`.

## Running checks

```bash
# library (repository root)
flutter pub get
flutter analyze                  # also covers example/ and demo/
flutter test                     # the package tests

# example
cd example && flutter test && flutter run -d chrome

# demo (always from demo/)
cd demo
flutter pub get
flutter test                     # the demo host tests
flutter run                      # device or simulator
flutter run -d web-server        # in a browser
```

If a test fails, find out what broke; do not weaken the assertion.

`test/` holds the package tests (rendering, parsing, theme, public API, plus guards that compare
the code with the contract artifacts). Tests named `*_cases_test.dart` run shared case tables
from `assets/contract/fixtures/`, so every reader of the contract is checked against the same
rows.

## The demo app

The demo shows exactly the document: it has no title bar or switches of its own, because they
would duplicate the document's `AppBar`. By default it opens `reward-catalog-screens`, a demo
catalog of rewards (a list with selection and a detail screen); it is the same fixture the
builder uses.

By default the demo never asks the network: the published document and theme are read only when
a storage base is named, and otherwise the bundled copies are used (the demo log says so).

Options that are not on screen but available at launch (`--dart-define`):

```bash
# from demo/
# read the published document and theme from your own storage bucket
flutter run --dart-define=HOTLAYOUT_STORAGE_BASE=https://firebasestorage.googleapis.com/v0/b/<bucket>
flutter run --dart-define=fixture=task-progress-screen   # another BUNDLED fixture
# the contract-9 showcase: four screens with their own theme (also taken from an asset),
# diagonal gradients and states; switch the network off
flutter run -d macos --dart-define=fixture=rewards-showcase-screens --dart-define=documentUrl=
flutter run --dart-define=documentUrl=https://...        # another publication URL
flutter run --dart-define=documentUrl=                   # network switched off entirely

# a built showcase to view next to the builder canvas
flutter build web --dart-define=fixture=rewards-showcase-screens --dart-define=documentUrl=
python3 -m http.server -d build/web 8099                 # -> http://localhost:8099
```

Gestures on the status-bar strip while the app runs:

| gesture | effect |
|---|---|
| long press | service panel: document state, refresh, source picker, theme picker |
| double tap | re-read the document from the network |

There is deliberately no button: this is a presentation tool, not product UI.

### Where the document comes from

`lib/src/data/document_source.dart` (package) and `demo/lib/main.dart` (which sources the demo
uses). The order is:

1. the first frame draws the **bundled copy**, which is local and therefore instant;
2. in parallel an HTTP request goes out with a 5 s timeout;
3. the response **replaces** the copy only if the document really differs (the body fingerprint
   is compared); otherwise a refresh would reset the screen stack under the viewer;
4. any failure (404 "not published yet", timeout, no network, not JSON, a foreign major version
   of the schema) leaves the bundled copy on screen and records the REASON in
   `DocumentLoad.status` / `detail`, visible in the service panel and the log.

Each request uses a slightly different URL (`&_req=<time>-<sequence>`): the storage serves
`Cache-Control` from the object metadata, and without the cache buster a refresh could show
yesterday's publication. The request does not send `Cache-Control: no-cache`; the reason is
explained in `document_source.dart`.

The on-device test is the only one that uses the network (in `flutter test` images always get
a 400):

```bash
cd demo && flutter test integration_test/demo_flow_test.dart -d <simulator udid>
```

`integration_test` pulls CocoaPods into the demo (`demo/ios/Podfile`, `pod install` on build).
If you need a project without pods, remove the dev dependency `integration_test` and the
`integration_test/` folder; the other tests do not depend on it.

To run on a **real iPhone** you must set your own signing team in Xcode (Runner target, Signing
& Capabilities) and sign in with its Apple ID. On macOS the demo needs the entitlement
`com.apple.security.network.client` (already in `demo/macos/Runner/*.entitlements`): without it
the sandbox resolves no host, everything silently comes from the bundle, and the network path is
not exercised at all. On iOS no entitlement is needed.

## Design decision: an unknown widget is normal

In an ordinary app an unknown type is a bug. In server-driven UI it is routine: the backend can
send a screen with a widget this app version does not know yet. Therefore:

- **the parser never throws.** An unknown `type` becomes an `UnknownNode` that keeps the `id`,
  the type string and the parsed children;
- **children of an unknown node are still drawn.** If an unknown *container* arrives, its content
  is composed of known widgets; dropping real content because of an unfamiliar wrapper is worse
  than showing it without the wrapper;
- **the "Unknown widget" badge appears in debug only.** The author of the document sees the
  problem while it can still be fixed; an end user would learn nothing from it, so in release
  the node is simply not shown.

The same goes for tokens: a name the theme does not declare gives the default of THAT field in
`props`, and in `style` the property is simply not applied. No exception, no "similar" token.

## Node style

The look of a node lives in `node.style` (and in `styleWhen[].style` states of the same shape),
identically on every widget. **There are no hidden defaults:** a node without `style` has no
background, padding, radius or shadow; the familiar card look is written into the document by
the builder.

| Field | Shape |
|---|---|
| `color`, `typography` | inherited down the tree; at the root `onSurface` / `bodyM` |
| `padding`, `margin` | a value or `{top, end, bottom, start}`; sides are logical, an unnamed side is 0 |
| `width`, `height`, `min...`, `max...` | a number of dp or a binding `{kind: 'binding', path, fallback}` |
| `radius` | a value or `{topStart, topEnd, bottomEnd, bottomStart}` |
| `border` | `{width, color}`, equal on all sides |
| `background` | a colour, a gradient (token or custom) or an image |
| `shadow` | a shadow token or 1-4 custom layers |
| `opacity` | 0...1 |

A colour is `"token"`, `{token, opacity}` (a tint of the token) or `{value: "#rrggbb", opacity?}`;
spacing and radius are a token or a number; a font is a token or `{token, fontSize?, fontWeight?,
lineHeight?, letterSpacing?}`.

How it is drawn:

- **One box for all widgets** (`nodeBox` in `lib/src/render/widgets/node_box.dart`): `margin` ->
  box (size, background, border, radius, shadow, opacity) -> `padding` -> content. The radius
  clips background and content, the shadow lies outside the clip, opacity applies to the whole
  box. No widget drawing code knows about style;
- **inheritance** goes through the renderer context (`Foreground` in `node_renderer.dart`), not
  `DefaultTextStyle`: only the widgets and parts that `x-style.colorParts` names read what is
  inherited. `Text` and `Icon` always do; `ListTile`, `AppBar`, `Tab` and `Accordion` only when a
  colour is NAMED on the node or an ancestor (main parts take it, secondary parts take it x 0.6);
  otherwise they use built-in colours;
- **states** are resolved at render time: the first state whose condition holds is applied over
  the base, field by field at the top level; the style is inherited after the overlay;
- **`Button` and `Badge`**: the theme role gives the default background, foreground and border;
  the node's own `background`, `color`, `border`, `radius`, `shadow`, `padding` and `typography`
  override each its own slot and sit on the widget surface, while `margin`, sizes and `opacity`
  go on the box around. An inherited colour does not override the role;
- **who sets the size**: weight beats `style.width`, a layer with `fill` takes the size of the
  stack, and `minWidth > maxWidth` makes the minimum win;
- **diagonal gradients** (45/135/225/315) have the exact geometry of CSS `to <corner>`
  (`CornerGradient`, `lib/src/theme/corner_gradient.dart`); angles are physical and are not
  mirrored in RTL;
- **parsing never throws**: an unknown style field is skipped, a number outside the schema range
  is clamped, a gradient or shadow with a broken part is dropped as a whole.

Tests: `node_style_test.dart` (shapes and parsing), `style_refs_test.dart` (references to theme
values, gradient geometry), `style_box_test.dart` (every box property, logical sides in RTL),
`style_inheritance_test.dart` (inheritance, composite widgets, button and badge),
`style_cases_test.dart` (states), `style_robustness_test.dart` (every widget x every size set x
every place in a layout, no exceptions).

## Contract artifacts

The package implements a reader of the HotLayout contract. The contract has independent
artifacts, each versioned on its own. `assets/contract/` holds copies of them:

| File | Describes |
|---|---|
| `screen-schema.json` | the widget vocabulary: which widgets, fields and tokens exist |
| `theme.json` | the values of the design system: what the tokens mean |
| `data-contract.json` | the data paths promised to a layout and their shapes |
| `icons.json` | the drawings (SVG bodies) for every icon name |
| `fixtures/` | example documents, themes and shared case tables |

The schema and the theme are versioned independently: a rebrand does not add widgets and a new
widget does not change the palette. The compatibility rule is the same for both
(`checkContractVersion`): the major version must match, a newer minor of the document is read
(minor changes only add optional fields). The versions this reader understands are
`kSupportedSchemaVersion` (`lib/src/model/compatibility.dart`, currently 9.19.0, also exposed
as `UiDocument.supportedSchemaVersion`) and `kSupportedThemeContractVersion`
(`lib/src/theme/theme_contract.dart`, currently 4.0.1).

A document with a foreign major version is not drawn. The notice has two texts
(`VersionVerdict.newerMajor` / `olderMajor`):

- a **newer** major: "Update the app to see this screen." (a newer app will read it);
- an **older** major (for example 8.x, whose look lives in `props` that this reader no longer
  looks for) or an unreadable version: the neutral "This screen is not available right now.".
  An update would not help; the document has to be republished from the builder. The reason and
  the versions go to the log (`[hotlayout] ... older major ... republished from the builder`).

The rule and the degradation policy come from the `x-compatibility` block of the artifact.
`test/schema_version_test.dart` checks both the rule and that the Dart mirror of the policy and
of the widget catalog has not drifted from the schema.

### Updating the copies

The artifacts are produced by the HotLayout builder, which owns the contract. Copy them from a
checkout of the builder into `assets/contract/`:

```bash
cp <builder>/contract/screen-schema.json assets/contract/
cp <builder>/contract/theme.json assets/contract/
cp <builder>/contract/data-contract.json assets/contract/
cp <builder>/contract/icons.json assets/contract/
cp -R <builder>/contract/fixtures/. assets/contract/fixtures/
```

then regenerate what is derived from them (see `tool/` below) and run the whole test suite.
Several parts of the Dart code mirror the artifacts (the version constants, the compatibility
policy, the catalog of widgets and actions, the layout rules). The guards in `test/` compare
them with the artifacts and fail with a description of the difference, so a forgotten update is
caught.

### Generators in `tool/`

| Command | Regenerates | When |
|---|---|---|
| `dart run tool/generate_fallback_theme.dart` | `lib/src/theme/fallback_theme.dart`, the embedded snapshot of the theme | after every copy of `theme.json` |
| `dart run tool/generate_icon_set.dart` | `lib/src/model/icon_set.dart`, the embedded icon set | after every copy of `icons.json` / `screen-schema.json` |
| `python3 tool/generate_plural_rules.py [path to intl/lib/src/plural_rules.dart]` | `lib/src/model/plural_rules.dart`: CLDR plural rules taken from `package:intl`, with operands computed by the package; run `dart format` on the output | when the `intl` version changes |

If you forget, the tests fail: `test/theme_contract_test.dart` compares the snapshot with the
`contract` block of the artifact byte for byte (and checks every row of the `x-compatibility`
policy by behaviour, not only by text), `test/icon_set_test.dart` does the same for the icon
set, and the plural test in `test/clarified_95_test.dart` compares the generated rules with
`intl`.

### Theme

`RenderTheme` reads token values from the theme file **at runtime**: there are no hex or px
values behind tokens in the code. A rebrand is replacing one file for every platform, not an app
release. The embedded snapshot (`fallback_theme.dart`) is for the case when the artifact cannot
be read: the app draws with it instead of an empty screen, and says so (`ThemeLoad.status`).

Every theme has `brightness: light | dark`, so the system dark mode picks a theme itself
(`ThemeContract.themeForBrightness`); theme names are not hard-coded in the app.

Notes on the theme format as the reader implements it:

- `roles` maps semantics to token names for `Badge.tone` and `Button.variant`. A theme without
  `roles` is unusable for the reader. The `background` and `border` slots are optional and mean
  "absent", not "transparent colour": a button without a background is a `TextButton` without
  a fill;
- the `gradient` set: an angle in CSS degrees (eight angles) and stops `{color, position}`;
  stops that are out of order give no gradient rather than an "almost right" one;
- the six dictionaries (`color`, `gradient`, `spacing`, `radius`, `elevation`, `typography`) are
  OPEN: the core (`x-tokens.core`) is required, and the theme declares the rest. `RenderTheme`
  therefore keeps tokens by name, and the enums in `tokens.dart` list only the core names the
  renderer itself refers to;
- a colour is `#rrggbb` or `#rrggbbaa` (alpha last; it is moved when building a `Color(int)`);
  roles may reference any colour of the theme, and a broken reference makes only its own slot
  neutral;
- a token the theme does not declare is **not drawn** and is not replaced by a similar one.

## Behaviour worth knowing before you change it

- **Multilingual documents.** The optional `localization` section is a table "language -> (place
  in the document -> text)". The host picks the language. The writing direction follows the
  language the document is SHOWN in: a language the document does not have does not flip the
  screen. If a place has no translation, the node's literal (the default language) is drawn:
  not empty, not a key, and **not the next language in the list**.
- **Bound value format** (`binding.format`): a date from data is shown as a date in the
  document's language and the device time zone, not as an ISO string. An unknown format and a
  value that does not parse are shown as they are.
- **Choice.** `ChoiceGroup` is the first node that describes state: the row whose `optionValue`
  equals the group's `value` is drawn as chosen; a tap moves the mark and the screen repaints.
  The state lives in the renderer; the document does not change.
- **Navigation.** `navigate` with `params.screenId` and `navigate.back` move through the
  renderer's own screen stack; an action it does not understand goes to the host. The system
  "back" (Android button and gesture, browser "back") steps back inside the document while it
  can, and on the first screen the event reaches the host's route. The host can intercept
  (`onSystemBack`), switch it off (`handleSystemBack: false`) or drive the stack itself
  (`ScreenFlowController`).
- **Visibility and data.** `visibleIf` works on any child node (`isTrue`/`isFalse`/`isEmpty`/
  `isNotEmpty`, `eq`/`neq`, `gt`/`gte`/`lt`/`lte`); a binding takes the value from the data map
  passed in, and `fallback` when it is absent.
- **Images.** An address whose PATH ends in `.svg` (query and fragment do not count; `.svgz` and
  SVG without an extension do not) is drawn as a vector with the same `fit`, ratio, radius,
  `alt` and placeholders as a raster image; scripts and external references in the file are not
  executed or loaded. `alt` of `Image` and `Icon` goes to the semantics tree.

## Publishing

The package is published on pub.dev. Before a release, see what pub says:

```bash
dart pub publish --dry-run
```

What is NOT in the pub archive (`.pubignore`) and why:

- `CONTRIBUTING.md` and local notes (`/CL*.md`, `/CONTRACT-*.md`): not for consumers;
- `demo/`: a separate app; the public entry point does not import it;
- `assets/`: contract artifacts and fixtures. The package neither declares nor reads them; they
  are for the tests and the demo;
- `test/` and `tool/`: the guard tests read the contract artifacts from disk and weigh about a
  megabyte; a consumer does not need them or the generators.

`example/` ships (it is the pub.dev Example tab), without `build/`, `.dart_tool/` and its lock
file.

## Current limitations

- **Icons are drawn from the embedded icon set** (`lib/src/model/icon_set.dart`, drawn by
  `lib/src/render/icon_glyph.dart` as `Path`s), not from an icon font, so release-build icon
  font tree-shaking does not affect them. The set is the same for every reader of the contract,
  so a new icon name means a new set version and a regenerated `icon_set.dart`.
- A document arrives **whole, as one file**: there is no delivery in parts, no drafts or
  versions, and no authentication (the file is publicly readable).
- A document does not say whether it changed: the contract has no revision or publication time,
  so the reader fingerprints the whole body.
- Navigation is **inside the document** only; the contract does not describe a jump to another
  document. `openUrl`, `deeplink` and `close` actions are validated by the reader and handed to
  the host, which executes them (`runStandardAction`).
- The system "back" is connected to the document stack through `PopScope` in `ScreenFlow`
  (`canPop` is true only on the first screen; see `test/system_back_test.dart`). The iOS swipe on
  a deeper screen is DISABLED, not turned into a step inside the document: this is how any route
  with `canPop: false` behaves, and the renderer has no gesture of its own. If a `ScreenFlow`
  stands outside any route (`ModalRoute.of` gives `null`), `PopScope` registers nothing and the
  flow does not see the event; use `ScreenFlowController` then.
- The `logo` / `banner` / `placeholder` assets are drawn gradients; there are no real files.
- Fonts are only named by the theme (for example `Inter`); the reader does not deliver font
  files, so the app must bundle them, otherwise the system fallback is drawn.
- Built-in user-facing texts are English by default (`RendererLabels`); `DocumentLoad.detail`
  and logs are English.
