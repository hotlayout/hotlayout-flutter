# Hardening review

The document, the theme and the data reach this package from the network, so the package treats all three as untrusted input. This file lists every safety limit the package promises or should promise, whether the limit holds today, the test that pins it, and the fix where it does not hold.

All tests are in `test/hardening/`. A test for a limit that holds passes. A test for a limit that does not hold describes the correct behaviour and **fails until the fix lands**. Run the tests with `flutter test test/hardening`.

State: every test in `test/hardening/` passes. The 10 findings that did not hold are fixed in 0.28.0 (marked FIXED below, each with the commit); `test/hardening/loader_hardening_test.dart` adds tests for the loader, the allow-lists and the extra numeric guards found by the sweep.

## Summary

| # | Limit | Status | Tests |
|---|---|---|---|
| 1 | Pictures: default address policy | **FIXED** | `picture_hardening_test.dart` — "default policy …" (36 failing, 1 control passing) |
| 2 | Theme numbers stay within the schema bounds | **FIXED** | `numbers_hardening_test.dart` — "theme numbers …"; `delivery_hardening_test.dart` — "ThemeLoad.parse …" |
| 3 | `ThemeLoad.fromNetwork` never throws | **FIXED** | `delivery_hardening_test.dart` — "ThemeLoad.fromNetwork with fontWeight 1e400 completes" |
| 4 | Document numbers never throw | **FIXED** (one function) | `numbers_hardening_test.dart` — `maxLength`, `titleMaxLines`, `subtitleMaxLines`, `size`, `fieldRadius` = ±1e400 |
| 5 | Picture body size is capped | **FIXED** | `picture_hardening_test.dart` — "the body is bounded" |
| 6 | Picture decode is bounded | **FIXED** | `picture_hardening_test.dart` — "the decode is bounded" |
| 7 | Redirects do not bypass the policy | **FIXED** | `picture_hardening_test.dart` — "redirects are not followed past the policy" |
| 8 | Writes only to paths the host allows (`writablePaths`) | **FIXED** | `actions_hardening_test.dart` — "writablePaths: …" |
| 9 | No data value in the log | **FIXED** | `logs_hardening_test.dart` |
| 10 | Document body size is capped | **FIXED** | `delivery_hardening_test.dart` — "body size" |
| 11 | Data numbers never throw | holds | `numbers_hardening_test.dart` — "data numbers …" |
| 12 | Picture requests carry nothing of the host | holds | `picture_hardening_test.dart` — "the request carries nothing of the host" |
| 13 | Accessible name of a pressable card leaves out hidden children | holds | `accessible_name_hardening_test.dart` |
| 14 | The package opens nothing itself | holds | `actions_hardening_test.dart` — "the package opens nothing itself" |
| 15 | `openUrl` / `deeplink`: hostile addresses are invalid and never opened | holds | `actions_hardening_test.dart` — "openUrl: …" |
| 16 | Parameters come from data only where `bindable: true` | holds | `actions_hardening_test.dart` — "navigate.screenId is not bindable …" |
| 17 | One gesture is one action | holds | `actions_hardening_test.dart` — "one gesture is one action" |
| 18 | Writes: unsafe paths are refused and nothing is written without a gesture | holds | `actions_hardening_test.dart` — "writes" |
| 19 | Deep nesting and long lists are bounded | holds | `bounds_hardening_test.dart` |
| 20 | Drawing and hit testing stay inside the host's box | holds | `bounds_hardening_test.dart` |
| 21 | Theme font names are names, not paths | holds | `bounds_hardening_test.dart` |

The limits that do not hold are listed in order of importance.

---

## 1. Pictures: default address policy — FIXED in 0.28.0

**Limit.** A picture address from the document or from the data is fetched only when it is an `https` address whose host is a name with an alphabetic top-level label. This is the host form the contract already uses for `openUrl` (`x-actions.forms.httpsUrl`). The default policy refuses all of the following:

- an IP literal in any notation: `127.0.0.1`, `2130706433`, `0x7f000001`, `0177.0.0.1` and `127.1`;
- private and link-local ranges, including `169.254.169.254`;
- IPv6 literals;
- single-word names such as `localhost` and `intranet`;
- addresses with user info;
- `http`, `file` and every other scheme.

