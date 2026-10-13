# hotlayout_flutter

Flutter renderer for **HotLayout** server-driven UI. A manager builds a screen in the HotLayout builder and publishes it; your app draws it with native Flutter widgets — no release needed to change a screen.

You give the renderer three things and get a widget back:

| Piece | What it is |
|---|---|
| Document | One JSON file: a set of screens built from widgets. Published by the builder as `published.json`. |
| Theme | One JSON file: token names (`primary`, `md`, `titleM`, and names of your own) and the values behind them. |
| Data | A `Map<String, Object?>` your app supplies: values for the paths the document is bound to (`user.points`, `tasks`). |

This version reads document contract **9.19.0** and theme contract **4.0.1** (`kSupportedSchemaVersion`, `kSupportedThemeContractVersion`), and has icon set **1.0.0** built in (`kIconSetVersion`).

## Install

```sh
flutter pub add hotlayout_flutter
```

or in `pubspec.yaml`:

```yaml
dependencies:
  hotlayout_flutter: ^0.19.0
```

Requires Dart `^3.11.5`. Everything you need is in one import:

```dart
import 'package:hotlayout_flutter/hotlayout_flutter.dart';
```

Nothing under `src/` is public.

## Quickstart

The complete app is [`example/lib/main.dart`](example/lib/main.dart); `cd example && flutter run -d chrome` shows it. The steps:

**1. Bundle a copy of the document and of the theme.** The renderer never shows an empty screen because the network failed: it draws a copy from your app bundle first. Export both files from the builder, put them into your app and declare them:

```yaml
flutter:
  assets:
    - assets/hotlayout/document.json
    - assets/hotlayout/theme.json
```

```dart
const documentAsset = 'assets/hotlayout/document.json';
const themeAsset = 'assets/hotlayout/theme.json';
```

**2. Read the theme before the first frame, and say where the document comes from.**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final transport = HttpDocumentTransport();

  // The theme is read BEFORE the first frame: replacing colors after the
  // screen is drawn is a visible jump. Neither call throws.
  final themeLoad = themeUrl.isEmpty
      ? await ThemeLoad.fromBundle(assetPath: themeAsset)
      : await ThemeLoad.fromNetwork(
          Uri.parse(themeUrl),
          transport: transport,
          assetPath: themeAsset,
        );
  if (themeLoad.isFallback) {
    debugPrint('theme fallback: ${themeLoad.status.name} ${themeLoad.detail ?? ''}');
  }

  const bundled = BundledDocumentSource(title: 'Bundled copy', assetPath: documentAsset);
  final DocumentSource source = documentUrl.isEmpty
      ? bundled
      : PublishedDocumentSource(
          url: Uri.parse(documentUrl),
          fallback: bundled,
          transport: transport,
        );
```

**3. Load: the bundled copy at once, the network after.**

```dart
  Future<void> _read() async {
    // 1. Draw the bundled copy at once: no loading state.
    final seed = widget.source.seed;
    if (seed != null) _show(await seed.load());

    // 2. Ask the network. This never throws because of the network.
    _show(await widget.source.load());
  }
```

**4. Draw.**

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
            onRecordAction: _onAction,
            onWrite: _onWrite,
            // Documents from a source you do not fully trust: no autofill hints.
            // autofill: false,
          ),
        ),
      ),
    );
```

