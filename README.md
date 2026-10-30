# HotLayout for Flutter — `hotlayout_flutter`

Flutter renderer for [HotLayout](https://hotlayout.com) server-driven UI (SDUI). A screen is put together in the HotLayout visual builder and published as JSON; your app draws it with native Flutter widgets, so changing a screen needs no app release.

**Quickstart:** [docs](https://hotlayout.com/docs/integrator/quickstart-flutter) · [video](https://youtu.be/CXSNkaRxisA) · **Builder and access:** [hotlayout.com](https://hotlayout.com) · [try the editor](https://hotlayout.com/try)

[![pub.dev](https://img.shields.io/pub/v/hotlayout_flutter?label=pub.dev&color=0a6cc9)](https://pub.dev/packages/hotlayout_flutter)
[![pub points](https://img.shields.io/pub/points/hotlayout_flutter?color=0a6cc9)](https://pub.dev/packages/hotlayout_flutter/score)
[![License](https://img.shields.io/badge/license-Apache--2.0-0a6cc9)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-hotlayout.com-0a6cc9)](https://hotlayout.com/docs)

<p align="center">
  <img src="https://raw.githubusercontent.com/hotlayout/.github/main/profile/assets/app-obsidian.png" alt="A rewards screen built in HotLayout, dark theme" width="240">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/hotlayout/.github/main/profile/assets/app-sunny.png" alt="The same kind of screen with another theme, light and playful" width="240">
</p>
<p align="center"><sub>Two screens built in HotLayout. Try the editor in your browser, no sign-up: <a href="https://hotlayout.com/try">https://hotlayout.com/try</a></sub></p>

```sh
flutter pub add hotlayout_flutter
```

The integration is one call, `renderDocument`, inside a screen of your own app:

The snippet is cut from `example/lib/main.dart`; the names it uses (`theme`, `document`, `_actions`, `_onWrite`) are defined there.

```dart
return Theme(
  data: theme.toMaterialTheme(),
  // The renderer draws only the document: the Scaffold and the safe area
  // are the host's.
  child: Scaffold(
    body: SafeArea(
      child: renderDocument(
        document,
        theme: theme,
        data: widget.data,
        locale: locale,
        onRecordAction: _actions.handle,
        onWrite: _onWrite,
        // Documents from a source you do not fully trust: no autofill hints.
        // autofill: false,
      ),
    ),
  ),
);
```

The app around this call is [`example/lib/main.dart`](example/lib/main.dart) (200 lines); the [Quickstart](#quickstart) below walks through it.

## What you get

- **One widget.** `renderDocument` returns a widget with its own stack of screens; it adds no `Scaffold` and does not use your `Navigator`.
- **Three separate inputs.** The document (screens), the theme (token values) and your data (a plain `Map`) are loaded and replaced independently.
- **Languages and right-to-left.** A document carries its translations; you pass the device locale, the renderer picks the language, the formats and the direction.
- **Accessibility.** Buttons, fields, tabs and pressable cards have roles, names and states for a screen reader, and work from the keyboard.
- **The document is untrusted input.** The renderer opens no address by itself: links and deep links reach your code parsed and checked.
- **A version policy.** A newer minor of the document is still drawn; another major falls back to the copy bundled with your app.
- **The same document on the web.** [`@hotlayout/react`](https://www.npmjs.com/package/@hotlayout/react) draws the same JSON in React.
- **The same document on iOS and Android.** The native readers draw the same JSON: iOS through Swift Package Manager (`https://github.com/hotlayout/hotlayout-ios`) and Android from Maven Central (`com.hotlayout:hotlayout-android`). All readers follow the open [contract](https://github.com/hotlayout/contract).

## Install

```sh
flutter pub add hotlayout_flutter
```

or in `pubspec.yaml`:

```yaml
dependencies:
  hotlayout_flutter: ^0.33.1
```

Requires Dart `^3.11.5`. Everything you need is in one import; nothing under `src/` is public.

```dart
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
```

You give the renderer three things and get a widget back:

| Piece | What it is |
|---|---|
| Document | One JSON file: a set of screens built from widgets. Published by the builder as `published.json`. |
| Theme | One JSON file: token names (`primary`, `md`, `titleM`, and names of your own) and the values behind them. |
| Data | A `Map<String, Object?>` your app supplies: values for the paths the document is bound to (`user.points`, `tasks`). |

## Quickstart

The complete app is [`example/lib/main.dart`](example/lib/main.dart); `cd example && flutter run -d chrome` shows it. In short:

1. **Bundle a copy of the document and of the theme.** The renderer never shows an empty screen because the network failed: it draws a copy from your app bundle first. Export both files from the builder and declare them as assets:

   ```yaml
   flutter:
     assets:
       - assets/hotlayout/document.json
       - assets/hotlayout/theme.json
   ```

2. **Read the theme before the first frame** (`ThemeLoad.fromBundle` or `ThemeLoad.fromNetwork`; neither throws), and say where the document comes from: a `BundledDocumentSource`, or a `PublishedDocumentSource` with the bundled copy as its `fallback`.
3. **Load: the bundled copy at once, the network after.** `source.seed` gives the copy without waiting; `source.load()` asks the network and never throws because of it.
4. **Draw** with the `renderDocument` call at the top of this page, passing your `data` and the callbacks for actions (`onRecordAction`, `onAction`) and for what the user typed (`onWrite`).

The same steps with every parameter explained, and the standard actions, analytics, haptics, live data, placements and the list of what a document can draw, are in the [documentation](#documentation).

## Versions

Three numbers describe what this package reads, and the package version is a fourth, separate one:

| What | Version | Constant |
|---|---|---|
| Package | `0.33.1` | — |
| Document contract (schema) | `9.33.0` | `kSupportedSchemaVersion` |
| Theme contract | `4.0.1` | `kSupportedThemeContractVersion` |
| Built-in icon set | `1.0.0` | `kIconSetVersion` |

**The major version must match; a newer minor is readable.** A document of the same major is drawn, and parts this package does not know degrade: an unknown widget is skipped and its children are still drawn, an unknown token is not applied. A document of another major is not drawn; the user sees a notice, or the copy bundled with your app when the document came from the network. Only a newer document is cured by updating the app; an older one has to be republished from the builder. The theme follows the same rule. The full table of verdicts is in the [reference](https://hotlayout.com/docs/integrator/flutter-reference#version-compatibility); what each schema minor added is in the [contract changelog](https://hotlayout.com/docs/integrator/changelog), and what changed in each package version is in [CHANGELOG.md](CHANGELOG.md).

## Platform notes

On two platforms a missing permission does not fail — every request silently becomes `unreachable` and the bundled copies are shown, so the network path is never exercised. Check these first.

**macOS.** A sandboxed app needs the client entitlement in **both** `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

**Android.** `flutter create` declares `INTERNET` only in the debug and profile manifests. Add it to `android/app/src/main/AndroidManifest.xml`, or the **release** build is the blind one:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS.** Nothing to add for HTTPS.

**Web.** The server of the document and the theme must allow cross-origin reads (CORS) of the files.

**Fonts.** A theme names its font families; the package does not deliver font files. Until your app declares the family under `flutter: fonts:` with the same name, text is drawn in the platform's default font and nothing fails.

## When nothing shows up

| What you see | What to check |
|---|---|
| The bundled copy instead of the published document | Log `load.status`. `notPublished`: wrong address, or a draft was saved but never published. `unreachable` on every run: see [Platform notes](#platform-notes). `incompatible`: read `load.detail` — a newer document needs a newer package; an older one has to be republished from the builder. |
| `network`, but the screen did not change | Compare `signature` values: the storage holds the same document as before. |
| The screen is there, the values are not | Bindings show their fallbacks: the keys of `data` must match the paths of the data dictionary exactly. |
| A list is empty | The value under the collection name is not a `List`, or its records use full paths (`task.title`) instead of field names (`title`). |
| A block is missing | Its `visibleIf` condition did not hold; a missing value counts as empty. |
| Colors look wrong | Log `themeLoad.status`; anything but `ok` is a fallback theme. |
| A gray placeholder with a widget name, debug builds only | The document contains a widget this version does not know. Release builds skip it. |
| Text is in the wrong language | Log the `locale` you pass and `document.shownLocale(locale)`. |

Debug builds print what the renderer decided not to draw, prefixed with `[hotlayout]`. To hear about it in release builds too, pass `onReport` to `renderDocument`.

## Documentation

The README is an introduction; the reference lives at [hotlayout.com/docs](https://hotlayout.com/docs).

| Topic | Page |
|---|---|
| Step by step, from `flutter create` to a published screen | [Quickstart for Flutter](https://hotlayout.com/docs/integrator/quickstart-flutter) |
| Every `renderDocument` parameter: data, actions and navigation, theme, language, network, live data, reports, version compatibility, what each widget guarantees, demo app, limitations | [Flutter reference](https://hotlayout.com/docs/integrator/flutter-reference) |
| Fields of every widget, tokens and conditions | [Widgets](https://hotlayout.com/docs/integrator/widgets) |
| Named places in the app (`HotlayoutPlacement`) | [Placements](https://hotlayout.com/docs/integrator/placements) |
| Which paths of data the backend supplies | [Data dictionary](https://hotlayout.com/docs/integrator/data-dictionary) |
| Theme tokens and fonts | [Theme](https://hotlayout.com/docs/integrator/theme) |
| Languages and right-to-left | [Localization](https://hotlayout.com/docs/integrator/localization) |
| Where the document files live and how they are read | [Delivery](https://hotlayout.com/docs/integrator/delivery) |
| Version rules and what appeared when | [Compatibility](https://hotlayout.com/docs/integrator/compatibility), [Contract changelog](https://hotlayout.com/docs/integrator/changelog) |

More: the demo app that draws the showcase apps and any contract fixture is [`demo/`](demo/); changes by version are in [CHANGELOG.md](CHANGELOG.md).

## Learn more

- Website: [hotlayout.com](https://hotlayout.com)
- Video quickstart: [YouTube](https://youtu.be/CXSNkaRxisA)
- Getting the builder: screens are made in the HotLayout builder, hosted at hotlayout.com or self-hosted. To get access, use "Get access" on [hotlayout.com](https://hotlayout.com) or write to [contact@hotlayout.com](mailto:contact@hotlayout.com).

## License

Apache-2.0. See [LICENSE](LICENSE).

The icon drawings built into the package are from [Lucide](https://lucide.dev) (ISC License; some of them derive from Feather, MIT License), except ten drawn for HotLayout. The notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md); if your app has a licences screen, include them there.