The host can narrow or widen the policy.

**Evidence.** `imageContent` (`lib/src/render/widgets/image.dart`) passes every `ImageUrl` straight to `Image.network`, or to `NetworkSvg` for SVG. There is no check and no host hook. All 18 hostile addresses were requested, both from the document and from the data. The device of the user makes these requests from inside the user's network: a document or a data field can probe the LAN, the router, or a cloud metadata endpoint.

**Fix.**
- Add `String? Function(String url)? resolveImageUrl` to `renderDocument`, `renderScreen` and `ScreenFlow`, and keep it in the render scope.
- The default is `paramFormProblem(ActionParamForm.httpsUrl, url) == null ? url : null`. That regular expression already refuses IP literals in every base, single-label hosts, user info and `http`.
- Apply the policy in `imageContent` before both branches. A refused address draws the broken-image placeholder and makes no request.
- `data:image/…` addresses need no network and keep their own branch. They are still covered by limit 6.

The test "the host can override the policy" calls the parameter dynamically, so it compiles before the parameter exists.

## 2. Theme numbers stay within the schema bounds — FIXED in 0.28.0

**Limit.** Every number in the theme is read against the bounds in the theme `x-schema`:

| Value | Bounds |
|---|---|
| `fontSize` | 8…96 |
| `lineHeight` | 0.8…3 |
| `letterSpacing` | −2…8 |
| `fontWeight` | integer, 100…900 |
| spacing | integer, 0…128 |
| radius | integer, 0…256 |
| shadow offset | −64…64 |
| shadow blur | 0…128 |
| shadow spread | −64…64 |
| opacity and gradient position | 0…1 |

A value outside its bounds never reaches a `TextStyle`, a padding or a constraint.

**Evidence.** `_number` and `_length` (`lib/src/theme/theme_json.dart`) accept any `num`, including infinity (`1e400` in JSON) and `1e300`. The bad values then reach layout:

- `fontSize` 1e300 gives "RenderParagraph was given an infinite size".
- A negative `fontSize` fails the `fontSize >= 0` assertion in `IconBox`.
- An infinite spacing gives "BoxConstraints has a NaN value" in `RenderScreenZones` and `RenderRowLayout`.
- A negative `lineHeight` gives a negative minimum height.
- An infinite `letterSpacing` fails the `maxIntrinsicLineExtent.isFinite` assertion.

In release builds these become broken or empty layout instead of assertions. A published theme with one bad value breaks every screen.

**Fix.** Read theme numbers with a helper that enforces the schema bounds. A value outside the bounds should be treated like a malformed value: the token is dropped and the fallback applies, as the code already does for a malformed colour. Clamping is the alternative if the theme compatibility policy prefers it. Either way, `isFinite` is checked first.

## 3. `ThemeLoad.fromNetwork` never throws — FIXED in 0.28.0

**Limit.** Loading a theme always completes with a `ThemeLoad` and a status. A hostile body is reported as `malformed` with the fallback theme; it never becomes an exception for the host.

**Evidence.** `themeFontWeight` (`theme_json.dart`) computes `(raw / 100).round()` on infinity and throws `UnsupportedError`. Nothing catches the error inside `ThemeLoad.parse` or `fromNetwork`, so the host's `await ThemeLoad.fromNetwork(...)` throws. `ThemeLoad.parse` and `fromJson` throw the same way.

**Fix.**
- Check `raw.isFinite` in `themeFontWeight`. Limit 2 then covers the range.
- Also wrap the body of `ThemeLoad.fromJson` in `on Object catch`, returning `_fallback(ThemeLoadStatus.malformed, …)`. That way a future parsing bug degrades to the fallback theme instead of escaping to the host.

## 4. Document numbers never throw — FIXED in 0.28.0 (one function)

**Limit.** No number in the document (finite, `±1e300`, `±infinity`, or `1e-300`) makes parsing or `build` throw.

**Evidence.** All other numeric fields in all fixtures hold: every number at once, and key by key. One helper does not. `wholeNumberIn` (`lib/src/model/style_values.dart`) runs:

```dart
final value = raw is double && raw == raw.truncateToDouble() ? raw.toInt() : raw;
```

`infinity.truncateToDouble() == infinity`, so `toInt()` throws. The error has two effects:

- From `build` (`maxLength`, `titleMaxLines`, `subtitleMaxLines`), it replaces the screen with an error widget.
- From parsing (`fieldRadius` and the part `size` through `strictRadiusRef`), it makes `UiDocument.fromJson` throw. `PublishedDocumentSource` turns that into the bundled fallback, but a host that calls `UiDocument.fromJson` directly gets the exception.

**Fix.** Add `raw.isFinite &&` before the `truncateToDouble` comparison. Consider also wrapping `UiDocument.fromJson` so that any parse error becomes a `FormatException`, which is a documented failure mode for direct callers.

## 5. Picture body size is capped — FIXED in 0.28.0

**Limit.** A picture response is read only up to a cap; this review uses 16 MiB. A `Content-Length` above the cap is refused before the body is read.

**Evidence.**
- Raster pictures go through the framework's `NetworkImage`, which consolidates the whole body. A 64 MiB body was read in full, with and without `Content-Length`.
- `_SvgStore._fetch` (`svg_image.dart`) uses `http.Client().get`, which buffers the whole body. 64 MiB was read.

Every picture on a screen multiplies the cost, so a hostile server can exhaust the app's memory.

**Fix.**
- Give the package its own `ImageProvider` for network pictures and use it in place of `Image.network`. It should:
  - use a dedicated `HttpClient`;
  - check `contentLength` first;
  - read the stream with a running counter and abort past the cap;
  - apply a timeout;
  - hand the bytes to `ImmutableBuffer` and `instantiateImageCodecWithSize` (see limit 6).
- In `_SvgStore._fetch`, use `client.send` and read `StreamedResponse.stream` with the same cap.

## 6. Picture decode is bounded — FIXED in 0.28.0

**Limit.** A small file that declares huge dimensions cannot make the app allocate the full bitmap. For example, a 20 kB PNG that declares 30000 × 30000 must not become 3.6 GB of pixels.

**Evidence.** `Image.network` and `Image.memory` (the `data:` branch) are created without `cacheWidth` or `cacheHeight`. Their provider is not a `ResizeImage`, so the codec decodes at the size the file declares.

**Fix.** Decode at a bounded size. Two options:
- Wrap the provider in `ResizeImage` with `policy: ResizeImagePolicy.fit` and a cap derived from the laid-out box × device pixel ratio (`LayoutBuilder`), with a hard ceiling such as 4096 px on the longer side.
- Use `instantiateImageCodecWithSize` with a `getTargetSize` that clamps.

Apply the same bound to the `data:` branch. If the fix checks dimensions in the header instead of resizing, update the two tests in this group to assert that check.

## 7. Redirects do not bypass the policy — FIXED in 0.28.0

**Limit.** A redirect from an allowed host to a refused one is not followed. Either redirects are not followed at all, or each hop is re-checked by the host policy, with a small hop limit.

**Evidence.** The framework's client follows redirects by default (`followRedirects` is `true` on the raster request), and so does `package:http` (the SVG request). With limit 1 in place, `https://cdn.example.com/a.png` → `302 https://169.254.169.254/…` would still be fetched.

**Fix.** In the loaders from limit 5, set `followRedirects = false` and handle 301, 302, 303, 307 and 308 by hand. Resolve `Location` against the request URL, run the result through `resolveImageUrl`, and allow at most 3 hops.

## 8. Writes only to paths the host allows (`writablePaths`) — FIXED in 0.28.0

**Limit.** The host can restrict which data paths a document may write. A write to a refused path reaches neither the session nor `onWrite`. The web reader has this parameter, and the contract names it.

**Evidence.** `isWritablePath` (`lib/src/model/write_action.dart`) is only `isSafeDataPath`, which checks the shape of the path. `renderDocument` has no parameter for an allow-list, so a document can make `onWrite` deliver any well-formed path, for example `user.balance`. A host that persists what it receives would store it.

What does hold: unsafe shapes are refused (`__proto__`, `constructor`, empty, over-long). Nothing is written without a gesture.