`renderDocument` keeps its own stack of screens and performs navigation inside the document; it does not use your `Navigator`. The system back button steps back through that stack before it leaves your route (see [the system back button](#the-system-back-button)). It adds no `Scaffold` and no safe-area padding. A screen with `presentation: 'modal'` is drawn as a layer over the previous one: a sheet from the bottom, or a window in the middle when the screen says `modalPlacement: 'center'` (see [Images, the app bar, windows](#images-the-app-bar-windows-and-the-status-bar)).

## Data

`data` maps paths to values. Flat and nested keys both work and can be mixed; a collection is a list of records under the collection name:

```dart
const Map<String, Object?> backendData = {
  // flat: the key is the whole path
  'user.firstName': 'Alex',
  'user.points': 1250,
  'user.level': 3,
  'user.isPremium': true,
  'user.memberSince': '2025-03-14T09:00:00.000Z',

  // nested: the path is walked segment by segment
  'campaign': {'title': 'Autumn rewards', 'endsAt': '2026-11-30T23:59:59.000Z'},
```

```dart
  // a collection: a list of records under the collection name;
  // a record uses field names (`title`), not full paths (`task.title`)
  'tasks': [
    {
      'title': 'Make 5 card payments',
      'progress': 3,
      'target': 5,
      'completed': false,
      'rewardPoints': 100,
      'status': 'inProgress',
    },
```

- **Keep types.** A number stays a number, a boolean a boolean. Dates are ISO 8601 strings **with time and zone** (`2026-10-31T23:59:59Z`, `…T23:59+03:00`); anything else — a date without a time, a time without a zone — is not a date for the renderer and is shown as it came. A number sent as a string (`"1850"`) is shown as it is: it gets no group separators and no plural word agrees with it.
- **A missing value is not an error.** The binding shows the `fallback` written in the document; a missing value counts as empty in visibility conditions. For a text, an **empty string** is a missing value too (the fallback is shown); a string of spaces is a value.
- **A list draws at most 50 records** (a contract limit).
- Pass a new map when the data changes and rebuild; the screen stack is kept.

Which paths exist is defined by the project's data dictionary (`data-contract.json`, exported from the builder).

### Sentences, numbers, money and days

A text of the document can be a sentence with named places — `{done} / {total} steps`, `Only {price} until {date}`, `{days} {unit} left` — filled from your data (contract 9.4.0). There is nothing to write in your app: the renderer substitutes the values, formats them and picks the word. What you should know:

| In the document | On screen | Rule |
|---|---|---|
| `format: 'number'` | `1,850` · `1 850` · `١٬٨٥٠` | group separators and decimal mark of the language shown; grouping is always on; up to three fraction digits |
| `format: 'currency'`, `currency: 'JOD'` | `120 JOD` · `1 850,50 USD` | the amount, a no-break space, the ISO 4217 code — the same order in every language; a whole amount has no fraction, any other has the digits of the currency (USD 2, JOD 3, JPY 0) |
| `format: 'daysUntil'` | `4` | whole days until the moment, rounded **up** (three hours left is 1), never below 0; no time zone is involved |
| a plural word | `1 day` · `4 days` · `5 днів` · `22 дні` | the form for the CLDR plural category of the number in the language of the **shown** words; a missing form is `other` |

- **A missing value does not hide the sentence.** Each value has its own fallback text: `— / 5 steps`. The fallback is shown as written, never formatted. When the fallback shown is a plain decimal number (`0`, `-2`, `1.5`), the plural word agrees with it: `0 points`, `0 балів`.
- **The translator moves the places.** The sentence and the plural forms are translated per language in the document; a place the translation misspells stays on screen with its braces (`{dayz}`), so the mistake is visible.
- **Words are not mixed across languages.** When the plural forms of the shown language are not translated, the source forms are used with the source language's rules.
- **Numbers follow the formatting locale** — the one you passed, when the document has that language (see [Language](#language-and-right-to-left)): Arabic text with `ar-EG` digits. A value without a `format` is shown as it came, without separators.
- **A value the format cannot take is shown as it is**: a string where a number is expected, a `currency` without a three-letter code, a number beyond ±9,007,199,254,740,991 (2⁵³ − 1, either sign; no plural word agrees with it either), a date not in the form above **or not a real calendar moment** (`2026-02-30T…`, month 13, hour 24, offset `+24:00`).
- **Rounding is half away from zero over the shortest decimal form of the number you send**: `1.005` is `1.01` in a two-digit currency, `1.0005` is `1.001` under `number`. Send the exact decimal you mean; do not pre-round.
- **A plural word agrees with a fraction by the CLDR rules of the language**: French `1.5 point` (`one`), English `1.5 points` (`other`). The same when the `intl` package has no number data for the language — except "days left", which then shows the counted days in plain digits.

"Days left" needs to know what time it is. By default that is the device clock, read when the screen is built; the screen **does not redraw itself** as time passes — rebuild it (on resume, on a timer of yours) when that matters. Pass `now` to count from a clock of your own, and always in tests:

```dart
Widget drawAt(UiDocument document, RenderTheme theme, Map<String, Object?> data, DateTime serverNow) {
  // Without `now` the device clock is read each time the screen is built.
  // The screen does not redraw itself at midnight: rebuild to refresh it.
  return renderDocument(document, theme: theme, data: data, now: serverNow);
}
```

`renderScreen` takes the same `now`. A host that uses `renderScreen` must pass `strings: document.stringsFor(locale)` as before — the table also tells the renderer the source language, which the plural words of an untranslated sentence follow.

### Data of one screen

A list row usually opens a details screen for the record that was tapped, and the renderer does it by itself: **an action carries the record of its node**. A `navigate` from a list row opens the screen *with that row's record*, so the details screen shows the tapped row without any code of yours (see [One screen, many records](#one-screen-many-records)). `scopeFor` is for what the row does not have — the host finds the rest of the entity by the id the row carries:

```dart
  // A list row opens a details screen and carries its own record, so the
  // screen already shows the tapped row. The host adds what the row does not
  // have: it finds the full record by the id the row carries.
  Map<String, Object?> scopeFor(ScreenScopeRequest request) {
    final id = request.record?['item.id'];
    final record = id is String ? itemsById[id] : null;
    return record == null ? const {} : {'item': record};
  }

  return renderDocument(document, theme: theme, data: data, scopeFor: scopeFor);
```

`ScreenScopeRequest` has three fields: `record` (the record the screen was opened with, or `null`), `params` (what the navigation passed — for you only) and `read` (a lookup of a path in the data without your own map). A path is looked up in this order, and the first layer that **has** the value answers (`null` counts as "none"):

1. the **record** — the row the screen was opened with, and the rows of the lists a node is drawn in;
2. what the user changed in a bound input on this visit (a `ChoiceGroup`);
3. the map returned by `scopeFor`;
4. `data`.

The record is stronger than the user's choice on purpose: tap the row "Bottle" while the radio stands on "Backpack", and the screen is about the bottle, whole. A `ChoiceGroup` bound to a path the record also carries still shows the user's pick for as long as the value under its binding does not change.

`navigate.params` are **not data**: there is no `params.*` path. They are a free map of strings for your host (`ScreenScopeRequest.params`, `action.params`).

## Actions and navigation

The renderer performs three action types itself and hands everything else to the host:

| `action.type` | Who performs it | Parameters | Reaches the host when |
|---|---|---|---|
| `none` | the renderer: nothing happens | — | never (it may still carry an analytics `track`) |
| `navigate` | the renderer: opens the screen named in `params['screenId']` | `screenId` | the document has no such screen |
| `navigate.back` | the renderer: goes one screen back | — | the first screen is shown — "leave the flow" |
| `openUrl` | **the host** | `url`, an `https://` address | always, checked: `action.standard` or `action.invalid` |
| `deeplink` | **the host** | `url`, a link of your app (`myapp://offers/42`) | always, checked |
| `close` | **the host**: close the flow | — | always; the screen stack is not touched |
| anything else | the host | — | always, untouched |

The host gets an action through `onRecordAction` (the action, the id of the node and **the record of that node**) or, when it does not need the record, through the older `onAction` (the action and the id). When both are given, only `onRecordAction` is called.

```dart
  // `record` is the record of the node that was tapped: the list row, or the
  // row that opened this screen. A flat map of paths, or null.
  void _onAction(ButtonAction action, String nodeId, Map<String, Object?>? record) {
    switch (action.type) {
      case ButtonAction.navigateBack:
        // "Back" on the first screen of the document: leave the flow.
        Navigator.of(context).maybePop();
      case 'share':
        _say('Your share sheet opens here');
      case 'redeem':
        // Which reward? The row says so. Check the id on your backend like
        // any user input before you spend points on it.
        _say('Redeem ${record?['item.name']} (${record?['item.id']})?');
      default:
        debugPrint('unhandled action ${action.type} from $nodeId');
    }
  }
```

An action type you do not know is not an error: log it and do nothing. To open the document at a named entry point (from a push, a banner, a deep link) pass `entry:`; a name the document does not have opens the initial screen.

### Standard actions, analytics and screen views (contract 9.8.0)

**The renderer opens nothing by itself.** A document comes from the network; an address in it that the renderer opened without your word would be a phishing page in one published file. So `openUrl`, `deeplink` and `close` reach your `onAction` / `onRecordAction` **parsed and checked**, and you perform them:

- `action.standard` is an `OpenUrlAction` (`url`), a `DeeplinkAction` (`url`, `scheme`) or a `CloseAction` — set only when every parameter passed its form. `url` is the checked **string**, byte for byte; `uri` is a convenience getter (`Uri.tryParse(url)`, may be `null`, and that never changes the verdict);
- `action.invalid` (`param`, `problem`) is set when one did not. The action is still handed over (you may know more than the document), but it is never run by the helper below;
- the form is a regular expression from the contract, not `Uri.parse` (which accepts `https:\\host` and `https://bank@evil.example`). The check order is: missing, too long, form. An `https` address needs a host of two or more labels whose last label is letters (or `xn--…`), so no IPv4 in any notation (`https://2130706433/` is `127.0.0.1`) and no single-word name passes; a port is 1…65535.

A parameter may come from data: `paramBindings: {url: 'offer.url'}` is read with the data scope of the tapped node at the moment of the tap. Only a non-empty string replaces the literal; a number is NOT turned into text, and a value that fails the form is not replaced by the literal — the action is invalid. A catalog parameter marked not bindable (`navigate.screenId`) is never read from data: the literal acts. A parameter is whole data or whole literal — nothing is concatenated. In `params` an entry is read only when its key is 1…32 characters without whitespace and not `__proto__` / `constructor` / `prototype`, and its value is a string of at most 2048 characters; anything else is skipped (a number or a flag is not turned into text). An analytics `track` with such a name is ignored as a whole.

`runStandardAction` performs a checked standard action with executors **you** pass; call it from your `onAction` / `onRecordAction`. The package has no `url_launcher` in it — `openBrowser` is where `launchUrl` of your own `url_launcher` goes:

```dart
bool performStandard(
  ButtonAction action, {
  required void Function(String url) openBrowser,
  required void Function(String url) openAppLink,
  required VoidCallback closeFlow,
}) {
  return runStandardAction(
    action,
    openUrl: openBrowser,
    // The schemes your app owns. Without the list a `deeplink` is never run,
    // whatever the document says.
    deeplinkSchemes: const ['myapp'],
    openDeeplink: openAppLink,
    close: closeFlow,
  );
}
```

The contract's own list of forbidden schemes (`javascript`, `data`, `file`, `intent`, `http`, …) is the first layer; your `deeplinkSchemes` is the second, and it is yours to keep.

**What stays with you** (the document is untrusted input):

- open only `action.standard`. The `params['url']` of an invalid action is a raw string from the document — never open it;
- a package older than Flutter 0.8 (React 0.9) hands `openUrl` / `deeplink` of a 9.8 document as an unknown action with raw `params` and no verdict. If your host already had its own `openUrl` branch, update the package before managers start using the catalog;
- the content of a `deeplink` is untrusted too. With your scheme in `deeplinkSchemes` the action is `standard`, but the path and the query stay the document's: `myapp://open?url=javascript:…` is for your app's router to judge. `tel:`, `sms:`, `mailto:` and `market:` pass the form; only your scheme list holds them back. The form cannot tell an internal name (`intranet.corp`) from a public one: which domains may be opened is your list to keep;
- a double tap is two actions, and a held Enter or Space is one (the auto-repeat of a key is not a press). Protecting a payment from a repeated press is the host's job;
- do not build a route from `action.params['screenId']` (`router.push('/app/$id')`): match it against your own list of routes.

**Analytics.** A node whose action has `track` gives `onTrack(TrackEvent event, String nodeId, Map<String, Object?>? record)` exactly once per tap, **before** anything else the tap causes: before a navigation, before the host gets the action, and for `none` too (a button that only measures). The event is not part of the handed action.

```dart
  return renderDocument(
    document,
    theme: theme,
    data: data,
    onTrack: (event, nodeId, record) => log(event.event, event.params),
    onScreenShown: (shown) => log('screen_view', {
      'screen': shown.screenId,
      'cause': shown.cause.name, // entry | forward | back
      'depth': '${shown.depth}',
      if (shown.entry != null) 'entry': shown.entry!,
    }),
  );
```

**Screen views.** `onScreenShown` (`ScreenShown`: `documentId`, `screenId`, `entry`, `presentation`, `cause`, `depth`, `record`, and, only when the screen names them, `modalPlacement` and `statusBarIcons`) fires once each time the screen on top of the stack changes: the first screen, a step forward (a modal sheet too), a step back (the screen beneath the removed one; a closed sheet is the same), and a new `entry` or document. It is not fired on a rebuild, new data, another language, a re-parsed copy of the same document, an action handed to you, or a navigation that did not happen. There is no "hidden" event. The system back button is a step back like any other. `onScreenChanged` (which only said *which* `ScreenEntry`) still works, is deprecated and is called at the same moment.

**`carryRecord`.** A `navigate` with `carryRecord: true` opens a page with the record of the tapped node ("Choose delivery" from the details of a reward); without it a page opened from outside a list row opens without a record, as in 9.2.0.

### One screen, many records

The record of a node is a **flat map of paths to values** — `{'item.id': 'bottle', 'item.name': 'Bottle'}` — the same shape as `source.record` in `@hotlayout/react`. It is the record the screen was opened with, and over it the records of the list rows the node is drawn in (the inner row wins; a field that is `null` hides nothing). Nested maps in your collections are flattened into paths (`item.task.title`); lists stay values.

| The action is pressed… | `navigate` opens the screen… | `record` the host gets |
|---|---|---|
| in a list row | with the row's record (laid over the record of its own screen) | the same record |
| outside a list, the target is a **page** | **without** a record — "Back to catalog" from a details screen is a clean catalog | the record its screen was opened with, if any |
| outside a list, the target is a **modal** sheet | with the record of the screen beneath — "Redeem *{item.name}*?" is about the same record | the same |

- A screen opened without a record (the initial screen, an `entry`, a button outside a list) reads `item.*` from the other layers, as before: put the record into your data or return it from `scopeFor`.
- The record belongs to a stack frame: going back drops it, and another row opens another record.
- It is a snapshot taken when the row was pressed. The map is unmodifiable and holds only keys that have the form of a data path (`item.selectedId`; segments such as `__proto__` are dropped).
- **Treat an id from the record as user input.** The values are yours, but check an id on your backend before you act on it.

`renderScreen`, for a host that keeps the stack itself, takes the record of the screen as `record:`.

### The system back button

There is nothing to wire. While the document has a screen to go back to, the Android back button and back gesture (predictive back included) and the browser's back button go **one screen back inside the document** — the same step as the document's own `navigate.back` — and a modal screen is closed. On the first screen of the document the event is not intercepted: your `Navigator` pops the route the document stands in, exactly as it would without the renderer.

| Where the user is | System back |
|---|---|
| a deeper screen of the document | one screen back inside the document; your route stays |
| a modal screen of the document | the modal is closed |
| the first screen | your `Navigator` pops the route (or the app is left, on its root route) |
| a dialog or sheet of **your** app is open above the document | your dialog is closed first; the document does not move |

The renderer takes part through Flutter's `PopScope`, with `canPop` true exactly on the first screen, so the system shows the right predictive-back animation. Two consequences follow from how Flutter delivers the event:

- **iOS back swipe.** It pops your route from the document's first screen. On a deeper screen the swipe is disabled, as for any route that handles "back" itself — the document's own back arrow is the way back.
- **A nested `Navigator`** (a navigator per tab) receives the system back event only if your app forwards it, usually with `NavigatorPopHandler`. Forwarded, everything above works; not forwarded, the event never reaches the document — use the controller below.

To drive "back" from your own control, give the flow a `ScreenFlowController`:

```dart
class _FlowWithOwnBackState extends State<FlowWithOwnBack> {
  // A handle on the document's screen stack.
  final _flow = ScreenFlowController();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The host's own arrow: one screen back inside the document, and out
        // of the flow from its first screen.
        leading: BackButton(
          onPressed: () {
            if (!_flow.goBack()) Navigator.of(context).maybePop();
          },
        ),
        // The controller notifies when the stack changes.
        title: ListenableBuilder(
          listenable: _flow,
          builder: (context, _) => Text(_flow.canGoBack ? 'Details' : 'Rewards'),
        ),
      ),
      body: renderDocument(
        widget.document,
        theme: widget.theme,
        data: widget.data,
        controller: _flow,
      ),
    );
  }
}
```

| `ScreenFlowController` | |
|---|---|
| `canGoBack` | `true` when the document has a screen to go back to |
| `currentScreenId` | the screen shown now; `null` while no flow is attached |
| `goBack()` | one screen back; returns `false` and does nothing on the first screen |
| `addListener` | called when either value changes |

To step in before the flow goes back — unsaved input, a confirmation — pass `onSystemBack`. It is called only when the document has a screen to go back to:

```dart
    // Called only when the document has a screen to go back to. Return true
    // when you handled the event yourself; false lets the flow step back.
    onSystemBack: () {
      if (!hasUnsavedInput()) return false;
      askToDiscard();
      return true;
    },
```

With `handleSystemBack: false` the renderer leaves the event alone altogether: the system back always goes to your `Navigator`, and `ScreenFlowController.goBack()` is how you step back inside the document.

## Theme

`ThemeLoad` never throws. `status` says why the theme in use is the one in use; anything but `ok` means a fallback (`assetMissing`, `malformed`, `networkUnavailable`, `incompatibleVersion`).

The package bundles no assets of its own. `ThemeLoad.fromBundle(assetPath: …)` reads the theme **your** app declares; `ThemeLoad.fromNetwork(…, assetPath: …)` falls back to it when the network gives none. The last line of defence is a theme compiled into the package (`ThemeContract.fallback()`): it is what you get when the asset cannot be read, or when `fromNetwork` is called without `assetPath`.

A theme file carries a set of themes, each marked `light` or `dark`, so app code needs no theme ids:

```dart
    // The contract marks every theme light or dark: no theme ids in app code.
    final theme = widget.themeLoad.contract.themeForBrightness(
      MediaQuery.platformBrightnessOf(context),
    );
```

A user's own pick:

```dart
RenderTheme pickTheme(ThemeContract contract, Brightness system, {String? userChoice}) {
  if (userChoice != null && contract.hasTheme(userChoice)) {
    return contract.themeById(userChoice);
  }
  return contract.themeForBrightness(system);
}
```

`theme.toMaterialTheme()` gives a `ThemeData` in the same colors for the `Theme` or `MaterialApp` around the document.

## Language and right-to-left

A document carries all its languages; you say which one to show by passing `locale`. Pass the device locale **as the platform gives it** — the document finds its own language for it:

```dart
    // The document matches the device languages against its own list:
    // `ar-EG` finds `ar`. A user's choice wins over the device.
    final locale =
        widget.locale ??
        document.localization?.localeFor(WidgetsBinding.instance.platformDispatcher.locales);
```

The rule (contract 9.1.0):

- the tag is normalised — `ar_EG`, `ar-eg` and `AR-EG` are one tag;
- subtags are dropped from the end until a language of the document matches: `ar-EG` → `ar`, `zh-Hant-TW` → `zh-Hant` → `zh`;
- **never the other way round**: a device that asks for `ar` does not get a document's `ar-EG`, and `pt-BR` does not get `pt-PT`;
- no match, or `locale: null`: the source language of the document;
- a language of the document is one that has at least one translated string: a code listed in `locales` with an empty `strings` table is not a language, so it neither shows source text under a foreign direction nor decides the date format;
- a tag longer than 100 characters is not a tag: the source language;
- a missing translation of one string shows the source text, not an empty space.

`localeFor` returns the **requested** tag in canonical form (`ar-EG`, not `ar`): dates bound with a `format` then use the regional format next to the Arabic text. Only the well-formed part of a tag is used for dates (`ja_JP_JP` formats as `ja-JP`). Which translation is shown is a separate question:

```dart
void describeLocale(UiDocument document, String deviceLocale) {
  final answer = document.localeResolution(deviceLocale);
  debugPrint('text: ${answer.translation}'); // ar — the document's own tag
  debugPrint('formats: ${answer.formatting}'); // ar-EG — the requested locale
  debugPrint('direction: ${directionOfLocale(answer.directionLocale)}'); // TextDirection.rtl
  debugPrint('found: ${answer.matched}');
}
```

**Direction.** The renderer wraps the document in its own `Directionality`, taken from the language the document is actually **shown** in. An Arabic document inside an English app is drawn right-to-left and the rest of your app stays as it is; an Arabic device on a document without Arabic gets the source language, left-to-right. There is nothing to do in your app; `directionOfLocale` and `isRtlLocale` answer the same question for your own widgets (from CLDR data, no hand-written list).

**The renderer's own words.** Four short texts do not come from the document: the accessibility label of the back arrow, the caption of a failed image and two version notices ("Update the app to see this screen." and "This screen is not available right now." — see [Versions](#versions)). They are English by default; pass your own:

```dart
const germanLabels = RendererLabels(
  back: 'Zurück',
  imageUnavailable: 'Bild nicht verfügbar',
  updateRequired: 'Bitte aktualisieren Sie die App, um diesen Bildschirm zu sehen.',
  screenUnavailable: 'Dieser Bildschirm ist gerade nicht verfügbar.',
);
```

## Network and the fallback

`PublishedDocumentSource.load()` never throws because of the network. It returns a `DocumentLoad`:

| Field | Meaning |
|---|---|
| `document` | The `UiDocument` to draw. |
| `status` | Why this document is on screen (below). |
| `isFallback` | `true` when the bundled copy is shown **instead of** the published one. |
| `detail` | The reason in English, for logs. Not for users. |
| `signature` | Fingerprint of the JSON text: tells "same document" from "new document". |

| `status` | What happened | Shown |
|---|---|---|
| `network` | Read from the network. | published document |
| `bundled` | A bundled source was read; the network was not asked. | bundled copy |
| `notPublished` | HTTP 404: nothing is published at the address yet. | bundled copy |
| `serverError` | Any other status code that is not 200. | bundled copy |
| `timedOut` | No answer within `timeout` (5 seconds by default). | bundled copy |
| `unreachable` | The request did not happen: no connection, DNS, TLS, a missing platform permission. | bundled copy |
| `malformed` | The answer is not a document. | bundled copy |
| `incompatible` | Another major contract version. | bundled copy |

**A fallback is silent on screen by design — log `status`.** Without that line "published but not shown" looks like a broken phone.

Every request gets an extra query parameter (`_req=…`) so that a cache in between cannot serve an old publication. `HttpDocumentTransport` sends no custom headers, which keeps a web build free of CORS preflights.

**Refreshing.** A new `UiDocument` object resets the screen stack, and most re-reads bring the same document. Keep the object that is on screen when the signature did not change:

```dart
DocumentLoad apply(DocumentLoad? previous, DocumentLoad next) {
  final unchanged = previous != null && previous.signature == next.signature;
  return unchanged ? next.reusing(previous.document) : next;
}
```

**Your own HTTP stack.** Implement `DocumentTransport` (it serves the theme too):

```dart
final class AuthorizedTransport implements DocumentTransport {
  AuthorizedTransport(this.client, this.token);

  final http.Client client;
  final String Function() token;

  @override
  Future<DocumentResponse> fetch(Uri url) async {
    // Let the exception through when the request did not happen; the source
    // applies the timeout. In a web build a custom header makes the browser
    // send a CORS preflight, which your server must then allow.
    final response = await client.get(url, headers: {'Authorization': 'Bearer ${token()}'});
    return (statusCode: response.statusCode, body: utf8.decode(response.bodyBytes));
  }
}
```

## Versions

The package version (`0.19.0`) and the contract versions are separate numbers. The contract rule: **the major version must match; a newer minor is readable.**

| Document | `versionVerdict` | What the user sees |
|---|---|---|
| same major, same or older minor | `ok` | the screen |
| same major, newer minor | `newerMinor` | the screen; parts this renderer does not know degrade — an unknown widget is skipped and its children are still drawn, an unknown token is not applied |
| a **newer** major, handed to `renderDocument` directly | `newerMajor` | a notice in place of the screen: `RendererLabels.updateRequired` — "Update the app to see this screen." |
| an **older** major, handed to `renderDocument` directly | `olderMajor` | a neutral notice: `RendererLabels.screenUnavailable` — "This screen is not available right now." |
| no readable `schemaVersion` | `unparsable` | the same neutral notice |
| any of the three above, from the network | — | **the bundled copy**: `PublishedDocumentSource` reports `incompatible` and falls back; `detail` says which case it is |

The two notices differ because the cure differs. A newer document is read by a newer app, so the user is asked to update. An older document (an `8.x` document in a `9.x` renderer) is read by no newer app: it has to be **republished from the builder**, and the user can do nothing — so the notice gives no advice, and the reason goes to the debug log (`[hotlayout] document schema 8.20.0 is an older major than this renderer reads (9.19.0): … the document has to be republished from the builder`). `verdict.isMajorMismatch` is true for both.

So a user on an old app version keeps seeing the screen that shipped with the app while newer apps see the newly published one. When you obtain a document another way, check it yourself and show your own message:

```dart
Widget drawChecked(String json, RenderTheme theme, Map<String, Object?> data) {
  final document = UiDocument.fromJsonString(json); // throws FormatException
  final verdict = document.versionVerdict;

  if (!verdict.canRender) {
    // This renderer cannot read the document. Only a NEWER document is cured
    // by an app update; an older one has to be republished from the builder.
    debugPrint('document ${document.schemaVersion}, renderer $kSupportedSchemaVersion: $verdict');
    return Center(
      child: Text(
        verdict == VersionVerdict.newerMajor
            ? 'Update the app to see this screen.'
            : 'This screen is not available right now.',
      ),
    );
  }
  return renderDocument(document, theme: theme, data: data);
}
```

The same rule applies to the theme: another major gives the built-in fallback theme and `ThemeLoadStatus.incompatibleVersion`.

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

## Fonts

A theme **names** its font families (for example `Inter`) and lists fallbacks; the package does not deliver font files. Until your app provides the family, text is drawn in the platform's default font — nothing fails. To get the designed look, add the font files to your app under the same family name:

```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

Changing the family in the builder therefore needs the new font in your app before it shows.

A variable font file works too: declare it once and the weight comes from its `wght` axis, so 500 and 600 are real weights, not 400 or 700. The [`demo/`](demo/) app does exactly this with Inter (SIL OFL 1.1; the files are the Inter variable fonts from the Google Fonts download, and `demo/assets/fonts/OFL.txt` is the licence text that came with them, copyright The Inter Project Authors):

```yaml
flutter:
  fonts:
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Variable.ttf
        - asset: assets/fonts/Inter-Italic-Variable.ttf
          style: italic
```

Which family a theme asks for is in `fontFamilies.*.primary` of the theme file (the built-in themes: `Inter`). A family you did not ship falls back to the platform font, and a web build then shows a different font from the browser reader — the first thing to check when the two do not match.

## Demo

[`demo/`](demo/) is an app of its own (not part of the package) that draws any contract fixture. Run it from `demo/`:

```bash
# macOS (or any device): a fixture, from the bundled assets
flutter run -d macos --dart-define=fixture=adaptive-screens

# web: build with the base path you serve it from, then serve the folder
flutter build web --release --dart-define=fixture=adaptive-screens --base-href /adaptive/ -o build/adaptive
python3 -m http.server -d build 8099        # → http://localhost:8099/adaptive/
```

| `--dart-define` | meaning |
|---|---|
| `fixture=<id>` | the fixture to draw (`assets/contract/fixtures/<id>.json`); default `reward-catalog-screens` |
| `screen=<screenId>` | the screen to start on instead of the document's initial one (unknown id → the initial screen, the log says so) |
| `locale=<tag>` | the device locale handed to the reader as is (`ar-EG`, `uk`); the reader matches it to the languages of the document |
| `theme=<id\|light\|dark>` | a theme of the set by id, or by brightness; default follows the system |
| `themeUrl=<url>` | read the theme from this address (empty — never read it from the network) |
| `documentUrl=<url>` | read the published document from this address (empty — bundled copy only) |
| `collectionUrl=<url>` | data records for the document's paths |

A named `fixture` **without** `themeUrl` / `documentUrl` is read from the assets: its own theme (the showcase has one) or the built-in one, and the document itself — never the live storage. Pass an address to turn the network back on. The log (`[demo] тема: …`, `[demo] документ: …`) says where the theme and the document really came from.

Example — the adaptive showcase on a wide window, in Arabic, dark:

```bash
flutter run -d macos --dart-define=fixture=adaptive-screens --dart-define=locale=ar-EG --dart-define=theme=dark
# or the lab screen on a wide web page
flutter build web --release --dart-define=fixture=adaptive-screens --dart-define=screen=lab --base-href /lab/ -o build/lab
```

Open the web build in a window of 1280 px: the class is `expanded`, the navigation bar is at the top and a modal screen is a window in the centre; narrow the window below 600 and it goes back to the phone shape. The survey fixture starts with an empty form (the dictionary samples under `survey.*` are not given to it), so its «Next» is disabled until the required fields are filled.

## Testing your screen

In a widget test, assets are read outside the test's fake clock — load the theme and pump the screen inside `tester.runAsync`:

```dart
    // Assets are read outside the fake clock of a widget test.
    await tester.runAsync(() async {
      final themeLoad = await ThemeLoad.fromBundle(assetPath: themeAsset);
      expect(themeLoad.status, ThemeLoadStatus.ok);

      await tester.pumpWidget(
        MaterialApp(
          home: HotLayoutScreen(
            source: const BundledDocumentSource(title: 'Bundled copy', assetPath: documentAsset),
            themeLoad: themeLoad,
            data: backendData,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
```

For the network, give `PublishedDocumentSource` a fake `DocumentTransport` that returns a status code and a body; no HTTP mocking is needed. The whole test is [`example/test/widget_test.dart`](example/test/widget_test.dart).

## Buttons, icon buttons and chips

Contract 9.5.0 gives a button an icon and a size, a badge an icon (the "chip" of a mock-up is a badge with an icon), and adds the `IconButton` widget. There is nothing to write in your app; what the renderer guarantees:

| | What is drawn |
|---|---|
| `Button.size` `sm` / `md` / `lg` | padding and label font of the contract's size table, in theme tokens — **28 / 40 / 48** dp high with the built-in theme; no field is `md`, the button of earlier versions. The corner radius does not depend on the size |
| `Button.icon`, `Badge.icon` | an icon beside the label: 4 dp apart (`xs`), centred on the line of the text, in the colour of the text, sized by the font of the text. It does not change the height of the widget |
| `iconPosition` `start` / `end` | the place in **reading order**. In a right-to-left language `start` is on the right; directional icons (arrows, chevrons) are also mirrored, objects (a gift, a clock) are only moved |
| `IconButton` | a circle with the icon in the centre and no visible text; the same three sizes, as high as a button of that size (28 / 40 / 48, plus the hairline border of the `secondary` role); variants are the theme's button roles |

- **The accessible name of an icon button is its `label`** — translated and bound like any other text, announced by the screen reader with the role of a button, never drawn. A document without a label still gets a working button, named by its icon ("chevron left"). The icon of a `Button` is decorative and not announced; a `Badge` is text, not a control.
- **The visible size is not padded to 48 dp.** A 28 dp button is 28 dp on screen; the renderer extends the *touch area* around it to 48 × 48 dp without moving its neighbours. Do not wrap the document in widgets that add a minimum tap size.
- **An icon button sends its action like a button**: `navigate` inside the document is performed by the renderer, everything else reaches `onAction` / `onRecordAction`, with the record of the list row when it stands in one.
- **An icon the renderer cannot draw** (a name of a newer icon set, a value that is not a name) leaves an empty box of the same size, and the gap stays: the label does not jump.
- A node's own `style` wins over the size, each field on its own: `style.padding` replaces the padding, `style.typography` the font (and with it the icon).

**Changed in 0.5.0:** the trailing text of a list row (`ListTile.trailing.text`) and the icon beside it are drawn in `onSurface` — the colour of the row's title — instead of the muted colour earlier versions used. The contract now names this colour; a row or an ancestor that names its own `style.color` still wins.

## Rich text

Contract 9.6.0 lets one `Text` draw parts of its string in their own style — "1,850 Points" with a big number and a small caption, or "Earn **double** points". There is nothing to write in your app; what the renderer guarantees:

- **The string is the same as without styles.** The parts are the places of the `content` template (`{amount} {unit}`), and `Text.spans` maps a place name to a `color` and/or `typography`. A translation may put the places in another order (`{unit}: {amount}`) and every part keeps its style.
- **One paragraph, one line pitch.** Words wrap across the parts, the parts stand on one baseline, and every line of the paragraph has the height of the tallest declared line (font size × line height of the text style and of every part the node declares), so the height of a paragraph does not depend on which line the big word fell on. `align`, `maxLines` and `overflow` work as for a text without parts.
- **Right-to-left**: the parts are laid out in the logical order of the translated string and ordered by the bidirectional algorithm over the whole string; a part is not isolated.
- **Accessibility**: a screen reader hears one node with the whole string.
- A word that is not data is `{kind: 'text', text: 'double'}` in the values of a template; it is translated by `<place>.values.<name>.text`.

## Pressable cards

Contract 9.19.0 lets a `Column`, `Row`, `Container` or `Stack` carry an `action` (and a hidden `label`): the whole card becomes a button on the finished screen. Nothing to write in your app; what the renderer guarantees:

- **The same action as a button's.** The card runs the action through the same path (`navigate` inside the document, everything else to `onAction` / `onRecordAction`, `track` once and before the action, the record of its list row). An action `none` without an event makes no card.
- **The innermost control takes the press.** A button, an icon button, a list row with an action, a field, a switch, a choice option, the tab strip and the header of an accordion keep their taps; the card gets every other point of its box (without the margin) and nothing it did not take. A disabled button inside swallows the press: neither it nor the card does anything.
- **For a screen reader the card is a button** whose name is the `label` first and then the text of its content. The controls inside stay separate nodes with their own names. Enter and Space press it from the keyboard; a held key is one press, and the keyboard focus shows a ring in the colour `primary` that follows the radius of the card. There is no pressed look: the document did not ask for one.
- The tree may be eight levels deep and a column may hold a column; the reader checks neither. A screen whose tree goes deeper than 32 levels below its root is not drawn at all (a neutral notice, `RendererLabels.screenUnavailable`, stands in its place): half a screen would be a wrong screen.

## Choice from plain nodes and the write actions

Contract 9.19.0 adds two actions the reader performs itself, `setValue` (puts a literal under a data path) and `toggleValue` (flips the flag under it). A segment, chips, cards and a scale are buttons and pressable cards with these actions; the look of "selected" is the document's own `styleWhen`. What the renderer guarantees:

- **The same write as a field's.** The value goes into the reader's session and to `onWrite` at the same moment, typed by the action's `valueType`: a `String`, a `bool`, a `num` (an empty `String` clears a number). The action never reaches `onAction`, valid or not; an unusable action (`missing-path`, `path-too-long`, `unknown-value-type`, `not-a-flag`, `not-a-number`) writes nothing and is named in the debug log. The analytics event (`track`) goes first, also when nothing is written.
- **Only literals.** The path and the value come from the document, never from data (`paramBindings` and `carryRecord` are not read). A path with a prototype segment or not of the form of a data path is not written. There is no list of allowed paths in this package: you see every write in `onWrite`.
- **The same value is not written twice** (equality by type: `"7"` is not `7`, an empty string equals an absent value); a toggle always writes the negation of what is shown.
- **For a screen reader** a node whose action sets a non-empty value is a radio with a checked state, a toggle is a button with a toggled state; a `setValue` that clears and an unusable action are plain buttons. The state is computed from the data on every build. The place in the group ("2 of 3") is not spoken by this package, and there are no arrow keys between options: every option is a stop of Tab.
- `isEmpty` / `isNotEmpty` judge the **value under the path**, whatever its type: a number (zero too) and a flag (`false` too) are not empty, a string of spaces is not empty (it is no longer trimmed), `""`, `null`, an absent value and an empty list are.

## Parts of a list row and of a text field

Contract 9.19.0, all optional: a row and a field without the new fields are drawn as before.

- **List row**: `trailing.style` / `styleWhen` (colour and font of the amount, with states), `trailing.caption` with `captionStyle` / `captionStyleWhen` (one line under the amount, both pushed to the logical end), `titleMaxLines` / `subtitleMaxLines` (1…5, the rest cut with an ellipsis at the logical end), `leading.color` and `leading.tile` (a tinted square, circle with `pill`, under the icon). A token the theme does not know skips that key. The style of a part goes nowhere down the tree.
- **Text field**: `fieldRadius`, `fieldBackground`, `fieldBorderColor`, `fieldBorderWidth` (1…4) and `fieldHeight` (32…120, one line only) style the box of the field, not the box of the node; focus and error replace only the colour of the border. `prefix` / `suffix` are a short text (the first 8 code points) or an icon inside the box, on the logical sides of the **screen** while the content of the field keeps its own direction; they are never written and a press on one focuses the field. `counter: true` with a `maxLength` shows `{count} / {max}` in code points under the box; it is part of the field's description and is not announced on every change.

## Description of a picture, icon from data, parts of a date, "none" in a width layer

- **`alt`** of an `Image` or an `Icon` is a string or a string of the document: it is translated under the key of the field, can be a binding or a template, and what is shown empty makes the picture decorative. A description of a picture inside a pressable card names the card.
- **`iconPath`** (`Icon`, `Button`, `Badge`, `IconButton`) names a data path that holds the NAME of an icon of the set; the icon of the document is drawn when the data has no value. A name that is not in the set, or a value that is not a string, is an empty box of the same size: an address or a drawing from data is never drawn. The mirroring follows the resolved name.
- **`dateParts`** beside `format: 'date'` (`dayMonth`, `weekdayDayMonth`, `dayMonthYear`): the parts of the date in the order the language puts them; the day is the one in the time zone of the device. On any other format the field is ignored.
- **`unset`** in `styleOn` and `propsOn` removes the named fields on a wider class first, then the layer is laid on; removed on `medium` stays removed on `expanded` until named again.

## Money

Contract 9.19.0 adds three optional fields to a binding with the `number` or `currency` format: `currencyDisplay: 'symbol'` (the sign of the currency instead of its code), `currencyPosition: 'before'` and `sign: 'always'`. Without any of them the text is exactly what earlier versions wrote; with at least one the amount takes one composed form in every language:

- **Order**: number sign, currency before, amount, currency after. The minus is U+2212 and the plus U+002B, written by the renderer (never the platform's); an amount written as zero has no sign. The sign of a currency comes from a table of twelve codes embedded in the renderer; another code is shown as the code, in the same place.
- **Right-to-left**: the whole composed form is wrapped in U+2066 … U+2069, so the signs and the currency keep their order inside an Arabic sentence.
- **Parts of the text**: `Text.spans[place].parts` styles the `fraction` (the decimal separator and the digits after it) and the `currency` of an amount ("24 580**,75** ₴"). A part with no style of its own is not a separate run, and a declared part counts in the height of the line even when the amount does not show it.

## The top of the screen

Contract 9.19.0: `Screen.props.bodyTop: 'screenTop'` makes the body start at the top edge of the screen, with the app bar lying over it where it always stood (it still does not scroll). What the renderer guarantees:

- **The reader adds the top safe inset itself**, from the `MediaQuery.viewPadding` of its own context: inside the app bar (its box is taller by the inset, so a named background covers the status bar), or above the body when there is no app bar. A host that already wraps the reader in a `SafeArea` gives zero and nothing changes. Inside a modal layer there is no inset; the sheet is no taller than the area below it. The reader never touches the status bar itself (`statusBarIcons` is still the host's).
- **From the top edge** the first child stands at the very top (no gap, no padding above it, nothing raised by `pull`), scrolled content shows under an app bar without a background, and the whole box of the app bar takes the press, also where nothing is drawn.

## Progress bar and ring

Contract 9.7.0 gives `ProgressBar` and `CircularProgress` a `thickness`, a `trackColor` and a `gradient`, and lets the node's box size the ring. Nothing to write in your app; what the renderer guarantees:

- **The track lies under the whole scale, the fill over it.** A gradient lies along the FILLED part (its last colour is at the end of the fill, whatever the value), on a bar from the logical start of the fill, on a ring as a sweep from the top. A gradient that does not resolve is dropped as a whole and the fill is the solid `color`.
- **The ring's arc lies inside the circle**: the outer diameter is the diameter (`size` × the `xl` spacing, or the smaller named side of the box content), the thickness is at most half of it. The arc starts at the top, runs clockwise, has flat ends and is not mirrored in a right-to-left language. A size given by the parent (a row weight, a stack fill layer) does not name the diameter: the ring keeps its size and stands at the centre of the place.
- **A bar fills from the logical start** (the right in a right-to-left language) and its fill has a rounded end. A limit of zero or less is an empty scale, not a full one.

**Changed in 0.7.0:** earlier versions drew these with Material's indicators, so a ring was `thickness` wider than its diameter, the fill of a bar ended flat, and a bar with a limit of `0` was full.

## Images, the app bar, windows and the status bar

Contract 9.9.0. There is nothing to write in your app, except one optional line for the status bar; what the renderer guarantees:

- **An image is the box of its node.** The width is the one the parent gives (or the named `style.width`); the height is the named `style.height` when there is one — the proportion is then **not read**, so a 56 × 56 avatar with `aspectRatio: '16:9'` is 56 × 56 — otherwise width ÷ proportion, clamped by `minHeight` / `maxHeight`. `aspectRatio` is a word (`1:1`, `16:9`, `4:3`) or your own pair `{ width: 343, height: 120 }`; a ratio the renderer does not understand is `16:9`, and one beyond 1:8 … 8:1 is clamped. The picture lies in the box by `fit`, centred, and the radius of the node clips it; the box has the same size while the file loads and when it fails. A circle is equal sides plus a radius: `pill` is a number of the theme, so a 160 × 160 square with `pill` is a rounded square, not a circle.
- **The app bar has three zones** in reading order: a back arrow, the title, the actions (children of the `AppBar` of type `IconButton`, in document order; other children are not drawn). The title stands in the **middle of the bar** while it fits and is moved just off the zones otherwise; there is no longer an empty counterweight opposite the arrow. A gap exists only next to a zone that has content. In a right-to-left language the order of reading is kept: the arrow on the right, the first action next to the title. An action paints itself (its role and its own `style.color`), never with the colour of the bar.
- **The app bar stands still; only the body scrolls** (`appBarScroll`). The bar is the first child of the screen root when it is an `AppBar` (by the document, not by visibility: a bar hidden by a condition has no zone, and the next node does not become the bar). It stands at the top inside the top and side padding of the screen; the rest of the children are the body, which scrolls vertically under it with the side and bottom padding and the gap of the screen inside the scroll. The background of the root lies under every zone and does not scroll; the body is clipped at the bottom edge of the bar, so a bar without its own background shows the background of the screen, never text sliding under it. A first body child pulled by `pull` raises the body area by its overlap (`pull` minus the gap, not above the top of the screen) from the first frame, and the body paints over the bar there. A modal layer has the same zones: its body scrolls, its bar stays.
- **A window in the middle**: `modalPlacement: 'center'` on a modal screen. The width is the area minus `xl` (24 dp) on each side, at most 400; the height is the content's, at most the area minus `xl` above and below; taller content scrolls **inside** the window. Without the field (or with a word this version does not know) a modal screen is a sheet from the bottom, as before. The layer has **no look of its own**: background, radius, shadow and padding are the `style` of the screen's root, and a root without a background is a transparent layer. The scrim is black at 45 %; a tap beside the window and the system back button are `navigate.back`. The window is a modal layer in every rule (it inherits the record of the screen beneath, it is a "modal" in `ScreenShown`).
- **The status bar is not touched.** A screen may ask for light or dark status-bar icons (`statusBarIcons: 'light' | 'dark'`). The package never calls `SystemChrome`; the request reaches you in `ScreenShown.statusBarIcons`, only when the screen named it, and carrying it out is yours — you know whether the document is laid edge to edge or inside your own bar. The `demo/` app shows the whole of it:

```dart
class _StatusBarIconsHostState extends State<StatusBarIconsHost> {
  String? _icons;

  @override
  Widget build(BuildContext context) {
    final screen = renderDocument(
      widget.document,
      theme: widget.theme,
      data: const {},
      onScreenShown: (shown) => setState(() => _icons = shown.statusBarIcons),
    );
    final style = switch (_icons) {
      'light' => SystemUiOverlayStyle.light,
      'dark' => SystemUiOverlayStyle.dark,
      _ => null, // the screen asks for nothing: the system decides
    };
    if (style == null) return screen;
    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: screen);
  }
}
```

**Changed in 0.9.0** (two places where earlier versions differed from the contract): the title used to be centred in what was left after a counterweight the size of the arrow and was cut shorter — it is now centred in the bar and a long title gets all the room between the zones; `aspectRatio: { width, height }` of a document was read as `16:9`.

## Overlays and pulled children

Contract 9.10.0. Nothing to write in your app. A child of `Stack` with `layer` is an overlay (a badge on the corner of an icon, a chip on the edge of a ring, a ribbon across a card): placed by its own alignment, shifted by `offset` and turned by `rotate`, and it never changes the size of the stack. A child of a column or a row with `pull` lies over the previous one (a sheet over a header, avatars with an overlap). A tap lands where an overlay is drawn, inside the box of the stack; what sticks out of the box is a drawing only. A stack does not clip by itself: the radius, a named size and scrolling do.

Contract 9.11.0. Nothing to write in your app. A `Row` with `scrollable: true` or a `Repeater` laid out in a row with a `carousel` field is a carousel: the scroll snaps to the start of every card and dots under it show the position (one per stop; none for one stop or more than ten). `perView` sets how many whole cards fit; `peek` how much of the next one shows. The state (which card is open) is kept by the widget while the screen is in the stack and is never written to the document. A `ProgressBar` with `segments` (2…12) is drawn as equal steps, each filled whole or not at all, with `currentColor` for the first unfilled one.

## Bottom navigation and a pinned block

Contract 9.12.0. Nothing to write in your app, and no new parameter. The LAST child of a screen root, when it is a `NavBar`, is the navigation bar: it stands at the bottom of the screen and does not scroll. Its `NavItem` children (up to five) share the width equally, icon above the label; the active one is the item whose action is `navigate.section` to the screen shown. A child of the root that has `pin: 'bottom'` (the last one, not counting the bar) is a block pinned above the bar: the body scrolls above it and ends at its top edge. `navigate.section` makes the named screen the only one in the stack (a new `onScreenShown` event with `cause: switch`, depth 1, no record); the system back button on a section goes to the host, as on the first screen. The reader adds the bottom safe inset itself (`MediaQuery.viewPaddingOf(context).bottom`) UNDER the bar, and the background of the bar reaches the physical bottom; a host that wraps the reader in `SafeArea` already gives zero, so nothing is doubled. A screen shown as a modal layer has no bar, but a pinned block stands at the bottom of the layer.

## Forms: text fields, switches and checkboxes

Contract 9.13.0. A screen can now ask: `TextField`, `Switch` and `Checkbox`. The value of a field is a path of the data dictionary (`form.email`, `settings.notifications`) — the reader reads it through the same layers as any binding and writes to it. What you add to your app is one callback:

```dart
  // What the user typed or switched in a `TextField`, `Switch`, `Checkbox` or
  // `ChoiceGroup`: the data path of the field and a String, a bool or (a number
  // `TextField`) a num; an empty String when the number was cleared. Called on
  // every change, at once. It is user input: check it on your backend like any
  // other, and throttle here if a network stands behind it.
  void _onWrite(String path, Object? value) {
    switch (value) {
      case String text:
        debugPrint('text field $path: ${text.length} characters');
      case bool on:
        debugPrint('switch or checkbox $path: $on');
      case num number:
        debugPrint('number field $path: $number');
    }
  }
```

Pass it as `onWrite:` to `renderDocument` (the same typedef `SduiValueWrite` as for `renderScreen`; its value is a `String` from a text field or a choice group, a `bool` from a switch or a checkbox, and — since 9.14.0 — a `num` from a number field (an `int` for a whole value, a `double` otherwise); since 9.19.0 the `setValue` and `toggleValue` actions write through it too: **host code that stored every value as a string must be reviewed**). Read the rules before you rely on them:

- **Every change is written at once**: on every edit of a text field and on every press of a switch or checkbox, into the reader's own session (so conditions and texts on the same screen follow the user) and to `onWrite`, in that order, before any action the user presses afterwards. There is no delay and no "on blur". Throttling a network behind it is **your** job.
- **The value is user input.** A document comes from the network, so it names the path a value is written to, and a hostile document can bind a field to any path of the dictionary. Validate on the backend what you receive, whatever the client showed. The reader never writes a field that is disabled (`disabledIf`), has no path, or whose text did not change; a composing IME text is written when the composition ends.
- **Errors are yours.** The reader validates nothing: the text of a field's `error` is a string in `data` under the path the document names (`form.phoneError`); a text that can be heard (not blank, not invisible characters) puts the field in the error state.
- **`autofill: false`** turns every autofill hint of the text fields off. By default a field gives the platform a hint from its keyboard (`email`, `telephoneNumber`, `url`) and nothing else — never credentials, a card, an address or a one-time code. A value the platform fills in before the user touched the field is neither kept nor written. Pass `false` for documents from a source you do not fully trust.
- **There is no password field** (`keyboard: 'password'` is read as plain `text`): the value would reach the host in the clear and the document is not yours.
- **The keyboard**: the reader reads `MediaQuery.viewInsetsOf` of its own context and leaves your `Scaffold` alone. The focused field, with its helper line, scrolls into the body area above the keyboard; a block pinned to the bottom rides above the keyboard, the navigation bar stays under it. A host whose `Scaffold` already resizes the body gives zero there, so nothing is subtracted twice.

### A form for a survey: required fields, a disabled button, a number field

Contract 9.14.0. Nothing new to pass to the reader: the state of a button is computed by the reader itself, from the document and the values the user has entered. A document can now say:

- **`required: true`** on a `TextField`, a `Checkbox` or a `ChoiceGroup` (only the literal `true`; any other value means "not required"). The reader draws a red `*` after the label of a text field or checkbox (the label and the mark wrap as one text) and tells the screen reader the field is required; the mark is not part of the accessible name. It shows **no text of its own** ("fill this in") and never turns a field into the error state because it is empty — the error text is still yours (`error` from `data`).
- **`requiresFilled: true`** on a `Button` or an `IconButton` (also an action in the app bar): the button is disabled while the form of its screen is not filled. A **disabled** button is drawn at half opacity with the same colours, does not react to a tap, Enter or Space, calls neither `onAction` nor `onTrack`, and stays in the focus order and in the screen reader's tree as "disabled". **`disabledIf`** (the same condition form as `visibleIf`) disables a button too; if either holds, the button is disabled.
- **`valueType: 'number'`** on a `TextField`: a number field. The reader parses the text with its own rule, not with `double.tryParse`: a minus, digits (ASCII, Arabic-Indic or Persian), one decimal separator (`.`, `,`, `٫`), at most 15 digits, no groups and no exponent (`"1,200"` is 1.2, `"1e5"` is not a number). It writes a **number** (`int` when whole: `12`, not `12.0`), or an **empty string `""`** when what is typed is not a number or was cleared (`"12a"` writes `""`, the field keeps the text). A string under the path of a number field (even `"12"`) is shown as an empty field. The keyboard is the numeric one and one line; `keyboard` and `lines` are not read.

What "filled" means: the form of a screen is filled when every **required** field the user can fill is filled — judged by the **value under the path** through the data layers (the user's own input first, then your `data`), not by what a widget shows. A text is filled if it can be heard (not blank), a number if there is a number, a checkbox if it is `true`, a choice group if it has a non-empty value. A required field that is hidden by `visibleIf` (its own or an ancestor's), disabled by `disabledIf`, or inside a list drawn from data does not count; a field in a tab that is not open does. A modal layer is a screen of its own with its own form. Because `ChoiceGroup` now writes the user's choice into the reader's session and to `onWrite` like any other field (the same option is not written twice), conditions and buttons on the screen follow a choice at once.

**Check the form on your backend too.** A disabled button is a convenience, not a guard: a hostile document simply does not set `requiresFilled`. A path whose value is not a non-empty string (a number, a checkbox) is not taken as an action parameter — the literal from `params` is used.

### Alignment, a custom app bar, text emphasis, list items (contracts 9.15.0–9.17.0)

Nothing to write in your app; what a document can now say and what the reader guarantees:

- **Alignment on both axes (9.15.0).** `Column.justify`, `Container.align` / `justify` and `Screen.align` / `justify` (the words of `Row`). `align` is the cross axis: it places only the children that do not stretch (a node with its own `style.width` and the widgets that keep their natural width); a stretched child keeps the full width at any word. `justify` is the main axis and acts only where there is free space: a column with `style.height`, `style.minHeight` or a stack layer with `fill`; a row container always; a screen — the visible body between the app bar and the bottom zone (an app bar, a pinned block and a navigation bar do not take part; content taller than the body scrolls and `justify` is not read). `gap` stays the smallest distance, shifts are not rounded, `between` with one child is `start`. An unknown word reads as no field.
- **A custom app bar (9.16.0).** A `Button` or `IconButton` child of `AppBar` with `zone: 'leading'` stands in the leading zone instead of the back arrow (the first such child in document order; a hidden one leaves `showBack` in charge); it is not one of the two actions and never wider than half of the bar. `AppBar.titleAlign: 'start'` puts the title right after the leading zone. `glyphSize` (a whole number 8…128) on `Icon` and `IconButton` sets the side of the drawing: the box of an icon button grows with it, a named `style.width` / `height` clamps it, and the system text scale does not multiply it. The system back button stays with the host.
- **Text emphasis (9.17.0).** `style.fontStyle` (`normal | italic`) and `style.textDecoration` (`none | underline | lineThrough`) on any node are inherited by `Text` only (an italic card does not make the label of a button inside it italic); `normal` and `none` cancel what is inherited. A part of a composed text can also name `weight` (`regular | medium | semibold | bold`, stronger than its font style), `fontStyle` and `textDecoration`. The line is drawn by every run on its own.
- **List items (9.17.0).** `Text.marker: 'bullet' | 'number'`: the marker column and the gap are fractions of the font size (not measured), the text hangs under its first line, numbers count the VISIBLE neighbours in a row and the width of the column follows the group by the document (digits follow the formatting language). A numbered template of a `Repeater` counts the drawn records.
- **A ring label (9.17.0).** `CircularProgress.labelTypography` and `labelColor`; without them the label is `caption` / `onSurface` as before. The label does not grow with the ring, does not inherit, and is not clipped by the ring.

### Adaptive layout by width (contract 9.18.0, step 1)

Nothing to write in your app: the reader measures the box the screen is drawn in and picks a **width class** from it. One document serves every width; it is built for a phone, and wider classes override it.

- **The class** comes from the width of the box of THIS screen (the root with its padding, logical pixels, a `LayoutBuilder`), not from the window and not from `MediaQuery`: a widget placed in a part of a tablet screen, or in a narrow column, gets the class of that box. `compact` is below 600, `medium` from 600, `expanded` from 1024; the width is not rounded (599.9 is `compact`), and an unbounded or unknown width is `compact`. The limits are data of the contract, not settings. A modal screen is drawn inside its own box, so it measures that box.
- **Changing the class** (a rotation, a split screen, a resized desktop window) redraws the same screen with the other class: the stack of screens, the session, the values and focus of fields and the position of carousels stay. The tree of a screen is resolved for a class once and cached; data changes do not resolve it again.
- **`showOn`** (a list of classes) on any node but the screen root: shown only on the named classes, and only while its `visibleIf` holds. A hidden node is hidden everywhere the reader asks "is it visible": the zones of the screen (a hidden app bar or pinned block leaves no zone, its neighbour does not take its place), the actions of the app bar and the items of the navigation bar (the first two / five VISIBLE ones are drawn), the numbers of list items, the open tab, required fields of a form, stack layers, row weights and carousel cards.
- **`styleOn`** (`medium`, `expanded`) overrides fields of `style` the way a state does (whole top-level fields), from the narrow class up: `style`, then `medium`, then `expanded`, then the first state whose condition holds — a state is stronger than the width.
- **`propsOn`** overrides a closed list of properties of six widgets: `Screen` (`gap`, `align`, `justify`, `contentMaxWidth`), `Column`, `Row` (with the `perView` of a carousel), `Container` (`direction`, `gap`, `align`, `justify`), `Grid` (`columns`, `gap`) and `Repeater` (`direction`, `columns`, `gap`, `carousel.perView`). `columns` in an override is 1…6 (the base keeps 2…4). A container that turns into a row on a wide class carries its children's `weight`; on the narrow classes the weights are not read.
- **`Screen.contentMaxWidth`** (320…1920): the header, the body, the pinned block and the items of the navigation bar form a column no wider than that, in the centre (the same in both writing directions); the backgrounds of the root and of the zones stay edge to edge.

A document that uses these fields on a reader older than 9.18.0 draws the phone layout on every width and shows every `showOn` node.

### Navigation and modal screens on a wide screen (contract 9.18.0, step 2)

The document does not change — the **place** is chosen by the reader from the width class of the screen, because a wide place has its own custom: a menu in the head of a site, tabs at the top of an iPad, a dialog in the middle instead of a sheet.

- **The navigation bar** (the last child of a section, `NavBar`) stays at the bottom on `compact`. On `medium` and `expanded` it goes to the top: its items stand in the app bar of the screen, in the trailing zone before the actions (icon and label in a row); a screen without an app bar (or with one that is hidden by its condition or class) gets a bar of its own at the top — fixed, edge to edge, items from the start of the row in the column of `contentMaxWidth`. `NavBar.widePlacement: 'bottom'` keeps the bar at the bottom on every width (the same word on every section). Items are the same controls as at the bottom: `navigate.section`, the active item, semantics (role `navigation`).
- **When the app bar is too narrow**: the title gives way first, then ALL labels hide together (the items become icons, a hidden label stays the accessible name), then the title goes to zero, then the leading node; what still does not fit is clipped at the end of the bar. Icons and actions never shrink.
- **The bottom zone** on a wide screen is only the pinned block (`pin: 'bottom'`); the reader adds the bottom safe inset only when the bottom zone exists.
- **A modal screen** (`presentation: 'modal'`) without `modalPlacement` is a sheet on `compact` and a **window in the centre** on `medium` and `expanded`: up to 560 wide, as tall as its content but at most 85 % of the height; the body scrolls, the app bar of the layer stays. The class is that of the AREA the host gave the stack, not of the layer; the class of the CONTENT is that of the box of the layer (a window of 560 is always `compact`, so the content is the phone layout). `modalPlacement: 'center'` is the window of 9.9.0 (400) on every width. The window never goes under the on-screen keyboard.
- **Nothing is lost on a change of the class**: the stack, the session, the values and focus of fields and an open modal layer stay.

A document that relies on this on a reader older than 0.17.0 (or older than 9.18.0) shows the bar at the bottom and the sheet at the bottom on every width — a working screen, but a phone one.

## Limitations

- A sentence with places (`kind: 'template'`) lives in texts for people: `Text`, `Button` and `Badge` labels, titles and subtitles of `AppBar`, `ListTile`, `Tab`, `Accordion`, and the trailing text of a row. The exact characters of a formatted number come from the `intl` package's CLDR data, which may be of another release than a browser's: the rule is the same on every platform, single characters (digits of plain `ar`, a group separator) may differ. Percentages, compact numbers ("1.2K"), currency symbols and "hours left" are not formats of the contract.
- A document arrives whole, as one public file: no partial delivery and no authentication built in (use your own `DocumentTransport` for the latter).
- Navigation is inside one document. Links to another document and deep links are yours to route — use `entry:`.
- The named image assets `logo`, `banner` and `placeholder` are drawn as generated gradients; real images come by URL (PNG, JPEG, WebP, SVG).
- Icons are the 332 names of the contract's icon set (`contract/icons.json`, set version `kIconSetVersion`); a document cannot bring its own. The drawings are built into the package and drawn as vector paths in the colour of the node, so they are the same drawings the manager saw in the builder — not Material Icons. A name this renderer does not have (a document of a newer minor), or an icon value that is not a name, leaves an **empty box of the same size**: no substitute icon is drawn and the layout does not move. In a right-to-left language the 29 directional icons the contract lists (arrows, chevrons, `undo`, `send`, …) are mirrored by the renderer; there is nothing to set in your app. The set adds about 65 KB of source to your app whether or not a document uses every icon, because the icon name is data of the document.

## When nothing shows up

1. **The bundled copy is on screen instead of the published one.** Log `load.status`. `notPublished`: wrong address, or a draft was saved but never published. `unreachable` on every run: see the platform notes. `incompatible`: read `load.detail` — a newer document needs a newer package; an older one has to be republished from the builder.
2. **`network`, but the screen did not change.** Compare `signature` values: the storage holds the same document as before.
3. **The screen is there, the values are not.** Bindings show their fallbacks: the keys of `data` must match the paths of the data dictionary exactly.
4. **A list is empty.** The value under the collection name is not a `List`, or its records use full paths (`task.title`) instead of field names (`title`).
5. **A block is missing.** Its `visibleIf` condition did not hold; a missing value counts as empty.
6. **Colors look wrong.** Log `themeLoad.status`; anything but `ok` is a fallback theme.
7. **A gray placeholder with a widget name, debug builds only.** The document contains a widget this version does not know. Release builds skip it.
8. **Text is in the wrong language.** Log the `locale` you pass and `document.shownLocale(locale)`.

Debug builds print what the renderer decided not to draw, prefixed with `[hotlayout]`.

## License

Apache-2.0. See [LICENSE](LICENSE).

The icon drawings built into the package are from [Lucide](https://lucide.dev) (ISC License; some of them derive from Feather, MIT License), except ten drawn for HotLayout. The notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md); if your app has a licences screen, include them there.