**Fix.** Add `bool Function(String path)? writablePaths` (or an `Iterable<String>` of allowed paths) to `renderDocument`, `renderScreen` and `ScreenFlow`. Check it in `runWriteStep` and in the field write path, in addition to `isSafeDataPath`. Document in the README that the default allows any well-formed path.

## 9. No data value in the log — FIXED in 0.28.0

**Limit.** A log line never contains a value from the host's data. `debugPrint` is **not** removed from release builds: it writes to the device log, which crash reporters and other tools collect.

**Evidence.**
- `svg_image.dart`, in the `onError` of `_load`, runs `debugPrint('[hotlayout] SVG not drawn ($url): $error')` without a `kDebugMode` guard. When the address comes from the data (`binding` source), it may carry a token or a user id, and it reaches the release log. The error text repeats the address (`ClientException … uri=…`).
- Debug builds only: the `ChoiceGroup` notice in `input_fields.dart` prints the data value, and `IconToken.parse` (`tokens.dart`) prints an unknown icon name that came from `iconPath` data.

**Fix.**
- SVG: guard the line with `kDebugMode` and log neither the URL nor the error text, only the status class: "SVG not drawn: HTTP 404" or "SVG not drawn: parse error".
- `ChoiceGroup`: print the node id and "a value no row carries", without the value.
- Unknown icon: print the node id or the data path, not the value.

## 10. Document body size is capped — FIXED in 0.28.0

**Limit.** The contract caps a document at `x-budget.maxDocumentBytes` (1 MiB, enforced by the producer). The reader still should not read an unbounded body. This review expects at most 4 × the budget to be read, and a larger `Content-Length` to be refused up front.

**Evidence.** `HttpDocumentTransport.fetch` calls `_client.get(url)`, which buffers the whole response. 64 MiB was read with and without `Content-Length`. The theme uses the same transport.

**Fix.** In `HttpDocumentTransport.fetch`:
- use `send`;
- check `contentLength`;
- read the stream with a counter and abort past `4 * maxDocumentBytes`.

An oversized body becomes a `malformed` load with the bundled fallback.

---

## Limits that hold

### 11. Data numbers never throw

Every number of the sample data was replaced by ±1e300, ±infinity, 1e-300 and NaN, and every fixture was drawn on every screen. No exception occurred (36 fixtures × 6 values). Progress (`progressRatio`), compact numbers, money, countdowns, value transitions and plural rules all check `isFinite` before converting.

### 12. Picture requests carry nothing of the host

Raster and SVG requests carry no `Cookie` or `Authorization` header and no cookies. `dart:io` has no cookie jar, and the package passes no headers.

There is one remaining exposure. The framework creates its single shared image `HttpClient` through `HttpOverrides`, and `package:http` does the same, so a host that installs a global override (a proxy, certificate pinning, a client that adds headers) applies it to document-chosen addresses too. The dedicated loader from limit 5 should create its client with `HttpClient()` and set nothing beyond what it needs. The README should say that a global `HttpOverrides` also applies to pictures.

### 13. Accessible name of a pressable card leaves out hidden children

A child hidden by `visibleIf` or by `showOn`, and the `alt` of a hidden picture, are not part of the card's merged semantics label. Hidden nodes are not built.

### 14. The package opens nothing itself

`pubspec.yaml` and `lib/` (comments ignored) contain no `url_launcher`, no `launchUrl`, no `Process.`, no `MethodChannel` and no `SystemNavigator`. Only three files make network requests: the document transport, the SVG loader and the image widget. `runStandardAction` is the only executor, and it acts only on `action.standard`.

### 15. `openUrl` / `deeplink`: hostile addresses are invalid and never opened

The test covers 15 hostile addresses, as literals and as data values:

- `http`, IP literals in several notations, `169.254.169.254`, IPv6 and `localhost`;
- user info, `https:\\`, `javascript:`, `data:` and `file:`;
- a leading space and a trailing U+202E.

Each one makes the handed action `invalid`, and `runStandardAction(openUrl:)` returns `false` without calling the executor. A data value that fails the form is not replaced by the literal. A good data address is `standard` and is opened only by the helper. A `deeplink` is never opened without the host's scheme list.

### 16. Parameters come from data only where `bindable: true`

`navigate` with `paramBindings: {screenId: …}` ignores the data and goes to the literal screen.

### 17. One gesture is one action

- A long press on a card that has both an action and a long press runs only the long press. Lifting the finger presses nothing.
- A held Enter with ten auto-repeats is one action.
- A double tap is two actions. This is pinned as documented behaviour: protecting against repeats is the host's job, and `HostActions` drops a press while its handler runs.

### 18. Writes: unsafe paths are refused and nothing is written without a gesture

`setValue` to `__proto__.x`, `constructor`, `user.__proto__`, `a..b`, an empty path, a 200-character path, or a path with a space writes nothing. A control path is written. Pumping a screen with a write button, a bound text field and a bound switch writes nothing until the user acts. See limit 8 for the missing allow-list.

### 19. Deep nesting and long lists are bounded

- Trees 33, 1000 and 20000 levels deep parse without a stack overflow and draw without an exception. Levels deeper than 32 below the root are not drawn; 30 levels are drawn.
- A `Repeater` over 100000 records draws 50.

### 20. Drawing and hit testing stay inside the host's box

A 4000 × 4000 pressable overlay, offset by 128 with a large shadow, inside a 200 × 200 host box:

- does not take a tap outside the box (the host's gesture detector gets it);
- is clipped, because the outermost clip under the host box has exactly the box's rect.

### 21. Theme font names are names, not paths

Family names are used only as `fontFamily` lookups. Path-like names, URLs, NUL characters, bidi controls and very long fallback names draw without an exception and make no request.

---

## Not covered here

- **SVG content.** `test/svg_image_test.dart` already tests that the parser ignores scripts and resolves no external references. It is not repeated here.
- **The `openUrl` and `deeplink` form table.** `test/actions_cases_test.dart` and `test/adversarial_98_actions_test.dart` already test it row by row. This file adds only the end-to-end path: screen → host → helper.

---

## Resolution (0.28.0, commit 88eee5e)

| # | Fix |
|---|---|
| 1 | `resolveImageUrl` on `renderDocument`, `renderScreen` and `ScreenFlow`; the default is the contract's `httpsUrl` form (`defaultImageUrlPolicy`). A refused address draws the placeholder. `data:` addresses are not judged by the default and are size-bounded; a host policy sees them too. |
| 2 | Theme numbers are read with `_bounded` against the schema bounds; a token with a corrupt number is dropped (a shadow layer or a gradient stop is left out). |
| 3 | `themeFontWeight` checks `isFinite` and 100…900; `ThemeLoad.fromJson`, `parse` and `fromNetwork` catch everything and return `malformed`. |
| 4 | `wholeNumberIn` checks `isFinite`. Sweep: `filledSegments` (NaN), `segmentFillInline` (not finite units) and `dashedLineOf` (not finite perimeter) are guarded; every other `toInt` / `round` / `floor` / `ceil` / `truncate` of a document number was already guarded by `isFinite` or a bound. Tests: `loader_hardening_test.dart`, "sweep". |
| 5, 6, 7 | One loader per platform (`picture_fetch_io.dart`, `picture_fetch_web.dart`): own `HttpClient`, `followRedirects = false`, at most three hops each re-checked by the policy, `Content-Length` check and a streamed cap (`maxDownloadBytes`, 10 MB), a 30 s overall timeout, cancellation of an SVG nobody waits for. Raster pictures use `NetworkPicture` inside a `ResizeImage` (`BoundedImage`: box × pixel ratio, ceiling 4096, no enlarging); `data:` pictures too. A host `HttpOverrides` still applies to the client the package creates (documented in the README). |
| 8 | `writablePaths` (predicate or list) is checked in `ScreenFlow._write`, which every field write and write action goes through, and in `renderScreen`. |
| 9 | The SVG failure line is debug-only and names the class of the failure; the choice and icon notices no longer print the value. |
| 10 | `HttpDocumentTransport.fetch` uses `send`, refuses a `Content-Length` of 4 MiB or more, and stops reading at 4 MiB; `DocumentTooLargeException` becomes a `malformed` load for documents and themes. |
